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

    /// The arguments only exist so the preview renderer can draw each size mode.
    init(initialMode: SizeMode = .original, percent: Double = 50, width: String? = nil,
         sourceSize: (width: Int, height: Int) = (4032, 3024), sampleImage: URL? = nil) {
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
    }

    private func choose(_ urls: [URL]) {
        files = urls; results = []; errors = []
        firstSize = urls.first.flatMap { ImageTools.pixelSize(of: $0) }
        previewImage = urls.first.flatMap { Self.thumbnail(of: $0) }
    }

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
        PageScroll {
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
                            Image(nsImage: previewImage).resizable().scaledToFit()
                                .frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink.opacity(0.25), lineWidth: 1))
                                .frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(files.count) selected").font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.6)
                            ForEach(Array(files.prefix(5)), id: \.self) { url in
                                HStack(spacing: 10) {
                                    Image(systemName: "photo").font(.system(size: 12, weight: .light))
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(fileLine(url)).foregroundStyle(Theme.mute).lineLimit(1)
                                }
                                .font(.mono(11))
                            }
                            if files.count > 5 { Hint("and \(files.count - 5) more") }
                        }
                    }
                }
            } right: {
                Card(title: "Settings", icon: "slider.horizontal.3") {
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
                    Button { convert() } label: {
                        Label(working ? "Working…" : "Convert", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.filled))
                    .disabled(files.isEmpty || working)
                    if files.isEmpty { Hint("Drop or choose some images first.") }
                }
            }

            if !results.isEmpty || !errors.isEmpty {
                Card(title: "Result", icon: "checkmark.circle") {
                    if !results.isEmpty {
                        let before = results.reduce(0) { $0 + $1.inputBytes }, after = results.reduce(0) { $0 + $1.outputBytes }
                        Text("\(results.count) converted · \(formatBytes(before)) → \(formatBytes(after))").font(.mono(16, .medium))
                        ForEach(results, id: \.output) { r in
                            HStack(spacing: 10) {
                                Image(systemName: "photo").font(.system(size: 13, weight: .light))
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
        }
    }

    private func convert() {
        working = true; results = []; errors = []
        let options = ImageOptions(format: format, quality: quality, resize: resizeMode, stripMetadata: strip,
                                  allowEnlarge: canEnlarge, sharpen: sharpen && canEnlarge)
        let list = files, folder = outputFolder
        Task.detached {
            var done: [ImageResult] = [], failed: [String] = []
            for file in list {
                do { done.append(try ImageTools.convert(file, options: options, outputFolder: folder)) }
                catch { failed.append(error.localizedDescription) }
            }
            await MainActor.run { [done, failed] in results = done; errors = failed; working = false }
        }
    }
}
