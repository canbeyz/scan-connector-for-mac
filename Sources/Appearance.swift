// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics
import ImageIO

enum ScanColorMode: String, Codable, CaseIterable, Identifiable {
    case color, grayscale, text
    var id: String { rawValue }
    var title: String {
        switch self { case .color: return "Color"; case .grayscale: return "Grayscale"; case .text: return "Text (B&W)" }
    }
}

struct ScanAppearance: Equatable {
    var mode: ScanColorMode = .color
    var enhance = true
    var density = 0
    var contrast = 0
    var textThreshold = 180
    static let original = ScanAppearance(enhance:false)
}

enum ScanImageProcessor {
    static func lookup(histogram: [Int], appearance: ScanAppearance) -> [UInt8] {
        let total = histogram.reduce(0,+)
        func percentile(_ fraction: Double) -> Int {
            let target = max(1,Int(Double(total)*fraction)); var sum = 0
            for index in 0..<256 { sum += histogram[index]; if sum >= target { return index } }
            return 255
        }
        var black = 0.0, white = 255.0
        if appearance.enhance && total > 0 {
            // Restore faint ink, without stretching nearly blank pages into noise.
            let candidate = percentile(0.002), high = percentile(0.995)
            if high - candidate >= 35 { black = Double(min(candidate,160)); white = Double(max(high,220)) }
        }
        let gamma = pow(2.0,Double(min(50,max(-50,appearance.density)))/35.0)
        let contrast = pow(2.0,Double(min(50,max(-50,appearance.contrast)))/50.0)
        return (0..<256).map { value in
            var v = min(1,max(0,(Double(value)-black)/(white-black)))
            v = min(1,max(0,(v-0.5)*contrast+0.5))
            return UInt8(min(255,max(0,Int((pow(v,gamma)*255).rounded()))))
        }
    }

    static func process(_ image: CGImage, appearance: ScanAppearance) throws -> CGImage {
        if appearance == .original { return image }
        let width = image.width, height = image.height
        guard width > 0, height > 0, width * height <= 100_000_000,
              let space = CGColorSpace(name:CGColorSpace.sRGB),
              let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,
                    bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let raw = context.data else { throw ScanFailure.message("Could not prepare image processing. Lower the resolution and try again.") }
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        let pixels = raw.assumingMemoryBound(to:UInt8.self)
        func luminance(_ p: Int) -> Int { (54*Int(pixels[p])+183*Int(pixels[p+1])+19*Int(pixels[p+2])+128)>>8 }
        var histogram = [Int](repeating:0,count:256)
        for i in 0..<(width*height) { histogram[luminance(i*4)] += 1 }
        let lut = lookup(histogram:histogram,appearance:appearance)
        if appearance.mode == .color {
            for i in 0..<(width*height) { let p=i*4; pixels[p]=lut[Int(pixels[p])];pixels[p+1]=lut[Int(pixels[p+1])];pixels[p+2]=lut[Int(pixels[p+2])] }
            guard let result = context.makeImage() else { throw ScanFailure.message("Could not save the color scan image.") }; return result
        }
        let binary = appearance.mode == .text
        let row = binary ? (width+7)/8 : width
        var output = Data(repeating:binary ? 255 : 0,count:row*height)
        output.withUnsafeMutableBytes { bytes in
            let buffer = bytes.bindMemory(to:UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let value = lut[luminance((y*width+x)*4)]
                if binary { if value < appearance.textThreshold { buffer[y*row+x/8] &= ~(UInt8(128) >> (x%8)) } }
                else { buffer[y*row+x] = value }
            } }
        }
        guard let provider = CGDataProvider(data:output as CFData),
              let result = CGImage(width:width,height:height,bitsPerComponent:binary ? 1 : 8,bitsPerPixel:binary ? 1 : 8,
                  bytesPerRow:row,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,
                  decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { throw ScanFailure.message("Could not save the grayscale or text scan image.") }
        return result
    }
}
