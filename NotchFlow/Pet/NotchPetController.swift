import AppKit
import Combine
import Foundation

enum NotchPetStage: Equatable {
    case sleeping
    case waking
    case emerging
    case idle
    case reacting
    case listening
    case speaking
    case celebrating
    case returning
}

@MainActor
final class NotchPetController: ObservableObject {
    @Published private(set) var stage: NotchPetStage = .sleeping
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var lastError: String?

    private let loader: NotchPetAssetLoader
    private var frameCache: [NotchPetMotion: [NSImage]] = [:]
    private var playbackTask: Task<Void, Never>?

    init(loader: NotchPetAssetLoader = NotchPetAssetLoader()) {
        self.loader = loader
        resetToSleep()
    }

    var isAwake: Bool {
        stage != .sleeping
    }

    var hasRenderableFrame: Bool {
        currentImage != nil
    }

    var isListening: Bool {
        stage == .listening
    }

    var isSpeaking: Bool {
        stage == .speaking
    }

    var acceptsConversationClick: Bool {
        stage == .idle || stage == .listening
    }

    var acceptsDesktopDrag: Bool {
        stage == .idle
    }

    var keepsVisibleWithoutPointer: Bool {
        stage == .listening || stage == .speaking || stage == .celebrating
    }

    func wakeUp() {
        guard stage == .sleeping else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            await self?.runWakeSequence()
        }
    }

    func returnToSleep() {
        guard stage != .sleeping, stage != .returning,
              !keepsVisibleWithoutPointer else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .returning
            guard await playOnce(.returnToSleep) else { return }
            stage = .sleeping
        }
    }

    func returnToSleepAfterDocking() {
        guard stage != .sleeping, stage != .returning else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .returning
            guard await playOnce(.returnToSleep) else { return }
            stage = .sleeping
        }
    }

    func reactToClick() {
        guard stage == .idle else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .reacting
            guard await playOnce(.clickReaction) else { return }
            stage = .idle
            await playCalmIdle()
        }
    }

    func startListening() {
        guard stage != .listening, stage != .celebrating,
              stage != .returning else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .listening
            await playLoop(.listening)
        }
    }

    func stopListening() {
        guard stage == .listening else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .idle
            await playCalmIdle()
        }
    }

    func startSpeaking() {
        guard stage != .speaking, stage != .celebrating,
              stage != .returning else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .speaking
            await playLoop(.speaking)
        }
    }

    func stopSpeaking() {
        guard stage == .speaking else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .idle
            await playCalmIdle()
        }
    }

    func celebrateSuccess() {
        guard stage != .celebrating, stage != .returning else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            stage = .celebrating
            guard await playOnce(.successCelebration) else { return }
            stage = .idle
            await playCalmIdle()
        }
    }

    func resetToSleep() {
        playbackTask?.cancel()
        playbackTask = nil
        stage = .sleeping
        do {
            currentImage = try frames(for: .sleepToPeek).first
            lastError = nil
        } catch {
            currentImage = nil
            lastError = error.localizedDescription
        }
    }

    private func runWakeSequence() async {
        // Decode and clean the larger 16-frame idle sheet before the pet becomes
        // visible. Doing this at the transition boundary can briefly starve the
        // transparent panel's redraw and look like a white flash.
        do {
            _ = try frames(for: .idle)
        } catch {
            lastError = error.localizedDescription
            return
        }
        stage = .waking
        guard await playOnce(.sleepToPeek) else { return }
        stage = .emerging
        guard await playOnce(.peekToEmerge) else { return }
        stage = .idle
        await playCalmIdle()
    }

    private func playOnce(_ motion: NotchPetMotion) async -> Bool {
        do {
            let images = try frames(for: motion)
            lastError = nil
            for image in images {
                guard !Task.isCancelled else { return false }
                currentImage = image
                try await Task.sleep(nanoseconds: frameInterval(for: motion))
            }
            return !Task.isCancelled
        } catch is CancellationError {
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func playCalmIdle() async {
        do {
            let images = try frames(for: .idle)
            guard let restingFrame = images.first else { return }
            lastError = nil
            currentImage = restingFrame
            var completedCycles = 0
            while !Task.isCancelled {
                // 先保持安静，再播放一次短促的呼吸和眨眼；避免鼠标停在刘海时
                // 角色持续循环、显得焦躁，同时保留自然的生命感。
                try await Task.sleep(for: .seconds(2))
                for image in images.dropFirst() {
                    guard !Task.isCancelled else { return }
                    currentImage = image
                    try await Task.sleep(nanoseconds: frameInterval(for: .idle))
                }
                currentImage = restingFrame
                try await Task.sleep(for: .seconds(5))

                completedCycles += 1
                if let flourish = NotchPetIdleChoreography.flourish(
                    afterCompletedCycles: completedCycles
                ) {
                    let flourishImages = try frames(for: flourish)
                    for image in flourishImages {
                        guard !Task.isCancelled else { return }
                        currentImage = image
                        try await Task.sleep(nanoseconds: frameInterval(for: flourish))
                    }
                    currentImage = restingFrame
                    try await Task.sleep(for: .seconds(4))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func playLoop(_ motion: NotchPetMotion) async {
        do {
            let images = try frames(for: motion)
            guard !images.isEmpty else { return }
            lastError = nil
            while !Task.isCancelled {
                for image in images {
                    guard !Task.isCancelled else { return }
                    currentImage = image
                    try await Task.sleep(nanoseconds: frameInterval(for: motion))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func frames(for motion: NotchPetMotion) throws -> [NSImage] {
        if let cached = frameCache[motion] { return cached }
        let loaded = try loader.frames(for: motion)
        frameCache[motion] = loaded
        return loaded
    }

    private func frameInterval(for motion: NotchPetMotion) -> UInt64 {
        UInt64(1_000_000_000 / max(motion.framesPerSecond, 1))
    }

}
