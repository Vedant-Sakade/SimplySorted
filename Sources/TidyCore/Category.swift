import Foundation

/// The folders files get sorted into. The raw value is the folder name created on disk.
public enum Category: String, CaseIterable, Codable, Sendable {
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"
    case spreadsheets = "Spreadsheets"
    case presentations = "Presentations"
    case design = "Design"
    case ebooks = "Ebooks"
    case archives = "Archives"
    case installers = "Installers"
    case code = "Code"
    case fonts = "Fonts"
    case other = "Other"

    /// File extensions (lowercase, no dot) that belong to each category.
    static let extensions: [Category: [String]] = [
        .images: ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg", "raw", "cr2", "nef", "arw", "dng", "ico"],
        .videos: ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp"],
        .audio: ["mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "opus", "wma", "mid", "midi"],
        .documents: ["pdf", "doc", "docx", "txt", "rtf", "pages", "md", "odt", "tex", "pages-tef", "key-tef"],
        .spreadsheets: ["xls", "xlsx", "csv", "tsv", "numbers", "ods"],
        .presentations: ["ppt", "pptx", "key", "odp"],
        .design: ["psd", "ai", "indd", "fig", "sketch", "xd", "afdesign", "afphoto", "eps", "blend", "cdr"],
        .ebooks: ["epub", "mobi", "azw", "azw3"],
        .archives: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "iso"],
        .installers: ["dmg", "pkg", "mpkg", "app-zip"],
        .code: ["swift", "py", "js", "ts", "jsx", "tsx", "html", "css", "json", "xml", "yml", "yaml", "sh", "c", "h", "cpp", "java", "kt", "go", "rs", "rb", "php", "sql", "ipynb"],
        .fonts: ["ttf", "otf", "woff", "woff2", "ttc"],
    ]

    private static let lookup: [String: Category] = {
        var map: [String: Category] = [:]
        for (category, list) in extensions {
            for ext in list { map[ext] = category }
        }
        return map
    }()

    /// The category for a file extension (case-insensitive). Unknown extensions go to `.other`.
    public static func of(extension ext: String) -> Category {
        lookup[ext.lowercased()] ?? .other
    }

    /// Extensions that mean "this file is still being written" - never moved.
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload", "aria2"]
}
