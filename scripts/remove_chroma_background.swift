import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: remove_chroma_background <input.png> <output.png>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
else {
    fputs("Unable to decode input image.\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let byteCount = bytesPerRow * height
let rawPixels = UnsafeMutableRawPointer.allocate(
    byteCount: byteCount,
    alignment: MemoryLayout<UInt8>.alignment
)
rawPixels.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
defer { rawPixels.deallocate() }

let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue

let context = CGContext(
    data: rawPixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
)

guard let context else {
    fputs("Unable to create bitmap context.\n", stderr)
    exit(1)
}

context.interpolationQuality = .none
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

let pixels = rawPixels.assumingMemoryBound(to: UInt8.self)

for offset in stride(from: 0, to: byteCount, by: bytesPerPixel) {
    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    let maxRedBlue = max(red, blue)
    let greenDominance = green - maxRedBlue
    let greenShare = Double(greenDominance) / Double(max(green, 1))

    guard greenDominance > 10, green > 30 else { continue }

    // Remove bright or dark chroma-green background pixels completely.
    if greenShare > 0.62 || (maxRedBlue < 28 && greenDominance > 20) {
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
        continue
    }

    // A partially covered #00FF00 pixel has alpha approximately
    // 255 - (green - max(red, blue)). Recover alpha and decontaminate green.
    var alpha = 255 - greenDominance
    alpha = min(255, max(0, alpha))
    let recoveredRed = min(255, red * 255 / alpha)
    let recoveredBlue = min(255, blue * 255 / alpha)
    let recoveredGreen = min(255, maxRedBlue * 255 / alpha)

    pixels[offset] = UInt8(recoveredRed)
    pixels[offset + 1] = UInt8(recoveredGreen)
    pixels[offset + 2] = UInt8(recoveredBlue)
    pixels[offset + 3] = UInt8(alpha)
}

var fullyTransparentPixels = 0
var translucentPixels = 0
for offset in stride(from: 0, to: byteCount, by: bytesPerPixel) {
    let alpha = pixels[offset + 3]
    if alpha == 0 {
        fullyTransparentPixels += 1
    } else if alpha < 255 {
        translucentPixels += 1
    }
}

guard
    let outputImage = context.makeImage(),
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

let totalPixels = width * height
let transparentPercent = Double(fullyTransparentPixels) / Double(totalPixels) * 100
print("Wrote transparent PNG: \(outputURL.path)")
print(String(format: "Fully transparent: %.2f%%; translucent edge pixels: %d", transparentPercent, translucentPixels))
