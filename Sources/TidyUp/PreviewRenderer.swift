import SwiftUI
import AppKit

/// Draws every screen to PNG files without opening a window (used to check the design).
/// Run: TidyUp.app/Contents/MacOS/TidyUp --render-preview <folder>
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
        try? FileManager.default.removeItem(at: demo)
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
