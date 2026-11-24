import SwiftUI
import AppKit
import PDFKit
import TidyCore

/// Draws README screenshots of the real app (real controls, not placeholders) using demo data only:
/// made-up files in a temporary folder, a generated picture and a generated PDF. Nothing from the user's Mac appears.
/// Run: SimplySorted --render-screenshots <folder>
@MainActor
enum ScreenshotRenderer {
    static func render(to directory: String) {
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("simplysorted-shots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // Make the demo folder look like it lives in a home folder ("~/Downloads", not a temp path).
        PathDisplay.homeOverride = root.path
        defer { PathDisplay.homeOverride = nil }
        let downloads = makeDemoDownloads(in: root)
        let photo = makePhoto(at: root.appendingPathComponent("Beach sunset.png"))
        let pdf = makePDF(at: root.appendingPathComponent("Quarterly report.pdf"))
        let screenshot = makeScreenshotImage(at: root.appendingPathComponent("Screenshot.png"))

        // Files waiting on the Move to tab.
        let staged = ["Logo v3.ai", "Contract.pdf", "Invoice 0142.pdf"].map { name -> URL in
            let url = root.appendingPathComponent("Inbox").appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return url
        }

        let model = AppModel(previewFolder: downloads)
        model.message = nil
        for name in ["Clients/Acme Co", "Projects/Website redesign", "Taxes 2026"] {
            let dest = root.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            model.addFavorite(dest)
        }

        let pages: [(name: String, item: SidebarItem, height: CGFloat, demo: [SidebarItem: AnyView])] = [
            ("sort", .sort, 1330, [:]),
            ("move-to", .moveTo, 620, [.moveTo: AnyView(MoveToView(demoStaged: staged))]),
            ("images", .images, 940, [.images: AnyView(ImagesView(initialMode: .percent, percent: 200, sampleImage: photo))]),
            ("pdf-delete-pages", .pdf, 880, [.pdf: AnyView(PDFToolsView(initial: .delete, previewFile: pdf))]),
            ("text-from-screen", .text, 800, [.text: AnyView(TextFromImageView(
                demoText: "Meeting notes\nTuesday 10:30\n\n• Ship version 1.3\n• Review the new icon\n• Send invoices", sampleImage: screenshot))]),
        ]
        for scheme in [ColorScheme.light, .dark] {
            model.appearance = scheme == .dark ? .dark : .light     // so the sun / moon switch shows the right side
            for page in pages {
                let suffix = scheme == .dark ? "-dark" : ""
                capture(ContentView(initial: page.item, demoPages: page.demo), model: model, scheme: scheme,
                        size: NSSize(width: 1000, height: page.height), to: out.appendingPathComponent("\(page.name)\(suffix).png"))
            }
        }
    }

    private static func capture<V: View>(_ view: V, model: AppModel, scheme: ColorScheme, size: NSSize, to url: URL) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(model).environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.isReleasedWhenClosed = false
        // Far off to the side, so nothing flashes on screen while the real window is drawn.
        window.setFrameOrigin(NSPoint(x: -20_000, y: 0))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))     // let thumbnails and lists load
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           cg.width > 0 {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url); return }
        }
        // Fallback: draw the view directly (can show faint edge artefacts on rounded shapes).
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    // MARK: demo content

    private static func makeDemoDownloads(in root: URL) -> URL {
        let dir = root.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let groups: [(String, Int)] = [
            ("IMG_%04d.jpg", 118), ("Screenshot %d.png", 38), ("Invoice-%d.pdf", 24), ("brand-%d.ai", 14),
            ("clip-%d.mov", 11), ("backup-%d.zip", 9), ("Setup-%d.dmg", 4), ("sheet-%d.xlsx", 7),
        ]
        let old = Date().addingTimeInterval(-86_400)
        for (pattern, count) in groups {
            for i in 1...count {
                let url = dir.appendingPathComponent(String(format: pattern, i))
                FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8), attributes: [.modificationDate: old])
            }
        }
        return dir
    }

    private static func write(_ image: NSImage, to url: URL) {
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    /// A simple generated landscape, so no real photo is ever shown.
    private static func makePhoto(at url: URL) -> URL {
        let size = NSSize(width: 1600, height: 1000)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(red: 0.98, green: 0.78, blue: 0.5, alpha: 1), NSColor(red: 0.93, green: 0.45, blue: 0.4, alpha: 1),
                            NSColor(red: 0.3, green: 0.3, blue: 0.5, alpha: 1)])?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(white: 1, alpha: 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1020, y: 470, width: 260, height: 260)).fill()
        NSColor(red: 0.18, green: 0.2, blue: 0.35, alpha: 1).setFill()
        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: 0, y: 0)); hills.line(to: NSPoint(x: 0, y: 330))
        hills.curve(to: NSPoint(x: 700, y: 300), controlPoint1: NSPoint(x: 250, y: 520), controlPoint2: NSPoint(x: 480, y: 180))
        hills.curve(to: NSPoint(x: 1600, y: 280), controlPoint1: NSPoint(x: 950, y: 440), controlPoint2: NSPoint(x: 1300, y: 150))
        hills.line(to: NSPoint(x: 1600, y: 0)); hills.close(); hills.fill()
        image.unlockFocus()
        write(image, to: url)
        return url
    }

    private static func makeScreenshotImage(at url: URL) -> URL {
        let size = NSSize(width: 900, height: 520)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let text = "Meeting notes\nTuesday 10:30\n\n• Ship version 1.3\n• Review the new icon\n• Send invoices"
        (text as NSString).draw(in: NSRect(x: 50, y: 40, width: 800, height: 440),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        image.unlockFocus()
        write(image, to: url)
        return url
    }

    private static func makePDF(at url: URL) -> URL {
        let doc = PDFDocument()
        for i in 0..<7 {
            let size = NSSize(width: 300, height: 400)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            NSColor.black.setFill(); NSRect(x: 30, y: 320, width: 200, height: 12).fill(); NSRect(x: 30, y: 290, width: 240, height: 6).fill()
            NSRect(x: 30, y: 270, width: 220, height: 6).fill(); NSRect(x: 30, y: 250, width: 240, height: 6).fill()
            ("Page \(i + 1)" as NSString).draw(at: NSPoint(x: 30, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
            image.unlockFocus()
            if let page = PDFPage(image: image) { doc.insert(page, at: i) }
        }
        doc.write(to: url)
        return url
    }
}
