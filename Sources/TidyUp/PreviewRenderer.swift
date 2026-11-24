import SwiftUI
import AppKit
import PDFKit

/// Draws every screen to PNG files without opening a window (used to check the design).
/// Run: Simply Sorted.app/Contents/MacOS/SimplySorted --render-preview <folder>
@MainActor
enum PreviewRenderer {
    static func render(to directory: String) {
        let out = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let demo = makeDemoFolder()
        let model = AppModel(previewFolder: demo)
        for scheme in [ColorScheme.light, .dark] {
            for (item, tall) in SidebarItem.allCases.map({ ($0, true) }) + [(SidebarItem.sort, false)] {
                let view = ContentView(initial: item)
                    .environment(model)
                    .environment(\.colorScheme, scheme)
                    .environment(\.previewMode, true)
                    .frame(width: 1000, height: item == .sort && tall ? 1250 : (item == .sort ? 800 : 800), alignment: .top)
                    .background(Theme.bg)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.5
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                let name = "\(item.rawValue)\(tall ? "" : "-top")-\(scheme == .dark ? "dark" : "light").png"
                try? png.write(to: out.appendingPathComponent(name))
            }
        }
        renderDeletePages(model: model, to: out)
        renderImageModes(model: model, to: out)
        try? FileManager.default.removeItem(at: demo)
    }

    /// The Images tab with the Scale and Pixels size modes switched on.
    private static func renderImageModes(model: AppModel, to out: URL) {
        // A sample picture so the Input card shows its preview.
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("Holiday photo.png")
        let art = NSImage(size: NSSize(width: 1448, height: 1086))
        art.lockFocus()
        NSGradient(colors: [NSColor(red: 0.95, green: 0.62, blue: 0.35, alpha: 1), NSColor(red: 0.25, green: 0.45, blue: 0.7, alpha: 1)])?
            .draw(in: NSRect(x: 0, y: 0, width: 1448, height: 1086), angle: 60)
        NSColor.white.withAlphaComponent(0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: 980, y: 700, width: 220, height: 220)).fill()
        art.unlockFocus()
        if let tiff = art.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { try? png.write(to: sample) }
        defer { try? FileManager.default.removeItem(at: sample) }
        let cases: [(String, ImagesView)] = [
            ("images-loaded", ImagesView(initialMode: .pixels, width: "2048", sampleImage: sample)),
            ("images-working", ImagesView(initialMode: .pixels, width: "2048", sampleImage: sample, demo: .working(done: 3, total: 12))),
            ("images-done", ImagesView(initialMode: .pixels, width: "2048", sampleImage: sample, demo: .finished)),
            ("images-scale", ImagesView(initialMode: .percent)),
            ("images-pixels", ImagesView(initialMode: .pixels)),
            ("images-enlarge-scale", ImagesView(initialMode: .percent, percent: 200, sourceSize: (1448, 1086))),
            ("images-enlarge-pixels", ImagesView(initialMode: .pixels, width: "2048", sourceSize: (1448, 1086))),
            ("images-enlarge-huge", ImagesView(initialMode: .percent, percent: 400, sourceSize: (6000, 4000))),
        ]
        for (name, imagesView) in cases {
            for scheme in [ColorScheme.light, .dark] {
                let page = imagesView
                    .padding(36)
                    .font(.mono(14)).foregroundStyle(Theme.ink)
                    .environment(model).environment(\.colorScheme, scheme).environment(\.previewMode, true)
                    .frame(width: 1000, height: name == "images-done" ? 1250 : 800, alignment: .top)
                    .background(Theme.bg)
                let renderer = ImageRenderer(content: page)
                renderer.scale = 1.5
                if let tiff = renderer.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: out.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }

    /// The Delete pages tab with a 7-page PDF open and pages 2 and 5 picked.
    private static func renderDeletePages(model: AppModel, to out: URL) {
        let doc = PDFDocument()
        for i in 0..<7 {
            let size = NSSize(width: 300, height: 400)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            NSColor.black.setFill(); NSRect(x: 30, y: 300, width: 200, height: 12).fill(); NSRect(x: 30, y: 270, width: 240, height: 6).fill()
            ("Page \(i + 1)" as NSString).draw(at: NSPoint(x: 30, y: 180), withAttributes: [.font: NSFont.systemFont(ofSize: 40)])
            image.unlockFocus()
            doc.insert(PDFPage(image: image)!, at: i)
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Quarterly report.pdf")
        doc.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack(alignment: .leading, spacing: 20) { DeletePane(previewFile: file) }
                .padding(36)
                .font(.mono(14)).foregroundStyle(Theme.ink)
                .environment(model).environment(\.colorScheme, scheme).environment(\.previewMode, true)
                .frame(width: 1000, height: 760, alignment: .top)
                .background(Theme.bg)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            if let tiff = renderer.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: out.appendingPathComponent("delete-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    private static func makeDemoFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tidyup-demo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let groups: [(String, [String], Int)] = [
            ("IMG_%04d.jpg", ["x"], 118), ("Screenshot %d.png", ["x"], 38), ("Invoice-%d.pdf", ["x"], 24), ("brand-%d.ai", ["x"], 14),
            ("clip-%d.mov", ["x"], 11), ("backup-%d.zip", ["x"], 9), ("Setup-%d.dmg", ["x"], 4), ("sheet-%d.xlsx", ["x"], 7), ("notes-%d", ["x"], 3),
        ]
        let old = Date().addingTimeInterval(-86_400)
        for (pattern, _, count) in groups {
            for i in 1...count {
                let url = dir.appendingPathComponent(String(format: pattern, i))
                FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8), attributes: [.modificationDate: old])
            }
        }
        return dir
    }
}
