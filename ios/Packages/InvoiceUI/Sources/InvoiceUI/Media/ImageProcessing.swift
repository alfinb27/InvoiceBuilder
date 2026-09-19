import CoreGraphics
import Foundation
import ImageIO
import InvoiceCore
import UniformTypeIdentifiers

/// Prepares logos and signatures for storage (`spec/setup.md` §9): orientation applied, longest side ≤ 1024 px,
/// PNG when transparent, otherwise JPEG, at most 300 KB. Re-encoding also drops EXIF metadata such as GPS.
enum ImageProcessing {
    static let maxPixelSize = 1024
    static let maxBytes = 300 * 1024
    static let jpegQualities = [0.85, 0.7, 0.55, 0.4]

    struct UnreadableImage: Error {}

    /// A logo from any image the system can decode. Runs off the main actor.
    static func logo(from data: Data) async throws -> ImagePayload {
        try await Task.detached(priority: .userInitiated) { try encodeLogo(data) }.value
    }

    static func encodeLogo(_ data: Data) throws -> ImagePayload {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              var image = thumbnail(source) else { throw UnreadableImage() }
        let transparent = hasTransparency(image)
        while true {
            if transparent {
                if let png = encode(image, as: .png), png.count <= maxBytes {
                    return ImagePayload(mime: ImagePayload.png, data: png)
                }
            } else {
                for quality in jpegQualities {
                    if let jpeg = encode(image, as: .jpeg, quality: quality), jpeg.count <= maxBytes {
                        return ImagePayload(mime: ImagePayload.jpeg, data: jpeg)
                    }
                }
            }
            guard image.width > 32, let smaller = scaled(image, by: 0.75) else { throw UnreadableImage() }
            image = smaller
        }
    }

    /// A signature PNG, scaled down so its longest side is at most 1024 px.
    static func signature(from image: CGImage) throws -> ImagePayload {
        var image = image
        let longest = max(image.width, image.height)
        if longest > maxPixelSize, let smaller = scaled(image, by: Double(maxPixelSize) / Double(longest)) {
            image = smaller
        }
        guard let png = encode(image, as: .png) else { throw UnreadableImage() }
        return ImagePayload(mime: ImagePayload.png, data: png)
    }

    /// Decoded, oriented (EXIF) and no larger than `maxPixelSize` on its longest side. Never upscales.
    static func thumbnail(_ source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// True when any pixel is not fully opaque.
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return true }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func scaled(_ image: CGImage, by factor: Double) -> CGImage? {
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
