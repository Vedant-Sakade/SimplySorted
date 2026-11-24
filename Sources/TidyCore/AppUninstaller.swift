import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String

    /// System apps, anything com.apple.*, and Simply Sorted itself (still the bundle id local.tidyup.app) are never offered for removal.
    public var isProtected: Bool {
        bundleID.hasPrefix("com.apple.") || url.path.hasPrefix("/System/") || bundleID == "local.tidyup.app"
    }
}

public struct Leftover: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    /// Where it was found, e.g. "Caches".
    public let place: String
    /// true when matched by the app's bundle ID (safe); false when matched only by name (user should check).
    public let confident: Bool
}

public enum AppUninstaller {
    public static var defaultAppFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    static let libraryPlaces = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
        "Saved Application State", "Logs", "HTTPStorages", "WebKit", "LaunchAgents", "Application Scripts", "Cookies",
    ]
    /// Places where a folder named exactly like the app is very likely the app's own.
    static let nameMatchPlaces: Set<String> = ["Application Support", "Caches", "Logs"]

    /// Finds apps in the given folders, looking one folder level deep (e.g. /Applications/Utilities).
    public static func installedApps(in folders: [URL] = defaultAppFolders) -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []
        func consider(_ url: URL) {
            guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            apps.append(InstalledApp(url: url, name: name, bundleID: id))
        }
        for folder in folders {
            for entry in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
                if entry.pathExtension == "app" { consider(entry); continue }
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    for inner in (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                        consider(inner)
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Looks through ~/Library for files this app left behind.
    public static func findLeftovers(for app: InstalledApp, library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) -> [Leftover] {
        let fm = FileManager.default
        let bid = app.bundleID
        let appFileName = app.url.deletingPathExtension().lastPathComponent.lowercased()
        let displayName = app.name.lowercased()
        var found: [Leftover] = []

        for place in libraryPlaces {
            let dir = library.appendingPathComponent(place, isDirectory: true)
            for entry in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? [] {
                let name = entry.lastPathComponent
                if name == bid || name.hasPrefix(bid + ".") || name.hasSuffix("." + bid) {
                    found.append(Leftover(url: entry, place: place, confident: true))
                } else if nameMatchPlaces.contains(place) {
                    let stem = (name as NSString).deletingPathExtension.lowercased()
                    if name.lowercased() == displayName || name.lowercased() == appFileName || stem == appFileName && !name.contains(".") {
                        found.append(Leftover(url: entry, place: place, confident: false))
                    }
                }
            }
        }
        return found
    }

    /// Total size on disk of a file or folder.
    public static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) {
            for case let file as URL in walker {
                let v = try? file.resourceValues(forKeys: Set(keys))
                if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
            }
        }
        return total
    }

    /// Moves items to the Trash (recoverable - nothing is deleted outright).
    public static func moveToTrash(_ urls: [URL]) -> (trashed: Int, failures: [String]) {
        var trashed = 0
        var failures: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (trashed, failures)
    }
}
