import SwiftUI
import AppKit

/// The app icon, drawn in SwiftUI. `scripts/make_icon.sh` renders it to PNG.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.32, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.30, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "square.stack.3d.up.fill")
                .resizable().scaledToFit().frame(width: 520)
                .foregroundStyle(.white)
                .offset(y: 30)
            Image(systemName: "sparkles")
                .resizable().scaledToFit().frame(width: 230)
                .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.4))
                .offset(x: 210, y: -230)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
enum IconRenderer {
    static func render(to directory: String) {
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("icon render failed\n".utf8)); exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon-1024.png"))
    }
}
