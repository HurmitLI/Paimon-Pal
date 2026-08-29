import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift ComposeIconAlpha.swift <artwork.png> <alpha-mask.png> <output.png>\n", stderr)
    exit(2)
}

let artworkURL = URL(fileURLWithPath: CommandLine.arguments[1])
let maskURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let artwork = CIImage(contentsOf: artworkURL),
      let mask = CIImage(contentsOf: maskURL) else {
    fputs("Unable to load artwork or alpha mask.\n", stderr)
    exit(3)
}

guard artwork.extent.integral == mask.extent.integral else {
    fputs("Artwork and alpha mask dimensions must match.\n", stderr)
    exit(4)
}

let filter = CIFilter.blendWithAlphaMask()
filter.inputImage = artwork
filter.maskImage = mask
filter.backgroundImage = CIImage(color: .clear).cropped(to: artwork.extent)

guard let output = filter.outputImage?.cropped(to: artwork.extent) else {
    fputs("Unable to compose output image.\n", stderr)
    exit(5)
}

let context = CIContext(options: [.useSoftwareRenderer: false])
do {
    try context.writePNGRepresentation(
        of: output,
        to: outputURL,
        format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        options: [:]
    )
} catch {
    fputs("Unable to write output PNG: \(error)\n", stderr)
    exit(6)
}
