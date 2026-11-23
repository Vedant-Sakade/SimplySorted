import SwiftUI
import AppKit
import ServiceManagement
import TidyCore

struct WatchedFolder: Codable, Identifiable, Hashable {
    var path: String
    var enabled: Bool
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

/// Shared state: which folders to sort, the live preview, undo, schedule and "Move to" favourites.
@MainActor @Observable
final class AppModel {
    var folders: [WatchedFolder] = []
    var plans: [String: SortPlan] = [:]          // keyed by folder path
    var planErrors: [String] = []
    var lastRun: SortRun?
    var schedule = Schedule()
    var favorites: [String] = []
    /// Also move font-family and mockup folders into Fonts / Mockups (off by default).
    var groupFolders = false
    var message: String?
    var isWorking = false
    var appearance: Appearance = .light
    var loginItemEnabled = false
    var loginItemError: String?

    var scheduleReference = Date()
    private var timer: Timer?
    private let sorter: Sorter
    private let store: RunStore
    private let appearanceStore: AppearanceStore
    private let defaults: UserDefaults
    private let initialFolders: [WatchedFolder]?
    /// false in tests and screenshots: no timer, no login-item lookup, no app-wide appearance change.
    private let live: Bool

    /// - Parameters are only changed by tests; the app uses the defaults (the real settings and folders).
    init(defaults: UserDefaults = .standard, runStore: RunStore = RunStore(), minimumAge: TimeInterval = 30,
         initialFolders: [WatchedFolder]? = nil, live: Bool = true) {
        self.defaults = defaults
        self.store = runStore
        self.appearanceStore = AppearanceStore(defaults: defaults)
        self.sorter = Sorter(minimumAge: minimumAge)
        self.initialFolders = initialFolders
        self.live = live

        appearance = appearanceStore.load()
        applyAppearance()
        load()
        lastRun = store.load()
        if live {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            // Every minute: pick up new files for the menu bar count and run a due schedule
            // (a run missed while the Mac slept is caught up on the next tick).
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.checkSchedule()
                }
            }
            checkSchedule()
        }
        refresh()
    }

    /// Screenshot mode: one demo folder, nothing read from or written to the user's real settings.
    convenience init(previewFolder: URL) {
        self.init(defaults: UserDefaults(suiteName: "tidyup.preview.\(UUID().uuidString)")!,
                  runStore: RunStore(fileURL: previewFolder.appendingPathComponent(".preview-run.json")),
                  minimumAge: 0,
                  initialFolders: [WatchedFolder(path: previewFolder.path, enabled: true)], live: false)
        if let plan = try? Sorter(minimumAge: 0).plan(folder: previewFolder) { plans[previewFolder.path] = plan }
        message = "Sorted 214 files."
    }

    // MARK: Derived

    var enabledFolders: [WatchedFolder] { folders.filter(\.enabled) }
    var pendingCount: Int { enabledFolders.reduce(0) { $0 + (plans[$1.path]?.moves.count ?? 0) } }
    var undoLabel: String? {
        guard let run = lastRun else { return nil }
        return run.kind == "move" ? "Undo last move" : "Undo last sort"
    }
    var nextScheduledRun: Date? { schedule.enabled ? schedule.nextRun(after: scheduleReference) : nil }

    // MARK: Light / dark

    /// Switches the look, applies it to the whole app (windows, menus, file pickers) and remembers it.
    func setAppearance(_ new: Appearance) {
        appearance = new
        appearanceStore.save(new)
        applyAppearance()
    }

    private func applyAppearance() {
        guard live else { return }
        NSApplication.shared.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    // MARK: Folders & preview

    func refresh() {
        let list = enabledFolders
        let sorter = sorter
        let group = groupFolders
        Task.detached {
            var result: [String: SortPlan] = [:]
            var errors: [String] = []
            for folder in list {
                do { result[folder.path] = try sorter.plan(folder: folder.url, groupFolders: group) }
                catch { errors.append("\(folder.name): \(error.localizedDescription)") }
            }
            await MainActor.run { [result, errors] in
                self.plans = result
                self.planErrors = errors
            }
        }
    }

    func setGroupFolders(_ on: Bool) {
        groupFolders = on
        save(); refresh()
    }

    func toggle(_ folder: WatchedFolder) {
        guard let i = folders.firstIndex(of: folder) else { return }
        folders[i].enabled.toggle()
        save(); refresh()
    }

    func addFolder(_ url: URL) {
        guard !folders.contains(where: { $0.path == url.path }) else { return }
        folders.append(WatchedFolder(path: url.path, enabled: true))
        save(); refresh()
    }

    func removeFolder(_ folder: WatchedFolder) {
        folders.removeAll { $0 == folder }
        plans[folder.path] = nil
        save()
    }

    // MARK: Sort & undo

    func sortNow(automatic: Bool = false) {
        guard !isWorking else { return }
        isWorking = true
        let list = enabledFolders
        let sorter = sorter
        let group = groupFolders
        Task.detached {
            var plans: [SortPlan] = []
            var errors: [String] = []
            for folder in list {
                do { plans.append(try sorter.plan(folder: folder.url, groupFolders: group)) }
                catch { errors.append("\(folder.name): \(error.localizedDescription)") }
            }
            let run = sorter.sort(plans)
            await MainActor.run { [run, errors] in
                self.finishSort(run, errors: errors, automatic: automatic)
            }
        }
    }

    private func finishSort(_ run: SortRun, errors: [String], automatic: Bool) {
        isWorking = false
        if !run.moved.isEmpty {
            lastRun = run
            store.save(run)
        }
        let prefix = automatic ? "Auto-sorted: " : ""
        var text = run.moved.isEmpty ? "\(prefix)Nothing to sort." : "\(prefix)Sorted \(run.moved.count) file\(run.moved.count == 1 ? "" : "s")."
        let problems = run.failures + errors
        if !problems.isEmpty { text += " \(problems.count) problem\(problems.count == 1 ? "" : "s"): \(problems[0])" }
        message = text
        refresh()
    }

    func undo() {
        guard let run = lastRun, !isWorking else { return }
        isWorking = true
        let sorter = sorter
        Task.detached {
            let result = sorter.undo(run)
            await MainActor.run { [result] in
                self.isWorking = false
                self.lastRun = nil
                self.store.clear()
                self.message = "Put back \(result.restored) file\(result.restored == 1 ? "" : "s")."
                    + (result.skipped > 0 ? " \(result.skipped) could not be put back (moved or renamed since)." : "")
                self.refresh()
            }
        }
    }

    // MARK: Move to…

    func move(_ files: [URL], to folder: URL) {
        let run = sorter.move(files, to: folder)
        if !run.moved.isEmpty {
            lastRun = run
            store.save(run)
        }
        var text = run.moved.isEmpty ? "Nothing moved." : "Moved \(run.moved.count) item\(run.moved.count == 1 ? "" : "s") to \(folder.lastPathComponent)."
        if let first = run.failures.first { text += " \(run.failures.count) problem\(run.failures.count == 1 ? "" : "s"): \(first)" }
        message = text
        refresh()
    }

    func addFavorite(_ url: URL) {
        guard !favorites.contains(url.path) else { return }
        favorites.append(url.path)
        save()
    }

    func removeFavorite(_ path: String) {
        favorites.removeAll { $0 == path }
        save()
    }

    // MARK: Schedule

    func scheduleChanged() {
        scheduleReference = Date()       // a changed schedule starts counting from now
        save()
    }

    func checkSchedule() {
        guard schedule.isDue(since: scheduleReference) else { return }
        scheduleReference = Date()
        save()
        sortNow(automatic: true)
    }

    func setLoginItem(_ on: Bool) {
        guard live else { return }          // tests and previews never touch the real login items
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: Text from screen (shared by the window and the menu bar)

    func captureTextFromScreen(onText: ((String) -> Void)? = nil) {
        Task.detached {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("tidyup-capture-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", file.path]     // -i: drag to choose an area, -x: no sound
            try? process.run()
            process.waitUntilExit()
            guard FileManager.default.fileExists(atPath: file.path) else {       // cancelled with Esc, or not allowed
                await MainActor.run {
                    self.message = "No capture taken. If you did not cancel, allow TidyUp in System Settings > Privacy & Security > Screen Recording."
                }
                return
            }
            do {
                let text = try TextRecognizer.recognize(imageAt: file)
                await MainActor.run { [text] in
                    if text.isEmpty {
                        self.message = "No text found in that area."
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.message = "Copied \(text.count) characters of text."
                    }
                    onText?(text)
                }
            } catch {
                await MainActor.run { self.message = "Could not read text: \(error.localizedDescription)" }
            }
        }
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var folders: [WatchedFolder]
        var schedule: Schedule
        var favorites: [String]
        var scheduleReference: Date
        var groupFolders: Bool?      // optional so older saved settings still load
    }

    private func save() {
        let saved = Saved(folders: folders, schedule: schedule, favorites: favorites, scheduleReference: scheduleReference, groupFolders: groupFolders)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "tidyup.state") }
    }

    private func load() {
        if let data = defaults.data(forKey: "tidyup.state"), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            folders = saved.folders
            schedule = saved.schedule
            favorites = saved.favorites
            scheduleReference = saved.scheduleReference
            groupFolders = saved.groupFolders ?? false
        } else if let initialFolders {
            folders = initialFolders
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folders = [
                WatchedFolder(path: home.appendingPathComponent("Downloads").path, enabled: true),
                WatchedFolder(path: home.appendingPathComponent("Desktop").path, enabled: true),
                WatchedFolder(path: home.appendingPathComponent("Documents").path, enabled: false),
            ]
        }
    }
}
