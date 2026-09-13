import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Pure ImageIO wrapper — no UIKit or AppKit, so it compiles and runs on
/// watchOS too. Downscales on save (bounded memory and sync cost) and decodes
/// once per display with a small cache so scrolling tiles do not re-decode.
nonisolated enum RecipeImage {

    /// Produces an orientation-corrected JPEG no larger than `maxPixelSize` on
    /// its longest side. Never upscales: a source already under the bound is
    /// returned as-is in the same orientation-corrected form. Returns nil for
    /// data ImageIO cannot read.
    static func downscaled(_ data: Data, maxPixelSize: Int = 1024) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Decodes stored bytes to a displayable `CGImage`. Returns nil for
    /// unreadable data.
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Keyed by object-ID URI plus byte count, which is enough to invalidate
    /// on the only realistic change: a same-size byte-identical replacement
    /// is the sole miss case, and it is negligible.
    private static let cache = NSCache<NSString, CGImage>()

    static func cachedDecode(data: Data, cacheKey: String) -> CGImage? {
        let key = "\(cacheKey)#\(data.count)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = decode(data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
