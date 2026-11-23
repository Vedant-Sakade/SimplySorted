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

    private let sizes = [(0, "Original size"), (3840, "4K (3840 px)"), (2560, "2560 px"), (1920, "Full HD (1920 px)"), (1280, "1280 px"), (800, "800 px")]

    var body: some View {
        SectionPage(title: "Images", subtitle: "Convert (HEIC to JPG, PNG…), shrink and resize photos. Originals are never touched.") {
            DropZone(title: "Drop images here", subtitle: "JPG, PNG, HEIC, TIFF, WebP and more", systemImage: "photo.on.rectangle",
                     types: [.image]) { files = $0; results = []; errors = [] }

            if !files.isEmpty {
                Text("\(files.count) image\(files.count == 1 ? "" : "s") selected: \(files.prefix(3).map(\.lastPathComponent).joined(separator: ", "))\(files.count > 3 ? "…" : "")")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Picker("Convert to", selection: $format) {
                ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 320)

            if format.usesQuality {
                HStack {
                    Text("Quality"); Slider(value: $quality, in: 0.2...1).frame(maxWidth: 240)
                    Text("\(Int(quality * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Picker("Size", selection: $maxSize) {
                ForEach(sizes, id: \.0) { Text($0.1).tag($0.0) }
            }
            .frame(maxWidth: 320)
            Toggle("Remove location and camera info (metadata)", isOn: $strip)

            HStack {
                Text("Save to").foregroundStyle(.secondary)
                Text(outputFolder?.lastPathComponent ?? "Next to the originals")
                Button("Change…") { outputFolder = chooseFolder(prompt: "Save Here") }
                if outputFolder != nil { Button("Reset") { outputFolder = nil } }
            }

            Button { convert() } label: {
                Label(working ? "Working…" : "Convert", systemImage: "wand.and.stars").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(files.isEmpty || working)

            if !results.isEmpty {
                let before = results.reduce(0) { $0 + $1.inputBytes }, after = results.reduce(0) { $0 + $1.outputBytes }
                Label("Converted \(results.count): \(formatBytes(before)) → \(formatBytes(after))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                ForEach(results, id: \.output) { r in
                    HStack {
                        Text(r.output.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text("\(formatBytes(r.inputBytes)) → \(formatBytes(r.outputBytes))").foregroundStyle(.secondary)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([r.output]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain).help("Show in Finder")
                    }
                    .font(.callout)
                }
            }
            ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
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
