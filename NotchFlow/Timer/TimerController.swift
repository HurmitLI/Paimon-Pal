import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class TimerController: ObservableObject {
    @Published private(set) var state: TimerRuntimeState = .idle
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var message = "选择时长后即可开始。"
    @Published private(set) var notificationStatus = "通知未检查"

    private let coordinator: ActivityCoordinator
    private let store: TimerStateStoring
    private var tickTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    init(
        coordinator: ActivityCoordinator,
        store: TimerStateStoring = UserDefaultsTimerStore()
    ) {
        self.coordinator = coordinator
        self.store = store
    }

    func start() {
        guard tickTask == nil else { return }
        state = store.load() ?? .idle
        let transition = state.reconcileAfterRestore(now: Date())
        handle(transition, restored: true)
        publish(now: Date())
        installObservers()
        refreshNotificationStatus()

        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let isActive = state.phase == .running || state.phase == .ringing
                try? await Task.sleep(for: isActive ? .milliseconds(250) : .seconds(1))
                guard !Task.isCancelled else { return }
                if state.phase == .running || state.phase == .ringing {
                    refresh(now: Date())
                }
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.forEach { observer in
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        coordinator.removeActivity(id: "timer.active")
        message = "计时器已关闭；进行中的计时状态会保留。"
    }

    func begin(seconds: Int, now: Date = Date()) {
        guard state.begin(seconds: seconds, now: now) else {
            message = "请输入至少 1 秒且不超过 99:59:59 的时长。"
            return
        }
        message = "计时进行中"
        saveAndPublish(now: now)
    }

    func pause(now: Date = Date()) {
        guard state.pause(now: now) else { return }
        message = "计时已暂停"
        saveAndPublish(now: now)
    }

    func resume(now: Date = Date()) {
        guard state.resume(now: now) else { return }
        message = "计时继续"
        saveAndPublish(now: now)
    }

    func cancel() {
        state.cancel()
        message = "计时已结束。"
        store.clear()
        publish(now: Date())
    }

    func acknowledge() {
        state.acknowledge()
        message = "计时提醒已确认。"
        store.clear()
        publish(now: Date())
    }

    func requestNotificationAuthorization() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                notificationStatus = "通知授权失败，刘海提醒仍可使用"
            }
            refreshNotificationStatus()
        }
    }

    func refresh(now: Date = Date(), correctedClock: Bool = false) {
        let transition = state.refresh(now: now)
        if correctedClock, state.phase == .running || state.phase == .paused {
            coordinator.showTemporaryHUD(IslandActivity(
                id: "timer.clockCorrection",
                kind: .systemHUD,
                title: "计时已校正",
                systemSymbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            ))
        }
        handle(transition, restored: false)
        saveAndPublish(now: now)
    }

    var progress: Double {
        guard state.totalSeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(state.totalSeconds), 0), 1)
    }

    private func publish(now: Date) {
        let shouldCollapseFinishedTimer = state.phase == .idle &&
            coordinator.state.presentation == .expanded &&
            coordinator.state.activity?.id == "timer.active"
        remainingSeconds = state.remainingSeconds(at: now)
        synchronizeActivity()
        if shouldCollapseFinishedTimer {
            coordinator.collapse()
        }
    }

    private func saveAndPublish(now: Date) {
        if state.phase == .idle {
            store.clear()
        } else {
            store.save(state)
        }
        publish(now: now)
    }

    private func synchronizeActivity() {
        switch state.phase {
        case .idle:
            coordinator.removeActivity(id: "timer.active")
        case .running, .paused:
            let nearEnd = remainingSeconds <= 60
            coordinator.upsert(IslandActivity(
                id: "timer.active",
                kind: .timer,
                title: TimerTextFormatter.clock(seconds: remainingSeconds),
                detail: state.phase == .paused ? "已暂停" : (nearEnd ? "即将结束" : "计时中"),
                systemSymbol: state.phase == .paused ? "pause.circle.fill" : "timer",
                progress: progress
            ))
        case .ringing:
            coordinator.upsert(IslandActivity(
                id: "timer.active",
                kind: .ringingTimer,
                title: "计时结束",
                detail: "点击确认",
                systemSymbol: "timer.circle.fill",
                progress: 0
            ))
        }
    }

    private func handle(_ transition: TimerTransition, restored: Bool) {
        switch transition {
        case .none:
            break
        case .finished:
            message = restored ? "计时已在应用关闭期间结束。" : "计时结束"
            NSSound.beep()
            deliverFinishedNotificationIfAllowed()
        case .autoDismissed:
            message = "上一次计时已结束。"
            store.clear()
        }
    }

    private func installObservers() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(now: Date()) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("NSSystemClockDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(now: Date(), correctedClock: true) }
        })
    }

    func refreshNotificationStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationAuthorization = settings.authorizationStatus
            notificationStatus = switch settings.authorizationStatus {
            case .authorized, .provisional: "通知已启用"
            case .denied: "通知未允许，刘海提醒仍会工作"
            case .notDetermined: "通知可选，尚未启用"
            @unknown default: "通知状态未知"
            }
        }
    }

    private func deliverFinishedNotificationIfAllowed() {
        guard [.authorized, .provisional].contains(notificationAuthorization) else { return }
        let content = UNMutableNotificationContent()
        content.title = "NotchFlow 计时结束"
        content.body = "设定的倒计时已经完成。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "NotchFlow.timer.finished",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
