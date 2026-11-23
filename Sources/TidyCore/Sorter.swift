import Foundation

/// One file that will be moved into a category folder.
public struct PlannedMove: Hashable, Sendable {
    public let source: URL
    public let category: Category
}

/// What a sort would do to one folder (a dry run - nothing is touched).
public struct SortPlan: Sendable {
    public let folder: URL
    public let moves: [PlannedMove]
    /// Items left alone: sub-folders, hidden files, unfinished downloads, files changed moments ago.
    public let skipped: Int

    public var counts: [Category: Int] {
        Dictionary(moves.map { ($0.category, 1) }, uniquingKeysWith: +)
    }
}

/// Recognises folders that belong in Fonts or Mockups.
enum FolderClassifier {
    static func category(of folder: URL) -> Category? {
        let name = folder.lastPathComponent.lowercased()
        if name.contains("mockup") || name.contains("mock-up") || name.contains("mocup") { return .mockups }

        // Count files up to three levels down; a folder is a font folder when fonts are at least half of it.
        var fonts = 0, others = 0, designFiles = 0, seen = 0
        let fm = FileManager.default
        let base = folder.pathComponents.count
        if let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                if url.pathComponents.count - base > 3 { walker.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                seen += 1
                if seen > 3000 { return nil }
                let ext = url.pathExtension.lowercased()
                if Category.fontExtensions.contains(ext) { fonts += 1 }
                else {
                    others += 1
                    if Category.designExtensions.contains(ext) { designFiles += 1 }
                }
            }
        }
        // A folder with design files (an Illustrator package, a logo project...) is a project that merely bundles fonts.
        guard fonts > 0, designFiles == 0 else { return nil }
        let looksLikeFont = name.contains("font") || name.contains("typeface")
        return (looksLikeFont || fonts * 2 >= fonts + others) ? .fonts : nil
    }
}

/// A file that was moved. Paths are stored as strings so a run can be saved to disk and undone later.
public struct MovedItem: Codable, Hashable, Sendable {
    public let from: String
    public let to: String
}

/// The record of one sort: enough to put every file back.
public struct SortRun: Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var moved: [MovedItem] = []
    /// Category folders this run created (removed again on undo if they end up empty).
    public var createdFolders: [String] = []
    public var failures: [String] = []
    /// "sort" or "move" - used to label the Undo button.
    public var kind = "sort"

    public init() {}
}

public struct UndoResult: Sendable {
    public let restored: Int
    public let skipped: Int
}

public struct Sorter: Sendable {
    /// Files modified more recently than this are skipped (they may still be downloading).
    public let minimumAge: TimeInterval

    public init(minimumAge: TimeInterval = 30) {
        self.minimumAge = minimumAge
    }

    // MARK: Plan

    /// - Parameter groupFolders: also plan to move font-family folders into "Fonts" and mockup folders into "Mockups".
    public func plan(folder: URL, groupFolders: Bool = false, now: Date = Date()) throws -> SortPlan {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey, .contentModificationDateKey]
        let reserved = Set(Category.allCases.map { $0.rawValue.lowercased() })
        let entries = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])

        var moves: [PlannedMove] = []
        var skipped = 0
        for url in entries {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            let ext = url.pathExtension.lowercased()

            if name.hasPrefix(".") || values?.isHidden == true { skipped += 1; continue }
            if values?.isSymbolicLink == true { skipped += 1; continue }
            if values?.isDirectory == true {
                // Folders are left alone, except (when asked) font-family and mockup folders.
                if groupFolders, values?.isPackage != true, !reserved.contains(name.lowercased()),
                   let category = FolderClassifier.category(of: url) {
                    moves.append(PlannedMove(source: url, category: category))
                } else {
                    skipped += 1
                }
                continue
            }
            if Category.partialExtensions.contains(ext) { skipped += 1; continue }
            if let modified = values?.contentModificationDate, now.timeIntervalSince(modified) < minimumAge {
                skipped += 1; continue
            }
            var category = Category.of(extension: ext)
            if category == .other, let sniffed = ContentSniffer.category(of: url) { category = sniffed }
            moves.append(PlannedMove(source: url, category: category))
        }
        moves.sort { $0.source.lastPathComponent.localizedStandardCompare($1.source.lastPathComponent) == .orderedAscending }
        return SortPlan(folder: folder, moves: moves, skipped: skipped)
    }

    // MARK: Sort

    /// Performs the plans. Never overwrites: a name clash becomes "name 2.ext".
    public func sort(_ plans: [SortPlan]) -> SortRun {
        let fm = FileManager.default
        var run = SortRun()
        for plan in plans {
            for move in plan.moves {
                let categoryFolder = plan.folder.appendingPathComponent(move.category.rawValue, isDirectory: true)
                do {
                    if !fm.fileExists(atPath: categoryFolder.path) {
                        try fm.createDirectory(at: categoryFolder, withIntermediateDirectories: false)
                        run.createdFolders.append(categoryFolder.path)
                    }
                    let destination = uniqueDestination(for: move.source.lastPathComponent, in: categoryFolder)
                    try fm.moveItem(at: move.source, to: destination)
                    run.moved.append(MovedItem(from: move.source.path, to: destination.path))
                } catch {
                    run.failures.append("\(move.source.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return run
    }

    /// Moves chosen files into one folder ("Move to..."). Same safety rules as sorting: never overwrites.
    public func move(_ files: [URL], to folder: URL) -> SortRun {
        let fm = FileManager.default
        var run = SortRun()
        run.kind = "move"
        for file in files {
            let source = file.standardizedFileURL
            let target = folder.standardizedFileURL
            if source.deletingLastPathComponent() == target { continue }
            if target.path == source.path || target.path.hasPrefix(source.path + "/") {
                run.failures.append("\(source.lastPathComponent): cannot move a folder into itself")
                continue
            }
            do {
                let destination = uniqueDestination(for: source.lastPathComponent, in: target)
                try fm.moveItem(at: source, to: destination)
                run.moved.append(MovedItem(from: source.path, to: destination.path))
            } catch {
                run.failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return run
    }

    func uniqueDestination(for fileName: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 2
        repeat {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = folder.appendingPathComponent(name)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    // MARK: Undo

    /// Puts files back where they came from. A file is skipped if it has since been moved or its old spot is taken.
    public func undo(_ run: SortRun) -> UndoResult {
        let fm = FileManager.default
        var restored = 0, skipped = 0
        for item in run.moved.reversed() {
            guard fm.fileExists(atPath: item.to), !fm.fileExists(atPath: item.from) else { skipped += 1; continue }
            do {
                try fm.moveItem(atPath: item.to, toPath: item.from)
                restored += 1
            } catch {
                skipped += 1
            }
        }
        for path in run.createdFolders {
            // Only removes a folder that is now empty (ignoring Finder's .DS_Store).
            let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
            if contents.allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(atPath: path) }
        }
        return UndoResult(restored: restored, skipped: skipped)
    }
}

/// Remembers the most recent sort on disk so Undo still works after the app is relaunched.
public struct RunStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = RunStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TidyUp", isDirectory: true).appendingPathComponent("last-sort.json")
    }

    public func save(_ run: SortRun) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(run) { try? data.write(to: fileURL, options: .atomic) }
    }

    public func load() -> SortRun? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SortRun.self, from: data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
