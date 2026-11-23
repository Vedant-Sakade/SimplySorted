import SwiftUI
import TidyCore

struct UninstallerView: View {
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var selected: InstalledApp?

    private var shown: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder).padding(10)
                List(shown, selection: $selected) { app in
                    HStack {
                        AppIcon(url: app.url)
                        Text(app.name).lineLimit(1)
                    }
                    .tag(app)
                }
            }
            .frame(width: 240)
            Divider()
            if let app = selected {
                AppDetail(app: app, onRemoved: { selected = nil; apps = AppUninstaller.installedApps() }).id(app.id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("Pick an app to remove it and the files it left behind").foregroundStyle(.secondary)
                    Text("Everything goes to the Trash first, so you can still get it back.").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if apps.isEmpty { apps = AppUninstaller.installedApps() } }
    }
}

private struct AppIcon: View {
    let url: URL
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
    }
}

private struct AppDetail: View {
    let app: InstalledApp
    var onRemoved: () -> Void

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
        SectionPage(title: app.name, subtitle: app.bundleID) {
            if app.isProtected {
                Label("This is a macOS or protected app and can’t be removed here.", systemImage: "lock.fill").foregroundStyle(.secondary)
            } else {
                if isRunning {
                    Label("\(app.name) is running. Quit it first, then come back.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if loading { ProgressView("Looking for leftover files…") }
                else {
                    row(app.url, place: "The app", confident: true)
                    if leftovers.isEmpty { Text("No leftover files found.").foregroundStyle(.secondary) }
                    ForEach(leftovers) { row($0.url, place: $0.place, confident: $0.confident) }
                    if leftovers.contains(where: { !$0.confident }) {
                        Text("Items marked “name match” were found by name only. They are unticked — check them before including.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Move to Trash…") { confirm = true }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(chosen.isEmpty || isRunning || loading)
                    Text("\(chosen.count) item\(chosen.count == 1 ? "" : "s") · \(formatBytes(chosenSize))").foregroundStyle(.secondary)
                }
                StatusLine(text: result)
            }
        }
        .task { await load() }
        .confirmationDialog("Move \(chosen.count) item\(chosen.count == 1 ? "" : "s") to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { remove() }
        } message: {
            Text("Frees about \(formatBytes(chosenSize)). You can restore them from the Trash.")
        }
    }

    private func row(_ url: URL, place: String, confident: Bool) -> some View {
        Toggle(isOn: Binding(get: { chosen.contains(url) }, set: { on in if on { chosen.insert(url) } else { chosen.remove(url) } })) {
            HStack {
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent)
                    Text(place + (confident ? "" : " · name match")).font(.caption).foregroundStyle(confident ? Color.secondary : Color.orange)
                }
                Spacer()
                Text(formatBytes(sizes[url] ?? 0)).foregroundStyle(.secondary).monospacedDigit()
            }
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
        if trashed > 0 && failures.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onRemoved() } }
    }
}
