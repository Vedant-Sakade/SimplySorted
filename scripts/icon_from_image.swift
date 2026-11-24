// Turns Resources/IconSource.png (a square logo on a flat sage background) into a 1024x1024
// macOS icon: centre of the image scaled into a rounded square, 100px transparent margin,
// soft drop shadow. Usage: swift icon_from_image.swift <source.png> <output.png>
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

// Keep the central 84% of the source so the logo fills about 80% of the tile
// (the flat background makes any crop safe). Works for any square source size.
let side = CGFloat(min(img.width, img.height)) * 0.84
let crop = CGRect(x: (CGFloat(img.width) - side) / 2, y: (CGFloat(img.height) - side) / 2, width: side, height: side)
guard let tile = img.cropping(to: crop) else { exit(1) }

let canvas = 1024, inner: CGFloat = 824
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
let rect = CGRect(x: (CGFloat(canvas) - inner) / 2, y: (CGFloat(canvas) - inner) / 2 - 6, width: inner, height: inner)
let radius = inner * 0.2237
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.28))
ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.91, green: 0.933, blue: 0.89, alpha: 1)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path); ctx.clip()
ctx.draw(tile, in: rect)
ctx.restoreGState()

let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
