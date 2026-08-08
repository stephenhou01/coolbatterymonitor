import CoreGraphics
import Foundation
import ImageIO

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("IconAlphaCheck: \(message)\n".utf8))
    exit(1)
}

private func checkIcon(at path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("cannot decode \(path)")
    }

    guard image.width == image.height, image.width > 0 else {
        fail("icon is not a non-empty square: \(path)")
    }

    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue

    let result = pixels.withUnsafeMutableBytes { buffer -> ([UInt8], Int)? in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )

        let corners = [
            3,
            (image.width - 1) * 4 + 3,
            (image.height - 1) * bytesPerRow + 3,
            (image.height - 1) * bytesPerRow + (image.width - 1) * 4 + 3,
        ].map { buffer[$0] }
        let transparentPixels = stride(from: 3, to: buffer.count, by: 4)
            .reduce(into: 0) { count, offset in
                if buffer[offset] == 0 { count += 1 }
            }
        return (corners, transparentPixels)
    }

    guard let (corners, transparentPixels) = result else {
        fail("cannot create RGBA context for \(path)")
    }
    guard corners.allSatisfy({ $0 == 0 }) else {
        fail("background is not transparent at all four corners: \(path), alpha=\(corners)")
    }
    guard transparentPixels > 0 else {
        fail("image has an alpha channel but no transparent pixels: \(path)")
    }

    print("✓ \((path as NSString).lastPathComponent): transparent corners and \(transparentPixels) clear pixels")
}

guard CommandLine.arguments.count > 1 else {
    fail("pass one or more PNG paths")
}

for path in CommandLine.arguments.dropFirst() {
    checkIcon(at: path)
}
