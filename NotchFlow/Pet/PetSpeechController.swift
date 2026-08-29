import AVFoundation
import Combine
import Foundation

enum PetSpeechPhase: Equatable {
    case idle
    case generating
    case playing
}

enum PetSpeechTextPreparer {
    static let maximumCharacters = 160

    static func prepare(_ source: String) -> String? {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let replacements: [(String, String)] = [
            (#"```[\s\S]*?```"#, ""),
            (#"`([^`]*)`"#, "$1"),
            (#"!\[[^\]]*\]\([^\)]*\)"#, ""),
            (#"\[([^\]]+)\]\([^\)]*\)"#, "$1"),
            (#"https?://\S+"#, ""),
            (#"[*_>#~]+"#, ""),
            (#"\s+"#, " "),
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("旅行者") {
            // 只朗读回复原文已经包含的称呼，不再每句强制添加。
            // 称呼存在时移除紧邻标点，避免 Qwen3-TTS 放大成拖长呼喊。
            text = text.replacingOccurrences(
                of: #"^旅行者[\s，,。.!！?？:：、]*"#,
                with: "旅行者",
                options: .regularExpression
            )
        }
        return String(text.prefix(maximumCharacters))
    }
}

struct PetSpeechRequestGate {
    private(set) var currentToken: UUID?

    mutating func begin() -> UUID {
        let token = UUID()
        currentToken = token
        return token
    }

    mutating func invalidate() {
        currentToken = nil
    }

    func isCurrent(_ token: UUID) -> Bool {
        currentToken == token
    }
}

@MainActor
protocol PetSpeechGenerating {
    func generate(text: String, token: UUID) async throws -> URL
}

@MainActor
protocol PetSpeechAudioPlaying: AnyObject {
    var onPlaybackEnded: (() -> Void)? { get set }
    func play(url: URL) throws
    func stop()
}

@MainActor
final class PetSpeechController: ObservableObject {
    @Published private(set) var phase: PetSpeechPhase = .idle
    @Published private(set) var lastError: String?

    private let isEnabled: @MainActor () -> Bool
    private let generator: any PetSpeechGenerating
    private let player: any PetSpeechAudioPlaying
    private var gate = PetSpeechRequestGate()
    private var generationTask: Task<Void, Never>?
    private var activeAudioURL: URL?
    private var completion: (() -> Void)?

    init(
        isEnabled: @escaping @MainActor () -> Bool,
        generator: any PetSpeechGenerating,
        player: any PetSpeechAudioPlaying
    ) {
        self.isEnabled = isEnabled
        self.generator = generator
        self.player = player
    }

    convenience init(preferences: AppPreferences) {
        self.init(
            isEnabled: { preferences.petVoiceEnabled },
            generator: BundledPetSpeechGenerator(),
            player: AVAudioPetSpeechPlayer()
        )
    }

    @discardableResult
    func speak(
        _ source: String,
        onPlaybackStarted: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) -> Bool {
        stop(notifyCompletion: false)
        guard isEnabled(), let text = PetSpeechTextPreparer.prepare(source) else {
            return false
        }

        let token = gate.begin()
        completion = onFinished
        lastError = nil
        phase = .generating
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let audioURL = try await generator.generate(text: text, token: token)
                guard !Task.isCancelled, gate.isCurrent(token) else {
                    try? FileManager.default.removeItem(at: audioURL)
                    return
                }

                activeAudioURL = audioURL
                player.onPlaybackEnded = { [weak self] in
                    guard let self, self.gate.isCurrent(token) else { return }
                    self.finishCurrentRequest()
                }
                try player.play(url: audioURL)
                phase = .playing
                onPlaybackStarted()
            } catch is CancellationError {
                return
            } catch {
                guard gate.isCurrent(token) else { return }
                lastError = error.localizedDescription
                finishCurrentRequest()
            }
        }
        return true
    }

    func stop(notifyCompletion: Bool = true) {
        let pendingCompletion = notifyCompletion ? completion : nil
        completion = nil
        gate.invalidate()
        generationTask?.cancel()
        generationTask = nil
        player.onPlaybackEnded = nil
        player.stop()
        removeActiveAudio()
        phase = .idle
        pendingCompletion?()
    }

    private func finishCurrentRequest() {
        let pendingCompletion = completion
        completion = nil
        gate.invalidate()
        generationTask?.cancel()
        generationTask = nil
        player.onPlaybackEnded = nil
        player.stop()
        removeActiveAudio()
        phase = .idle
        pendingCompletion?()
    }

    private func removeActiveAudio() {
        guard let activeAudioURL else { return }
        try? FileManager.default.removeItem(at: activeAudioURL)
        self.activeAudioURL = nil
    }
}

@MainActor
final class AVAudioPetSpeechPlayer: NSObject, PetSpeechAudioPlaying, AVAudioPlayerDelegate {
    var onPlaybackEnded: (() -> Void)?
    private var player: AVAudioPlayer?

    func play(url: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else { throw PetSpeechError.playbackFailed }
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.onPlaybackEnded?()
        }
    }
}

@MainActor
struct BundledPetSpeechGenerator: PetSpeechGenerating {
    private let bundle: Bundle
    private let fileManager: FileManager

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func generate(text: String, token: UUID) async throws -> URL {
        let layout = try PetSpeechRuntimeLayout.locate(in: bundle)
        let outputDirectory = try PetSpeechRuntimeLayout.outputDirectory(
            fileManager: fileManager
        )
        PetSpeechRuntimeLayout.removeStaleAudioFiles(
            in: outputDirectory,
            fileManager: fileManager
        )
        let outputURL = outputDirectory
            .appendingPathComponent(token.uuidString)
            .appendingPathExtension("wav")
        try? fileManager.removeItem(at: outputURL)

        let invocation = PetSpeechProcessInvocation(
            layout: layout,
            text: text,
            outputURL: outputURL
        )
        try await invocation.run()
        guard fileManager.fileExists(atPath: outputURL.path),
              (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 44
        else {
            throw PetSpeechError.missingGeneratedAudio
        }
        return outputURL
    }
}

struct PetSpeechRuntimeLayout: Equatable, Sendable {
    let pythonExecutable: URL
    let pythonHome: URL
    let sitePackages: URL
    let runtimeScript: URL
    let modelDirectory: URL
    let referenceAudio: URL

    static func locate(in bundle: Bundle) throws -> PetSpeechRuntimeLayout {
        guard let resources = bundle.resourceURL else {
            throw PetSpeechError.missingRuntime
        }
        let root = resources.appendingPathComponent("PaimonTTS", isDirectory: true)
        let pythonHome = root.appendingPathComponent("Runtime/Python", isDirectory: true)
        let layout = PetSpeechRuntimeLayout(
            pythonExecutable: pythonHome.appendingPathComponent("bin/python3.12"),
            pythonHome: pythonHome,
            sitePackages: root.appendingPathComponent("Runtime/SitePackages", isDirectory: true),
            runtimeScript: root.appendingPathComponent("Runtime/paimon_tts_runtime.py"),
            modelDirectory: root.appendingPathComponent("Model", isDirectory: true),
            referenceAudio: root.appendingPathComponent("VoiceReference.wav")
        )
        let required = [
            layout.pythonExecutable,
            layout.sitePackages,
            layout.runtimeScript,
            layout.modelDirectory,
            layout.referenceAudio,
        ]
        guard required.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw PetSpeechError.missingRuntime
        }
        return layout
    }

    static func outputDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PetSpeechError.outputDirectoryUnavailable
        }
        let directory = applicationSupport
            .appendingPathComponent("Paimon Pal", isDirectory: true)
            .appendingPathComponent("Speech", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func removeStaleAudioFiles(
        in directory: URL,
        fileManager: FileManager = .default
    ) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "wav" {
            try? fileManager.removeItem(at: file)
        }
    }
}

private final class PetSpeechProcessInvocation: @unchecked Sendable {
    private let process = Process()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let lock = NSLock()
    private var cancellationRequested = false

    init(layout: PetSpeechRuntimeLayout, text: String, outputURL: URL) {
        process.executableURL = layout.pythonExecutable
        process.arguments = [
            layout.runtimeScript.path,
            "--model", layout.modelDirectory.path,
            "--reference", layout.referenceAudio.path,
            "--output", outputURL.path,
            "--text", text,
        ]
        process.currentDirectoryURL = layout.runtimeScript.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONHOME"] = layout.pythonHome.path
        environment["PYTHONPATH"] = layout.sitePackages.path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["MLX_METAL_CACHE_DIR"] = outputURL.deletingLastPathComponent().path
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                let shouldCancel = lock.withLock { cancellationRequested }
                if shouldCancel { throw CancellationError() }

                try process.run()
                let cancelAfterLaunch = lock.withLock { cancellationRequested }
                if cancelAfterLaunch, process.isRunning { process.terminate() }
                process.waitUntilExit()

                let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
                let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                if Task.isCancelled || cancelAfterLaunch { throw CancellationError() }
                guard process.terminationStatus == 0 else {
                    let errorText = String(decoding: errorData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw PetSpeechError.generationFailed(
                        errorText.isEmpty ? "本地语音进程异常退出。" : errorText
                    )
                }
                let output = String(decoding: outputData, as: UTF8.self)
                guard output.contains("PAIMON_TTS_RESULT_BEGIN"),
                      output.contains("PAIMON_TTS_RESULT_END") else {
                    throw PetSpeechError.invalidRuntimeResponse
                }
            }.value
        } onCancel: {
            let isRunning = lock.withLock {
                cancellationRequested = true
                return process.isRunning
            }
            if isRunning { process.terminate() }
        }
    }
}

enum PetSpeechError: LocalizedError {
    case missingRuntime
    case outputDirectoryUnavailable
    case generationFailed(String)
    case invalidRuntimeResponse
    case missingGeneratedAudio
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .missingRuntime:
            "安装包中缺少本地语音模型或运行组件，已保留文字回复。"
        case .outputDirectoryUnavailable:
            "无法创建本地语音临时目录，已保留文字回复。"
        case .generationFailed(let message):
            "本地语音生成失败：\(message)"
        case .invalidRuntimeResponse:
            "本地语音进程返回了无法识别的结果。"
        case .missingGeneratedAudio:
            "本地语音没有生成可播放的音频。"
        case .playbackFailed:
            "本地语音播放失败。"
        }
    }
}

extension Notification.Name {
    static let paimonStopVoiceRequested = Notification.Name("PaimonPal.StopVoiceRequested")
}
