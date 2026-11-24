import SwiftUI
import AppKit

@main
enum Launcher {
    static func main() {
        Fonts.register()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
            MainActor.assumeIsolated { PreviewRenderer.render(to: args[i + 1]) }
            return
        }
        if let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count {
            MainActor.assumeIsolated { ScreenshotRenderer.render(to: args[i + 1]) }
            return
        }
        TidyUpApp.main()
    }
}

struct TidyUpApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Simply Sorted", id: "main") {
            ContentView().environment(model)
                .preferredColorScheme(model.appearance == .dark ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 720)

        MenuBarExtra("Simply Sorted", systemImage: "sparkles") {
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
        Button(model.appearance == .dark ? "Switch to Light Mode" : "Switch to Dark Mode") {
            model.setAppearance(model.appearance.toggled)
        }
        Button("Capture Text from Screen") { model.captureTextFromScreen() }
        if let message = model.message { Text(message) }
        Divider()
        Button("Open Simply Sorted") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Simply Sorted") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
