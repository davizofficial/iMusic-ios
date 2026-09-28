import CoreImage
import SwiftUI
import UIKit

/// Average color of an artwork, used for the Now Playing gradient.
@MainActor
enum DominantColor {
    private static var cache: [String: Color] = [:]

    static func color(for urlString: String) async -> Color? {
        if let cached = cache[urlString] { return cached }
        guard let url = URL(string: urlString), !urlString.isEmpty else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else { return nil }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: input,
                                                 kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &bitmap, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let color = Color(red: Double(bitmap[0]) / 255,
                          green: Double(bitmap[1]) / 255,
                          blue: Double(bitmap[2]) / 255)
        cache[urlString] = color
        return color
    }
}
