import XCTest
@testable import TidyCore

final class SorterTests: XCTestCase {
    var dir: URL!
    let sorter = Sorter(minimumAge: 0)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func touch(_ name: String) {
        FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("x".utf8))
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(relative).path)
    }

    func testCategoryLookupIsCaseInsensitive() {
        XCTAssertEqual(Category.of(extension: "JPG"), .images)
        XCTAssertEqual(Category.of(extension: "pdf"), .documents)
        XCTAssertEqual(Category.of(extension: "xyz"), .other)
        XCTAssertEqual(Category.of(extension: ""), .other)
    }

    func testSortsFilesIntoCategoryFolders() throws {
        ["a.png", "b.PDF", "c.zip", "d.mp4", "noext"].forEach(touch)
        let run = sorter.sort([try sorter.plan(folder: dir)])
        XCTAssertEqual(run.moved.count, 5)
        XCTAssertTrue(exists("Images/a.png"))
        XCTAssertTrue(exists("Documents/b.PDF"))
        XCTAssertTrue(exists("Archives/c.zip"))
        XCTAssertTrue(exists("Videos/d.mp4"))
        XCTAssertTrue(exists("Other/noext"))
        XCTAssertFalse(exists("a.png"))
    }

    func testLeavesFoldersHiddenAndPartialDownloadsAlone() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("My Project"), withIntermediateDirectories: true)
        ["x.crdownload", ".hidden.png", "real.png"].forEach(touch)
        let plan = try sorter.plan(folder: dir)
        XCTAssertEqual(plan.moves.map(\.source.lastPathComponent), ["real.png"])
        XCTAssertEqual(plan.skipped, 3)
    }

    func testRecentlyModifiedFilesAreSkipped() throws {
        touch("fresh.png")
        let plan = try Sorter(minimumAge: 3600).plan(folder: dir)
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.skipped, 1)
    }

    func testNameClashNeverOverwrites() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Images"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: dir.appendingPathComponent("Images/a.png"))
        touch("a.png")
        _ = sorter.sort([try sorter.plan(folder: dir)])
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("Images/a.png")), "old")
        XCTAssertTrue(exists("Images/a 2.png"))
    }

    func testUndoRestoresFilesAndRemovesCreatedFolders() throws {
        ["a.png", "b.pdf"].forEach(touch)
        let run = sorter.sort([try sorter.plan(folder: dir)])
        let result = sorter.undo(run)
        XCTAssertEqual(result.restored, 2)
        XCTAssertTrue(exists("a.png"))
        XCTAssertTrue(exists("b.pdf"))
        XCTAssertFalse(exists("Images"))
        XCTAssertFalse(exists("Documents"))
    }

    func testUndoKeepsPreExistingFolders() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Images"), withIntermediateDirectories: true)
        touch("a.png")
        let run = sorter.sort([try sorter.plan(folder: dir)])
        _ = sorter.undo(run)
        XCTAssertTrue(exists("Images"))
        XCTAssertTrue(exists("a.png"))
    }

    func testRunStoreRoundTrip() throws {
        touch("a.png")
        let run = sorter.sort([try sorter.plan(folder: dir)])
        let store = RunStore(fileURL: dir.appendingPathComponent("log/last.json"))
        store.save(run)
        XCTAssertEqual(store.load()?.moved, run.moved)
        store.clear()
        XCTAssertNil(store.load())
    }
}
