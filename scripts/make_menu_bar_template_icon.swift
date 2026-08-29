#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconBuildError: LocalizedError {
    case usage
    case unreadableSource
    case missingVisiblePixels
    case renderFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            "用法：make_menu_bar_template_icon.swift <source.png> <output.png>"
        case .unreadableSource:
            "无法读取源 PNG"
        case .missingVisiblePixels:
            "源图中没有可用的深色图形"
        case .renderFailed:
            "无法渲染菜单栏图标"
        case .writeFailed:
            "无法写入菜单栏图标"
        }
    }
}

private let outputPixels = 36
private let contentPixels = 32

func loadImage(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw IconBuildError.unreadableSource
    }
    return image
}

func makeTemplateMask(from source: CGImage) throws -> (CGImage, CGRect) {
    let width = source.width
    let height = source.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
    ), let data = context.data else {
        throw IconBuildError.renderFailed
    }

    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = data.assumingMemoryBound(to: UInt8.self)
    var minimumX = width
    var minimumY = height
    var maximumX = -1
    var maximumY = -1

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let sourceAlpha = CGFloat(pixels[offset + 3]) / 255
            let red = CGFloat(pixels[offset]) / 255
            let green = CGFloat(pixels[offset + 1]) / 255
            let blue = CGFloat(pixels[offset + 2]) / 255
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

            // macOS template images only use alpha. Dark character pixels become
            // the glyph; white eye highlights become transparent cut-outs.
            let darkness = max(0, min(1, (0.92 - luminance) / 0.82))
            let alpha = UInt8((sourceAlpha * darkness * 255).rounded())
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = alpha

            if alpha > 12 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
    }

    guard maximumX >= minimumX, maximumY >= minimumY,
          let image = context.makeImage() else {
        throw IconBuildError.missingVisiblePixels
    }
    return (
        image,
        CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    )
}

func renderIcon(mask: CGImage, bounds: CGRect) throws -> CGImage {
    guard let cropped = mask.cropping(to: bounds),
          let context = CGContext(
              data: nil,
              width: outputPixels,
              height: outputPixels,
              bitsPerComponent: 8,
              bytesPerRow: outputPixels * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                  | CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw IconBuildError.renderFailed
    }

    let scale = min(
        CGFloat(contentPixels) / bounds.width,
        CGFloat(contentPixels) / bounds.height
    )
    let drawSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    let drawRect = CGRect(
        x: (CGFloat(outputPixels) - drawSize.width) / 2,
        y: (CGFloat(outputPixels) - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    context.interpolationQuality = .high
    context.draw(cropped, in: drawRect)
    guard let result = context.makeImage() else { throw IconBuildError.renderFailed }
    return result
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw IconBuildError.writeFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconBuildError.writeFailed
    }
}

do {
    guard CommandLine.arguments.count == 3 else { throw IconBuildError.usage }
    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let source = try loadImage(at: inputURL)
    let (mask, bounds) = try makeTemplateMask(from: source)
    let icon = try renderIcon(mask: mask, bounds: bounds)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try writePNG(icon, to: outputURL)
    print("已生成 \(outputPixels)x\(outputPixels) @2x 菜单栏模板图标：\(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
