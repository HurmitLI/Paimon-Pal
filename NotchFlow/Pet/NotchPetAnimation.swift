import AppKit
import ImageIO

enum NotchPetMotion: String, CaseIterable {
    case sleepToPeek
    case peekToEmerge
    case idle
    case clickReaction
    case listening
    case speaking
    case returnToSleep

    var resourceName: String {
        switch self {
        case .sleepToPeek: "den-sleep-to-peek-transparent-v4"
        case .peekToEmerge: "peek-to-emerge-transparent-v1"
        case .idle: "notch-idle-loop-transparent-v1"
        case .clickReaction: "click-reaction-transparent-v1"
        case .listening: "listening-loop-transparent-v1"
        case .speaking: "speaking-loop-transparent-v1"
        case .returnToSleep: "return-to-sleep-transparent-v1"
        }
    }

    var framesPerSecond: Int {
        switch self {
        case .sleepToPeek, .returnToSleep: 8
        case .peekToEmerge, .clickReaction: 10
        case .idle, .listening, .speaking: 6
        }
    }
}

enum NotchPetAssetError: LocalizedError {
    case missingResource(String)
    case unreadableResource(String)
    case cropFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "缺少宠物动作素材：\(name).png"
        case .unreadableResource(let name): "无法读取宠物动作素材：\(name).png"
        case .cropFailed(let index): "无法切取宠物动作第 \(index + 1) 帧"
        }
    }
}

enum NotchPetFrameSlicer {
    static let columns = 4
    static let rows = 2

    static func cropRects(imageWidth: Int, imageHeight: Int) -> [CGRect] {
        (0..<(columns * rows)).map { index in
            let column = index % columns
            let row = index / columns
            let x0 = Int((Double(column) * Double(imageWidth) / Double(columns)).rounded())
            let x1 = Int((Double(column + 1) * Double(imageWidth) / Double(columns)).rounded())
            let y0 = Int((Double(row) * Double(imageHeight) / Double(rows)).rounded())
            let y1 = Int((Double(row + 1) * Double(imageHeight) / Double(rows)).rounded())
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }
}

enum NotchPetOverlayCleaner {
    private static let bytesPerPixel = 4

    /// 生图素材中把黑色“假刘海”和横向托边画进了每一帧。
    /// 这里只清理横跨大半幅画面的暗色连通区，保留派蒙自身的眼睛、围巾和轮廓。
    static func removingGeneratedNotch(from image: CGImage) -> CGImage {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * bytesPerPixel,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let data = context.data
        else {
            return image
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * bytesPerPixel
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let pixelCount = width * height
        var dark = Array(repeating: false, count: pixelCount)
        var seeds: [Int] = []

        for y in 0..<height {
            var darkCount = 0
            let rowStart = y * width
            for x in 0..<width {
                let pixelIndex = rowStart + x
                let offset = y * bytesPerRow + x * bytesPerPixel
                let alpha = Int(pixels[offset + 3])
                let maximumChannel = max(
                    Int(pixels[offset]),
                    Int(pixels[offset + 1]),
                    Int(pixels[offset + 2])
                )
                let isDark = alpha > 8 && maximumChannel < 58
                dark[pixelIndex] = isDark
                if isDark { darkCount += 1 }
            }

            if darkCount >= Int(Double(width) * 0.45) {
                for x in 0..<width where dark[rowStart + x] {
                    seeds.append(rowStart + x)
                }
            }
        }

        guard !seeds.isEmpty else { return image }

        var removed = Array(repeating: false, count: pixelCount)
        var queue: [Int] = []
        queue.reserveCapacity(pixelCount / 3)
        for seed in seeds where !removed[seed] {
            removed[seed] = true
            queue.append(seed)
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1

            let x = index % width
            let y = index / width
            for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                for neighborX in max(0, x - 1)...min(width - 1, x + 1) {
                    let neighbor = neighborY * width + neighborX
                    if dark[neighbor], !removed[neighbor] {
                        removed[neighbor] = true
                        queue.append(neighbor)
                    }
                }
            }
        }

        // 有些转场帧的托边带渐变，而且会被手和身体截成几段。
        // 只清理“首尾横跨大半画面”的暗色行，保留角色局部的围巾和眼睛。
        let minimumOverlayPixels = Int(Double(width) * 0.24)
        let minimumOverlaySpan = Int(Double(width) * 0.65)
        for y in 0..<height {
            var overlayPixels: [Int] = []
            overlayPixels.reserveCapacity(width / 2)
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let alpha = Int(pixels[offset + 3])
                let maximumChannel = max(
                    Int(pixels[offset]),
                    Int(pixels[offset + 1]),
                    Int(pixels[offset + 2])
                )
                if alpha > 8 && maximumChannel < 120 {
                    overlayPixels.append(x)
                }
            }

            guard overlayPixels.count >= minimumOverlayPixels,
                  let first = overlayPixels.first,
                  let last = overlayPixels.last,
                  last - first >= minimumOverlaySpan
            else { continue }

            for x in overlayPixels {
                removed[y * width + x] = true
            }
        }

        // 同时清掉 1px 的黑色抗锯齿边，避免留下灰黑细线。
        var expandedRemoval = removed
        for index in 0..<pixelCount where removed[index] {
            let x = index % width
            let y = index / width
            for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                for neighborX in max(0, x - 1)...min(width - 1, x + 1) {
                    expandedRemoval[neighborY * width + neighborX] = true
                }
            }
        }

        for index in 0..<pixelCount where expandedRemoval[index] {
            let y = index / width
            let x = index % width
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        }

        return context.makeImage() ?? image
    }
}

struct NotchPetAssetLoader {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func frames(for motion: NotchPetMotion) throws -> [NSImage] {
        guard let url = bundle.url(
            forResource: motion.resourceName,
            withExtension: "png"
        ) else {
            throw NotchPetAssetError.missingResource(motion.resourceName)
        }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NotchPetAssetError.unreadableResource(motion.resourceName)
        }

        let cleanedFrames = try NotchPetFrameSlicer.cropRects(
            imageWidth: image.width,
            imageHeight: image.height
        ).enumerated().map { index, rect in
            guard let frame = image.cropping(to: rect) else {
                throw NotchPetAssetError.cropFailed(index)
            }
            return NotchPetOverlayCleaner.removingGeneratedNotch(from: frame)
        }
        return cleanedFrames.map { cleanedFrame in
            return NSImage(
                cgImage: cleanedFrame,
                size: NSSize(width: cleanedFrame.width, height: cleanedFrame.height)
            )
        }
    }
}
