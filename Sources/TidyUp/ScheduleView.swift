import SwiftUI
import TidyCore

struct ScheduleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SectionPage(title: "Schedule", subtitle: "Sort your folders automatically, without clicking anything.") {
            Toggle("Sort automatically", isOn: $model.schedule.enabled).toggleStyle(.switch)

            if model.schedule.enabled {
                Picker("Repeat", selection: $model.schedule.frequency) {
                    Text("Every day").tag(Schedule.Frequency.daily)
                    Text("Every week").tag(Schedule.Frequency.weekly)
                }
                .pickerStyle(.segmented).frame(maxWidth: 280)

                if model.schedule.frequency == .weekly {
                    Picker("On", selection: $model.schedule.weekday) {
                        ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
                    }
                    .frame(maxWidth: 280)
                }

                DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute).frame(maxWidth: 280)

                if let next = model.nextScheduledRun {
                    Label("Next sort: \(next.formatted(date: .complete, time: .shortened))", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                Text("It sorts the folders ticked on the Sort page. If your Mac was asleep or TidyUp was closed at that time, it sorts once the next time TidyUp is running.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            Toggle("Open TidyUp when I log in", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) }))
            Text("Schedules only run while TidyUp is open. It lives in the menu bar, so opening at login keeps them running.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.loginItemError {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            StatusLine(text: model.message)
        }
        .onChange(of: model.schedule) { model.scheduleChanged() }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: model.schedule.hour, minute: model.schedule.minute)) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.schedule.hour = parts.hour ?? 18
            model.schedule.minute = parts.minute ?? 0
        }
    }
}
