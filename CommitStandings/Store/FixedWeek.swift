import Foundation

/// A Week in the spec's sense (#124): Monday through Sunday in your time zone, named by GitHub's
/// civil days (`"2026-11-09"` … `"2026-11-15"`). It isn't a Window: the Board keeps Today, 7 days and
/// 30 days. Your records use it for the best week and the first week at #1; last week's final and
/// the rivalry record use the same weeks.
///
/// It works on civil days in the calendar it's given (a `ContributionHistory`'s), so a week has 7
/// days whatever the clocks do.
struct FixedWeek: Hashable, Sendable {
    /// The Monday that starts it, as a day key.
    let first: String
    /// The Sunday that ends it, as a day key.
    let last: String
    /// The start of its Monday in the calendar it was made in.
    let start: Date

    /// The week containing `date` in `calendar`.
    init(containing date: Date, in calendar: Calendar) {
        let day = calendar.startOfDay(for: date)
        // Sunday is 1 and Monday 2 in every Gregorian calendar, whatever its first weekday.
        let sinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: day) ?? day
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        start = monday
        first = ContributionHistory.key(for: monday, in: calendar)
        last = ContributionHistory.key(for: sunday, in: calendar)
    }

    /// The week before this one.
    func previous(in calendar: Calendar) -> FixedWeek {
        FixedWeek(containing: calendar.date(byAdding: .day, value: -7, to: start) ?? start, in: calendar)
    }

    /// Whether the civil day `key` falls in it. Day keys sort in date order.
    func contains(_ key: String) -> Bool {
        key >= first && key <= last
    }
}
