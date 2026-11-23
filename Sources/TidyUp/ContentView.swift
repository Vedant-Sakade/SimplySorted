import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case sort, schedule, moveTo, images, pdf, text, uninstall
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sort: "Sort"
        case .schedule: "Schedule"
        case .moveTo: "Move to…"
        case .images: "Images"
        case .pdf: "PDF"
        case .text: "Text from Screen"
        case .uninstall: "Uninstall Apps"
        }
    }
    var symbol: String {
        switch self {
        case .sort: "sparkles"
        case .schedule: "clock"
        case .moveTo: "folder.badge.plus"
        case .images: "photo"
        case .pdf: "doc.richtext"
        case .text: "text.viewfinder"
        case .uninstall: "trash"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .sort

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection ?? .sort {
            case .sort: SortView()
            case .schedule: ScheduleView()
            case .moveTo: MoveToView()
            case .images: ImagesView()
            case .pdf: PDFToolsView()
            case .text: TextFromImageView()
            case .uninstall: UninstallerView()
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
