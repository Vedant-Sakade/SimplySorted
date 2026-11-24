import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case sort, moveTo, images, pdf, text, uninstall
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sort: "Sort"
        case .moveTo: "Move to…"
        case .images: "Images"
        case .pdf: "PDF"
        case .text: "Text from Screen"
        case .uninstall: "Uninstall Apps"
        }
    }
    var tabTitle: String {
        switch self {
        case .text: "Text"
        case .uninstall: "Uninstall"
        default: title.replacingOccurrences(of: "…", with: "")
        }
    }
    var subtitle: String {
        switch self {
        case .sort: "One click puts every loose file into its type folder, or let it run on a schedule. Nothing is overwritten, and you can undo."
        case .moveTo: "Keep favourite folders here. Drop files on one to send them there."
        case .images: "Convert, shrink, enlarge and resize photos. Originals are never touched."
        case .pdf: "Merge, split or shrink PDFs. Your original files are never changed."
        case .text: "Copy the text out of any screenshot or picture. Runs on your Mac."
        case .uninstall: "Remove an app and the files it left behind. Everything goes to the Trash first."
        }
    }
    var symbol: String {
        switch self {
        case .sort: "sparkles"
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
    @State private var selection: SidebarItem
    /// Tabs opened so far. They stay alive when you switch away, so a job in progress, a picked image
    /// or a result is still there when you come back.
    @State private var visited: Set<SidebarItem>

    /// Screenshots only: a ready-made page (with demo data) to show instead of the normal one.
    private let demoPages: [SidebarItem: AnyView]

    init(initial: SidebarItem = .sort, demoPages: [SidebarItem: AnyView] = [:]) {
        _selection = State(initialValue: initial)
        _visited = State(initialValue: [initial])
        self.demoPages = demoPages
    }

    @ViewBuilder private func page(_ item: SidebarItem) -> some View {
        if let demo = demoPages[item] {
            demo
        } else {
            realPage(item)
        }
    }

    @ViewBuilder private func realPage(_ item: SidebarItem) -> some View {
        switch item {
        case .sort: SortView()
        case .moveTo: MoveToView()
        case .images: ImagesView()
        case .pdf: PDFToolsView()
        case .text: TextFromImageView()
        case .uninstall: UninstallerView()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TabBar(selection: $selection)
            ZStack(alignment: .top) {
                ForEach(SidebarItem.allCases.filter { visited.contains($0) }, id: \.self) { item in
                    page(item)
                        .opacity(selection == item ? 1 : 0)
                        .allowsHitTesting(selection == item)
                        .accessibilityHidden(selection != item)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .foregroundStyle(Theme.ink)
        .font(.mono(14))
        .tint(Theme.ink)
        .background(Theme.bg.ignoresSafeArea())
        .frame(minWidth: 900, minHeight: 660)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .onChange(of: selection) { _, new in
            visited.insert(new)
            model.message = nil                     // "Sorted 214 files." must not follow you onto other tabs
            if new == .sort { model.refresh() }
        }
    }

    private var header: some View {
        PageHeader(item: selection, isDark: Binding(get: { model.appearance == .dark },
                                                    set: { model.setAppearance($0 ? .dark : .light) }))
    }
}

/// Title, one-or-two-line subtitle and the light/dark switch. Its height is the same on every page,
/// so the tab bar below never jumps when you change tabs.
struct PageHeader: View {
    var item: SidebarItem
    @Binding var isDark: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.mono(40, .regular)).lineLimit(1)
                Text(item.subtitle).font(.mono(12)).foregroundStyle(Theme.mute).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)   // always room for two lines
            }
            ThemeSwitch(isDark: $isDark).padding(.top, 6)
        }
        .padding(.bottom, 22)
    }
}

/// Icon + uppercase label tabs with a heavy rule under the selected one, like the reference.
struct TabBar: View {
    @Binding var selection: SidebarItem
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SidebarItem.allCases) { item in
                let selected = item == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = item }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .light))
                        Text(item.tabTitle).font(.mono(11, .semibold)).textCase(.uppercase).tracking(0.6).lineLimit(1)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 3)
                            if selected {
                                Rectangle().fill(Theme.ink).frame(height: 3).matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .foregroundStyle(selected ? Theme.ink : Theme.mute)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.subtitle)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1) }
    }
}
