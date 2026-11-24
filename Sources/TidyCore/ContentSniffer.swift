import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Works out what a file really is by looking inside it. Used only when the name gives no clue
/// (no extension, or an extension Simply Sorted doesn't know), e.g. images saved from Instagram with a caption as the name.
enum ContentSniffer {
    static func category(of url: URL) -> Category? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let head = ((try? handle.read(upToCount: 16)) ?? nil) ?? Data()
        try? handle.close()
        guard head.count >= 4 else { return nil }
        let b = [UInt8](head)

        func starts(_ text: String, at offset: Int = 0) -> Bool {
            let t = Array(text.utf8)
            return b.count >= offset + t.count && Array(b[offset..<offset + t.count]) == t
        }

        if starts("%PDF") { return .documents }
        if starts("PK") && b[2] == 0x03 && b[3] == 0x04 { return .archives }
        if b[0] == 0x1F && b[1] == 0x8B { return .archives }                       // gzip
        if starts("7z") && b[2] == 0xBC && b[3] == 0xAF { return .archives }       // 7-Zip
        if starts("Rar!") { return .archives }

        // Any picture format this Mac can decode (PNG, JPEG, GIF, WebP, HEIC, TIFF...).
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
           let type = CGImageSourceGetType(src), UTType(type as String)?.conforms(to: .image) == true {
            return .images
        }

        if starts("ftyp", at: 4) {
            let brand = b.count >= 12 ? String(decoding: b[8..<12], as: UTF8.self) : ""
            return (brand == "M4A " || brand == "M4B ") ? .audio : .videos
        }
        if b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3 { return .videos }   // Matroska / WebM
        if starts("RIFF") { return starts("WAVE", at: 8) ? .audio : (starts("AVI ", at: 8) ? .videos : nil) }
        if starts("ID3") || starts("OggS") || starts("fLaC") { return .audio }
        if b[0] == 0xFF && (b[1] & 0xE0) == 0xE0 { return .audio }                  // bare MP3 frame
        return nil
    }
}
