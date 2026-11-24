import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TidyCore

struct TextFromImageView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @State private var picked: URL?
    @State private var pickedThumb: NSImage?

    var body: some View {
        PageScroll {
            TwoColumns(stretch: true) {
                Card(title: "Capture", icon: "viewfinder", fill: true) {
                    Button { model.captureTextFromScreen { text = $0 } } label: {
                        Label("Capture screen area", systemImage: "viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.filled))
                    Hint("Drag over the text you want. It is copied to your clipboard and shown here.")
                    HairlineDivider()
                    DropZone(title: "Or drop an image", subtitle: "Screenshot, scan or photo of a page",
                             systemImage: "text.viewfinder", types: [.image], multiple: false) { files in
                        if let file = files.first { pick(file) }
                    }
                    if let picked {
                        if let pickedThumb {
                            Image(nsImage: pickedThumb).resizable().scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink.opacity(0.25), lineWidth: 1))
                                .frame(maxWidth: .infinity)
                        }
                        PickedFileRow(name: picked.lastPathComponent, detail: "") { clearPicked() }
                            .disabled(working)
                    }
                }
            } right: {
                Card(title: "Result", icon: "text.alignleft", fill: true) {
                    if working { WorkProgress(title: "Reading the text…", fraction: nil) }
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
                        HStack(spacing: 10) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                model.message = "Copied."
                            } label: { Label("Copy", systemImage: "doc.on.doc") }
                                .buttonStyle(.pill(.outlined, compact: true))
                            Button { text = ""; error = nil; model.message = nil } label: { Label("Clear", systemImage: "xmark") }
                                .buttonStyle(.pill(.outlined, compact: true))
                        }
                    }
                    StatusLine(text: model.message)
                }
            }
        }
    }

    private func pick(_ file: URL) {
        picked = file
        pickedThumb = ImagesView.thumbnail(of: file, maxSide: 480)
        read(file)
    }

    private func clearPicked() {
        picked = nil; pickedThumb = nil; text = ""; error = nil; model.message = nil
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
