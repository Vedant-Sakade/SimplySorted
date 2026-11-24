import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import TidyCore

struct PDFToolsView: View {
    enum Mode: String, Hashable { case merge, split, delete, compress }
    @State private var mode: Mode = .merge

    var body: some View {
        PageScroll {
            HStack {
                PillSegmented(selection: $mode, options: [(.merge, "Merge"), (.split, "Split"), (.delete, "Delete pages"), (.compress, "Compress")])
                Spacer()
            }
            switch mode {
            case .merge: MergePane()
            case .split: SplitPane()
            case .delete: DeletePane()
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
        TwoColumns(stretch: true) {
            Card(title: "Input", icon: "doc.on.doc", fill: true) {
                DropZone(title: "Drop PDFs to merge", subtitle: "They are joined in the order listed", systemImage: "doc.on.doc", types: [.pdf]) {
                    files.append(contentsOf: $0.filter { !files.contains($0) })
                }
                Hint("Add as many PDFs as you like, then use the arrows on the right to put them in order. The cross removes one by mistake.")
            }
        } right: {
            Card(title: "Order", icon: "list.number", fill: true) {
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
        TwoColumns(stretch: true) {
            Card(title: "Input", icon: "scissors", fill: true) {
                DropZone(title: "Drop a PDF to split", subtitle: "One file at a time", systemImage: "scissors", types: [.pdf], multiple: false) {
                    file = $0.first; status = nil
                }
                if let file {
                    PickedFileRow(name: file.lastPathComponent, detail: "\(PDFTools.pageCount(of: file) ?? 0) pages") { self.file = nil; status = nil }
                }
            }
        } right: {
            Card(title: "Split by", icon: "slider.horizontal.3", fill: true) {
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
    @State private var progressDone = 0
    @State private var cancelled = false
    @State private var justDone = false
    @State private var finishTick = 0
    @State private var job: Task<Void, Never>?

    var body: some View {
        TwoColumns(stretch: true) {
            Card(title: "Input", icon: "arrow.down.right.and.arrow.up.left", fill: true) {
                DropZone(title: "Drop PDFs to shrink", subtitle: "Best for scans and picture-heavy PDFs",
                         systemImage: "arrow.down.right.and.arrow.up.left", types: [.pdf]) { files = $0; status = []; justDone = false }
                if !files.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(files.count) selected").font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.6)
                            Spacer()
                            Button { files = []; status = [] } label: { Label("Clear all", systemImage: "xmark.circle") }
                                .buttonStyle(.pill(.outlined, compact: true)).disabled(working)
                        }
                        ForEach(files, id: \.self) { url in
                            PickedFileRow(name: url.lastPathComponent, detail: formatBytes(Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))) {
                                files.removeAll { $0 == url }
                            }
                            .disabled(working)
                        }
                    }
                }
            }
        } right: {
            Card(title: "Settings", icon: "slider.horizontal.3", fill: true) {
                SettingRow(label: "Quality") {
                    Slider(value: $quality, in: 0.2...1).tint(Theme.ink).frame(maxWidth: 190)
                    Text("\(Int((quality * 100).rounded()))%").font(.mono(12)).frame(width: 40, alignment: .trailing)
                }
                SettingRow(label: "Detail") {
                    PillPicker(selection: $dpi, options: [(96.0, "Screen · 96 dpi"), (144.0, "Good · 144 dpi"), (200.0, "Print · 200 dpi")], minWidth: 150)
                }
                Hint("Pages are turned into images, so text can no longer be selected or searched. A file that would not get smaller is left alone.")
                if quality >= 0.9 || dpi >= 200 {
                    Hint("High quality keeps pages sharp but the file may not shrink much. If it can’t get smaller, it is left as it is.")
                }
                if working {
                    WorkProgress(title: files.count > 1 ? "Compressing \(min(progressDone + 1, files.count)) of \(files.count)…" : "Compressing…",
                                 fraction: files.count > 1 ? Double(progressDone) / Double(files.count) : nil,
                                 onCancel: files.count > 1 ? { job?.cancel() } : nil)
                } else if justDone {
                    DonePill()
                } else {
                    Button { compress() } label: {
                        Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.filled)).disabled(files.isEmpty)
                }
                if files.isEmpty { Hint("Drop one or more PDFs first.") }
                if cancelled { StatusLine(text: "Cancelled after \(progressDone) of \(files.count).", isError: true) }
                ForEach(status, id: \.self) { Text($0).font(.mono(11)).foregroundStyle(Theme.mute) }
            }
        }
    }

    private func compress() {
        working = true; status = []; cancelled = false; justDone = false; progressDone = 0
        let list = files, q = quality, d = dpi
        let started = Date()
        job = Task.detached(priority: .userInitiated) {
            var lines: [String] = []
            var failed = false, stopped = false, done = 0
            for file in list {
                if Task.isCancelled { stopped = true; break }
                let out = PDFTools.unique(file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-compressed.pdf"))
                do {
                    let r = try PDFTools.compress(file, quality: q, dpi: d, to: out)
                    lines.append(r.output != nil
                        ? "✓ \(file.lastPathComponent): \(formatBytes(r.before)) → \(formatBytes(r.after)), saved as \(out.lastPathComponent)"
                        : "– \(file.lastPathComponent): would not get smaller, left alone")
                } catch { lines.append("! \(file.lastPathComponent): \(error.localizedDescription)"); failed = true }
                done += 1
                let completed = done
                await MainActor.run { progressDone = completed }
            }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.6, !stopped { try? await Task.sleep(nanoseconds: UInt64((0.6 - elapsed) * 1_000_000_000)) }
            let finalLines = lines, anyFailed = failed, wasStopped = stopped
            let tick = await MainActor.run { () -> Int in
                status = finalLines; working = false; job = nil; cancelled = wasStopped
                justDone = !anyFailed && !wasStopped && !finalLines.isEmpty
                finishTick += 1
                return finishTick
            }
            if await MainActor.run(body: { justDone }) {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run { if finishTick == tick { justDone = false } }
            }
        }
    }
}

/// A picked file with a cross to take it out again (for a wrong pick).
struct PickedFileRow: View {
    var name: String
    var detail: String
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc").font(.system(size: 12, weight: .light))
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(detail).foregroundStyle(Theme.mute).lineLimit(1)
            Button(action: onRemove) { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 20)).help("Remove \(name)")
        }
        .font(.mono(11))
    }
}


// MARK: - Delete pages

/// One page picture. Click to mark it for deletion. (Display only, so it can be tested without a real PDF.)
struct ThumbCell: View {
    var number: Int
    var image: NSImage?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card)
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().padding(6)
                    } else {
                        Image(systemName: "doc").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.mute)
                    }
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warn.opacity(0.18))
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.warn)
                    }
                }
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Theme.warn : Theme.ink.opacity(0.5), lineWidth: selected ? 2.5 : 1))
                Text("\(number)").font(.mono(12, selected ? .semibold : .regular)).foregroundStyle(selected ? Theme.warn : Theme.mute)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(number)")
        .accessibilityValue(selected ? "marked for deletion" : "kept")
    }
}

/// Loads a page picture only when the cell scrolls into view.
private struct PageThumb: View {
    let document: PDFDocument
    let number: Int
    let selected: Bool
    let action: () -> Void
    @State private var image: NSImage?

    var body: some View {
        ThumbCell(number: number, image: image, selected: selected, action: action)
            .task {
                image = document.page(at: number - 1)?.thumbnail(of: CGSize(width: 260, height: 340), for: .cropBox)
            }
    }
}

struct DeletePane: View {
    @State private var file: URL?
    @State private var document: PDFDocument?
    @State private var pageCount = 0
    @State private var selected: Set<Int> = []
    @State private var rangeText = ""
    @State private var rangeError: String?
    @State private var syncingFromText = false
    @State private var status: String?
    @State private var ok = true

    init(previewFile: URL? = nil) {
        // Only used for design previews: opens with a PDF loaded and two pages picked.
        guard let previewFile, let doc = PDFDocument(url: previewFile) else { return }
        _file = State(initialValue: previewFile)
        _document = State(initialValue: doc)
        _pageCount = State(initialValue: doc.pageCount)
        _selected = State(initialValue: [2, 5])
        _rangeText = State(initialValue: "2, 5")
    }

    private var keepCount: Int { pageCount - selected.count }
    private var canDelete: Bool { !selected.isEmpty && selected.count < pageCount }

    var body: some View {
        TwoColumns(stretch: true) {
            Card(title: "Input", icon: "doc", fill: true) {
                DropZone(title: "Drop a PDF", subtitle: "Then click the pages you want to remove",
                         systemImage: "doc", types: [.pdf], multiple: false) { load($0.first) }
                if let file {
                    PickedFileRow(name: file.lastPathComponent, detail: "\(pageCount) pages") { clear() }
                }
            }
        } right: {
            Card(title: "Pages to delete", icon: "trash", fill: true) {
                if file == nil {
                    Hint("Drop a PDF first.")
                } else {
                    PillField(placeholder: "Type pages, e.g. 2, 5-7", text: $rangeText, icon: "number")
                    StatusLine(text: rangeError, isError: true)
                    Text(selected.isEmpty ? "No pages picked yet" : "\(selected.count) picked · the new file will have \(keepCount) page\(keepCount == 1 ? "" : "s")")
                        .font(.mono(14, .semibold))
                    Hint("Click pages in the grid below to pick them, or type page numbers above.")
                    if selected.count >= pageCount && pageCount > 0 { StatusLine(text: "You can’t delete every page. Keep at least one.", isError: true) }
                    HStack {
                        Button { delete() } label: { Label("Delete pages", systemImage: "trash") }
                            .buttonStyle(.pill(.filled)).disabled(!canDelete)
                        Button { selected = []; rangeText = "" } label: { Label("Clear", systemImage: "xmark") }
                            .buttonStyle(.pill(.outlined)).disabled(selected.isEmpty)
                    }
                    Hint("Your original file is not changed. The result is saved next to it as a new file.")
                }
                StatusLine(text: status, isError: !ok)
            }
        }
        .onChange(of: rangeText) { applyTypedPages() }
        .onChange(of: selected) {
            if syncingFromText { syncingFromText = false; return }
            rangeText = PDFTools.formatRanges(selected)
            rangeError = nil
        }

        if let document, pageCount > 0 {
            Card(title: "Pick pages", icon: "square.grid.3x3") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 16)], spacing: 16) {
                    ForEach(1...pageCount, id: \.self) { number in
                        PageThumb(document: document, number: number, selected: selected.contains(number)) {
                            if selected.contains(number) { selected.remove(number) } else { selected.insert(number) }
                        }
                    }
                }
            }
        }
    }

    private func clear() {
        file = nil; document = nil; pageCount = 0; selected = []; rangeText = ""; rangeError = nil; status = nil
    }

    private func load(_ url: URL?) {
        status = nil; rangeError = nil; selected = []; rangeText = ""
        guard let url else { return }
        guard let doc = PDFDocument(url: url) else { file = nil; document = nil; pageCount = 0; status = "That file could not be opened as a PDF."; ok = false; return }
        if doc.isLocked { file = nil; document = nil; pageCount = 0; status = "That PDF is password protected. Unlock it first."; ok = false; return }
        file = url; document = doc; pageCount = doc.pageCount
    }

    /// Typing page numbers updates the picked pages (ignoring half-typed input).
    private func applyTypedPages() {
        guard pageCount > 0 else { return }
        let trimmed = rangeText.trimmingCharacters(in: .whitespaces)
        let parsed: Set<Int>
        if trimmed.isEmpty { parsed = [] }
        else {
            do { parsed = try PDFTools.pageSet(from: trimmed, pageCount: pageCount); rangeError = nil }
            catch { rangeError = error.localizedDescription; return }
        }
        if parsed != selected { syncingFromText = true; selected = parsed }
    }

    private func delete() {
        guard let file else { return }
        let out = PDFTools.unique(file.deletingLastPathComponent()
            .appendingPathComponent(file.deletingPathExtension().lastPathComponent + " - pages removed.pdf"))
        do {
            let remaining = try PDFTools.deletePages(from: file, pages: selected, to: out)
            status = "Saved “\(out.lastPathComponent)” with \(remaining) page\(remaining == 1 ? "" : "s")."; ok = true
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch { status = error.localizedDescription; ok = false }
    }
}
