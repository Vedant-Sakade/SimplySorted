import XCTest
import AppKit
@testable import TidyCore

final class ImprovementTests: XCTestCase {
    var dir: URL!
    let sorter = Sorter(minimumAge: 0)
    let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("tidy-imp-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 20, height: 20).fill(); image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
    func write(_ name: String, _ data: Data, in folder: URL? = nil) throws {
        let base = folder ?? dir!
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try data.write(to: base.appendingPathComponent(name))
    }
    func exists(_ rel: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(rel).path) }

    // MARK: content sniffing

    func testExtensionlessImageGoesToImages() throws {
        try write("HAND image", pngData())
        try write("morrre_dsgn on Instagram_ “LEXA. Identity design by saul_osuna_ for online bank", pngData())  // caption with dots = bogus extension
        try write("notes", Data("just some text, nothing special".utf8))
        let run = sorter.sort([try sorter.plan(folder: dir)])
        XCTAssertEqual(run.moved.count, 3)
        XCTAssertTrue(exists("Images/HAND image"))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.appendingPathComponent("Images").path).count, 2)
        XCTAssertTrue(exists("Other/notes"), "unidentifiable files still go to Other")
    }

    func testMagicBytes() throws {
        try write("a", Data("%PDF-1.7 hello".utf8))
        try write("b", Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]))
        try write("c", Data([0, 0, 0, 0x18] + Array("ftypmp42".utf8) + [0, 0, 0, 0]))
        try write("d", Data(Array("ID3".utf8) + [3, 0, 0, 0, 0]))
        XCTAssertEqual(ContentSniffer.category(of: dir.appendingPathComponent("a")), .documents)
        XCTAssertEqual(ContentSniffer.category(of: dir.appendingPathComponent("b")), .archives)
        XCTAssertEqual(ContentSniffer.category(of: dir.appendingPathComponent("c")), .videos)
        XCTAssertEqual(ContentSniffer.category(of: dir.appendingPathComponent("d")), .audio)
    }

    func testKnownExtensionWinsOverContent() throws {
        try write("picture.txt", pngData())      // the name says text, so it stays a document
        _ = sorter.sort([try sorter.plan(folder: dir)])
        XCTAssertTrue(exists("Documents/picture.txt"))
    }

    // MARK: folder grouping

    func makeFolders() throws {
        try write("Geist-Regular.ttf", Data("x".utf8), in: dir.appendingPathComponent("Geist"))
        try write("Geist-Bold.ttf", Data("x".utf8), in: dir.appendingPathComponent("Geist"))
        try write("OFL.txt", Data("licence".utf8), in: dir.appendingPathComponent("Geist"))
        try write("a.otf", Data("x".utf8), in: dir.appendingPathComponent("brand-font-2026/static"))
        try write("preview.png", pngData(), in: dir.appendingPathComponent("brand-font-2026"))
        try write("preview2.png", pngData(), in: dir.appendingPathComponent("brand-font-2026"))
        try write("a.psd", Data("x".utf8), in: dir.appendingPathComponent("coffee-cup-mockup-v3"))
        try write("logo.ai", Data("x".utf8), in: dir.appendingPathComponent("Joyzen_Folder"))
        // An Illustrator-style package: a design file plus bundled fonts. It is a project, not a font family.
        try write("brand.ai", Data("x".utf8), in: dir.appendingPathComponent("Sunflower_Folder"))
        try write("a.ttf", Data("x".utf8), in: dir.appendingPathComponent("Sunflower_Folder/Document fonts"))
        try write("b.ttf", Data("x".utf8), in: dir.appendingPathComponent("Sunflower_Folder/Document fonts"))
        try write("one.ttf", Data("x".utf8), in: dir.appendingPathComponent("Joyzen_Folder2"))   // 1 font among 3 other files: not a font folder
        try write("p.png", pngData(), in: dir.appendingPathComponent("Joyzen_Folder2"))
        try write("q.png", pngData(), in: dir.appendingPathComponent("Joyzen_Folder2"))
        try write("r.png", pngData(), in: dir.appendingPathComponent("Joyzen_Folder2"))
    }

    func testFoldersLeftAloneByDefault() throws {
        try makeFolders()
        let plan = try sorter.plan(folder: dir)
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.skipped, 6)
    }

    func testGroupsFontAndMockupFolders() throws {
        try makeFolders()
        let run = sorter.sort([try sorter.plan(folder: dir, groupFolders: true)])
        XCTAssertEqual(run.moved.count, 3)
        XCTAssertTrue(exists("Fonts/Geist/Geist-Bold.ttf"))
        XCTAssertTrue(exists("Fonts/brand-font-2026/static/a.otf"), "name says font and it holds a font")
        XCTAssertTrue(exists("Mockups/coffee-cup-mockup-v3/a.psd"))
        XCTAssertTrue(exists("Joyzen_Folder/logo.ai"), "ordinary folders stay put")
        XCTAssertTrue(exists("Joyzen_Folder2/one.ttf"), "mostly-images folder stays put")
        XCTAssertTrue(exists("Sunflower_Folder/brand.ai"), "a design project that bundles fonts stays put")
    }

    func testCategoryFoldersAreNeverMovedIntoThemselves() throws {
        try write("x.ttf", Data("x".utf8), in: dir.appendingPathComponent("Fonts"))
        let plan = try sorter.plan(folder: dir, groupFolders: true)
        XCTAssertTrue(plan.moves.isEmpty)
    }

    func testUndoRestoresMovedFolders() throws {
        try makeFolders()
        let run = sorter.sort([try sorter.plan(folder: dir, groupFolders: true)])
        let result = sorter.undo(run)
        XCTAssertEqual(result.restored, 3)
        XCTAssertTrue(exists("Geist/Geist-Bold.ttf"))
        XCTAssertTrue(exists("coffee-cup-mockup-v3/a.psd"))
        XCTAssertFalse(exists("Fonts"))
        XCTAssertFalse(exists("Mockups"))
    }
}

final class AppearanceTests: XCTestCase {
    func makeDefaults() -> (UserDefaults, String) {
        let suite = "tidyup-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testStartsLightThenRemembersChoice() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppearanceStore(defaults: defaults).load(), .light, "first launch is the off-white look")

        AppearanceStore(defaults: defaults).save(.dark)
        // A brand-new store object (like the next app launch) reads the saved choice.
        XCTAssertEqual(AppearanceStore(defaults: UserDefaults(suiteName: suite)!).load(), .dark)

        AppearanceStore(defaults: defaults).save(.light)
        XCTAssertEqual(AppearanceStore(defaults: UserDefaults(suiteName: suite)!).load(), .light)
    }

    func testIgnoresGarbageAndToggles() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("purple", forKey: "tidyup.appearance")
        XCTAssertEqual(AppearanceStore(defaults: defaults).load(), .light)
        XCTAssertEqual(Appearance.light.toggled, .dark)
        XCTAssertEqual(Appearance.dark.toggled, .light)
    }
}
