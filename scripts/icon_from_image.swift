// Turns Resources/IconSource.png (a square logo on a flat sage background) into a 1024x1024
// macOS icon: a rounded square with 100px transparent margin and a soft drop shadow. Usage: swift icon_from_image.swift <source.png> <output.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write(Data("usage: icon_from_image <source.png> <output.png>\n".utf8)); exit(1)
}

// The source is a logo on a flat sage background. It is drawn centred on a sage tile,
// scaled so the source covers `cover` of the tile width (0.9 puts this logo at about
// 74% of the tile). Below 1 the background is padded; above 1 it is cropped.
let cover: CGFloat = 0.9

let canvas = 1024, inner: CGFloat = 824
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
let rect = CGRect(x: (CGFloat(canvas) - inner) / 2, y: (CGFloat(canvas) - inner) / 2 - 6, width: inner, height: inner)
let sage = CGColor(red: 0.91, green: 0.933, blue: 0.89, alpha: 1)
let radius = inner * 0.2237
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.28))
ctx.addPath(path); ctx.setFillColor(sage); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path); ctx.clip()
ctx.setFillColor(sage); ctx.fill(rect)
let side = inner * cover
ctx.draw(img, in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
ctx.restoreGState()

let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
