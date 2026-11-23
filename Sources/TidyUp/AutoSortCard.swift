import SwiftUI
import TidyCore

/// Schedule settings, shown on the Sort tab under Options.
struct AutoSortCard: View {
    @Environment(AppModel.self) private var model

    private var hours: [(Int, String)] { (0..<24).map { ($0, String(format: "%02d", $0)) } }
    private var minutes: [(Int, String)] {
        var values = Array(stride(from: 0, to: 60, by: 5))
        if !values.contains(model.schedule.minute) { values.append(model.schedule.minute); values.sort() }
        return values.map { ($0, String(format: "%02d", $0)) }
    }
    private var weekdays: [(Int, String)] { (1...7).map { ($0, Calendar.current.weekdaySymbols[$0 - 1]) } }

    var body: some View {
        @Bindable var model = model
        Card(title: "Auto sort", icon: "clock") {
            HStack(alignment: .top, spacing: 28) {
                // Left: the schedule
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $model.schedule.enabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sort automatically").font(.mono(14, .semibold))
                            Hint("Tidies the folders switched on above, on a schedule, without you clicking anything.")
                        }
                    }
                    .toggleStyle(.pill)

                    if model.schedule.enabled {
                        HairlineDivider()
                        SettingRow(label: "Repeat") {
                            PillSegmented(selection: $model.schedule.frequency, options: [(.daily, "Daily"), (.weekly, "Weekly")])
                        }
                        if model.schedule.frequency == .weekly {
                            SettingRow(label: "On") { PillPicker(selection: $model.schedule.weekday, options: weekdays, minWidth: 130) }
                        }
                        SettingRow(label: "At") {
                            HStack(spacing: 8) {
                                PillPicker(selection: $model.schedule.hour, options: hours)
                                Text(":")
                                PillPicker(selection: $model.schedule.minute, options: minutes)
                            }
                        }
                        if let next = model.nextScheduledRun {
                            Label("Next sort: \(next.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))", systemImage: "calendar")
                                .font(.mono(13, .semibold))
                        }
                        Hint("If your Mac was asleep or TidyUp was closed at that time, it sorts once when TidyUp is running again.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Rectangle().fill(Theme.ink.opacity(0.18)).frame(width: 1)

                // Right: keep it running
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open TidyUp when I log in").font(.mono(14, .semibold))
                            Hint("Auto sort only runs while TidyUp is open. It lives in the menu bar, so opening at login keeps it running.")
                        }
                    }
                    .toggleStyle(.pill)
                    StatusLine(text: model.loginItemError, isError: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: model.schedule) { model.scheduleChanged() }
    }
}
