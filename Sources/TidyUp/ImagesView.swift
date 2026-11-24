import SwiftUI
import UniformTypeIdentifiers
import TidyCore

struct ImagesView: View {
    @State private var files: [URL] = []
    @State private var format: ImageFormat = .jpeg
    @State private var quality = 0.8
    @State private var sizeMode: SizeMode
    @State private var percent: Double
    @State private var enlarge = true        // Pixels mode: also grow images smaller than the box
    @State private var sharpen = false
    @State private var widthText: String
    @State private var heightText = ""
    @State private var firstSize: (width: Int, height: Int)?
    @State private var previewImage: NSImage?

    @State private var strip = false
    @State private var outputFolder: URL?
    @State private var results: [ImageResult] = []
    @State private var errors: [String] = []
    @State private var working = false
    @State private var progressDone = 0
    @State private var progressTotal = 0
    @State private var cancelled = false
    @State private var justDone = false          // the button shows "Done" for a couple of seconds
    @State private var scrollTick = 0
    @State private var job: Task<Void, Never>?

    /// The arguments only exist so the preview renderer can draw each size mode.
    enum DemoState { case working(done: Int, total: Int), finished }

    init(initialMode: SizeMode = .original, percent: Double = 50, width: String? = nil,
         sourceSize: (width: Int, height: Int) = (4032, 3024), sampleImage: URL? = nil, demo: DemoState? = nil) {
        _sizeMode = State(initialValue: initialMode)
        _percent = State(initialValue: percent)
        _widthText = State(initialValue: width ?? (initialMode == .pixels ? "1920" : ""))
        if let sampleImage {
            _files = State(initialValue: [sampleImage])
            _firstSize = State(initialValue: ImageTools.pixelSize(of: sampleImage))
            _previewImage = State(initialValue: Self.thumbnail(of: sampleImage))
        } else {
            _firstSize = State(initialValue: initialMode == .original ? nil : sourceSize)
        }
        switch demo {
        case .working(let done, let total)?:
            _working = State(initialValue: true); _progressDone = State(initialValue: done); _progressTotal = State(initialValue: total)
        case .finished?:
            let a = URL(fileURLWithPath: "/demo/Holiday photo.jpg"), b = URL(fileURLWithPath: "/demo/Beach.jpg")
            _results = State(initialValue: [
                ImageResult(source: URL(fileURLWithPath: "/demo/Holiday photo.png"), output: a, inputBytes: 2_240_000, outputBytes: 612_000),
                ImageResult(source: URL(fileURLWithPath: "/demo/Beach.png"), output: b, inputBytes: 3_900_000, outputBytes: 1_020_000)])
            _justDone = State(initialValue: true)
        case nil: break
        }
    }

    /// Takes the pictures at `urls` as the new selection (or an empty one).
    private func choose(_ urls: [URL]) {
        files = urls; results = []; errors = []; cancelled = false; justDone = false
        firstSize = urls.first.flatMap { ImageTools.pixelSize(of: $0) }
        previewImage = urls.first.flatMap { Self.thumbnail(of: $0) }
    }

    private func remove(_ url: URL) { choose(files.filter { $0 != url }) }

    /// A small upright picture of the image for the Input card.
    static func thumbnail(of url: URL, maxSide: Int = 640) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxSide]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func fileLine(_ url: URL) -> String {
        let size = ImageTools.pixelSize(of: url).map { "\($0.width) × \($0.height)" } ?? "unreadable"
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { formatBytes(Int64($0)) } ?? ""
        return [size, bytes].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    enum SizeMode: Hashable { case original, percent, pixels }

    private let quickSizes: [(Int, String)] = [(0, "Quick pick…"), (7680, "8K · 7680 px"), (3840, "4K · 3840 px"),
                                               (2560, "QHD · 2560 px"), (2048, "2K · 2048 px"), (1920, "Full HD · 1920 px"),
                                               (1280, "1280 px"), (800, "800 px")]

    /// Whether this setup can make pictures bigger than they are.
    private var canEnlarge: Bool {
        switch sizeMode {
        case .original: false
        case .percent: percent > 100
        case .pixels: enlarge
        }
    }

    private var resizeMode: ResizeMode {
        switch sizeMode {
        case .original: .original
        case .percent: .percent(percent / 100)
        case .pixels:
            Int(widthText) == nil && Int(heightText) == nil ? .original : .fit(width: Int(widthText), height: Int(heightText))
        }
    }

    /// "4032 × 3024 → 2016 × 1512 px" for the first picked image, or nil when nothing changes.
    private var sizePreview: String? {
        guard let first = firstSize, resizeMode != .original else { return nil }
        let out = resizeMode.targetSize(width: first.width, height: first.height, allowEnlarge: canEnlarge)
        let more = files.count > 1 ? " (first of \(files.count))" : ""
        if out == first { return "\(first.width) × \(first.height) px stays the same" + more }
        return "\(first.width) × \(first.height) → \(out.width) × \(out.height) px" + more
    }

    /// Extra notes about enlarging: it is estimated, big results are heavy, and the 16,000 px limit.
    private var enlargeNote: String? {
        guard canEnlarge else { return nil }
        var notes: [String] = []
        if let first = firstSize {
            let out = resizeMode.targetSize(width: first.width, height: first.height, allowEnlarge: true)
            guard out.width > first.width || out.height > first.height else { return nil }
            notes.append("Bigger, not sharper: new pixels are estimated from the old ones.")
            let mp = Double(out.width * out.height) / 1_000_000
            if resizeMode.isCapped(width: first.width, height: first.height, allowEnlarge: true) {
                notes.append("Limited to \(ResizeMode.maxOutputSide.formatted()) px on the longest side.")
            }
            if mp >= 50 { notes.append(String(format: "About %.0f megapixels: this may take a moment and make a large file.", mp)) }
        } else {
            notes.append("Bigger, not sharper: new pixels are estimated from the old ones.")
        }
        return notes.joined(separator: " ")
    }

    private func digits(_ text: Binding<String>) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(5)) })
    }

    var body: some View {
        PageScroll(scrollTo: (id: "result", tick: scrollTick)) {
            TwoColumns(stretch: true) {
                Card(title: "Input", icon: "photo.on.rectangle", fill: true) {
                    DropZone(title: "Drop images", subtitle: "JPG, PNG, HEIC, TIFF, WebP and more", systemImage: "photo.on.rectangle",
                             types: [.image]) { choose($0) }
                    if files.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What you can do").font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.6)
                            Hint("Convert photos between JPEG, PNG and HEIC.")
                            Hint("Shrink big photos for email and the web.")
                            Hint("Enlarge small ones up to 2K, 4K or 8K.")
                            Hint("Remove location and camera info before sharing.")
                        }
                        .padding(.top, 6)
                    } else {
                        if let previewImage {
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: previewImage).resizable().scaledToFit()
                                    .frame(maxHeight: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink.opacity(0.25), lineWidth: 1))
                                if let first = files.first {
                                    Button { remove(first) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(IconButtonStyle(size: 30))
                                        .background(Circle().fill(Theme.card))
                                        .padding(10)
                                        .help("Remove this image")
                                        .disabled(working)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(files.count) selected").font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.6)
                                Spacer()
                                Button { choose([]) } label: { Label("Clear all", systemImage: "xmark.circle") }
                                    .buttonStyle(.pill(.outlined, compact: true)).disabled(working)
                            }
                            ForEach(Array(files.prefix(5)), id: \.self) { url in
                                HStack(spacing: 10) {
                                    Image(systemName: "photo").font(.system(size: 12, weight: .light))
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(fileLine(url)).foregroundStyle(Theme.mute).lineLimit(1)
                                    Button { remove(url) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(IconButtonStyle(size: 20)).help("Remove \(url.lastPathComponent)")
                                        .disabled(working)
                                }
                                .font(.mono(11))
                            }
                            if files.count > 5 { Hint("and \(files.count - 5) more") }
                        }
                    }
                }
            } right: {
                Card(title: "Settings", icon: "slider.horizontal.3", fill: true) {
                    SettingRow(label: "Format") {
                        PillSegmented(selection: $format, options: ImageFormat.allCases.map { ($0, $0.title) })
                    }
                    if format.usesQuality {
                        SettingRow(label: "Quality") {
                            Slider(value: $quality, in: 0.2...1).tint(Theme.ink).frame(maxWidth: 190)
                            Text("\(Int((quality * 100).rounded()))%").font(.mono(12)).frame(width: 40, alignment: .trailing)
                        }
                    }
                    SettingRow(label: "Size") {
                        PillSegmented(selection: $sizeMode, options: [(.original, "Original"), (.percent, "Scale"), (.pixels, "Pixels")])
                    }
                    if sizeMode == .percent {
                        SettingRow(label: "Scale") {
                            Slider(value: $percent, in: 10...400, step: 5).tint(Theme.ink).frame(maxWidth: 190)
                            Text("\(Int(percent))%").font(.mono(12)).frame(width: 40, alignment: .trailing)
                        }
                    }
                    if sizeMode == .pixels {
                        SettingRow(label: "Width") {
                            PillField(placeholder: "any", text: digits($widthText)).frame(width: 96)
                            Text("px").font(.mono(12)).foregroundStyle(Theme.mute)
                        }
                        SettingRow(label: "Height") {
                            PillField(placeholder: "any", text: digits($heightText)).frame(width: 96)
                            Text("px").font(.mono(12)).foregroundStyle(Theme.mute)
                        }
                        SettingRow(label: "") {
                            PillPicker(selection: Binding(get: { 0 }, set: { if $0 > 0 { widthText = "\($0)"; heightText = "\($0)" } }),
                                       options: quickSizes, minWidth: 150)
                        }
                    }
                    if sizeMode == .pixels {
                        SettingRow(label: "Enlarge") {
                            Toggle(isOn: $enlarge) { Text("Also grow smaller images").font(.mono(12)) }.toggleStyle(.pill)
                        }
                    }
                    if canEnlarge {
                        SettingRow(label: "Sharpen") {
                            Toggle(isOn: $sharpen) { Text("Sharpen after enlarging").font(.mono(12)) }.toggleStyle(.pill)
                        }
                    }
                    if sizeMode != .original {
                        Hint(sizePreview ?? (sizeMode == .pixels
                             ? "Type a width, a height, or both. The shape is always kept."
                             : "Pick a percentage. Above 100% the image is enlarged."))
                        if let note = enlargeNote { Hint(note) }
                    }
                    SettingRow(label: "Privacy") {
                        Toggle(isOn: $strip) { Text("Remove location & camera info").font(.mono(12)) }.toggleStyle(.pill)
                    }
                    SettingRow(label: "Save to") {
                        Text(outputFolder?.lastPathComponent ?? "Next to originals").font(.mono(12)).lineLimit(1)
                        Button { outputFolder = chooseFolder(prompt: "Save Here") } label: { Image(systemName: "folder") }
                            .buttonStyle(IconButtonStyle(size: 26))
                        if outputFolder != nil {
                            Button { outputFolder = nil } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(IconButtonStyle(size: 26))
                        }
                    }
                    convertArea
                    if files.isEmpty { Hint("Drop or choose some images first.") }
                }
            }

            if !working, !results.isEmpty || !errors.isEmpty {
                resultCard.id("result")
            }
        }
    }

    // MARK: Convert button, progress and result

    @ViewBuilder private var convertArea: some View {
        if working {
            WorkProgress(title: progressTotal > 1 ? "Converting \(min(progressDone + 1, progressTotal)) of \(progressTotal)…" : "Converting…",
                         fraction: progressTotal > 1 ? Double(progressDone) / Double(progressTotal) : nil,
                         onCancel: progressTotal > 1 ? { job?.cancel() } : nil)
        } else if justDone {
            DonePill()
        } else {
            Button { convert() } label: {
                Label("Convert", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.filled))
            .disabled(files.isEmpty)
        }
    }

    private var resultCard: some View {
        let before = results.reduce(0) { $0 + $1.inputBytes }, after = results.reduce(0) { $0 + $1.outputBytes }
        let allGood = errors.isEmpty && !cancelled && !results.isEmpty
        let icon = allGood ? "checkmark.circle.fill" : (results.isEmpty && !cancelled ? "xmark.circle" : "exclamationmark.triangle")
        let title = allGood ? "Done" : (cancelled ? "Cancelled" : (results.isEmpty ? "Nothing converted" : "Done, with problems"))
        var detail: [String] = []
        if !results.isEmpty { detail.append("\(results.count) converted · \(formatBytes(before)) → \(formatBytes(after))") }
        if !errors.isEmpty { detail.append("\(errors.count) failed") }
        if cancelled { detail.append("stopped after \(progressDone) of \(progressTotal)") }
        return Card(title: "Result", icon: "checkmark.circle") {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 36, weight: .light))
                    .foregroundStyle(allGood ? Theme.good : Theme.warn)
                    .symbolEffect(.bounce, value: results.count)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.mono(20, .semibold))
                    Text(detail.joined(separator: " · ")).font(.mono(12)).foregroundStyle(Theme.mute)
                }
            }
            if !results.isEmpty {
                HairlineDivider()
                ForEach(results, id: \.output) { r in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.good)
                        Text(r.output.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text("\(formatBytes(r.inputBytes)) → \(formatBytes(r.outputBytes))").foregroundStyle(Theme.mute)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([r.output]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(IconButtonStyle(size: 24)).help("Show in Finder")
                    }
                    .font(.mono(12))
                    HairlineDivider()
                }
            }
            ForEach(errors, id: \.self) { StatusLine(text: $0, isError: true) }
        }
    }

    private func convert() {
        working = true; results = []; errors = []; cancelled = false; justDone = false
        progressDone = 0; progressTotal = files.count
        let options = ImageOptions(format: format, quality: quality, resize: resizeMode, stripMetadata: strip,
                                  allowEnlarge: canEnlarge, sharpen: sharpen && canEnlarge)
        let list = files, folder = outputFolder
        let started = Date()
        job = Task.detached(priority: .userInitiated) {
            let outcome = ImageTools.convertBatch(list, options: options, outputFolder: folder,
                                                  isCancelled: { Task.isCancelled },
                                                  progress: { completed, _ in DispatchQueue.main.async { progressDone = completed } })
            // A single small picture finishes in a blink; keep the progress visible long enough to be seen.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.6, !outcome.cancelled { try? await Task.sleep(nanoseconds: UInt64((0.6 - elapsed) * 1_000_000_000)) }
            let tick = await MainActor.run { () -> Int in
                results = outcome.results; errors = outcome.errors; cancelled = outcome.cancelled
                progressDone = outcome.completed
                working = false; job = nil
                justDone = !outcome.results.isEmpty && outcome.errors.isEmpty && !outcome.cancelled
                scrollTick += 1
                return scrollTick
            }
            if await MainActor.run(body: { justDone }) {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run { if scrollTick == tick { justDone = false } }   // not if a newer run finished meanwhile
            }
        }
    }
}
