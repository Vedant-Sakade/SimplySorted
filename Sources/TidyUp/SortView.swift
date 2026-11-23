import SwiftUI
import TidyCore

struct SortView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionPage(title: "Sort", subtitle: "One click puts every loose file into its type folder. Nothing is overwritten, and you can undo.") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.folders) { folder in
                    FolderRow(folder: folder)
                    Divider()
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Add Folder…") {
                    if let url = chooseFolder(prompt: "Add") { model.addFolder(url) }
                }
                Spacer()
                if let label = model.undoLabel {
                    Button(label) { model.undo() }.disabled(model.isWorking)
                }
                Button {
                    model.sortNow()
                } label: {
                    Label(model.pendingCount == 0 ? "Nothing to sort" : "Sort Now (\(model.pendingCount))", systemImage: "sparkles")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.pendingCount == 0 || model.isWorking)
            }

            StatusLine(text: model.message)
            ForEach(model.planErrors, id: \.self) { error in
                Label(error + " — allow TidyUp access in System Settings > Privacy & Security > Files and Folders.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }

            if model.pendingCount > 0 {
                Text("Preview").font(.title3.bold()).padding(.top, 4)
                ForEach(model.enabledFolders) { folder in
                    if let plan = model.plans[folder.path], !plan.moves.isEmpty {
                        PreviewGroup(folder: folder, plan: plan)
                    }
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
        HStack {
            Toggle("", isOn: Binding(get: { folder.enabled }, set: { _ in model.toggle(folder) })).labelsHidden()
            Image(systemName: "folder.fill").foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(folder.name)
                Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if folder.enabled, let plan = model.plans[folder.path] {
                Text("\(plan.moves.count) to sort").foregroundStyle(.secondary)
            }
            Button { model.removeFolder(folder) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).foregroundStyle(.tertiary).help("Remove from list")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

private struct PreviewGroup: View {
    let folder: WatchedFolder
    let plan: SortPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(folder.name).font(.headline)
            ForEach(Category.allCases.filter { plan.counts[$0] != nil }, id: \.self) { category in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(plan.moves.filter { $0.category == category }, id: \.self) { move in
                            Text(move.source.lastPathComponent).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                } label: {
                    Text("\(category.rawValue)  ·  \(plan.counts[category] ?? 0)")
                }
            }
            if plan.skipped > 0 {
                Text("\(plan.skipped) item\(plan.skipped == 1 ? "" : "s") left alone (folders, hidden files, unfinished downloads).")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
