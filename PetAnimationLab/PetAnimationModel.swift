import AppKit
import Foundation
import ImageIO

struct PetAnimationManifest: Decodable {
    let schemaVersion: Int
    let assetPack: String
    let grid: PetAnimationGrid
    let animations: [PetAnimationDefinition]
}

struct PetAnimationGrid: Decodable, Hashable {
    let columns: Int
    let rows: Int
    let frameCount: Int
}

struct PetAnimationDefinition: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let sourceWidth: Int
    let sourceHeight: Int
    let fps: Int
    let playback: String
    let nextState: String?
    let grid: PetAnimationGrid?

    var displayName: String {
        switch id {
        case "denSleepToPeek": "1. 睡醒探头"
        case "peekToEmerge": "2. 飞出刘海"
        case "idle": "3. 待机循环"
        case "clickReaction": "4. 点击反馈"
        case "listening": "5. 倾听循环"
        case "speaking": "6. 说话循环"
        case "success": "7. 成功庆祝"
        case "returnToSleep": "8. 返回睡眠"
        default: id
        }
    }

    var playbackDescription: String {
        playback == "loop" ? "循环播放" : "单次播放"
    }
}

enum PetAnimationLoadError: LocalizedError {
    case manifestNotFound(String)
    case invalidGrid
    case sourceNotFound(String)
    case imageDecodeFailed(String)
    case sourceSizeMismatch(expected: String, actual: String)
    case cropFailed(Int)

    var errorDescription: String? {
        switch self {
        case .manifestNotFound(let path):
            "找不到素材清单：\(path)"
        case .invalidGrid:
            "素材清单的行列或帧数无效。"
        case .sourceNotFound(let path):
            "找不到动作表：\(path)"
        case .imageDecodeFailed(let path):
            "无法读取动作表：\(path)"
        case .sourceSizeMismatch(let expected, let actual):
            "动作表尺寸不一致，清单为 \(expected)，实际为 \(actual)。"
        case .cropFailed(let index):
            "第 \(index + 1) 帧切取失败。"
        }
    }
}

enum ProportionalFrameSlicer {
    static func cropRects(
        imageWidth: Int,
        imageHeight: Int,
        columns: Int,
        rows: Int
    ) throws -> [CGRect] {
        guard imageWidth > 0, imageHeight > 0, columns > 0, rows > 0 else {
            throw PetAnimationLoadError.invalidGrid
        }

        return (0..<(columns * rows)).map { index in
            let column = index % columns
            let row = index / columns

            let x0 = Int((Double(column) * Double(imageWidth) / Double(columns)).rounded())
            let x1 = Int((Double(column + 1) * Double(imageWidth) / Double(columns)).rounded())
            let topY0 = Int((Double(row) * Double(imageHeight) / Double(rows)).rounded())
            let topY1 = Int((Double(row + 1) * Double(imageHeight) / Double(rows)).rounded())

            // CGImage.cropping(to:) 使用位图左上角坐标，动作表按上排到下排读取。
            return CGRect(x: x0, y: topY0, width: x1 - x0, height: topY1 - topY0)
        }
    }
}

struct PetAnimationAssetLoader {
    static var defaultManifestURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PrivatePetAssets/Paimon/animation-manifest-v1.json")
    }

    static func loadManifest(from url: URL) throws -> PetAnimationManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PetAnimationLoadError.manifestNotFound(url.path)
        }
        return try JSONDecoder().decode(PetAnimationManifest.self, from: Data(contentsOf: url))
    }

    static func loadFrames(
        definition: PetAnimationDefinition,
        defaultGrid: PetAnimationGrid,
        manifestURL: URL
    ) throws -> [NSImage] {
        let grid = definition.grid ?? defaultGrid
        guard grid.columns * grid.rows == grid.frameCount else {
            throw PetAnimationLoadError.invalidGrid
        }

        let sourceURL = manifestURL
            .deletingLastPathComponent()
            .appendingPathComponent(definition.source)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw PetAnimationLoadError.sourceNotFound(sourceURL.path)
        }
        guard
            let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw PetAnimationLoadError.imageDecodeFailed(sourceURL.path)
        }

        guard sourceImage.width == definition.sourceWidth,
              sourceImage.height == definition.sourceHeight else {
            throw PetAnimationLoadError.sourceSizeMismatch(
                expected: "\(definition.sourceWidth)×\(definition.sourceHeight)",
                actual: "\(sourceImage.width)×\(sourceImage.height)"
            )
        }

        let cropRects = try ProportionalFrameSlicer.cropRects(
            imageWidth: sourceImage.width,
            imageHeight: sourceImage.height,
            columns: grid.columns,
            rows: grid.rows
        )

        return try cropRects.enumerated().map { index, rect in
            guard let frame = sourceImage.cropping(to: rect) else {
                throw PetAnimationLoadError.cropFailed(index)
            }
            return NSImage(
                cgImage: frame,
                size: NSSize(width: frame.width, height: frame.height)
            )
        }
    }
}

@MainActor
final class PetAnimationPlayerModel: ObservableObject {
    @Published private(set) var manifest: PetAnimationManifest?
    @Published private(set) var manifestURL: URL?
    @Published private(set) var frames: [NSImage] = []
    @Published private(set) var selectedAnimation: PetAnimationDefinition?
    @Published private(set) var currentFrame = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var statusMessage = "正在读取素材…"

    private var playbackTask: Task<Void, Never>?

    var animations: [PetAnimationDefinition] {
        manifest?.animations ?? []
    }

    var currentImage: NSImage? {
        frames.indices.contains(currentFrame) ? frames[currentFrame] : nil
    }

    init() {
        loadManifest(from: PetAnimationAssetLoader.defaultManifestURL)
    }

    deinit {
        playbackTask?.cancel()
    }

    func loadManifest(from url: URL) {
        pause()
        do {
            let loadedManifest = try PetAnimationAssetLoader.loadManifest(from: url)
            manifest = loadedManifest
            manifestURL = url
            statusMessage = "已读取 \(loadedManifest.animations.count) 组动作"

            let preferred = loadedManifest.animations.first(where: { $0.id == "idle" })
                ?? loadedManifest.animations.first
            if let preferred {
                selectAnimation(preferred)
            }
        } catch {
            manifest = nil
            manifestURL = nil
            frames = []
            selectedAnimation = nil
            statusMessage = error.localizedDescription
        }
    }

    func selectAnimation(_ definition: PetAnimationDefinition) {
        pause()
        guard let manifest, let manifestURL else { return }

        do {
            frames = try PetAnimationAssetLoader.loadFrames(
                definition: definition,
                defaultGrid: manifest.grid,
                manifestURL: manifestURL
            )
            selectedAnimation = definition
            currentFrame = 0
            statusMessage = "切帧成功：\(frames.count) 帧"
            play()
        } catch {
            frames = []
            selectedAnimation = definition
            currentFrame = 0
            statusMessage = error.localizedDescription
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !frames.isEmpty, let definition = selectedAnimation else { return }
        if currentFrame == frames.count - 1, definition.playback != "loop" {
            currentFrame = 0
        }
        isPlaying = true
        startPlaybackTask(fps: definition.fps)
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func restart() {
        pause()
        currentFrame = 0
        play()
    }

    func showPreviousFrame() {
        pause()
        guard !frames.isEmpty else { return }
        currentFrame = (currentFrame - 1 + frames.count) % frames.count
    }

    func showNextFrame() {
        pause()
        guard !frames.isEmpty else { return }
        currentFrame = (currentFrame + 1) % frames.count
    }

    private func startPlaybackTask(fps: Int) {
        playbackTask?.cancel()
        let interval = UInt64(1_000_000_000 / max(fps, 1))

        playbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard let self, self.isPlaying else { return }
                self.advancePlaybackFrame()
            }
        }
    }

    private func advancePlaybackFrame() {
        guard !frames.isEmpty, let definition = selectedAnimation else {
            pause()
            return
        }

        if currentFrame + 1 < frames.count {
            currentFrame += 1
        } else if definition.playback == "loop" {
            currentFrame = 0
        } else {
            pause()
        }
    }
}
