import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: align_pet_sprite_sheet <reference-4x2.png> <source-4x4.png> <output.png>\n", stderr)
    exit(2)
}

let referenceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

func loadImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

guard
    let referenceSheet = loadImage(at: referenceURL),
    let sourceSheet = loadImage(at: sourceURL),
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
else {
    fputs("Unable to decode an input image.\n", stderr)
    exit(1)
}

let columns = 4
let sourceRows = 4

func cropRects(width: Int, height: Int, rows: Int) -> [CGRect] {
    (0..<(columns * rows)).map { index in
        let column = index % columns
        let row = index / columns
        let x0 = Int((Double(column) * Double(width) / Double(columns)).rounded())
        let x1 = Int((Double(column + 1) * Double(width) / Double(columns)).rounded())
        let y0 = Int((Double(row) * Double(height) / Double(rows)).rounded())
        let y1 = Int((Double(row + 1) * Double(height) / Double(rows)).rounded())
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

func visibleBounds(of image: CGImage) -> CGRect? {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let byteCount = bytesPerRow * height
    let data = UnsafeMutableRawPointer.allocate(
        byteCount: byteCount,
        alignment: MemoryLayout<UInt8>.alignment
    )
    data.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    defer { data.deallocate() }

    guard let context = CGContext(
        data: data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = data.assumingMemoryBound(to: UInt8.self)
    var minimumX = width
    var minimumY = height
    var maximumX = -1
    var maximumY = -1

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let alpha = Int(pixels[offset + 3])
            // Generated sheets sometimes contain a dark fake notch. The actual
            // character has abundant mid-tone/bright pixels, so ignore near-black
            // pixels when finding the stable character box used for alignment.
            guard alpha > 20, max(red, green, blue) > 78 else { continue }
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

let referenceRects = cropRects(
    width: referenceSheet.width,
    height: referenceSheet.height,
    rows: 2
)
let sourceRects = cropRects(
    width: sourceSheet.width,
    height: sourceSheet.height,
    rows: sourceRows
)

guard
    let referenceFrame = referenceSheet.cropping(to: referenceRects[7]),
    let firstSourceFrame = sourceSheet.cropping(to: sourceRects[0]),
    let referenceBounds = visibleBounds(of: referenceFrame),
    let sourceBounds = visibleBounds(of: firstSourceFrame)
else {
    fputs("Unable to locate the character in the transition frames.\n", stderr)
    exit(1)
}

let cellSize = max(referenceFrame.width, referenceFrame.height)
let outputWidth = cellSize * columns
let outputHeight = cellSize * sourceRows
let bytesPerPixel = 4
let bytesPerRow = outputWidth * bytesPerPixel
let byteCount = bytesPerRow * outputHeight
let outputData = UnsafeMutableRawPointer.allocate(
    byteCount: byteCount,
    alignment: MemoryLayout<UInt8>.alignment
)
outputData.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
defer { outputData.deallocate() }

guard let outputContext = CGContext(
    data: outputData,
    width: outputWidth,
    height: outputHeight,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create output bitmap.\n", stderr)
    exit(1)
}

let widthScale = referenceBounds.width / sourceBounds.width
let heightScale = referenceBounds.height / sourceBounds.height
let scale = min(widthScale, heightScale)
let referenceCenter = CGPoint(x: referenceBounds.midX, y: referenceBounds.midY)
var minimumTranslationX = CGFloat.greatestFiniteMagnitude
var maximumTranslationX = -CGFloat.greatestFiniteMagnitude
var minimumTranslationY = CGFloat.greatestFiniteMagnitude
var maximumTranslationY = -CGFloat.greatestFiniteMagnitude

outputContext.interpolationQuality = .high
for (index, rect) in sourceRects.enumerated() {
    guard let frame = sourceSheet.cropping(to: rect) else {
        fputs("Unable to crop source frame \(index + 1).\n", stderr)
        exit(1)
    }

    guard let frameBounds = visibleBounds(of: frame) else {
        fputs("Unable to locate the character in source frame \(index + 1).\n", stderr)
        exit(1)
    }
    // AI-generated sprite frames do not share a perfectly fixed anchor. Keep
    // one scale for the whole sequence, but translate every frame so its
    // character center remains fixed. This removes the unintended side-to-side
    // twitch while preserving breathing and blinking inside the artwork.
    let translation = CGPoint(
        x: referenceCenter.x - frameBounds.midX * scale,
        y: referenceCenter.y - frameBounds.midY * scale
    )
    minimumTranslationX = min(minimumTranslationX, translation.x)
    maximumTranslationX = max(maximumTranslationX, translation.x)
    minimumTranslationY = min(minimumTranslationY, translation.y)
    maximumTranslationY = max(maximumTranslationY, translation.y)

    let column = index % columns
    // CGImage rows are cropped top-to-bottom, while CGContext destinations are
    // addressed bottom-to-top. Reverse the output row to preserve frame order.
    let sourceRow = index / columns
    let destinationRow = sourceRows - sourceRow - 1
    let cellOrigin = CGPoint(x: column * cellSize, y: destinationRow * cellSize)
    let destination = CGRect(
        x: cellOrigin.x + translation.x,
        y: cellOrigin.y + translation.y,
        width: CGFloat(frame.width) * scale,
        height: CGFloat(frame.height) * scale
    )
    outputContext.draw(frame, in: destination)
}

guard
    let outputImage = outputContext.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        "public.png" as CFString,
        1,
        nil
    )
else {
    fputs("Unable to create output image.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write output PNG.\n", stderr)
    exit(1)
}

print("Reference bounds: \(referenceBounds)")
print("Source bounds: \(sourceBounds)")
print(String(format: "Applied scale %.4f", scale))
print(String(
    format: "Per-frame translation ranges: x %.2f...%.2f, y %.2f...%.2f",
    minimumTranslationX,
    maximumTranslationX,
    minimumTranslationY,
    maximumTranslationY
))
print("Wrote aligned 4x4 sprite sheet: \(outputURL.path)")
