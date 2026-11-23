import SwiftUI
import AppKit
import UniformTypeIdentifiers

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

@MainActor
func chooseFiles(types: [UTType] = [], multiple: Bool = true) -> [URL] {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = multiple
    if !types.isEmpty { panel.allowedContentTypes = types }
    return panel.runModal() == .OK ? panel.urls : []
}

@MainActor
func chooseFolder(prompt: String = "Choose") -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func chooseSaveLocation(name: String, type: UTType) -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [type]
    return panel.runModal() == .OK ? panel.url : nil
}

/// A dashed box you can drop files on, with a button as the click alternative.
struct DropZone: View {
    var title: String
    var subtitle: String
    var systemImage = "square.and.arrow.down"
    var types: [UTType] = []
    var multiple = true
    var onFiles: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Button("Choose…") {
                let urls = chooseFiles(types: types, multiple: multiple)
                if !urls.isEmpty { onFiles(urls) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14))
        )
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            onFiles(multiple ? files : Array(files.prefix(1)))
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// Page layout shared by every section: title, subtitle, then content.
struct SectionPage<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusLine: View {
    var text: String?
    var body: some View {
        if let text {
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
