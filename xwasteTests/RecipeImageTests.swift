import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import xwaste

/// `RecipeImage` is pure ImageIO with no Core Data dependency, so fixtures are
/// generated in-process with `CGContext` rather than checked-in image files.
struct RecipeImageTests {

    private func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func encode(_ image: CGImage, orientation: CGImagePropertyOrientation? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation.rawValue
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test("A 3000x2000 input downscales to at most 1024 on the long side")
    func downscalesLargeImage() throws {
        let data = encode(makeImage(width: 3000, height: 2000))

        let downscaled = try #require(RecipeImage.downscaled(data, maxPixelSize: 1024))
        let decoded = try #require(RecipeImage.decode(downscaled))

        #expect(max(decoded.width, decoded.height) <= 1024)
        #expect(decoded.width > decoded.height, "aspect ratio is preserved")
    }

    @Test("A 400x300 input is not upscaled")
    func doesNotUpscaleSmallImage() throws {
        let data = encode(makeImage(width: 400, height: 300))

        let downscaled = try #require(RecipeImage.downscaled(data, maxPixelSize: 1024))
        let decoded = try #require(RecipeImage.decode(downscaled))

        #expect(decoded.width <= 400)
        #expect(decoded.height <= 300)
    }

    @Test("Garbage bytes return nil for both downscaling and decoding")
    func garbageBytesReturnNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        #expect(RecipeImage.downscaled(garbage) == nil)
        #expect(RecipeImage.decode(garbage) == nil)
    }

    @Test("A rotated-by-EXIF input comes out with the visual orientation applied")
    func bakesInExifOrientation() throws {
        // A wide (landscape) source tagged with a 90°-rotation orientation:
        // `kCGImageSourceCreateThumbnailWithTransform` bakes the rotation in,
        // so the output's pixel dimensions come out swapped (tall).
        let data = encode(makeImage(width: 800, height: 400), orientation: .right)

        let downscaled = try #require(RecipeImage.downscaled(data, maxPixelSize: 1024))
        let decoded = try #require(RecipeImage.decode(downscaled))

        #expect(decoded.height > decoded.width, "the baked-in orientation swaps width and height")
    }
}
