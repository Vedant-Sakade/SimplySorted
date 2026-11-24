import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png, heic

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        }
    }
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        }
    }
    /// PNG is lossless, so the quality slider does nothing for it.
    public var usesQuality: Bool { self != .png }
}

/// How an image's pixel size changes.
public enum ResizeMode: Equatable, Sendable {
    case original
    /// Fraction of the original size, 0.01 ... 4.0 (0.5 = half the width and height, 2 = double).
    case percent(Double)
    /// Fit inside a width / height box, keeping the shape. Either side may be nil (no limit).
    case fit(width: Int?, height: Int?)

    /// Output is never made larger than this on its longest side (keeps memory and file size sane).
    public static let maxOutputSide = 16_000
    public static let maxPercent = 4.0

    /// The output size for an image of `width` x `height` pixels (after rotation is applied).
    /// Without `allowEnlarge` the image is only ever made smaller.
    public func targetSize(width: Int, height: Int, allowEnlarge: Bool = false) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (width, height) }
        var scale = 1.0
        switch self {
        case .original:
            break
        case .percent(let p):
            scale = min(max(p, 0.01), Self.maxPercent)
        case .fit(let w, let h):
            var limits: [Double] = []
            if let w, w > 0 { limits.append(Double(w) / Double(width)) }
            if let h, h > 0 { limits.append(Double(h) / Double(height)) }
            if let tightest = limits.min() { scale = tightest }
        }
        if !allowEnlarge { scale = min(scale, 1) }
        if scale > 1 {
            // Cap the longest side; never shrink an image below its own size because of the cap.
            scale = max(1, min(scale, Double(Self.maxOutputSide) / Double(max(width, height))))
        }
        if scale == 1 { return (width, height) }
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// True when the size asked for is bigger than the 16,000 px limit allows.
    public func isCapped(width: Int, height: Int, allowEnlarge: Bool) -> Bool {
        guard allowEnlarge else { return false }
        let wanted = uncappedSize(width: width, height: height)
        return max(wanted.width, wanted.height) > Self.maxOutputSide
    }

    private func uncappedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        var scale = 1.0
        switch self {
        case .original: break
        case .percent(let p): scale = min(max(p, 0.01), Self.maxPercent)
        case .fit(let w, let h):
            var limits: [Double] = []
            if let w, w > 0 { limits.append(Double(w) / Double(width)) }
            if let h, h > 0 { limits.append(Double(h) / Double(height)) }
            if let tightest = limits.min() { scale = tightest }
        }
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}

public struct ImageOptions: Sendable {
    public var format: ImageFormat
    /// 0.1 ... 1.0 (JPEG / HEIC only)
    public var quality: Double
    /// Pixel size change: original, a percentage, or a width / height box.
    public var resize: ResizeMode
    /// Drops EXIF, GPS location and other metadata.
    public var stripMetadata: Bool
    /// Lets the size grow past the original. Off, images only ever shrink.
    public var allowEnlarge: Bool
    /// Gently sharpens an enlarged image (enlarging makes pictures slightly soft).
    public var sharpen: Bool

    /// Longest side in pixels (shortcut for a square `fit` box). nil keeps the original size.
    public var maxDimension: Int? {
        get { if case .fit(let w, let h) = resize, w == h { return w } else { return nil } }
        set { resize = newValue.map { .fit(width: $0, height: $0) } ?? .original }
    }

    public init(format: ImageFormat = .jpeg, quality: Double = 0.8, maxDimension: Int? = nil,
                resize: ResizeMode? = nil, stripMetadata: Bool = false,
                allowEnlarge: Bool = false, sharpen: Bool = false) {
        self.format = format
        self.quality = quality
        self.resize = resize ?? maxDimension.map { .fit(width: $0, height: $0) } ?? .original
        self.stripMetadata = stripMetadata
        self.allowEnlarge = allowEnlarge
        self.sharpen = sharpen
    }
}

public struct ImageResult: Sendable {
    public let source: URL
    public let output: URL
    public let inputBytes: Int64
    public let outputBytes: Int64

    public init(source: URL, output: URL, inputBytes: Int64, outputBytes: Int64) {
        self.source = source; self.output = output; self.inputBytes = inputBytes; self.outputBytes = outputBytes
    }
}

/// What a batch conversion produced.
public struct BatchOutcome: Sendable {
    public var results: [ImageResult] = []
    public var errors: [String] = []
    /// True when the batch was stopped before every file was done.
    public var cancelled = false
    public var total = 0
    /// Files that were started (converted or failed).
    public var completed: Int { results.count + errors.count }
}

public enum ImageToolsError: LocalizedError {
    case cannotRead(String)
    case cannotWrite(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRead(let n): "\(n) is not an image this Mac can read."
        case .cannotWrite(let n): "Could not save \(n)."
        case .unsupported(let f): "This Mac cannot write \(f) files."
        }
    }
}

public enum ImageTools {
    /// Converts, resizes and compresses one image. The original is never changed or deleted.
    public static func convert(_ source: URL, options: ImageOptions, outputFolder: URL? = nil) throws -> ImageResult {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ImageToolsError.cannotRead(source.lastPathComponent)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        guard let (width, height) = orientedSize(of: props) else { throw ImageToolsError.cannotRead(source.lastPathComponent) }

        // Always decode through the thumbnail path so camera rotation is baked into the pixels
        // (needed when metadata is stripped) and resizing uses high-quality scaling.
        let target = options.resize.targetSize(width: width, height: height, allowEnlarge: options.allowEnlarge)
        let enlarging = target.width > width || target.height > height
        // The decoder can only shrink, so when enlarging it decodes at full size and we scale up below.
        let decodeSide = enlarging ? max(width, height) : max(target.width, target.height)
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeSide,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(src, 0, decodeOptions as CFDictionary) else {
            throw ImageToolsError.cannotRead(source.lastPathComponent)
        }
        if enlarging {
            guard let bigger = upscale(image, toWidth: target.width, height: target.height, sharpen: options.sharpen) else {
                throw ImageToolsError.cannotWrite(source.lastPathComponent)
            }
            image = bigger
        } else if options.resize != .original, (image.width != target.width || image.height != target.height),
                  abs(image.width - target.width) <= 2, abs(image.height - target.height) <= 2,
                  let exact = redraw(image, width: target.width, height: target.height) {
            // The decoder fixes the longest side; nudge the other side so the size is exactly what was asked for.
            image = exact
        }
        if options.format == .jpeg, hasAlpha(image) {
            image = flattenOnWhite(image) ?? image
        }

        var destProps: [CFString: Any] = [:]
        if !options.stripMetadata {
            destProps = props.filter { $0.key != kCGImagePropertyPixelWidth && $0.key != kCGImagePropertyPixelHeight }
            destProps[kCGImagePropertyOrientation] = 1   // rotation is already in the pixels
            if var tiff = destProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                destProps[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        if options.format.usesQuality {
            destProps[kCGImageDestinationLossyCompressionQuality] = min(max(options.quality, 0.05), 1.0)
        }

        let folder = outputFolder ?? source.deletingLastPathComponent()
        let output = outputURL(for: source, format: options.format, folder: folder, sameFolder: outputFolder == nil)
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, options.format.type.identifier as CFString, 1, nil) else {
            throw ImageToolsError.unsupported(options.format.title)
        }
        CGImageDestinationAddImage(dest, image, destProps as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: output)
            throw ImageToolsError.cannotWrite(output.lastPathComponent)
        }
        return ImageResult(source: source, output: output, inputBytes: fileSize(source), outputBytes: fileSize(output))
    }

    /// Converts a list of images one after another, reporting progress after each one.
    /// `isCancelled` is checked before every file, so a cancel stops cleanly between pictures.
    public static func convertBatch(_ files: [URL], options: ImageOptions, outputFolder: URL? = nil,
                                    isCancelled: () -> Bool = { false },
                                    progress: (_ completed: Int, _ total: Int) -> Void = { _, _ in }) -> BatchOutcome {
        var outcome = BatchOutcome()
        outcome.total = files.count
        for file in files {
            if isCancelled() { outcome.cancelled = true; break }
            do { outcome.results.append(try convert(file, options: options, outputFolder: outputFolder)) }
            catch { outcome.errors.append(error.localizedDescription) }
            progress(outcome.completed, files.count)
        }
        return outcome
    }

    static func outputURL(for source: URL, format: ImageFormat, folder: URL, sameFolder: Bool) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let sameType = source.pathExtension.lowercased() == format.fileExtension
            || (format == .jpeg && source.pathExtension.lowercased() == "jpeg")
        // Re-saving a JPEG next to the original must not clash with it.
        let stem = (sameFolder && sameType) ? "\(base)-optimized" : base
        var candidate = folder.appendingPathComponent("\(stem).\(format.fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(n).\(format.fileExtension)")
            n += 1
        }
        return candidate
    }

    /// Pixel size of an image as it is displayed (camera rotation applied), or nil if unreadable.
    public static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        guard let size = orientedSize(of: props) else { return nil }
        return (size.0, size.1)
    }

    static func orientedSize(of props: [CFString: Any]) -> (Int, Int)? {
        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard w > 0, h > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return (5...8).contains(orientation) ? (h, w) : (w, h)
    }

    static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let info = hasAlpha(image) ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: info) ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// High-quality (Lanczos) enlargement to an exact size, optionally followed by a light sharpen.
    static func upscale(_ image: CGImage, toWidth w: Int, height h: Int, sharpen: Bool) -> CGImage? {
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        let sy = Double(h) / Double(image.height)
        let sx = Double(w) / Double(image.width)
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(sy, forKey: kCIInputScaleKey)
        filter.setValue(sx / sy, forKey: kCIInputAspectRatioKey)
        guard var out = filter.outputImage else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        out = out.cropped(to: rect)
        if sharpen, let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(out, forKey: kCIInputImageKey)
            unsharp.setValue(min(3.0, max(1.0, max(sx, sy) * 0.8)), forKey: kCIInputRadiusKey)
            unsharp.setValue(0.6, forKey: kCIInputIntensityKey)
            if let sharpened = unsharp.outputImage { out = sharpened.cropped(to: rect) }
        }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
        guard let result = context.createCGImage(out, from: rect, format: .RGBA8, colorSpace: space) else { return nil }
        // Keep opaque pictures opaque (Core Image always hands back an alpha channel).
        return hasAlpha(image) ? result : (flattenOnWhite(result) ?? result)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Int64(size)
    }
}
