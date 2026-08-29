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

    var keepsVisibleWithoutPointer: Bool {
        stage == .listening
    }

    func wakeUp() {
        guard stage == .sleeping else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            await self?.runWakeSequence()
        }
    }

    func returnToSleep() {
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
        guard stage != .listening, stage != .returning else { return }
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
            while !Task.isCancelled {
                // 当前生成的“眨眼”帧会同时改变身体姿势。
                // 在拆出独立眼部图层前，待机保持完全静止，避免角色左右晃动。
                try await Task.sleep(for: .seconds(60))
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
