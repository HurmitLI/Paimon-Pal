import AppKit
import Combine
import Foundation

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var snapshot: MusicSnapshot = .unavailable
    @Published private(set) var message = "正在检查 Apple Music…"
    @Published private(set) var isPerformingCommand = false
    @Published private(set) var lastError: MusicServiceError?

    private let provider: MusicPlaybackProviding
    private let coordinator: ActivityCoordinator
    private var pollTask: Task<Void, Never>?
    private var pausedSince: Date?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        coordinator: ActivityCoordinator,
        provider: MusicPlaybackProviding = AppleMusicAdapter()
    ) {
        self.coordinator = coordinator
        self.provider = provider
    }

    func start() {
        guard pollTask == nil else { return }
        installWorkspaceObservers()
        refresh()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: Self.pollingInterval(for: snapshot.playbackState))
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        pausedSince = nil
        coordinator.removeActivity(id: "music.appleMusic")
        message = "Apple Music 监听已暂停。"
    }

    func refresh() {
        switch provider.readSnapshot() {
        case .success(let newSnapshot):
            lastError = nil
            snapshot = newSnapshot
            message = statusMessage(for: newSnapshot)
            synchronizeActivity(with: newSnapshot)
        case .failure(let error):
            lastError = error
            message = error.localizedDescription
            coordinator.removeActivity(id: "music.appleMusic")
        }
    }

    @discardableResult
    func send(_ command: MusicCommand) -> Result<Void, MusicServiceError> {
        guard !isPerformingCommand else {
            return .failure(.commandFailed("Apple Music 正在处理上一条指令，请稍后再试。"))
        }
        isPerformingCommand = true
        let result = provider.send(command)
        switch result {
        case .success:
            lastError = nil
            message = "指令已发送，正在等待 Apple Music 更新…"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.isPerformingCommand = false
                self?.refresh()
            }
        case .failure(let error):
            isPerformingCommand = false
            lastError = error
            message = error.localizedDescription
        }
        return result
    }

    func seek(to position: TimeInterval) {
        switch provider.seek(to: position) {
        case .success:
            lastError = nil
            message = "播放进度已更新。"
            refresh()
        case .failure(let error):
            lastError = error
            message = error.localizedDescription
        }
    }

    func openSource() {
        provider.openSource()
    }

    static func pollingInterval(for state: MusicPlaybackState) -> Duration {
        state == .playing ? .seconds(1) : .seconds(2)
    }

    private func synchronizeActivity(with snapshot: MusicSnapshot) {
        guard snapshot.isActive else {
            pausedSince = nil
            coordinator.removeActivity(id: "music.appleMusic")
            return
        }

        if snapshot.playbackState == .paused {
            pausedSince = pausedSince ?? Date()
            if let pausedSince, Date().timeIntervalSince(pausedSince) >= 600 {
                coordinator.removeActivity(id: "music.appleMusic")
                return
            }
        } else {
            pausedSince = nil
        }

        coordinator.upsert(IslandActivity(
            id: "music.appleMusic",
            kind: .music,
            title: snapshot.title,
            detail: snapshot.artist
        ))
    }

    private func statusMessage(for snapshot: MusicSnapshot) -> String {
        guard snapshot.installed else { return "本机未安装 Apple Music。" }
        guard snapshot.running else { return "Apple Music 未运行。" }
        switch snapshot.playbackState {
        case .playing: return "正在播放"
        case .paused: return "已暂停"
        case .stopped: return "Apple Music 已停止播放。"
        case .unavailable: return "暂时无法读取 Apple Music 状态。"
        }
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.Music"
                else { return }
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
    }
}
