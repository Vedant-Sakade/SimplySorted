import SwiftUI
import UniformTypeIdentifiers
import TidyCore

struct PDFToolsView: View {
    enum Mode: String, CaseIterable, Identifiable { case merge = "Merge", split = "Split", compress = "Compress"; var id: String { rawValue } }
    @State private var mode: Mode = .merge

    var body: some View {
        SectionPage(title: "PDF", subtitle: "Merge, split or shrink PDFs. Your original files are never changed.") {
            Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
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
        DropZone(title: "Drop PDFs to merge", subtitle: "They are joined in the order listed below", systemImage: "doc.on.doc", types: [.pdf]) {
            files.append(contentsOf: $0.filter { !files.contains($0) })
        }
        if !files.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack {
                        Text("\(index + 1).").foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                        Text(file.lastPathComponent).lineLimit(1)
                        Text("\(PDFTools.pageCount(of: file) ?? 0) pages").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { files.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                        Button { files.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }.disabled(index == files.count - 1)
                        Button { files.remove(at: index) } label: { Image(systemName: "xmark.circle") }
                    }
                    .buttonStyle(.plain).padding(.vertical, 5)
                    Divider()
                }
            }
            HStack {
                Button("Clear") { files = []; status = nil }
                Button("Merge…") { merge() }.buttonStyle(.borderedProminent).disabled(files.count < 2)
            }
        }
        if let status { Text(status).foregroundStyle(ok ? Color.green : Color.orange).font(.callout) }
    }

    private func merge() {
        guard let out = chooseSaveLocation(name: "Merged.pdf", type: .pdf) else { return }
        do { try PDFTools.merge(files, to: out); status = "Saved \(out.lastPathComponent)"; ok = true
            NSWorkspace.shared.activateFileViewerSelecting([out]) }
        catch { status = error.localizedDescription; ok = false }
    }
}

private struct SplitPane: View {
    @State private var file: URL?
    @State private var everyPage = true
    @State private var ranges = ""
    @State private var status: String?
    @State private var ok = true

    var body: some View {
        DropZone(title: "Drop a PDF to split", subtitle: "One file at a time", systemImage: "scissors", types: [.pdf], multiple: false) { file = $0.first; status = nil }
        if let file {
            let count = PDFTools.pageCount(of: file) ?? 0
            Text("\(file.lastPathComponent) — \(count) pages").foregroundStyle(.secondary)
            Picker("", selection: $everyPage) {
                Text("Every page as its own file").tag(true)
                Text("Page ranges").tag(false)
            }
            .pickerStyle(.radioGroup).labelsHidden()
            if !everyPage {
                TextField("e.g. 1-3, 5, 8-10  (each range becomes one file)", text: $ranges).frame(maxWidth: 420)
            }
            Button("Split") { split(file, pages: count) }.buttonStyle(.borderedProminent).disabled(!everyPage && ranges.isEmpty)
        }
        if let status { Text(status).foregroundStyle(ok ? Color.green : Color.orange).font(.callout) }
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
        DropZone(title: "Drop PDFs to shrink", subtitle: "Best for scans and picture-heavy PDFs", systemImage: "arrow.down.right.and.arrow.up.left", types: [.pdf]) { files = $0; status = [] }
        if !files.isEmpty {
            Text("\(files.count) file\(files.count == 1 ? "" : "s") selected").foregroundStyle(.secondary)
            HStack { Text("Quality"); Slider(value: $quality, in: 0.2...0.9).frame(maxWidth: 240); Text("\(Int(quality * 100))%").monospacedDigit() }
            Picker("Detail", selection: $dpi) {
                Text("Screen (96 dpi)").tag(96.0)
                Text("Good (144 dpi)").tag(144.0)
                Text("Print (200 dpi)").tag(200.0)
            }.frame(maxWidth: 300)
            Text("Pages are turned into images, so text can no longer be selected or searched. If a file would not get smaller, it is left alone.")
                .font(.callout).foregroundStyle(.secondary)
            Button(working ? "Working…" : "Compress") { compress() }.buttonStyle(.borderedProminent).disabled(working)
        }
        ForEach(status, id: \.self) { Text($0).font(.callout) }
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
                        ? "✓ \(file.lastPathComponent): \(formatBytes(r.before)) → \(formatBytes(r.after)) (saved as \(out.lastPathComponent))"
                        : "– \(file.lastPathComponent): would not get smaller, left alone")
                } catch { lines.append("⚠︎ \(file.lastPathComponent): \(error.localizedDescription)") }
            }
            await MainActor.run { [lines] in status = lines; working = false }
        }
    }
}
