// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ninon

import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("pixelcheck: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 5,
      let red = Int(arguments[1]),
      let green = Int(arguments[2]),
      let blue = Int(arguments[3]),
      let tolerance = Int(arguments[4]),
      [red, green, blue].allSatisfy({ (0...255).contains($0) }),
      (0...255).contains(tolerance) else {
    fail("usage: pixelcheck ONE_PIXEL.png RED GREEN BLUE TOLERANCE")
}

let url = URL(fileURLWithPath: arguments[0])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read PNG")
}
guard image.width == 1, image.height == 1 else {
    fail("expected a 1x1 crop, got \(image.width)x\(image.height)")
}

var bytes = [UInt8](repeating: 0, count: 4)
let sampled = bytes.withUnsafeMutableBytes { storage -> Bool in
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: storage.baseAddress, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
          ) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return true
}
guard sampled else { fail("cannot create sRGB pixel buffer") }
let actual = bytes.prefix(3).map(Int.init)
let expected = [red, green, blue]
guard bytes[3] == 255,
      zip(actual, expected).allSatisfy({ abs($0 - $1) <= tolerance }) else {
    fail("expected RGB \(expected) +/- \(tolerance), got \(actual), alpha \(bytes[3])")
}
