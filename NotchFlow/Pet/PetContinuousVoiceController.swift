@preconcurrency import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

enum PetContinuousVoicePhase: Equatable {
    case idle
    case requestingPermission
    case listening
    case processing
    case speaking
    case failed(String)

    var isActive: Bool {
        switch self {
        case .requestingPermission, .listening, .processing, .speaking:
            true
        case .idle, .failed:
            false
        }
    }

    var displayName: String {
        switch self {
        case .idle: "未开启"
        case .requestingPermission: "正在请求麦克风权限"
        case .listening: "正在听"
        case .processing: "正在理解并生成回复"
        case .speaking: "派蒙正在说话"
        case .failed(let message): "已停止：\(message)"
        }
    }
}

enum PetContinuousVoicePolicy {
    static let maximumTurns = 12
    static let maximumDuration: TimeInterval = 10 * 60
    static let silenceCommitDelay: Duration = .milliseconds(1_300)
    static let playbackCooldown: Duration = .milliseconds(900)
    static let duplicateSuppressionWindow: TimeInterval = 5

    static func normalizedTranscript(_ source: String) -> String? {
        let normalized = source
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    static func shouldAccept(
        transcript: String,
        previousTranscript: String?,
        secondsSincePrevious: TimeInterval?
    ) -> Bool {
        guard let normalized = normalizedTranscript(transcript) else { return false }
        guard let previousTranscript,
              let secondsSincePrevious,
              secondsSincePrevious < duplicateSuppressionWindow else { return true }
        return normalized != previousTranscript
    }

    static func shouldStop(turns: Int, elapsed: TimeInterval) -> Bool {
        turns >= maximumTurns || elapsed >= maximumDuration
    }
}

enum PetContinuousVoiceError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case onDeviceRecognitionUnavailable
    case audioInputUnavailable
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "没有麦克风权限。请到系统设置的隐私与安全性中允许 Paimon Pal 使用麦克风。"
        case .speechRecognitionDenied:
            "没有语音识别权限。请到系统设置的隐私与安全性中允许 Paimon Pal 使用语音识别。"
        case .onDeviceRecognitionUnavailable:
            "当前系统没有可用的普通话本机语音识别，因此没有回退到联网转写。"
        case .audioInputUnavailable:
            "没有检测到可用的音频输入设备。"
        case .recognitionFailed(let message):
            "语音识别已停止：\(message)"
        }
    }
}

@MainActor
final class PetContinuousVoiceController: ObservableObject {
    @Published private(set) var phase: PetContinuousVoicePhase = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var turnCount = 0

    var onTranscriptCommitted: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var sessionTimeoutTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var sessionStartedAt: Date?
    private var latestPartialTranscript = ""
    private var previousCommittedTranscript: String?
    private var previousCommitDate: Date?
    private var hasInputTap = false
    private var sessionIsActive = false

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    deinit {
        silenceTask?.cancel()
        sessionTimeoutTask?.cancel()
        resumeTask?.cancel()
        recognitionTask?.cancel()
        if let audioEngine, audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    func toggle() {
        if sessionIsActive || phase.isActive {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !sessionIsActive, !phase.isActive else { return }
        updatePhase(.requestingPermission)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await requestPermissions()
                try beginSession()
            } catch {
                fail(error)
            }
        }
    }

    func stop() {
        sessionIsActive = false
        stopCapture()
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = nil
        resumeTask?.cancel()
        resumeTask = nil
        sessionStartedAt = nil
        updatePhase(.idle)
    }

    func markProcessing() {
        guard sessionIsActive else { return }
        stopCapture()
        updatePhase(.processing)
    }

    func markSpeaking() {
        guard sessionIsActive else { return }
        stopCapture()
        updatePhase(.speaking)
    }

    func resumeAfterReply() {
        guard sessionIsActive else { return }
        let elapsed = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        guard !PetContinuousVoicePolicy.shouldStop(turns: turnCount, elapsed: elapsed) else {
            stop()
            return
        }

        resumeTask?.cancel()
        resumeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: PetContinuousVoicePolicy.playbackCooldown)
                guard let self, self.sessionIsActive else { return }
                try self.beginListening()
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error)
            }
        }
    }

    private func requestPermissions() async throws {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechStatus = .authorized
        case .notDetermined:
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        case .denied, .restricted:
            throw PetContinuousVoiceError.speechRecognitionDenied
        @unknown default:
            throw PetContinuousVoiceError.speechRecognitionDenied
        }
        guard speechStatus == .authorized else {
            throw PetContinuousVoiceError.speechRecognitionDenied
        }

        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAllowed = true
        case .notDetermined:
            microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            microphoneAllowed = false
        @unknown default:
            microphoneAllowed = false
        }
        guard microphoneAllowed else { throw PetContinuousVoiceError.microphoneDenied }
    }

    private func beginSession() throws {
        guard let recognizer,
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw PetContinuousVoiceError.onDeviceRecognitionUnavailable
        }
        sessionIsActive = true
        sessionStartedAt = Date()
        turnCount = 0
        lastTranscript = nil
        previousCommittedTranscript = nil
        previousCommitDate = nil
        try beginListening()

        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(PetContinuousVoicePolicy.maximumDuration))
                self?.stop()
            } catch {
                return
            }
        }
    }

    private func beginListening() throws {
        guard sessionIsActive else { return }
        stopCapture()
        guard let recognizer,
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw PetContinuousVoiceError.onDeviceRecognitionUnavailable
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw PetContinuousVoiceError.audioInputUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        latestPartialTranscript = ""

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInputTap = true
        engine.prepare()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorText = error?.localizedDescription
            Task { @MainActor in
                self?.handleRecognitionUpdate(
                    transcript: transcript,
                    isFinal: isFinal,
                    errorText: errorText
                )
            }
        }

        audioEngine = engine
        recognitionRequest = request
        try engine.start()
        updatePhase(.listening)
    }

    private func handleRecognitionUpdate(
        transcript: String?,
        isFinal: Bool,
        errorText: String?
    ) {
        guard sessionIsActive, phase == .listening else { return }
        if let transcript,
           let normalized = PetContinuousVoicePolicy.normalizedTranscript(transcript) {
            latestPartialTranscript = normalized
            scheduleSilenceCommit()
        }
        if isFinal, !latestPartialTranscript.isEmpty {
            commitLatestTranscript()
            return
        }
        if let errorText, latestPartialTranscript.isEmpty {
            fail(PetContinuousVoiceError.recognitionFailed(errorText))
        }
    }

    private func scheduleSilenceCommit() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: PetContinuousVoicePolicy.silenceCommitDelay)
                self?.commitLatestTranscript()
            } catch {
                return
            }
        }
    }

    private func commitLatestTranscript() {
        guard sessionIsActive, phase == .listening,
              let transcript = PetContinuousVoicePolicy.normalizedTranscript(latestPartialTranscript)
        else { return }

        let now = Date()
        let secondsSincePrevious = previousCommitDate.map { now.timeIntervalSince($0) }
        let accepted = PetContinuousVoicePolicy.shouldAccept(
            transcript: transcript,
            previousTranscript: previousCommittedTranscript,
            secondsSincePrevious: secondsSincePrevious
        )
        latestPartialTranscript = ""
        stopCapture()

        guard accepted else {
            resumeAfterReply()
            return
        }
        previousCommittedTranscript = transcript
        previousCommitDate = now
        lastTranscript = transcript
        turnCount += 1
        updatePhase(.processing)
        if let onTranscriptCommitted {
            onTranscriptCommitted(transcript)
        } else {
            resumeAfterReply()
        }
    }

    private func stopCapture() {
        silenceTask?.cancel()
        silenceTask = nil
        if let audioEngine {
            if audioEngine.isRunning { audioEngine.stop() }
            if hasInputTap { audioEngine.inputNode.removeTap(onBus: 0) }
        }
        hasInputTap = false
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
    }

    private func updatePhase(_ phase: PetContinuousVoicePhase) {
        self.phase = phase
    }

    private func fail(_ error: Error) {
        sessionIsActive = false
        stopCapture()
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = nil
        resumeTask?.cancel()
        resumeTask = nil
        let message = error.localizedDescription
        updatePhase(.failed(message))
        onFailure?(message)
    }
}

extension Notification.Name {
    static let paimonToggleContinuousVoiceRequested = Notification.Name(
        "PaimonPal.ToggleContinuousVoiceRequested"
    )
}
