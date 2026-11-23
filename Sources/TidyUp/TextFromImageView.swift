import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TidyCore

struct TextFromImageView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        SectionPage(title: "Text from Screen", subtitle: "Copy the text out of any screenshot, photo or picture. Runs on your Mac — nothing is uploaded.") {
            HStack {
                Button {
                    model.captureTextFromScreen { text = $0 }
                } label: {
                    Label("Capture Screen Area", systemImage: "viewfinder").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Text("Drag over the text you want. It is copied to your clipboard.").font(.callout).foregroundStyle(.secondary)
            }

            DropZone(title: "Or drop an image", subtitle: "Screenshot, scan or photo of a page", systemImage: "text.viewfinder", types: [.image], multiple: false) { files in
                if let file = files.first { read(file) }
            }

            if working { ProgressView("Reading…") }
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }

            if !text.isEmpty {
                HStack {
                    Text("Result").font(.title3.bold())
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        model.message = "Copied."
                    }
                }
                TextEditor(text: $text)
                    .font(.body).frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            StatusLine(text: model.message)
        }
    }

    private func read(_ file: URL) {
        working = true; error = nil
        Task.detached {
            do {
                let result = try TextRecognizer.recognize(imageAt: file)
                await MainActor.run { [result] in
                    text = result; working = false
                    if result.isEmpty { error = "No text found in that image." }
                    else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        model.message = "Read \(result.count) characters and copied them."
                    }
                }
            } catch {
                await MainActor.run { self.working = false; self.error = "Could not read that image: \(error.localizedDescription)" }
            }
        }
    }
}
