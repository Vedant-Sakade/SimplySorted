import SwiftUI
import TidyCore

struct UninstallerView: View {
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var selected: InstalledApp?
    @State private var loadingApps = false
    @State private var removedNote: String?

    private var shown: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Card(title: "Apps", icon: "square.grid.2x2") {
                PillField(placeholder: "Search apps", text: $search, icon: "magnifyingglass")
                if loadingApps { WorkProgress(title: "Finding your apps…", fraction: nil) }
                if !loadingApps && shown.isEmpty { Hint(search.isEmpty ? "No apps found." : "No app matches “\(search)”.") }
                AdaptiveScroll {
                    LazyVStack(spacing: 4) {
                        ForEach(shown) { app in
                            let isSelected = selected == app
                            Button { selected = app } label: {
                                HStack(spacing: 10) {
                                    AppIcon(url: app.url)
                                    Text(app.name).font(.mono(12, isSelected ? .semibold : .regular)).lineLimit(1)
                                    Spacer()
                                    if app.isProtected { Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.mute) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Theme.ink.opacity(0.1) : Color.clear))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink.opacity(isSelected ? 0.9 : 0), lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 290)

            Card(title: "Remove", icon: "trash") {
                if let app = selected {
                    AppDetail(app: app, onRemoved: { note in
                        removedNote = note; selected = nil; loadApps()
                    }).id(app.id)
                } else {
                    VStack(spacing: 10) {
                        if let removedNote {
                            Label(removedNote, systemImage: "checkmark.circle.fill")
                                .font(.mono(13, .semibold)).foregroundStyle(Theme.bg)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Capsule().fill(Theme.good))
                                .padding(.bottom, 10)
                        }
                        Image(systemName: "trash").font(.system(size: 30, weight: .light)).frame(width: 70, height: 70)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: 1.2))
                        Text("Pick an app").font(.mono(13, .semibold)).textCase(.uppercase)
                        Hint("You will see the app and the files it left behind. Everything goes to the Trash, so you can get it back.")
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.top, 22).padding(.bottom, 28)
        .onAppear { if apps.isEmpty { loadApps() } }
    }

    /// The app list is read off the main thread so the tab opens instantly.
    private func loadApps() {
        loadingApps = true
        Task.detached {
            let found = AppUninstaller.installedApps()
            await MainActor.run { [found] in apps = found; loadingApps = false }
        }
    }
}

private struct AppIcon: View {
    let url: URL
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: size, height: size)
    }
}

private struct AppDetail: View {
    let app: InstalledApp
    var onRemoved: (String) -> Void

    @State private var leftovers: [Leftover] = []
    @State private var chosen: Set<URL> = []
    @State private var sizes: [URL: Int64] = [:]
    @State private var loading = true
    @State private var confirm = false
    @State private var result: String?

    private var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
    }
    private var items: [URL] { [app.url] + leftovers.map(\.url) }
    private var chosenSize: Int64 { chosen.reduce(0) { $0 + (sizes[$1] ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AppIcon(url: app.url, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.mono(20, .medium)).lineLimit(1)
                    Text(app.bundleID).font(.mono(11)).foregroundStyle(Theme.mute)
                }
            }
            if app.isProtected {
                StatusLine(text: "This is a macOS or protected app and can’t be removed here.", isError: true)
            } else {
                if isRunning { StatusLine(text: "\(app.name) is running. Quit it first, then come back.", isError: true) }
                if loading {
                    Label("Looking for leftover files…", systemImage: "hourglass").font(.mono(12)).foregroundStyle(Theme.mute)
                } else {
                    AdaptiveScroll {
                        VStack(spacing: 0) {
                            row(app.url, place: "The app", confident: true)
                            if leftovers.isEmpty { Hint("No leftover files found.").padding(.vertical, 10) }
                            ForEach(leftovers) { row($0.url, place: $0.place, confident: $0.confident) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    if leftovers.contains(where: { !$0.confident }) {
                        Hint("“Name match” items were found by name only. They start unticked — check them before including.")
                    }
                }
                HStack(spacing: 14) {
                    Button { confirm = true } label: { Label("Move to Trash", systemImage: "trash") }
                        .buttonStyle(.pill(.filled))
                        .disabled(chosen.isEmpty || isRunning || loading)
                    Text("\(chosen.count) item\(chosen.count == 1 ? "" : "s") · \(formatBytes(chosenSize))")
                        .font(.mono(12)).foregroundStyle(Theme.mute)
                }
                StatusLine(text: result)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await load() }
        .confirmationDialog("Move \(chosen.count) item\(chosen.count == 1 ? "" : "s") to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { remove() }
        } message: {
            Text("Frees about \(formatBytes(chosenSize)). You can restore them from the Trash.")
        }
    }

    private func row(_ url: URL, place: String, confident: Bool) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(get: { chosen.contains(url) }, set: { on in if on { chosen.insert(url) } else { chosen.remove(url) } })) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.mono(12, .medium)).lineLimit(1)
                        Text(place + (confident ? "" : " · name match")).font(.mono(10)).foregroundStyle(confident ? Theme.mute : Theme.warn)
                    }
                    Spacer()
                    Text(formatBytes(sizes[url] ?? 0)).font(.mono(11)).foregroundStyle(Theme.mute)
                }
            }
            .toggleStyle(.check)
            .padding(.vertical, 9)
            HairlineDivider()
        }
    }

    private func load() async {
        let app = app
        let (found, sized) = await Task.detached { () -> ([Leftover], [URL: Int64]) in
            let found = AppUninstaller.findLeftovers(for: app)
            var sized: [URL: Int64] = [:]
            for url in [app.url] + found.map(\.url) { sized[url] = AppUninstaller.size(of: url) }
            return (found, sized)
        }.value
        leftovers = found
        sizes = sized
        chosen = Set([app.url] + found.filter(\.confident).map(\.url))
        loading = false
    }

    private func remove() {
        let urls = items.filter { chosen.contains($0) }
        let (trashed, failures) = AppUninstaller.moveToTrash(urls)
        result = "Moved \(trashed) item\(trashed == 1 ? "" : "s") to the Trash." + (failures.isEmpty ? "" : " \(failures.count) failed: \(failures[0])")
        if trashed > 0 && failures.isEmpty {
            let note = "\(app.name) removed · \(formatBytes(chosenSize)) freed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onRemoved(note) }
        }
    }
}
