import TidyCore

extension Category {
    /// Three-letter label for the chart axis.
    var short: String {
        switch self {
        case .images: "IMG"
        case .videos: "VID"
        case .audio: "AUD"
        case .documents: "DOC"
        case .spreadsheets: "XLS"
        case .presentations: "PPT"
        case .design: "DSN"
        case .ebooks: "EBK"
        case .archives: "ZIP"
        case .installers: "DMG"
        case .code: "COD"
        case .fonts: "FNT"
        case .mockups: "MCK"
        case .other: "OTH"
        }
    }

    var symbol: String {
        switch self {
        case .images: "photo"
        case .videos: "film"
        case .audio: "music.note"
        case .documents: "doc.text"
        case .spreadsheets: "tablecells"
        case .presentations: "rectangle.on.rectangle"
        case .design: "pencil.and.ruler"
        case .ebooks: "book"
        case .archives: "archivebox"
        case .installers: "shippingbox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .fonts: "textformat"
        case .mockups: "cube"
        case .other: "questionmark.folder"
        }
    }
}

/// Pins the name to TidyCore's Category (another framework also exports one).
typealias Category = TidyCore.Category
