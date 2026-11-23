import SwiftUI
import TidyCore

struct MoveToView: View {
    @Environment(AppModel.self) private var model
    @State private var staged: [URL] = []

    var body: some View {
        SectionPage(title: "Move to…", subtitle: "Keep your favourite folders here. Drop files on one to send them there in a single step.") {
            DropZone(title: "Drop files or folders to move", subtitle: "Then pick a destination below — or drop straight onto a destination.",
                     systemImage: "tray.and.arrow.down") { staged.append(contentsOf: $0) }

            if !staged.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(staged.count) ready to move").font(.headline)
                        Spacer()
                        Button("Clear") { staged = [] }
                    }
                    ForEach(staged, id: \.self) { Text($0.lastPathComponent).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
            }

            HStack {
                Text("Destinations").font(.title3.bold())
                Spacer()
                Button("Add Destination…") { if let url = chooseFolder(prompt: "Add") { model.addFavorite(url) } }
            }

            if model.favorites.isEmpty {
                Text("No destinations yet. Add the folders you move files to most, like a client or project folder.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.favorites, id: \.self) { path in
                DestinationRow(path: path, staged: $staged)
            }
            StatusLine(text: model.message)
            if let label = model.undoLabel {
                Button(label) { model.undo() }
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
        HStack {
            Image(systemName: exists ? "folder.fill" : "folder.badge.questionmark").foregroundStyle(exists ? .blue : .orange)
            VStack(alignment: .leading) {
                Text(url.lastPathComponent)
                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Move \(staged.isEmpty ? "" : "\(staged.count) here")") {
                model.move(staged, to: url)
                staged = []
            }
            .disabled(staged.isEmpty || !exists)
            Button { model.removeFavorite(path) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(targeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard exists, !files.isEmpty else { return false }
            model.move(files, to: url)
            return true
        } isTargeted: { targeted = $0 }
    }
}
