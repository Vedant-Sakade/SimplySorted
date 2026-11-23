import SwiftUI
import AppKit

@main
enum Launcher {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            MainActor.assumeIsolated { IconRenderer.render(to: args[i + 1]) }
            return
        }
        TidyUpApp.main()
    }
}

struct TidyUpApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("TidyUp", id: "main") {
            ContentView().environment(model)
        }
        .defaultSize(width: 960, height: 640)

        MenuBarExtra("TidyUp", systemImage: "sparkles") {
            MenuContent().environment(model)
        }
    }
}

private struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.pendingCount == 0 ? "Nothing to sort" : "Sort Now (\(model.pendingCount) files)") { model.sortNow() }
            .disabled(model.pendingCount == 0 || model.isWorking)
        if let label = model.undoLabel { Button(label) { model.undo() } }
        Button("Capture Text from Screen") { model.captureTextFromScreen() }
        if let message = model.message { Text(message) }
        Divider()
        Button("Open TidyUp") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit TidyUp") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
