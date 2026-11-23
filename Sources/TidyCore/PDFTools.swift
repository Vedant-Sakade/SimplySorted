import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum PDFToolsError: LocalizedError {
    case cannotOpen(String)
    case locked(String)
    case badRange(String)
    case cannotWrite(String)
    case nothingToDo(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let n): "\(n) could not be opened as a PDF."
        case .locked(let n): "\(n) is password protected. Unlock it first."
        case .badRange(let r): "\"\(r)\" is not a valid page range. Use something like 1-3, 5, 8-10."
        case .cannotWrite(let n): "Could not save \(n)."
        case .nothingToDo(let m): m
        }
    }
}

public struct CompressResult: Sendable {
    public let output: URL?        // nil when the result would not be smaller, so nothing was saved
    public let before: Int64
    public let after: Int64
}

public enum PDFTools {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw PDFToolsError.cannotOpen(url.lastPathComponent) }
        if doc.isLocked { throw PDFToolsError.locked(url.lastPathComponent) }
        return doc
    }

    public static func pageCount(of url: URL) -> Int? {
        PDFDocument(url: url)?.pageCount
    }

    // MARK: Merge

    /// Joins PDFs in the given order into one new file.
    public static func merge(_ urls: [URL], to output: URL) throws {
        guard urls.count >= 2 else { throw PDFToolsError.nothingToDo("Choose at least two PDFs to merge.") }
        let merged = PDFDocument()
        for url in urls {
            let doc = try open(url)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: merged.pageCount)
            }
        }
        guard merged.write(to: output) else { throw PDFToolsError.cannotWrite(output.lastPathComponent) }
    }

    // MARK: Split

    /// Turns "1-3, 5, 8-10" into 1-based ranges, checked against the page count.
    public static func parseRanges(_ text: String, pageCount: Int) throws -> [ClosedRange<Int>] {
        let pieces = text.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw PDFToolsError.badRange(text) }
        var result: [ClosedRange<Int>] = []
        for piece in pieces {
            let bounds = piece.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard bounds.count <= 2, let first = Int(bounds[0]) else { throw PDFToolsError.badRange(piece) }
            let last = bounds.count == 2 ? Int(bounds[1]) : first
            guard let last, first >= 1, last >= first, last <= pageCount else { throw PDFToolsError.badRange(piece) }
            result.append(first...last)
        }
        return result
    }

    public enum SplitMode: Sendable {
        case everyPage
        case ranges([ClosedRange<Int>])   // 1-based, each range becomes one file
    }

    /// Writes the pieces into `folder` and returns their URLs. Never overwrites.
    public static func split(_ url: URL, mode: SplitMode, into folder: URL) throws -> [URL] {
        let doc = try open(url)
        let base = url.deletingPathExtension().lastPathComponent
        let ranges: [ClosedRange<Int>]
        switch mode {
        case .everyPage: ranges = (1...max(doc.pageCount, 1)).map { $0...$0 }
        case .ranges(let r): ranges = r
        }
        guard doc.pageCount > 0 else { throw PDFToolsError.nothingToDo("This PDF has no pages.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var outputs: [URL] = []
        for range in ranges {
            let piece = PDFDocument()
            for number in range {
                guard let page = doc.page(at: number - 1)?.copy() as? PDFPage else { continue }
                piece.insert(page, at: piece.pageCount)
            }
            let label = range.count == 1 ? "page \(range.lowerBound)" : "pages \(range.lowerBound)-\(range.upperBound)"
            let out = unique(folder.appendingPathComponent("\(base) - \(label).pdf"))
            guard piece.write(to: out) else { throw PDFToolsError.cannotWrite(out.lastPathComponent) }
            outputs.append(out)
        }
        return outputs
    }

    // MARK: Compress

    /// Shrinks a PDF by turning each page into a JPEG image. Text stops being selectable, so this suits
    /// scans and picture-heavy files. If the result is not smaller, nothing is saved.
    public static func compress(_ url: URL, quality: Double, dpi: Double, to output: URL) throws -> CompressResult {
        let doc = try open(url)
        guard doc.pageCount > 0 else { throw PDFToolsError.nothingToDo("This PDF has no pages.") }
        let before = ImageTools.fileSize(url)
        let scale = max(dpi, 36) / 72.0

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("tidyup-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        var firstBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: temp as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
            throw PDFToolsError.cannotWrite(output.lastPathComponent)
        }

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let pixelW = max(Int(bounds.width * scale), 1), pixelH = max(Int(bounds.height * scale), 1)
            guard let bitmap = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
            bitmap.scaleBy(x: scale, y: scale)
            bitmap.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .cropBox, to: bitmap)
            guard let raster = bitmap.makeImage(), let jpeg = jpegData(raster, quality: quality),
                  let provider = CGDataProvider(data: jpeg as CFData),
                  let embedded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { continue }
            var box = CGRect(origin: .zero, size: bounds.size)
            pdf.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            pdf.draw(embedded, in: box)
            pdf.endPDFPage()
        }
        pdf.closePDF()

        let after = ImageTools.fileSize(temp)
        guard after > 0, after < before else { return CompressResult(output: nil, before: before, after: after) }
        try FileManager.default.moveItem(at: temp, to: output)
        return CompressResult(output: output, before: before, after: after)
    }

    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// "name.pdf" -> "name 2.pdf" if taken.
    public static func unique(_ url: URL) -> URL {
        var candidate = url
        var n = 2
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
