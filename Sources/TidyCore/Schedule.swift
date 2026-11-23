import Foundation

/// When TidyUp should sort on its own (daily or weekly at a set time).
public struct Schedule: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily, weekly
    }

    public var enabled = false
    public var frequency: Frequency = .daily
    public var hour = 18
    public var minute = 0
    /// Calendar weekday: 1 = Sunday ... 7 = Saturday. Only used when weekly.
    public var weekday = 2

    public init() {}

    /// The first scheduled moment strictly after `date`.
    public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        var parts = DateComponents(hour: hour, minute: minute, second: 0)
        if frequency == .weekly { parts.weekday = weekday }
        return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
    }

    /// True when a scheduled moment has passed since `reference` (the last run, or when the schedule was switched on).
    /// A run missed while the Mac was asleep or the app was closed counts as due, so it is caught up once.
    public func isDue(since reference: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard enabled, let next = nextRun(after: reference, calendar: calendar) else { return false }
        return next <= now
    }
}
