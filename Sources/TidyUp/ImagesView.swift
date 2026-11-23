import SwiftUI
import UniformTypeIdentifiers
import TidyCore

struct ImagesView: View {
    @State private var files: [URL] = []
    @State private var format: ImageFormat = .jpeg
    @State private var quality = 0.8
    @State private var maxSize = 0               // 0 = original size
    @State private var strip = false
    @State private var outputFolder: URL?
    @State private var results: [ImageResult] = []
    @State private var errors: [String] = []
    @State private var working = false

    private let sizes: [(Int, String)] = [(0, "Original size"), (3840, "4K · 3840 px"), (2560, "2560 px"),
                                          (1920, "Full HD · 1920 px"), (1280, "1280 px"), (800, "800 px")]

    var body: some View {
        PageScroll {
            TwoColumns {
                Card(title: "Input", icon: "photo.on.rectangle") {
                    DropZone(title: "Drop images", subtitle: "JPG, PNG, HEIC, TIFF, WebP and more", systemImage: "photo.on.rectangle",
                             types: [.image]) { files = $0; results = []; errors = [] }
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
                            Text("\(Int(quality * 100))%").font(.mono(12)).frame(width: 40, alignment: .trailing)
                        }
                    }
                    SettingRow(label: "Size") { PillPicker(selection: $maxSize, options: sizes, minWidth: 150) }
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
        let options = ImageOptions(format: format, quality: quality, maxDimension: maxSize == 0 ? nil : maxSize, stripMetadata: strip)
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
