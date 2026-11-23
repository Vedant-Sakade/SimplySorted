import SwiftUI
import TidyCore

struct MoveToView: View {
    @Environment(AppModel.self) private var model
    @State private var staged: [URL] = []

    var body: some View {
        PageScroll {
            TwoColumns {
                Card(title: "Files to move", icon: "tray.and.arrow.down") {
                    DropZone(title: "Drop files or folders", subtitle: "Then pick a destination — or drop straight onto one.",
                             systemImage: "tray.and.arrow.down") { staged.append(contentsOf: $0) }
                    if !staged.isEmpty {
                        HStack {
                            Text("\(staged.count) ready").font(.mono(12, .semibold)).textCase(.uppercase)
                            Spacer()
                            Button { staged = [] } label: { Label("Clear", systemImage: "xmark") }
                                .buttonStyle(.pill(.outlined, compact: true))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(staged.prefix(12), id: \.self) {
                                Label($0.lastPathComponent, systemImage: $0.hasDirectoryPath ? "folder" : "doc")
                                    .font(.mono(11)).foregroundStyle(Theme.mute).lineLimit(1)
                            }
                            if staged.count > 12 { Hint("and \(staged.count - 12) more") }
                        }
                    }
                }
            } right: {
                Card(title: "Destinations", icon: "folder.badge.plus") {
                    if model.favorites.isEmpty {
                        Hint("No destinations yet. Add the folders you move files to most, like a client or project folder.")
                    }
                    ForEach(model.favorites, id: \.self) { path in
                        DestinationRow(path: path, staged: $staged)
                    }
                    Button {
                        if let url = chooseFolder(prompt: "Add") { model.addFavorite(url) }
                    } label: { Label("Add destination", systemImage: "plus") }
                        .buttonStyle(.pill(.outlined, compact: true))
                    StatusLine(text: model.message)
                    if let label = model.undoLabel {
                        Button { model.undo() } label: { Label(label, systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.pill(.outlined, compact: true))
                    }
                }
            }
        }
    }
}

private struct DestinationRow: View {
    @Environment(AppModel.self) private var model
    let path: String
    @Binding var staged: [URL]
    @State private var targeted = false

    private var url: URL { URL(fileURLWithPath: path) }
    private var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exists ? "folder" : "questionmark.folder").font(.system(size: 18, weight: .light))
                .foregroundStyle(exists ? Theme.ink : Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.mono(13, .semibold)).lineLimit(1)
                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.mono(10)).foregroundStyle(Theme.mute).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                model.move(staged, to: url)
                staged = []
            } label: { Label(staged.isEmpty ? "Move" : "Move \(staged.count)", systemImage: "arrow.right") }
                .buttonStyle(.pill(.filled, compact: true))
                .disabled(staged.isEmpty || !exists)
            Button { model.removeFavorite(path) } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 26))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(targeted ? Theme.ink.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.ink.opacity(targeted ? 1 : 0.5), lineWidth: 1))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard exists, !files.isEmpty else { return false }
            model.move(files, to: url)
            return true
        } isTargeted: { targeted = $0 }
    }
}
