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
        PageScroll {
            TwoColumns {
                Card(title: "Capture", icon: "viewfinder") {
                    Button { model.captureTextFromScreen { text = $0 } } label: {
                        Label("Capture screen area", systemImage: "viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.filled))
                    Hint("Drag over the text you want. It is copied to your clipboard and shown here.")
                    HairlineDivider()
                    DropZone(title: "Or drop an image", subtitle: "Screenshot, scan or photo of a page",
                             systemImage: "text.viewfinder", types: [.image], multiple: false) { files in
                        if let file = files.first { read(file) }
                    }
                }
            } right: {
                Card(title: "Result", icon: "text.alignleft") {
                    if working { Label("Reading…", systemImage: "hourglass").font(.mono(12)).foregroundStyle(Theme.mute) }
                    StatusLine(text: error, isError: true)
                    if text.isEmpty && !working && error == nil {
                        Hint("The text from your picture will appear here.")
                    }
                    if !text.isEmpty {
                        TextEditor(text: $text)
                            .font(.mono(12)).scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(10)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.5), lineWidth: 1))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            model.message = "Copied."
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(.pill(.outlined, compact: true))
                    }
                    StatusLine(text: model.message)
                }
            }
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
