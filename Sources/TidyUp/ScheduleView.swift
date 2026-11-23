import SwiftUI
import TidyCore

struct ScheduleView: View {
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
        PageScroll {
            TwoColumns {
                Card(title: "Auto sort", icon: "clock") {
                    Toggle(isOn: $model.schedule.enabled) { Text("Sort automatically").font(.mono(13, .semibold)) }
                        .toggleStyle(.pill)

                    if model.schedule.enabled {
                        HairlineDivider()
                        SettingRow(label: "Repeat") {
                            PillSegmented(selection: $model.schedule.frequency,
                                          options: [(.daily, "Daily"), (.weekly, "Weekly")])
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
                        Hint("It sorts the folders switched on in the Sort tab. If your Mac was asleep or TidyUp was closed at that time, it sorts once when TidyUp is running again.")
                    }
                }
            } right: {
                Card(title: "Next sort", icon: "calendar") {
                    if let next = model.nextScheduledRun {
                        Text(next.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.mono(22))
                        Text(next.formatted(date: .omitted, time: .shortened))
                            .font(.mono(40))
                    } else {
                        Text("Off").font(.mono(40))
                        Hint("Switch on Auto sort to pick a time.")
                    }
                    StatusLine(text: model.message)
                }
                Card(title: "At login", icon: "power") {
                    Toggle(isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) })) {
                        Text("Open TidyUp when I log in").font(.mono(13, .semibold))
                    }
                    .toggleStyle(.pill)
                    Hint("Schedules only run while TidyUp is open. It lives in the menu bar, so opening at login keeps them running.")
                    StatusLine(text: model.loginItemError, isError: true)
                }
            }
        }
        .onChange(of: model.schedule) { model.scheduleChanged() }
    }
}
