import AppKit
import AVFoundation
import Foundation
import Speech

struct WorkspaceRecording: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
    var transcript: String

    init(
        id: UUID = UUID(),
        fileName: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        transcript: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
    }
}

protocol RecordingLibraryPersisting {
    var directoryURL: URL { get }
    func load() throws -> [WorkspaceRecording]
    func save(_ recordings: [WorkspaceRecording]) throws
}

struct FileRecordingLibrary: RecordingLibraryPersisting {
    let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let root = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.directoryURL = root
                .appendingPathComponent("Paimon Pal", isDirectory: true)
                .appendingPathComponent("recordings", isDirectory: true)
        }
    }

    private var indexURL: URL { directoryURL.appendingPathComponent("index.json") }

    func load() throws -> [WorkspaceRecording] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([WorkspaceRecording].self, from: Data(contentsOf: indexURL))
            .filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ recordings: [WorkspaceRecording]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recordings).write(to: indexURL, options: .atomic)
    }

    func fileURL(for recording: WorkspaceRecording) -> URL {
        directoryURL.appendingPathComponent(recording.fileName)
    }
}

@MainActor
final class RecordingController: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published private(set) var recordings: [WorkspaceRecording] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var statusText = "麦克风只会在主动开始录音后启用。"

    private let library: RecordingLibraryPersisting
    private var recorder: AVAudioRecorder?
    private var activeRecordingID: UUID?
    private var activeURL: URL?
    private var activeStartedAt: Date?

    init(library: RecordingLibraryPersisting = FileRecordingLibrary()) {
        self.library = library
        super.init()
        do {
            recordings = try library.load()
        } catch {
            statusText = "录音索引无法读取：\(error.localizedDescription)"
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : requestPermissionAndStart()
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        isRecording = false
        statusText = "录音已保存，正在尝试本机转写……"
    }

    func play(_ recording: WorkspaceRecording) {
        NSWorkspace.shared.open(fileURL(for: recording))
    }

    func reveal(_ recording: WorkspaceRecording) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: recording)])
    }

    func delete(_ recording: WorkspaceRecording) {
        let url = fileURL(for: recording)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            recordings.removeAll { $0.id == recording.id }
            try library.save(recordings)
            statusText = "录音已移到废纸篓。"
        } catch {
            statusText = "无法删除录音：\(error.localizedDescription)"
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard let id = activeRecordingID, let url = activeURL else { return }
        let duration = max(0, activeStartedAt.map { Date().timeIntervalSince($0) } ?? recorder.currentTime)
        self.recorder = nil
        activeRecordingID = nil
        activeURL = nil
        activeStartedAt = nil
        guard flag else {
            try? FileManager.default.removeItem(at: url)
            statusText = "录音未能完整保存。"
            return
        }
        let item = WorkspaceRecording(
            id: id,
            fileName: url.lastPathComponent,
            duration: duration
        )
        recordings.insert(item, at: 0)
        persist()
        transcribe(item)
    }

    private func requestPermissionAndStart() {
        Task { @MainActor in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else {
                statusText = "麦克风权限未开启，可到系统设置的“隐私与安全性 → 麦克风”中调整。"
                return
            }
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try FileManager.default.createDirectory(
                at: library.directoryURL,
                withIntermediateDirectories: true
            )
            let id = UUID()
            let url = library.directoryURL.appendingPathComponent("\(id.uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            activeRecordingID = id
            activeURL = url
            activeStartedAt = Date()
            isRecording = true
            statusText = "正在录音……点击停止后会保存到本机。"
        } catch {
            statusText = "无法开始录音：\(error.localizedDescription)"
        }
    }

    private func transcribe(_ recording: WorkspaceRecording) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) else {
            statusText = "录音已保存，但本机没有可用的中文转写器。"
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            statusText = "录音已保存；当前 Mac 不支持中文设备端转写，不会改用联网识别。"
            return
        }
        Task { @MainActor in
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard authorization == .authorized else {
                statusText = "录音已保存；未授权语音识别，所以没有转写。"
                return
            }
            isTranscribing = true
            let request = SFSpeechURLRecognitionRequest(url: fileURL(for: recording))
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true
            recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard result?.isFinal == true || error != nil else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    isTranscribing = false
                    if let text = result?.bestTranscription.formattedString,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                        recordings[index].transcript = text
                        persist()
                        statusText = "录音与转写已保存。"
                    } else {
                        statusText = "录音已保存，本次未识别出文字。"
                    }
                }
            }
        }
    }

    private func fileURL(for recording: WorkspaceRecording) -> URL {
        library.directoryURL.appendingPathComponent(recording.fileName)
    }

    private func persist() {
        do {
            try library.save(recordings)
        } catch {
            statusText = "录音索引保存失败：\(error.localizedDescription)"
        }
    }
}
