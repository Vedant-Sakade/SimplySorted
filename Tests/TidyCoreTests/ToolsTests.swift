import XCTest
import UniformTypeIdentifiers
import AppKit
import PDFKit
@testable import TidyCore

final class ToolsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: helpers

    func makePNG(_ name: String, size: CGSize = CGSize(width: 800, height: 400), text: String? = nil, transparent: Bool = false) throws -> URL {
        let image = NSImage(size: size)
        image.lockFocus()
        if !transparent {
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        }
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1).setFill()
        NSRect(x: 10, y: 10, width: 100, height: 100).fill()
        if let text {
            (text as NSString).draw(at: NSPoint(x: 40, y: size.height / 2),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 60), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let url = dir.appendingPathComponent(name)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func makePDF(_ name: String, pages: Int) throws -> URL {
        let doc = PDFDocument()
        for i in 0..<pages {
            let image = NSImage(size: NSSize(width: 300, height: 400))
            image.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 300, height: 400).fill()
            ("Page \(i + 1)" as NSString).draw(at: NSPoint(x: 20, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 40)])
            image.unlockFocus()
            doc.insert(PDFPage(image: image)!, at: i)
        }
        let url = dir.appendingPathComponent(name)
        XCTAssertTrue(doc.write(to: url))
        return url
    }

    func pixelSize(_ url: URL) -> (Int, Int) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }

    // MARK: Schedule

    func testScheduleDailyDueAfterTime() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }
        var s = Schedule(); s.enabled = true; s.hour = 18; s.minute = 0
        XCTAssertEqual(s.nextRun(after: date(23, 10, 0), calendar: cal), date(23, 18, 0))
        XCTAssertFalse(s.isDue(since: date(23, 10, 0), now: date(23, 17, 59), calendar: cal))
        XCTAssertTrue(s.isDue(since: date(23, 10, 0), now: date(23, 18, 1), calendar: cal))
        // missed for days -> still due once
        XCTAssertTrue(s.isDue(since: date(20, 19, 0), now: date(23, 9, 0), calendar: cal))
        s.enabled = false
        XCTAssertFalse(s.isDue(since: date(20, 19, 0), now: date(23, 19, 0), calendar: cal))
    }

    func testScheduleWeekly() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var s = Schedule(); s.enabled = true; s.frequency = .weekly; s.weekday = 2; s.hour = 9   // Monday 09:00
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10))!   // 23 Nov 2026 is a Monday
        let next = s.nextRun(after: monday, calendar: cal)!
        XCTAssertEqual(cal.component(.weekday, from: next), 2)
        XCTAssertEqual(cal.component(.day, from: next), 30)
    }

    // MARK: Move to

    func testMoveToFolderAndUndo() throws {
        let a = dir.appendingPathComponent("a.txt"); try Data("a".utf8).write(to: a)
        let dest = dir.appendingPathComponent("Dest"); try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: dest.appendingPathComponent("a.txt"))
        let sorter = Sorter(minimumAge: 0)
        let run = sorter.move([a], to: dest)
        XCTAssertEqual(run.moved.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a 2.txt").path))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a.txt")), "old")
        _ = sorter.undo(run)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    func testCannotMoveFolderIntoItself() throws {
        let inner = dir.appendingPathComponent("Parent/Child"); try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let run = Sorter().move([dir.appendingPathComponent("Parent")], to: inner)
        XCTAssertTrue(run.moved.isEmpty)
        XCTAssertEqual(run.failures.count, 1)
    }

    // MARK: Images

    func testConvertPNGToJPEGFlattensTransparency() throws {
        let png = try makePNG("t.png", transparent: true)
        let r = try ImageTools.convert(png, options: ImageOptions(format: .jpeg, quality: 0.7))
        XCTAssertEqual(r.output.pathExtension, "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "original must stay")
        XCTAssertGreaterThan(r.outputBytes, 0)
    }

    func testResizeNeverEnlarges() throws {
        let png = try makePNG("big.png", size: CGSize(width: 800, height: 400))
        let small = try ImageTools.convert(png, options: ImageOptions(format: .png, maxDimension: 200))
        XCTAssertEqual(pixelSize(small.output).0, 200)
        let same = try ImageTools.convert(png, options: ImageOptions(format: .png, maxDimension: 99999))
        XCTAssertEqual(pixelSize(same.output).0, pixelSize(png).0, "an image smaller than the limit must keep its size")
    }

    func testResizeModeMath() {
        XCTAssertTrue(ResizeMode.original.targetSize(width: 4000, height: 3000) == (4000, 3000))
        XCTAssertTrue(ResizeMode.percent(0.5).targetSize(width: 4000, height: 3000) == (2000, 1500))
        XCTAssertTrue(ResizeMode.percent(0.333).targetSize(width: 1000, height: 501) == (333, 167))
        XCTAssertTrue(ResizeMode.percent(2.0).targetSize(width: 400, height: 300) == (400, 300), "percent never enlarges")
        XCTAssertTrue(ResizeMode.percent(0).targetSize(width: 1000, height: 1000) == (10, 10), "percent is clamped to 1%")
        XCTAssertTrue(ResizeMode.fit(width: 800, height: nil).targetSize(width: 4000, height: 3000) == (800, 600))
        XCTAssertTrue(ResizeMode.fit(width: nil, height: 600).targetSize(width: 4000, height: 3000) == (800, 600))
        XCTAssertTrue(ResizeMode.fit(width: 800, height: 300).targetSize(width: 4000, height: 3000) == (400, 300), "the tighter side wins")
        XCTAssertTrue(ResizeMode.fit(width: 9999, height: 9999).targetSize(width: 400, height: 300) == (400, 300), "fit never enlarges")
        XCTAssertTrue(ResizeMode.fit(width: nil, height: nil).targetSize(width: 400, height: 300) == (400, 300))
        XCTAssertTrue(ResizeMode.fit(width: 0, height: -5).targetSize(width: 400, height: 300) == (400, 300), "zero or negative means no limit")
    }

    func testScaleByPercentGivesExactSize() throws {
        let png = try makePNG("pct.png", size: CGSize(width: 800, height: 400))
        let src = pixelSize(png)
        let r = try ImageTools.convert(png, options: ImageOptions(format: .png, resize: .percent(0.5)))
        let out = pixelSize(r.output)
        XCTAssertEqual(out.0, Int((Double(src.0) * 0.5).rounded()))
        XCTAssertEqual(out.1, Int((Double(src.1) * 0.5).rounded()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "original must stay")
    }

    func testFitToWidthKeepsShapeAndHitsRequestedWidth() throws {
        let png = try makePNG("fitw.png", size: CGSize(width: 800, height: 400))
        let src = pixelSize(png)
        let want = src.0 / 4 + 1   // an awkward number on purpose
        let r = try ImageTools.convert(png, options: ImageOptions(format: .png, resize: .fit(width: want, height: nil)))
        let out = pixelSize(r.output)
        XCTAssertEqual(out.0, want, "the width must be exactly what was asked for")
        XCTAssertEqual(Double(out.1), Double(src.1) * Double(want) / Double(src.0), accuracy: 1)
    }

    func testFitToHeightOnTallImageHitsRequestedHeight() throws {
        let png = try makePNG("fith.png", size: CGSize(width: 300, height: 900))
        let src = pixelSize(png)
        let want = src.1 / 3 - 1
        let r = try ImageTools.convert(png, options: ImageOptions(format: .jpeg, resize: .fit(width: nil, height: want)))
        let out = pixelSize(r.output)
        XCTAssertEqual(out.1, want)
        XCTAssertEqual(Double(out.0), Double(src.0) * Double(want) / Double(src.1), accuracy: 1)
    }

    func testPixelSizeReadsUnrotatedImage() throws {
        let png = try makePNG("ps.png", size: CGSize(width: 640, height: 320))
        let size = try XCTUnwrap(ImageTools.pixelSize(of: png))
        XCTAssertEqual(size.width, pixelSize(png).0)
        XCTAssertEqual(size.height, pixelSize(png).1)
        XCTAssertNil(ImageTools.pixelSize(of: dir.appendingPathComponent("missing.png")))
    }

    /// A phone photo is stored sideways with an EXIF "rotate" flag; sizes must follow what the user sees.
    func testSizesFollowCameraRotation() throws {
        let png = try makePNG("sideways-src.png", size: CGSize(width: 600, height: 300))
        let srcImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png as CFURL, nil)!, 0, nil))
        let jpg = dir.appendingPathComponent("sideways.jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(jpg as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, srcImage, [kCGImagePropertyOrientation: 6] as CFDictionary)   // 6 = rotate 90 degrees
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let shown = try XCTUnwrap(ImageTools.pixelSize(of: jpg))
        XCTAssertEqual(shown.width, srcImage.height, "a rotated photo reports its upright width")
        XCTAssertEqual(shown.height, srcImage.width)

        let want = shown.width / 2
        let r = try ImageTools.convert(jpg, options: ImageOptions(format: .jpeg, resize: .fit(width: want, height: nil)))
        let out = pixelSize(r.output)
        XCTAssertEqual(out.0, want, "width limits apply to the upright image")
        XCTAssertGreaterThan(out.1, out.0, "the photo is still taller than it is wide")
    }

    // MARK: Enlarging

    func testEnlargeMath() {
        typealias R = ResizeMode
        XCTAssertTrue(R.percent(2).targetSize(width: 1000, height: 500, allowEnlarge: true) == (2000, 1000))
        XCTAssertTrue(R.percent(2).targetSize(width: 1000, height: 500) == (1000, 500), "without allowEnlarge nothing grows")
        XCTAssertTrue(R.percent(10).targetSize(width: 100, height: 100, allowEnlarge: true) == (400, 400), "percent tops out at 400%")
        XCTAssertTrue(R.fit(width: 2048, height: nil).targetSize(width: 1448, height: 1086, allowEnlarge: true) == (2048, 1536))
        XCTAssertTrue(R.fit(width: 2048, height: 2048).targetSize(width: 1000, height: 500, allowEnlarge: true) == (2048, 1024), "a square box means longest side")
        XCTAssertTrue(R.fit(width: 4000, height: 600).targetSize(width: 1000, height: 500, allowEnlarge: true) == (1200, 600), "tighter side wins when enlarging too")
        XCTAssertTrue(R.fit(width: 2048, height: 2048).targetSize(width: 3000, height: 1000, allowEnlarge: true) == (2048, 683), "a bigger image still shrinks")
        XCTAssertTrue(R.fit(width: nil, height: nil).targetSize(width: 400, height: 300, allowEnlarge: true) == (400, 300))
        XCTAssertTrue(R.original.targetSize(width: 400, height: 300, allowEnlarge: true) == (400, 300))
    }

    func testEnlargeIsCappedAt16000() {
        let t = ResizeMode.fit(width: 40_000, height: nil).targetSize(width: 4000, height: 2000, allowEnlarge: true)
        XCTAssertEqual(t.width, ResizeMode.maxOutputSide)
        XCTAssertEqual(t.height, ResizeMode.maxOutputSide / 2)
        XCTAssertTrue(ResizeMode.fit(width: 40_000, height: nil).isCapped(width: 4000, height: 2000, allowEnlarge: true))
        XCTAssertFalse(ResizeMode.fit(width: 8000, height: nil).isCapped(width: 4000, height: 2000, allowEnlarge: true))
        XCTAssertFalse(ResizeMode.fit(width: 40_000, height: nil).isCapped(width: 4000, height: 2000, allowEnlarge: false))
        // An image already larger than the cap is never shrunk because of it.
        let big = ResizeMode.percent(2).targetSize(width: 20_000, height: 10_000, allowEnlarge: true)
        XCTAssertTrue(big == (20_000, 10_000))
    }

    func testEnlargeToExactWidthForEachFormat() throws {
        let png = try makePNG("small.png", size: CGSize(width: 300, height: 200))
        let src = pixelSize(png)
        let want = src.0 * 2 + 7   // awkward on purpose
        for format in [ImageFormat.png, .jpeg, .heic] {
            let r = try ImageTools.convert(png, options: ImageOptions(format: format, resize: .fit(width: want, height: nil), allowEnlarge: true))
            let out = pixelSize(r.output)
            XCTAssertEqual(out.0, want, "\(format) width")
            XCTAssertEqual(Double(out.1), Double(src.1) * Double(want) / Double(src.0), accuracy: 1, "\(format) keeps the shape")
        }
        XCTAssertEqual(pixelSize(png).0, src.0, "original untouched")
    }

    func testEnlargeByPercentDoublesSize() throws {
        let png = try makePNG("dbl.png", size: CGSize(width: 240, height: 120))
        let src = pixelSize(png)
        let r = try ImageTools.convert(png, options: ImageOptions(format: .png, resize: .percent(2), allowEnlarge: true))
        let out = pixelSize(r.output)
        XCTAssertEqual(out.0, src.0 * 2)
        XCTAssertEqual(out.1, src.1 * 2)
    }

    func testEnlargeOffKeepsImagesSmall() throws {
        let png = try makePNG("keep.png", size: CGSize(width: 240, height: 120))
        let src = pixelSize(png)
        let r = try ImageTools.convert(png, options: ImageOptions(format: .png, resize: .fit(width: 5000, height: nil), allowEnlarge: false))
        XCTAssertEqual(pixelSize(r.output).0, src.0, "Also grow smaller images switched off: stays the same size")
    }

    func testEnlargedOpaqueImageStaysOpaqueAndTransparentKeepsAlpha() throws {
        // A photo (JPEG) has no transparency to begin with.
        let opaque = try ImageTools.convert(try makePNG("op.png", size: CGSize(width: 120, height: 80)), options: ImageOptions(format: .jpeg)).output
        let o = try ImageTools.convert(opaque, options: ImageOptions(format: .png, resize: .percent(2), allowEnlarge: true))
        let oImg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(o.output as CFURL, nil)!, 0, nil))
        XCTAssertFalse(ImageTools.hasAlpha(oImg), "an opaque picture must not gain an alpha channel")

        let clear = try makePNG("tr.png", size: CGSize(width: 120, height: 80), transparent: true)
        let t = try ImageTools.convert(clear, options: ImageOptions(format: .png, resize: .percent(2), allowEnlarge: true))
        let tImg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(t.output as CFURL, nil)!, 0, nil))
        XCTAssertTrue(ImageTools.hasAlpha(tImg), "transparency survives enlarging")
    }

    /// A realistic big job: a 1448 x 1086 picture (like a screenshot or AI image) enlarged to 8K.
    func testEnlargeToEightKIsExactAndReasonablyFast() throws {
        let png = try makePNG("shot.png", size: CGSize(width: 724, height: 543))   // 1448 x 1086 on a Retina Mac
        let src = pixelSize(png)
        let start = Date()
        let r = try ImageTools.convert(png, options: ImageOptions(format: .jpeg, quality: 0.9, resize: .fit(width: 7680, height: nil), allowEnlarge: true, sharpen: true))
        let seconds = Date().timeIntervalSince(start)
        let out = pixelSize(r.output)
        XCTAssertEqual(out.0, 7680)
        XCTAssertEqual(Double(out.1), Double(src.1) * 7680 / Double(src.0), accuracy: 1)
        XCTAssertLessThan(seconds, 20, "an 8K enlarge should take seconds, not minutes (took \(seconds)s)")
        print("8K enlarge took \(String(format: "%.2f", seconds))s, output \(r.outputBytes) bytes")
    }

    func testSharpenChangesTheEnlargedPicture() throws {
        let png = try makePNG("sharp.png", size: CGSize(width: 160, height: 100), text: "Aa")
        let plain = try ImageTools.convert(png, options: ImageOptions(format: .png, resize: .percent(3), allowEnlarge: true, sharpen: false))
        let sharp = try ImageTools.convert(png, options: ImageOptions(format: .png, resize: .percent(3), allowEnlarge: true, sharpen: true))
        XCTAssertEqual(pixelSize(plain.output).0, pixelSize(sharp.output).0, "same size either way")
        XCTAssertNotEqual(try Data(contentsOf: plain.output), try Data(contentsOf: sharp.output), "sharpening must change the pixels")
    }

    func testEnlargeUsesUprightSizeOfSidewaysPhoto() throws {
        let png = try makePNG("side-src2.png", size: CGSize(width: 300, height: 150))
        let srcImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png as CFURL, nil)!, 0, nil))
        let jpg = dir.appendingPathComponent("side2.jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(jpg as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, srcImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let shown = try XCTUnwrap(ImageTools.pixelSize(of: jpg))
        let r = try ImageTools.convert(jpg, options: ImageOptions(format: .jpeg, resize: .fit(width: shown.width * 2, height: nil), allowEnlarge: true))
        let out = pixelSize(r.output)
        XCTAssertEqual(out.0, shown.width * 2)
        XCTAssertEqual(out.1, shown.height * 2)
        XCTAssertGreaterThan(out.1, out.0, "still upright (taller than wide)")
    }

    func testRecompressSameFormatDoesNotOverwriteOriginal() throws {
        let png = try makePNG("p.png")
        let jpg = try ImageTools.convert(png, options: ImageOptions(format: .jpeg)).output
        let again = try ImageTools.convert(jpg, options: ImageOptions(format: .jpeg, quality: 0.3))
        XCTAssertNotEqual(again.output, jpg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpg.path))
    }

    func testHEICWritesIfSupported() throws {
        let png = try makePNG("h.png")
        do {
            let r = try ImageTools.convert(png, options: ImageOptions(format: .heic, quality: 0.6))
            XCTAssertTrue(FileManager.default.fileExists(atPath: r.output.path))
        } catch ImageToolsError.unsupported {
            throw XCTSkip("HEIC writing unavailable here")
        }
    }

    func testUnreadableFileThrows() throws {
        let bad = dir.appendingPathComponent("bad.png"); try Data("not an image".utf8).write(to: bad)
        XCTAssertThrowsError(try ImageTools.convert(bad, options: ImageOptions()))
    }

    // MARK: PDF

    func testParseRanges() throws {
        XCTAssertEqual(try PDFTools.parseRanges("1-3, 5", pageCount: 6), [1...3, 5...5])
        XCTAssertThrowsError(try PDFTools.parseRanges("0-2", pageCount: 6))
        XCTAssertThrowsError(try PDFTools.parseRanges("2-9", pageCount: 6))
        XCTAssertThrowsError(try PDFTools.parseRanges("a", pageCount: 6))
        XCTAssertThrowsError(try PDFTools.parseRanges("3-2", pageCount: 6))
        XCTAssertThrowsError(try PDFTools.parseRanges("", pageCount: 6))
    }

    func testMergeAndSplit() throws {
        let a = try makePDF("a.pdf", pages: 2), b = try makePDF("b.pdf", pages: 3)
        let merged = dir.appendingPathComponent("m.pdf")
        try PDFTools.merge([a, b], to: merged)
        XCTAssertEqual(PDFTools.pageCount(of: merged), 5)
        XCTAssertThrowsError(try PDFTools.merge([a], to: dir.appendingPathComponent("x.pdf")))

        let every = try PDFTools.split(merged, mode: .everyPage, into: dir.appendingPathComponent("every"))
        XCTAssertEqual(every.count, 5)
        let ranges = try PDFTools.split(merged, mode: .ranges([1...2, 5...5]), into: dir.appendingPathComponent("ranges"))
        XCTAssertEqual(ranges.map { PDFTools.pageCount(of: $0) }, [2, 1])
    }

    func testCompressOnlySavesWhenSmaller() throws {
        // A noisy full-colour page compresses well as JPEG at low DPI.
        let doc = PDFDocument()
        let size = NSSize(width: 600, height: 800)
        let image = NSImage(size: size)
        image.lockFocus()
        for _ in 0..<400 {
            NSColor(red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1).setFill()
            NSRect(x: .random(in: 0...550), y: .random(in: 0...750), width: 50, height: 50).fill()
        }
        image.unlockFocus()
        doc.insert(PDFPage(image: image)!, at: 0)
        let src = dir.appendingPathComponent("noisy.pdf"); XCTAssertTrue(doc.write(to: src))
        let out = dir.appendingPathComponent("noisy-small.pdf")
        let r = try PDFTools.compress(src, quality: 0.4, dpi: 72, to: out)
        // The slider now goes up to 100%: that must work and never write a bigger file.
        let best = try PDFTools.compress(src, quality: 1.0, dpi: 200, to: dir.appendingPathComponent("best.pdf"))
        if best.output != nil { XCTAssertLessThan(best.after, best.before) }
        if r.output != nil {
            XCTAssertLessThan(r.after, r.before)
            XCTAssertEqual(PDFTools.pageCount(of: out), 1)
        } else {
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
        }
    }

    // MARK: OCR

    func testRecognizesText() throws {
        let png = try makePNG("text.png", size: CGSize(width: 900, height: 300), text: "Hello TidyUp 2026")
        let text = try TextRecognizer.recognize(imageAt: png)
        XCTAssertTrue(text.lowercased().contains("hello"), "got: \(text)")
        XCTAssertTrue(text.contains("2026"), "got: \(text)")
    }

    // MARK: Uninstaller

    func testFindsLeftoversByBundleID() throws {
        let fm = FileManager.default
        let appURL = dir.appendingPathComponent("Apps/Fancy.app/Contents")
        try fm.createDirectory(at: appURL, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.test.fancy", "CFBundleName": "Fancy", "CFBundleExecutable": "Fancy"]
        try (plist as NSDictionary).write(to: appURL.appendingPathComponent("Info.plist"))

        let lib = dir.appendingPathComponent("Library")
        for p in ["Caches/com.test.fancy", "Preferences/com.test.fancy.plist", "Application Support/Fancy",
                  "Group Containers/ABCDE12345.com.test.fancy", "Caches/com.test.fancybar", "Caches/Unrelated", "Saved Application State/com.test.fancy.savedState"] {
            let url = lib.appendingPathComponent(p)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }

        let apps = AppUninstaller.installedApps(in: [dir.appendingPathComponent("Apps")])
        XCTAssertEqual(apps.map(\.bundleID), ["com.test.fancy"])
        let left = AppUninstaller.findLeftovers(for: apps[0], library: lib)
        let names = Set(left.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("com.test.fancy"))
        XCTAssertTrue(names.contains("com.test.fancy.plist"))
        XCTAssertTrue(names.contains("ABCDE12345.com.test.fancy"))
        XCTAssertTrue(names.contains("com.test.fancy.savedState"))
        XCTAssertFalse(names.contains("com.test.fancybar"), "different app sharing a prefix must not match")
        XCTAssertFalse(names.contains("Unrelated"))
        XCTAssertEqual(left.first { $0.url.lastPathComponent == "Fancy" }?.confident, false, "name-only match is flagged")
        XCTAssertEqual(left.first { $0.url.lastPathComponent == "com.test.fancy" }?.confident, true)
    }

    func testAppleAppsAreProtected() {
        XCTAssertTrue(InstalledApp(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari", bundleID: "com.apple.Safari").isProtected)
        XCTAssertFalse(InstalledApp(url: URL(fileURLWithPath: "/Applications/X.app"), name: "X", bundleID: "com.x.y").isProtected)
    }
}

final class DeletePagesTests: XCTestCase {
    var dir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("tidy-del-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    /// A PDF whose pages are different sizes, so each page can be told apart by its width.
    func makePDF(pages: Int) throws -> URL {
        let doc = PDFDocument()
        for i in 0..<pages {
            let size = NSSize(width: 100 + i * 10, height: 150)
            let image = NSImage(size: size)
            image.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill(); image.unlockFocus()
            doc.insert(PDFPage(image: image)!, at: i)
        }
        let url = dir.appendingPathComponent("src.pdf")
        XCTAssertTrue(doc.write(to: url))
        return url
    }

    func widths(_ url: URL) -> [Int] {
        let doc = PDFDocument(url: url)!
        return (0..<doc.pageCount).map { Int(doc.page(at: $0)!.bounds(for: .mediaBox).width) }
    }

    func testDeletesTheRightPagesAndKeepsTheOriginal() throws {
        let src = try makePDF(pages: 5)                        // widths 100,110,120,130,140
        let out = dir.appendingPathComponent("out.pdf")
        let remaining = try PDFTools.deletePages(from: src, pages: [2, 4], to: out)
        XCTAssertEqual(remaining, 3)
        XCTAssertEqual(widths(out), [100, 120, 140], "pages 2 and 4 are gone, the order is kept")
        XCTAssertEqual(PDFTools.pageCount(of: src), 5, "the original keeps all its pages")
    }

    func testDeletesFirstAndLastPage() throws {
        let src = try makePDF(pages: 4)
        let out = dir.appendingPathComponent("out.pdf")
        try PDFTools.deletePages(from: src, pages: [1, 4], to: out)
        XCTAssertEqual(widths(out), [110, 120])
    }

    func testRefusesBadRequests() throws {
        let src = try makePDF(pages: 3)
        let out = dir.appendingPathComponent("out.pdf")
        XCTAssertThrowsError(try PDFTools.deletePages(from: src, pages: [], to: out), "nothing picked")
        XCTAssertThrowsError(try PDFTools.deletePages(from: src, pages: [4], to: out), "page does not exist")
        XCTAssertThrowsError(try PDFTools.deletePages(from: src, pages: [0], to: out), "page 0 does not exist")
        XCTAssertThrowsError(try PDFTools.deletePages(from: src, pages: [1, 2, 3], to: out), "would remove everything")
        XCTAssertFalse(fm.fileExists(atPath: out.path), "no file is written when the request is refused")
    }

    func testPageSetAndFormatting() throws {
        XCTAssertEqual(try PDFTools.pageSet(from: "2, 4-5", pageCount: 6), [2, 4, 5])
        XCTAssertEqual(try PDFTools.pageSet(from: "1-3, 2-4", pageCount: 6), [1, 2, 3, 4], "overlaps merge")
        XCTAssertThrowsError(try PDFTools.pageSet(from: "7", pageCount: 6))
        XCTAssertEqual(PDFTools.formatRanges([1, 2, 3, 5]), "1-3, 5")
        XCTAssertEqual(PDFTools.formatRanges([4]), "4")
        XCTAssertEqual(PDFTools.formatRanges([]), "")
        XCTAssertEqual(PDFTools.formatRanges([9, 2, 3, 7, 8]), "2-3, 7-9")
    }
}
