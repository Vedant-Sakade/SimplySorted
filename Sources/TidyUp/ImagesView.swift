import SwiftUI
import UniformTypeIdentifiers
import TidyCore

struct ImagesView: View {
    @State private var files: [URL] = []
    @State private var format: ImageFormat = .jpeg
    @State private var quality = 0.8
    @State private var sizeMode: SizeMode
    @State private var percent = 50.0
    @State private var widthText: String
    @State private var heightText = ""
    @State private var firstSize: (width: Int, height: Int)?

    /// The arguments only exist so the preview renderer can draw each size mode.
    init(initialMode: SizeMode = .original) {
        _sizeMode = State(initialValue: initialMode)
        _widthText = State(initialValue: initialMode == .pixels ? "1920" : "")
        _firstSize = State(initialValue: initialMode == .original ? nil : (4032, 3024))
    }
    @State private var strip = false
    @State private var outputFolder: URL?
    @State private var results: [ImageResult] = []
    @State private var errors: [String] = []
    @State private var working = false

    enum SizeMode: Hashable { case original, percent, pixels }

    private let quickSizes: [(Int, String)] = [(0, "Quick pick…"), (3840, "4K · 3840 px"), (2560, "2560 px"),
                                               (1920, "Full HD · 1920 px"), (1280, "1280 px"), (800, "800 px")]

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
        let out = resizeMode.targetSize(width: first.width, height: first.height)
        let more = files.count > 1 ? " (first of \(files.count))" : ""
        if out == first { return "\(first.width) × \(first.height) px stays the same" + more }
        return "\(first.width) × \(first.height) → \(out.width) × \(out.height) px" + more
    }

    private func digits(_ text: Binding<String>) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(5)) })
    }

    var body: some View {
        PageScroll {
            TwoColumns {
                Card(title: "Input", icon: "photo.on.rectangle") {
                    DropZone(title: "Drop images", subtitle: "JPG, PNG, HEIC, TIFF, WebP and more", systemImage: "photo.on.rectangle",
                             types: [.image]) { files = $0; results = []; errors = []; firstSize = $0.first.flatMap { ImageTools.pixelSize(of: $0) } }
                    if !files.isEmpty {
                        Label("\(files.count) selected: \(files.prefix(3).map(\.lastPathComponent).joined(separator: ", "))\(files.count > 3 ? "…" : "")",
                              systemImage: "checkmark.circle")
                            .font(.mono(11)).foregroundStyle(Theme.mute).lineLimit(2)
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
                            Slider(value: $percent, in: 10...100, step: 5).tint(Theme.ink).frame(maxWidth: 190)
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
                    if sizeMode != .original {
                        Hint(sizePreview ?? (sizeMode == .pixels
                             ? "Type a width, a height, or both. The shape is kept and images are never enlarged."
                             : "Pick a percentage. Images are never enlarged."))
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
        let options = ImageOptions(format: format, quality: quality, resize: resizeMode, stripMetadata: strip)
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
