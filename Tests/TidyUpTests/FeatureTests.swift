import XCTest
import AppKit
@testable import TidyUp
@testable import TidyCore

/// Every button in the app calls one of these model actions, so these tests exercise each feature end to end.
/// All work happens in temporary folders and a throwaway settings suite - never the real Downloads or settings.
@MainActor
final class FeatureTests: XCTestCase {
    var root: URL!
    var inbox: URL!
    var suite: String!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("tidyup-features-\(UUID().uuidString)")
        inbox = root.appendingPathComponent("Inbox")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        suite = "tidyup-ui-test-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? fm.removeItem(at: root)
    }

    // MARK: helpers

    func makeModel(folders: [URL]? = nil) -> AppModel {
        AppModel(defaults: UserDefaults(suiteName: suite)!, runStore: RunStore(fileURL: root.appendingPathComponent("last-sort.json")),
                 minimumAge: 0, initialFolders: (folders ?? [inbox]).map { WatchedFolder(path: $0.path, enabled: true) }, live: false)
    }

    func touch(_ name: String, in folder: URL? = nil, data: Data = Data("x".utf8)) throws {
        let dir = folder ?? inbox!
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name))
    }

    func exists(_ relative: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(relative).path) }

    func until(_ what: String = "condition", timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { break }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        let ok = condition()
        XCTAssertTrue(ok, "timed out waiting for: \(what)")
    }

    // MARK: Sort, preview, undo

    func testPreviewCountsAndFolderSwitch() async throws {
        try ["a.jpg", "b.pdf", "c.zip"].forEach { try touch($0) }
        let model = makeModel()
        await until("preview shows 3") { model.pendingCount == 3 }

        model.toggle(model.folders[0])                      // switch the folder off
        XCTAssertEqual(model.pendingCount, 0)
        model.toggle(model.folders[0])                      // and on again
        await until("preview back to 3") { model.pendingCount == 3 }
    }

    func testSortNowThenUndo() async throws {
        try ["a.jpg", "b.pdf", "c.zip"].forEach { try touch($0) }
        let model = makeModel()
        await until("preview") { model.pendingCount == 3 }

        model.sortNow()
        await until("sorted") { model.lastRun != nil && !model.isWorking }
        XCTAssertTrue(exists("Inbox/Images/a.jpg"))
        XCTAssertTrue(exists("Inbox/Documents/b.pdf"))
        XCTAssertTrue(exists("Inbox/Archives/c.zip"))
        XCTAssertEqual(model.message, "Sorted 3 files.")
        XCTAssertEqual(model.undoLabel, "Undo last sort")
        await until("preview empties") { model.pendingCount == 0 }

        model.undo()
        await until("undone") { model.lastRun == nil && !model.isWorking }
        XCTAssertTrue(exists("Inbox/a.jpg"))
        XCTAssertFalse(exists("Inbox/Images"))
        XCTAssertEqual(model.message, "Put back 3 files.")
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("last-sort.json").path), "undo record is cleared")
    }

    func testUndoStillWorksAfterRestart() async throws {
        try touch("a.jpg")
        let first = makeModel()
        await until("preview") { first.pendingCount == 1 }
        first.sortNow()
        await until("sorted") { first.lastRun != nil && !first.isWorking }

        let second = makeModel()                             // "next launch"
        XCTAssertEqual(second.undoLabel, "Undo last sort")
        second.undo()
        await until("undone") { second.lastRun == nil && !second.isWorking }
        XCTAssertTrue(exists("Inbox/a.jpg"))
    }

    func testSortingNothingKeepsThePreviousUndo() async throws {
        try touch("a.jpg")
        let model = makeModel()
        await until("preview") { model.pendingCount == 1 }
        model.sortNow()
        await until("sorted") { model.lastRun != nil && !model.isWorking }
        let id = model.lastRun?.id
        model.sortNow()                                      // nothing left to sort
        await until("second run finished") { !model.isWorking && model.message == "Nothing to sort." }
        XCTAssertEqual(model.lastRun?.id, id, "an empty second sort must not erase the undo for the first")
    }

    func testExtensionlessImageIsSortedByContent() async throws {
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .png, properties: [:])!
        try touch("HAND image", data: png)
        let model = makeModel()
        await until("preview") { model.pendingCount == 1 }
        model.sortNow()
        await until("sorted") { model.lastRun != nil && !model.isWorking }
        XCTAssertTrue(exists("Inbox/Images/HAND image"))
    }

    func testGroupFoldersOptionAndItIsRemembered() async throws {
        try touch("Geist-Regular.ttf", in: inbox.appendingPathComponent("Geist"))
        try touch("a.jpg")
        let model = makeModel()
        await until("preview") { model.pendingCount == 1 }   // the font folder is left alone by default

        model.setGroupFolders(true)
        await until("folder joins the preview") { model.pendingCount == 2 }
        XCTAssertTrue(makeModel().groupFolders, "the choice survives a restart")

        model.sortNow()
        await until("sorted") { model.lastRun != nil && !model.isWorking }
        XCTAssertTrue(exists("Inbox/Fonts/Geist/Geist-Regular.ttf"))
    }

    func testAddAndRemoveFolders() async throws {
        let other = root.appendingPathComponent("Other"); try fm.createDirectory(at: other, withIntermediateDirectories: true)
        try touch("n.txt", in: other)
        let model = makeModel()
        model.addFolder(other)
        model.addFolder(other)                               // adding twice is ignored
        XCTAssertEqual(model.folders.count, 2)
        await until("preview includes new folder") { model.pendingCount == 1 }
        model.removeFolder(model.folders[1])
        XCTAssertEqual(model.folders.count, 1)
        XCTAssertEqual(makeModel().folders.map(\.path), [inbox.path], "the shorter list is what gets saved")
    }

    func testMissingFolderShowsAnErrorInsteadOfCrashing() async throws {
        let model = makeModel(folders: [root.appendingPathComponent("DoesNotExist")])
        await until("error shown") { !model.planErrors.isEmpty }
        XCTAssertEqual(model.pendingCount, 0)
    }

    // MARK: Schedule

    func testDueScheduleSortsOnItsOwn() async throws {
        try touch("a.jpg")
        let model = makeModel()
        await until("preview") { model.pendingCount == 1 }
        model.schedule.enabled = true
        model.schedule.hour = 6
        model.scheduleReference = Date().addingTimeInterval(-3 * 86_400)   // the 06:00 slot passed days ago
        model.checkSchedule()
        await until("auto-sorted") { model.lastRun != nil && !model.isWorking }
        XCTAssertTrue(exists("Inbox/Images/a.jpg"))
        XCTAssertTrue(model.message?.hasPrefix("Auto-sorted") == true)
    }

    func testScheduleDoesNothingWhenOffOrNotDueYet() async throws {
        try touch("a.jpg")
        let model = makeModel()
        await until("preview") { model.pendingCount == 1 }
        model.scheduleReference = Date().addingTimeInterval(-3 * 86_400)
        model.checkSchedule()                                              // schedule is off
        model.schedule.enabled = true
        model.scheduleChanged()                                            // reference = now, so nothing is due yet
        model.checkSchedule()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(exists("Inbox/a.jpg"))
        XCTAssertNotNil(model.nextScheduledRun)
    }

    // MARK: Progress and Done

    func testSortShowsDoneTickAfterCleanRunButNotWhenFilesFail() async throws {
        try touch("a.jpg"); try touch("b.pdf"); try touch("c.zip")
        let model = makeModel()
        model.refresh()
        await until("planned") { model.pendingCount == 3 }
        model.sortNow()
        await until("sorted") { model.lastRun != nil && !model.isWorking }
        XCTAssertTrue(model.justFinished, "clean sort shows Done")
        XCTAssertNil(model.progress)
    }

    func testMovingNothingDoesNotShowDone() async throws {
        let dest = root.appendingPathComponent("Dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let model = makeModel()
        model.move([root.appendingPathComponent("does-not-exist.txt")], to: dest)
        await until("finished") { !model.isWorking && model.message != nil }
        XCTAssertFalse(model.justFinished, "nothing moved, so no Done tick")
        XCTAssertNotNil(model.message)
    }

    func testAnotherJobIsRefusedWhileOneRuns() async throws {
        let dest = root.appendingPathComponent("Dest2")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try touch("one.txt")
        let model = makeModel()
        model.move([inbox.appendingPathComponent("one.txt")], to: dest)
        model.move([inbox.appendingPathComponent("one.txt")], to: dest)   // second call while the first runs
        XCTAssertEqual(model.message, "Please wait, another job is still running.")
        await until("first done") { !model.isWorking }
    }

    // MARK: Move to…

    func testMoveToFavouriteAndUndo() async throws {
        let dest = root.appendingPathComponent("Clients/Joyzen")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try touch("logo.ai")
        let model = makeModel()
        model.addFavorite(dest)
        model.addFavorite(dest)
        XCTAssertEqual(model.favorites.count, 1)

        model.move([inbox.appendingPathComponent("logo.ai")], to: dest)
        XCTAssertTrue(model.isWorking, "moving runs in the background so the window never freezes")
        await until("moved") { model.message == "Moved 1 item to Joyzen." && !model.isWorking }
        XCTAssertTrue(exists("Clients/Joyzen/logo.ai"))
        XCTAssertEqual(model.undoLabel, "Undo last move")
        XCTAssertTrue(model.justFinished, "a clean move shows the green Done tick")
        XCTAssertNil(model.progress, "progress is cleared when the job ends")

        model.removeFavorite(dest.path)
        XCTAssertTrue(model.favorites.isEmpty)
    }

    // MARK: Settings are remembered

    func testSettingsPersistAcrossRestarts() throws {
        let extra = root.appendingPathComponent("Extra"); try fm.createDirectory(at: extra, withIntermediateDirectories: true)
        let model = makeModel()
        model.addFolder(extra)
        model.addFavorite(extra)
        model.schedule.enabled = true
        model.schedule.frequency = .weekly
        model.schedule.hour = 7
        model.scheduleChanged()

        let next = makeModel()
        XCTAssertEqual(next.folders.map(\.path), [inbox.path, extra.path])
        XCTAssertEqual(next.favorites, [extra.path])
        XCTAssertTrue(next.schedule.enabled)
        XCTAssertEqual(next.schedule.frequency, .weekly)
        XCTAssertEqual(next.schedule.hour, 7)
    }

    func testLightDarkChoiceIsRemembered() {
        let model = makeModel()
        XCTAssertEqual(model.appearance, .light, "first launch is the off-white look")
        model.setAppearance(.dark)
        XCTAssertEqual(makeModel().appearance, .dark, "dark is remembered on the next launch")
        model.setAppearance(.light)
        XCTAssertEqual(makeModel().appearance, .light)
    }
}
