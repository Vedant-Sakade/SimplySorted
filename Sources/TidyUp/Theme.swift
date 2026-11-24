import SwiftUI
import AppKit
import CoreText

/// Simply Sorted's look: pale sage paper, thin ink outlines, monospaced type, big rounded cards and pill buttons.
enum Theme {
    static let bg = Color(light: 0xE8EEE3, dark: 0x121712)
    static let card = Color(light: 0xEFF4EA, dark: 0x1A211A)
    static let ink = Color(light: 0x1A1F1B, dark: 0xE6EDE2)
    static let mute = Color(light: 0x5C655D, dark: 0x93A092)
    static let warn = Color(light: 0xB4521E, dark: 0xE08A52)
    static let radius: CGFloat = 26
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Fonts {
    /// Registers the Geist Mono files bundled in the app (SIL Open Font License).
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Geist Mono, falling back to the system monospaced font if the files are missing.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "GeistMono-Bold"
        case .semibold: name = "GeistMono-SemiBold"
        case .medium: name = "GeistMono-Medium"
        default: name = "GeistMono-Regular"
        }
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
