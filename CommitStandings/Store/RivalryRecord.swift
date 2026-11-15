import Foundation

/// Your rivalry record against one person: who won each of the last 12 finished weeks (Monday to
/// Sunday in your time zone, `FixedWeek`), your wins and losses ("7–5") and your longest run of
/// wins among them. The iPhone draws it in someone else's person view as Weekly record, and in
/// place of the streak on Your rivals.
///
/// It's worked out from the two calendars each time and never saved. A week's winner has the higher
/// Monday-to-Sunday total, and ties count for you, as they do on the Board. A week counts only
/// once both calendars cover it from its Monday: earlier weeks, and one a calendar starts partway
/// through, are empty squares. `fixtures/habit-conformance.json` (`rivalry`) holds the worked cases.
struct RivalryRecord: Equatable, Sendable {
    /// One week's square.
    enum Week: String, Equatable, Sendable {
        /// Your total was at least theirs.
        case win
        /// Theirs was higher.
        case loss
        /// Before one of your calendars starts.
        case none
    }

    /// How many finished weeks the record covers.
    static let weekCount = 12

    /// The last 12 finished weeks, oldest first.
    let weeks: [Week]

    var wins: Int { weeks.filter { $0 == .win }.count }
    var losses: Int { weeks.filter { $0 == .loss }.count }
    /// Weeks with a result: wins plus losses.
    var played: Int { wins + losses }

    /// Your most wins in a row among the 12 weeks.
    var longestRun: Int {
        var run = 0
        var longest = 0
        for week in weeks {
            run = week == .win ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// "7–5": wins, an en dash, losses.
    var text: String { "\(wins.formatted())–\(losses.formatted())" }

    /// The record read aloud: "You've won 7 of the last 12 weeks against ezra-q".
    func spoken(against login: String) -> String {
        if played == 1 {
            return wins == 1 ? "You won the last week against \(login)" : "You lost the last week against \(login)"
        }
        return "You’ve won \(wins.formatted()) of the last \(played.formatted()) weeks against \(login)"
    }

    /// The caption under the squares: "Longest run: 4 weeks in a row", "Longest run: 1 week",
    /// "No wins in these weeks yet".
    var runCaption: String {
        switch longestRun {
        case 0: "No wins in these weeks yet"
        case 1: "Longest run: 1 week"
        default: "Longest run: \(longestRun.formatted()) weeks in a row"
        }
    }

    /// The record between your calendar and theirs as of `reference`, in your calendar's weeks, or
    /// nil until there's a finished week both calendars cover.
    static func between(you: ContributionHistory, them: ContributionHistory, asOf reference: Date)
        -> RivalryRecord? {
        guard let yourFirst = you.days.keys.min(), let theirFirst = them.days.keys.min() else { return nil }
        let calendar = you.calendar
        let firstDay = max(yourFirst, theirFirst)
        var week = FixedWeek(containing: reference, in: calendar)
        var weeks: [Week] = []
        for _ in 0..<weekCount {
            week = week.previous(in: calendar)
            // Day keys sort in date order, so a week is covered when its Monday isn't before either
            // calendar's first day.
            guard week.first >= firstDay else {
                weeks.append(.none)
                continue
            }
            let keys = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
                .map { ContributionHistory.key(for: $0, in: calendar) }
            let yours = keys.reduce(0) { $0 + (you.days[$1] ?? 0) }
            let theirs = keys.reduce(0) { $0 + (them.days[$1] ?? 0) }
            weeks.append(yours >= theirs ? .win : .loss)
        }
        let record = RivalryRecord(weeks: weeks.reversed())
        return record.played > 0 ? record : nil
    }
}
