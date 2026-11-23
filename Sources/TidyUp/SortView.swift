import SwiftUI
import TidyCore

struct SortView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = "all"

    private var shownMoves: [PlannedMove] {
        model.enabledFolders.compactMap { folder in
            (filter == "all" || filter == folder.path) ? model.plans[folder.path] : nil
        }.flatMap(\.moves)
    }
    private var counts: [Category: Int] {
        Dictionary(shownMoves.map { ($0.category, 1) }, uniquingKeysWith: +)
    }

    var body: some View {
        PageScroll {
            TwoColumns(stretch: true) {
                Card(title: "Folders", icon: "folder") {
                    VStack(spacing: 0) {
                        ForEach(model.folders) { folder in
                            FolderRow(folder: folder)
                            HairlineDivider()
                        }
                    }
                    Hint("Switch on the folders you want tidied. Downloads and Desktop are the usual ones.")
                    Button {
                        if let url = chooseFolder(prompt: "Add") { model.addFolder(url) }
                    } label: { Label("Add folder", systemImage: "plus") }
                        .buttonStyle(.pill(.outlined, compact: true))
                }
                Card(title: "Options", icon: "slider.horizontal.3", fill: true) {
                    Toggle(isOn: Binding(get: { model.groupFolders }, set: { model.setGroupFolders($0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Also group folders").font(.mono(13, .semibold))
                            Hint("Font-family folders go into Fonts, mockup folders into Mockups. Other folders stay put.")
                        }
                    }
                    .toggleStyle(.pill)
                }
            } right: {
                Card(title: "Ready to sort", icon: "sparkles", fill: true) {
                    TickDial(value: "\(model.pendingCount)",
                             caption: model.enabledFolders.isEmpty ? "no folder on"
                                 : (model.pendingCount == 0 ? "all tidy" : (model.pendingCount == 1 ? "file ready" : "files ready")),
                             detail: model.enabledFolders.isEmpty ? "switch one on" : model.enabledFolders.map(\.name).joined(separator: " · "),
                             progress: min(Double(model.pendingCount) / 300, 1))
                        .frame(width: 260, height: 260).frame(maxWidth: .infinity)

                    if model.pendingCount > 0 {
                        Button { model.sortNow() } label: {
                            Label(model.isWorking ? "Sorting…" : "Sort now", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pill(.filled))
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isWorking)
                        Hint("Moves \(model.pendingCount) file\(model.pendingCount == 1 ? "" : "s") into folders like Images, Documents and Archives. Nothing is overwritten, and you can undo it.")
                    } else {
                        Hint(model.enabledFolders.isEmpty
                             ? "Switch on at least one folder on the left to get started."
                             : "Nothing to sort. Your folders are already tidy.")
                    }

                    // Small buttons, side by side.
                    HStack(spacing: 10) {
                        Button { model.refresh() } label: { Label("Check again", systemImage: "arrow.clockwise") }
                            .buttonStyle(.pill(.outlined, compact: true))
                        if let label = model.undoLabel {
                            Button { model.undo() } label: { Label(label, systemImage: "arrow.uturn.backward") }
                                .buttonStyle(.pill(.outlined, compact: true))
                                .disabled(model.isWorking)
                        }
                    }

                    ResultStrip()
                    ForEach(model.planErrors, id: \.self) { error in
                        StatusLine(text: error + " Allow TidyUp in System Settings > Privacy & Security > Files and Folders.", isError: true)
                    }
                }
            }

            AutoSortCard()

            if model.pendingCount > 0 {
                Card(title: "Preview by type", icon: "chart.bar") {
                    PillPicker(selection: $filter,
                               options: [("all", "All folders")] + model.enabledFolders.map { ($0.path, $0.name) })
                    TwoColumns {
                        ThinBars(items: Category.allCases.filter { counts[$0] != nil }
                            .map { .init(id: $0.rawValue, label: $0.short, value: counts[$0] ?? 0) })
                    } right: {
                        VStack(spacing: 0) {
                            ForEach(Category.allCases.filter { counts[$0] != nil }, id: \.self) { category in
                                TypeRow(category: category, moves: shownMoves.filter { $0.category == category })
                            }
                        }
                    }
                    let skipped = model.enabledFolders.reduce(0) { $0 + (model.plans[$1.path]?.skipped ?? 0) }
                    if skipped > 0 { Hint("\(skipped) item\(skipped == 1 ? "" : "s") left alone (folders, hidden files, unfinished downloads).") }
                }
            }
        }
        .onAppear { model.refresh() }
    }
}

private struct FolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: WatchedFolder

    var body: some View {
        HStack(spacing: 8) {
            // Clicking anywhere on the folder (switch, name, count) turns it on or off.
            Toggle(isOn: Binding(get: { folder.enabled }, set: { _ in model.toggle(folder) })) {
                HStack(spacing: 10) {
                    Image(systemName: "folder").font(.system(size: 16, weight: .light))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name).font(.mono(14, .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.mono(11)).foregroundStyle(Theme.mute).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if folder.enabled, let plan = model.plans[folder.path] {
                        Text("\(plan.moves.count) to sort").font(.mono(12)).foregroundStyle(Theme.mute)
                    }
                }
            }
            .toggleStyle(.pill)
            Button { model.removeFolder(folder) } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 28)).help("Remove \(folder.name) from this list")
        }
        .padding(.vertical, 6)
    }
}

/// Shows what just happened.
private struct ResultStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.message {
            Label(message, systemImage: "checkmark.circle").font(.mono(13)).textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.4), lineWidth: 1))
        }
    }
}

private struct TypeRow: View {
    let category: Category
    let moves: [PlannedMove]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: category.symbol).font(.system(size: 14, weight: .light)).frame(width: 20)
                    Text(category.rawValue).font(.mono(12, .semibold)).textCase(.uppercase).tracking(0.5)
                    Spacer()
                    Text("\(moves.count)").font(.mono(12))
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mute)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(moves.prefix(40), id: \.self) { move in
                        Text(move.source.lastPathComponent).font(.mono(11)).foregroundStyle(Theme.mute).lineLimit(1)
                    }
                    if moves.count > 40 { Hint("and \(moves.count - 40) more") }
                }
                .padding(.leading, 30)
            }
            HairlineDivider().padding(.top, 4)
        }
        .padding(.top, 8)
    }
}
