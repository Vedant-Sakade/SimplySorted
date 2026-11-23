import XCTest
import SwiftUI
import AppKit
@testable import TidyUp
@testable import TidyCore

/// Real mouse clicks sent to real SwiftUI controls inside a window, so "hard to press" problems show up here.
@MainActor
final class ControlTests: XCTestCase {
    final class Box: ObservableObject {
        @Published var on = false
        @Published var choice = "a"
        @Published var taps = 0
    }

    // MARK: harness

    func show<V: View>(_ view: V, width: CGFloat = 420, height: CGFloat = 160) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view.frame(width: width, height: height, alignment: .topLeading))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        settle()
        return window
    }

    func settle(_ seconds: TimeInterval = 0.15) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Click at a point measured from the window's top-left corner.
    func click(_ window: NSWindow, x: CGFloat, y: CGFloat) {
        let point = NSPoint(x: x, y: window.frame.height - y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
            settle(0.05)
        }
        settle()
    }

    // MARK: views under test

    struct ToggleView: View {
        @ObservedObject var box: Box
        var body: some View {
            Toggle(isOn: $box.on) { Text("Sort automatically").font(.mono(14, .semibold)) }
                .toggleStyle(.pill)
        }
    }

    struct CheckView: View {
        @ObservedObject var box: Box
        var body: some View {
            Toggle(isOn: $box.on) { Text("Include this file") }.toggleStyle(.check)
        }
    }

    struct SegmentView: View {
        @ObservedObject var box: Box
        var body: some View {
            PillSegmented(selection: $box.choice, options: [("a", "Daily"), ("b", "Weekly")])
        }
    }

    struct ThemeView: View {
        @ObservedObject var box: Box
        var body: some View { ThemeSwitch(isDark: $box.on) }
    }

    struct ButtonsView: View {
        @ObservedObject var box: Box
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Button { box.taps += 1 } label: { Label("Sort now", systemImage: "sparkles") }.buttonStyle(.pill(.filled))
                Button { box.taps += 10 } label: { Image(systemName: "xmark") }.buttonStyle(.roundIcon)
            }
        }
    }

    struct ThumbView: View {
        @ObservedObject var box: Box
        var body: some View {
            HStack(spacing: 16) {
                ThumbCell(number: 1, image: nil, selected: box.on) { box.on.toggle() }.frame(width: 110)
                ThumbCell(number: 2, image: nil, selected: false) { box.taps += 1 }.frame(width: 110)
            }
        }
    }

    // MARK: tests

    func testToggleReactsToClickOnSwitch() {
        let box = Box()
        let w = show(ToggleView(box: box))
        click(w, x: 24, y: 16)
        XCTAssertTrue(box.on, "clicking the switch must turn it on")
        click(w, x: 24, y: 16)
        XCTAssertFalse(box.on, "clicking again must turn it off")
    }

    func testToggleReactsToClickOnItsLabel() {
        let box = Box()
        let w = show(ToggleView(box: box))
        click(w, x: 150, y: 16)
        XCTAssertTrue(box.on, "clicking the words next to a switch must also toggle it")
    }

    func testToggleReactsJustOutsideTheSwitchGraphic() {
        let box = Box()
        let w = show(ToggleView(box: box))
        click(w, x: 24, y: 30)     // below the 26pt-tall switch graphic: still inside a comfortable target
        XCTAssertTrue(box.on, "the clickable area must be taller than the drawn switch")
    }

    func testCheckboxReactsToLabelAndBox() {
        let box = Box()
        let w = show(CheckView(box: box))
        click(w, x: 12, y: 16)
        XCTAssertTrue(box.on)
        click(w, x: 120, y: 16)
        XCTAssertFalse(box.on, "label click toggles the checkbox too")
    }

    func testSegmentedControlSwitchesOption() {
        let box = Box()
        let w = show(SegmentView(box: box))
        click(w, x: 130, y: 20)    // right half = "Weekly"
        XCTAssertEqual(box.choice, "b")
        click(w, x: 40, y: 20)
        XCTAssertEqual(box.choice, "a")
    }

    func testThemeSwitchFlipsFromEitherSide() {
        let box = Box()
        let w = show(ThemeView(box: box))
        click(w, x: 55, y: 16)
        XCTAssertTrue(box.on)
        click(w, x: 20, y: 16)
        XCTAssertFalse(box.on)
    }

    func testPillAndIconButtonsFire() {
        let box = Box()
        let w = show(ButtonsView(box: box))
        click(w, x: 60, y: 20)
        XCTAssertEqual(box.taps, 1, "pill button")
        click(w, x: 16, y: 74)
        XCTAssertEqual(box.taps, 11, "round icon button")
    }

    func testPageThumbnailsCanBePickedByClicking() {
        let box = Box()
        let w = show(ThumbView(box: box), width: 260, height: 200)
        click(w, x: 55, y: 70)      // middle of page 1's picture
        XCTAssertTrue(box.on, "clicking a page picture marks it")
        click(w, x: 55, y: 70)
        XCTAssertFalse(box.on, "clicking again unmarks it")
        click(w, x: 55, y: 180)     // on the page number under the picture
        click(w, x: 180, y: 70)
        XCTAssertEqual(box.taps, 1, "the second page's own picture works too")
    }

    func testAutoSortSwitchOnTheSortTabTurnsTheScheduleOn() {
        let suite = "tidyup-card-test-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: UserDefaults(suiteName: suite)!,
                             runStore: RunStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")),
                             minimumAge: 0, initialFolders: [], live: false)
        let w = show(AutoSortCard().environment(model), width: 900, height: 520)
        XCTAssertFalse(model.schedule.enabled)
        click(w, x: 47, y: 90)                      // on the switch
        XCTAssertTrue(model.schedule.enabled, "the Auto sort switch must turn the schedule on")
        click(w, x: 250, y: 90)                     // on the words next to it
        XCTAssertFalse(model.schedule.enabled, "clicking the words turns it off again")
    }
}
