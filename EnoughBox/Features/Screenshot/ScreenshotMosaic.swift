import CoreImage
import CoreGraphics

enum ScreenshotMosaic {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Pixelates `pixelRect` (CGImage space) using Core Image `CIPixellate`.
    static func apply(to image: CGImage, pixelRect: CGRect, blockSize: CGFloat = 12) -> CGImage {
        let crop = pixelRect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard crop.width >= 2, crop.height >= 2, let piece = image.cropping(to: crop) else { return image }
        let ciImage = CIImage(cgImage: piece)
        guard let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage,
              let mosaicPiece = context.createCGImage(output, from: ciImage.extent),
              let canvas = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }
        canvas.interpolationQuality = .none
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        canvas.draw(mosaicPiece, in: crop)
        return canvas.makeImage() ?? image
    }
}
