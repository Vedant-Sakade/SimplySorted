import SwiftUI
import UniformTypeIdentifiers
import TidyCore

struct PDFToolsView: View {
    enum Mode: String, Hashable { case merge, split, compress }
    @State private var mode: Mode = .merge

    var body: some View {
        PageScroll {
            HStack {
                PillSegmented(selection: $mode, options: [(.merge, "Merge"), (.split, "Split"), (.compress, "Compress")])
                Spacer()
            }
            switch mode {
            case .merge: MergePane()
            case .split: SplitPane()
            case .compress: CompressPane()
            }
        }
    }
}

private struct MergePane: View {
    @State private var files: [URL] = []
    @State private var status: String?
    @State private var ok = true

    var body: some View {
        TwoColumns {
            Card(title: "Input", icon: "doc.on.doc") {
                DropZone(title: "Drop PDFs to merge", subtitle: "They are joined in the order listed", systemImage: "doc.on.doc", types: [.pdf]) {
                    files.append(contentsOf: $0.filter { !files.contains($0) })
                }
            }
        } right: {
            Card(title: "Order", icon: "list.number") {
                if files.isEmpty { Hint("Nothing added yet.") }
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.mono(11, .semibold)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.lastPathComponent).lineLimit(1)
                            Text("\(PDFTools.pageCount(of: file) ?? 0) pages").font(.mono(10)).foregroundStyle(Theme.mute)
                        }
                        Spacer()
                        Button { files.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(IconButtonStyle(size: 24)).disabled(index == 0)
                        Button { files.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(IconButtonStyle(size: 24)).disabled(index == files.count - 1)
                        Button { files.remove(at: index) } label: { Image(systemName: "xmark") }
                            .buttonStyle(IconButtonStyle(size: 24))
                    }
                    .font(.mono(12))
                    HairlineDivider()
                }
                if files.count == 1 { Hint("Add at least one more PDF to merge.") }
                HStack {
                    Button { merge() } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                        .buttonStyle(.pill(.filled)).disabled(files.count < 2)
                    Button { files = []; status = nil } label: { Label("Clear", systemImage: "xmark") }
                        .buttonStyle(.pill(.outlined)).disabled(files.isEmpty)
                }
                StatusLine(text: status, isError: !ok)
            }
        }
    }

    private func merge() {
        guard let out = chooseSaveLocation(name: "Merged.pdf", type: .pdf) else { return }
        do {
            try PDFTools.merge(files, to: out); status = "Saved \(out.lastPathComponent)"; ok = true
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch { status = error.localizedDescription; ok = false }
    }
}

private struct SplitPane: View {
    @State private var file: URL?
    @State private var everyPage = true
    @State private var ranges = ""
    @State private var status: String?
    @State private var ok = true

    var body: some View {
        TwoColumns {
            Card(title: "Input", icon: "scissors") {
                DropZone(title: "Drop a PDF to split", subtitle: "One file at a time", systemImage: "scissors", types: [.pdf], multiple: false) {
                    file = $0.first; status = nil
                }
                if let file {
                    Label("\(file.lastPathComponent) · \(PDFTools.pageCount(of: file) ?? 0) pages", systemImage: "doc")
                        .font(.mono(11)).foregroundStyle(Theme.mute).lineLimit(2)
                }
            }
        } right: {
            Card(title: "Split by", icon: "slider.horizontal.3") {
                PillSegmented(selection: $everyPage, options: [(true, "Every page"), (false, "Ranges")])
                if !everyPage {
                    PillField(placeholder: "e.g. 1-3, 5, 8-10", text: $ranges, icon: "number")
                    Hint("Each range becomes its own file.")
                }
                Button { if let file { split(file, pages: PDFTools.pageCount(of: file) ?? 0) } } label: {
                    Label("Split", systemImage: "scissors").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.filled)).disabled(file == nil || (!everyPage && ranges.isEmpty))
                if file == nil { Hint("Drop a PDF first.") }
                StatusLine(text: status, isError: !ok)
            }
        }
    }

    private func split(_ file: URL, pages: Int) {
        do {
            let mode: PDFTools.SplitMode = everyPage ? .everyPage : .ranges(try PDFTools.parseRanges(ranges, pageCount: pages))
            let folder = file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + " - split", isDirectory: true)
            let out = try PDFTools.split(file, mode: mode, into: folder)
            status = "Created \(out.count) file\(out.count == 1 ? "" : "s") in “\(folder.lastPathComponent)”"; ok = true
            NSWorkspace.shared.activateFileViewerSelecting(out)
        } catch { status = error.localizedDescription; ok = false }
    }
}

private struct CompressPane: View {
    @State private var files: [URL] = []
    @State private var quality = 0.6
    @State private var dpi = 144.0
    @State private var status: [String] = []
    @State private var working = false

    var body: some View {
        TwoColumns {
            Card(title: "Input", icon: "arrow.down.right.and.arrow.up.left") {
                DropZone(title: "Drop PDFs to shrink", subtitle: "Best for scans and picture-heavy PDFs",
                         systemImage: "arrow.down.right.and.arrow.up.left", types: [.pdf]) { files = $0; status = [] }
                if !files.isEmpty {
                    Label("\(files.count) file\(files.count == 1 ? "" : "s") selected", systemImage: "checkmark.circle")
                        .font(.mono(11)).foregroundStyle(Theme.mute)
                }
            }
        } right: {
            Card(title: "Settings", icon: "slider.horizontal.3") {
                SettingRow(label: "Quality") {
                    Slider(value: $quality, in: 0.2...0.9).tint(Theme.ink).frame(maxWidth: 190)
                    Text("\(Int(quality * 100))%").font(.mono(12)).frame(width: 40, alignment: .trailing)
                }
                SettingRow(label: "Detail") {
                    PillPicker(selection: $dpi, options: [(96.0, "Screen · 96 dpi"), (144.0, "Good · 144 dpi"), (200.0, "Print · 200 dpi")], minWidth: 150)
                }
                Hint("Pages are turned into images, so text can no longer be selected or searched. A file that would not get smaller is left alone.")
                Button { compress() } label: {
                    Label(working ? "Working…" : "Compress", systemImage: "arrow.down.right.and.arrow.up.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.filled)).disabled(files.isEmpty || working)
                if files.isEmpty { Hint("Drop one or more PDFs first.") }
                ForEach(status, id: \.self) { Text($0).font(.mono(11)).foregroundStyle(Theme.mute) }
            }
        }
    }

    private func compress() {
        working = true; status = []
        let list = files, q = quality, d = dpi
        Task.detached {
            var lines: [String] = []
            for file in list {
                let out = PDFTools.unique(file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-compressed.pdf"))
                do {
                    let r = try PDFTools.compress(file, quality: q, dpi: d, to: out)
                    lines.append(r.output != nil
                        ? "✓ \(file.lastPathComponent): \(formatBytes(r.before)) → \(formatBytes(r.after)), saved as \(out.lastPathComponent)"
                        : "– \(file.lastPathComponent): would not get smaller, left alone")
                } catch { lines.append("! \(file.lastPathComponent): \(error.localizedDescription)") }
            }
            await MainActor.run { [lines] in status = lines; working = false }
        }
    }
}
