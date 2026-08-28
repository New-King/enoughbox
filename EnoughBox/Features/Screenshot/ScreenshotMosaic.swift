import CoreImage
import CoreGraphics

enum ScreenshotMosaic {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Pixelates a circular brush stamp at `pixelCenter` with `pixelDiameter` (CGImage space).
    static func applyBrush(
        to image: CGImage,
        pixelCenter: CGPoint,
        pixelDiameter: CGFloat,
        blockSize: CGFloat = 8
    ) -> CGImage {
        let radius = pixelDiameter / 2
        guard radius >= 1 else { return image }

        let crop = CGRect(
            x: pixelCenter.x - radius,
            y: pixelCenter.y - radius,
            width: pixelDiameter,
            height: pixelDiameter
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

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
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }

        canvas.interpolationQuality = .none
        canvas.setBlendMode(.copy)
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        canvas.saveGState()
        let localCenter = CGPoint(x: pixelCenter.x - crop.origin.x, y: pixelCenter.y - crop.origin.y)
        canvas.addEllipse(in: CGRect(
            x: localCenter.x - radius,
            y: localCenter.y - radius,
            width: pixelDiameter,
            height: pixelDiameter
        ))
        canvas.clip()
        canvas.draw(mosaicPiece, in: crop)
        canvas.restoreGState()

        return canvas.makeImage() ?? image
    }
}
