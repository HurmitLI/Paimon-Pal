import Combine
import Foundation

@MainActor
final class SystemStatusController: ObservableObject {
    @Published private(set) var snapshot: SystemStatusSnapshot = .unavailable
    @Published private(set) var message = "正在读取系统状态…"

    private let coordinator: ActivityCoordinator
    private let reader: SystemStatusReading
    private var monitorTask: Task<Void, Never>?
    private var audioTick = 0

    init(
        coordinator: ActivityCoordinator,
        reader: SystemStatusReading = LiveSystemStatusReader()
    ) {
        self.coordinator = coordinator
        self.reader = reader
    }

    func start() {
        guard monitorTask == nil else { return }
        refreshBattery()
        refreshAudio()
        updateMessage()

        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                refreshAudio()
                audioTick += 1
                if audioTick >= 5 {
                    audioTick = 0
                    refreshBattery()
                }
                updateMessage()
            }
        }
    }

    func refreshNow() {
        refreshBattery()
        refreshAudio()
        updateMessage()
    }

    private func refreshBattery() {
        guard let current = reader.readBattery() else { return }
        let events = SystemStatusEventResolver.powerEvents(
            previous: snapshot.battery,
            current: current
        )
        snapshot.battery = current
        present(events)
    }

    private func refreshAudio() {
        guard let current = reader.readAudio() else { return }
        let events = SystemStatusEventResolver.audioEvents(
            previous: snapshot.audio,
            current: current
        )
        snapshot.audio = current
        present(events)
    }

    private func present(_ events: [SystemStatusEvent]) {
        for event in events {
            coordinator.showTemporaryHUD(event.activity, duration: event.duration)
        }
    }

    private func updateMessage() {
        switch (snapshot.battery, snapshot.audio) {
        case (.some, .some):
            message = "电池、电源、音量与静音状态正在实时监听。"
        case (.some, .none):
            message = "电池状态正常；当前输出设备未提供可读音量。"
        case (.none, .some):
            message = "音量状态正常；系统暂未返回电池信息。"
        case (.none, .none):
            message = "系统暂未返回可用状态。"
        }
    }
}
