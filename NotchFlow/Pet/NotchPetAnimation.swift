import AppKit
import ImageIO

enum NotchPetMotion: String, CaseIterable {
    case sleepToPeek
    case peekToEmerge
    case idle
    case clickReaction
    case listening
    case speaking
    case successCelebration
    case returnToSleep

    var resourceName: String {
        switch self {
        case .sleepToPeek: "den-sleep-to-peek-transparent-v4"
        case .peekToEmerge: "peek-to-emerge-transparent-v1"
        case .idle: "notch-idle-loop-transparent-v4"
        case .clickReaction: "click-reaction-transparent-v1"
        case .listening: "listening-loop-transparent-v1"
        case .speaking: "speaking-loop-transparent-v1"
        case .successCelebration: "success-celebration-transparent-v1"
        case .returnToSleep: "return-to-sleep-transparent-v1"
        }
    }

    var framesPerSecond: Int {
        switch self {
        case .sleepToPeek, .successCelebration, .returnToSleep: 8
        case .peekToEmerge, .clickReaction: 10
        case .idle: 10
        case .listening, .speaking: 6
        }
    }

    var gridRows: Int {
        self == .idle ? 4 : 2
    }

    var usesStableBodyCanvas: Bool {
        switch self {
        case .idle, .clickReaction, .listening, .speaking, .successCelebration:
            true
        case .sleepToPeek, .peekToEmerge, .returnToSleep:
            false
        }
    }

    var transitionCalibration: NotchPetTransitionCalibration? {
        switch self {
        case .sleepToPeek:
            // 与 peekToEmerge 首帧保持同一头部尺寸和垂直落点。
            .init(referenceFrameIndex: 7, targetContentHeight: 207, bottomInset: 77)
        case .peekToEmerge:
            // 最后一帧必须与待机第一帧同尺寸、同脚底落点。
            .init(referenceFrameIndex: 7, targetContentHeight: 332, bottomInset: 24)
        case .returnToSleep:
            // 第一帧必须与待机最后一帧同尺寸、同脚底落点。
            .init(referenceFrameIndex: 0, targetContentHeight: 332, bottomInset: 24)
        case .idle, .clickReaction, .listening, .speaking, .successCelebration:
            nil
        }
    }

    var transitionZoomCompensation: [CGFloat]? {
        switch self {
        case .sleepToPeek:
            Array(repeating: 0.80, count: 8)
        case .peekToEmerge:
            [0.80, 0.86, 0.88, 0.89, 0.89, 0.92, 0.97, 1.00]
        case .idle, .clickReaction, .listening, .speaking,
             .successCelebration, .returnToSleep:
            nil
        }
    }
}

struct NotchPetTransitionCalibration: Equatable {
    let referenceFrameIndex: Int
    let targetContentHeight: CGFloat
    let bottomInset: CGFloat
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

    static func cropRects(imageWidth: Int, imageHeight: Int, rows: Int = 2) -> [CGRect] {
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

enum NotchPetFrameNormalizer {
    static let canvasSize = CGSize(width: 512, height: 512)
    static let targetContentHeight: CGFloat = 332
    static let maximumContentWidth: CGFloat = 456
    static let bottomInset: CGFloat = 24
    private static let bytesPerPixel = 4

    static func normalizing(_ frames: [CGImage]) -> [CGImage] {
        let measuredFrames = frames.compactMap { frame -> (CGImage, CGRect)? in
            guard let bounds = contentBounds(in: frame) else { return nil }
            return (frame, bounds)
        }
        guard measuredFrames.count == frames.count,
              let representativeHeight = median(measuredFrames.map(\.1.height)),
              let representativeCenterX = median(measuredFrames.map(\.1.midX)),
              let minimumSourceBottom = measuredFrames.map({
                  CGFloat($0.0.height) - $0.1.maxY
              }).min(),
              let maximumFrameContentWidth = measuredFrames.map(\.1.width).max(),
              representativeHeight > 0,
              maximumFrameContentWidth > 0 else { return frames }

        let scale = min(
            targetContentHeight / representativeHeight,
            maximumContentWidth / maximumFrameContentWidth
        )

        return rendering(
            frames,
            scale: scale,
            sourceCenterX: representativeCenterX,
            sourceBottomInset: minimumSourceBottom,
            targetBottomInset: bottomInset
        )
    }

    static func normalizing(
        _ frames: [CGImage],
        transition calibration: NotchPetTransitionCalibration
    ) -> [CGImage] {
        guard frames.indices.contains(calibration.referenceFrameIndex) else { return frames }
        let referenceFrame = frames[calibration.referenceFrameIndex]
        guard let referenceBounds = contentBounds(in: referenceFrame),
              referenceBounds.height > 0 else { return frames }
        let scale = min(
            calibration.targetContentHeight / referenceBounds.height,
            maximumContentWidth / referenceBounds.width
        )
        let sourceBottomInset = CGFloat(referenceFrame.height) - referenceBounds.maxY
        return rendering(
            frames,
            scale: scale,
            sourceCenterX: referenceBounds.midX,
            sourceBottomInset: sourceBottomInset,
            targetBottomInset: calibration.bottomInset
        )
    }

    static func compensatingTransitionZoom(
        _ frames: [CGImage],
        scaleFactors: [CGFloat]
    ) -> [CGImage] {
        guard frames.count == scaleFactors.count else { return frames }
        return zip(frames, scaleFactors).map { frame, requestedScale in
            let scale = min(max(requestedScale, 0.5), 1)
            guard scale < 0.999,
                  let bounds = contentBounds(in: frame),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: frame.width,
                      height: frame.height,
                      bitsPerComponent: 8,
                      bytesPerRow: frame.width * bytesPerPixel,
                      space: colorSpace,
                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                          | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return frame }

            // 生成素材前半段自带镜头近景，头部比待机大约 25%。
            // 以当前可见内容的水平中心和底边为支点收小，既消除大头，
            // 又保留双手趴在刘海边缘以及身体向下露出的原始轨迹。
            let sourceBottomInset = CGFloat(frame.height) - bounds.maxY
            context.interpolationQuality = .high
            context.draw(
                frame,
                in: CGRect(
                    x: bounds.midX * (1 - scale),
                    y: sourceBottomInset * (1 - scale),
                    width: CGFloat(frame.width) * scale,
                    height: CGFloat(frame.height) * scale
                )
            )
            return context.makeImage() ?? frame
        }
    }

    private static func rendering(
        _ frames: [CGImage],
        scale: CGFloat,
        sourceCenterX: CGFloat,
        sourceBottomInset: CGFloat,
        targetBottomInset: CGFloat
    ) -> [CGImage] {
        frames.map { frame in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: Int(canvasSize.width),
                      height: Int(canvasSize.height),
                      bitsPerComponent: 8,
                      bytesPerRow: Int(canvasSize.width) * bytesPerPixel,
                      space: colorSpace,
                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                          | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return frame }

            context.interpolationQuality = .high
            context.draw(
                frame,
                in: CGRect(
                    x: canvasSize.width / 2 - sourceCenterX * scale,
                    // Bitmap rows are measured from the image top, while Core
                    // Graphics draws from the lower-left. A whole action uses
                    // one source anchor and one scale, preserving its original
                    // movement without introducing per-frame size pumping.
                    y: targetBottomInset - sourceBottomInset * scale,
                    width: CGFloat(frame.width) * scale,
                    height: CGFloat(frame.height) * scale
                )
            )
            return context.makeImage() ?? frame
        }
    }

    static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func contentBounds(in image: CGImage) -> CGRect? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
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
              let data = context.data else { return nil }

        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = image.width * bytesPerPixel
        var minimumX = image.width
        var minimumY = image.height
        var maximumX = -1
        var maximumY = -1

        for y in 0..<image.height {
            for x in 0..<image.width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                guard alpha > 8 else { continue }
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
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
            imageHeight: image.height,
            rows: motion.gridRows
        ).enumerated().map { index, rect in
            guard let frame = image.cropping(to: rect) else {
                throw NotchPetAssetError.cropFailed(index)
            }
            return NotchPetOverlayCleaner.removingGeneratedNotch(from: frame)
        }
        let normalizedFrames = motion.usesStableBodyCanvas
            ? NotchPetFrameNormalizer.normalizing(cleanedFrames)
            : motion.transitionCalibration.map {
                NotchPetFrameNormalizer.normalizing(
                    cleanedFrames,
                    transition: $0
                )
            } ?? cleanedFrames
        let presentationFrames = motion.transitionZoomCompensation.map {
            NotchPetFrameNormalizer.compensatingTransitionZoom(
                normalizedFrames,
                scaleFactors: $0
            )
        } ?? normalizedFrames
        return presentationFrames.map { cleanedFrame in
            return NSImage(
                cgImage: cleanedFrame,
                size: NSSize(width: cleanedFrame.width, height: cleanedFrame.height)
            )
        }
    }
}
