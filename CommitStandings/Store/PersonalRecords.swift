import Foundation

/// Your records (#127): your bests over the past year of GitHub's calendar, as your own person view
/// shows them on iPhone, and the records you broke today, which the Board's record card (and the
/// relay's record notifications, #134) announce. Worked out from saved calendars
/// (`ContributionHistory`), beside `PersonSummary`. The rules are held to the `records` cases in
/// `fixtures/habit-conformance.json`, which the relay runs too:
///
/// - Only your calendar's days from its first day through today count, in its time zone. A missing
///   day is 0 and a later day never counts.
/// - A week is a `FixedWeek`, Monday to Sunday; this week counts so far.
/// - Equalling a best is never a record, and when several days, weeks, runs or windows share the
///   best, the earliest holds it: it set it first.
/// - Days at #1 and the first week at #1 are against `rivals`, the people on your board now, so
///   hiding someone changes them. A tie counts for you; a day or week you had nothing never counts.
///   Only a finished week (its Sunday before today) can be your first week at #1.
/// - `setToday` lists the records broken today, once each: today beat every earlier day; this week
///   passed the best earlier week today; today's run became one day longer than any before it.
struct PersonalRecords: Equatable, Sendable {
    /// The six tiles, in the grid's order.
    enum Kind: String, CaseIterable, Sendable {
        case bestDay, bestWeek, longestStreak, daysAtNumberOne, best30Days, firstWeekAtNumberOne
    }

    /// The days a record covers, as civil day keys (`"2026-11-09"`).
    struct Span: Equatable, Sendable {
        let first: String
        let last: String
    }

    /// A best, the earliest to reach it.
    struct Record: Equatable, Sendable {
        let value: Int
        let span: Span
        /// The tile's New badge: a best day or best 30 days ending today, a best week that's this
        /// week, a longest streak whose run reaches today.
        let isNew: Bool
    }

    struct DaysAtNumberOne: Equatable, Sendable {
        let count: Int
        /// The latest day you were #1; nil when you haven't been.
        let mostRecent: String?
    }

    struct FirstWeekAtNumberOne: Equatable, Sendable {
        /// nil until you've led a finished week.
        let week: Span?
        /// That week is last week.
        let isNew: Bool
        /// Where you stand this week so far: 1 plus the rivals with more than you.
        let rankThisWeek: Int
    }

    /// A record broken today: the record card's subject, and a record notification's.
    struct Broken: Equatable, Sendable, Identifiable {
        /// `.bestDay`, `.bestWeek` or `.longestStreak`.
        let kind: Kind
        let value: Int
        /// The best it beat; nil when there was none.
        let oldBest: Old?
        /// The old best is big enough to celebrate (`minimumOldBest`).
        let meetsMinimum: Bool
        /// Which record this is, so a dismissed card stays gone for it: the kind and today, this
        /// week's Monday, or the run's first day.
        let id: String

        struct Old: Equatable, Sendable {
            let value: Int
            let span: Span
        }
    }

    /// Today, as a day key.
    let today: String
    let bestDay: Record?
    let bestWeek: Record?
    let longestStreak: Record?
    let best30Days: Record?
    /// nil without a rival: there's nobody to be #1 over.
    let daysAtNumberOne: DaysAtNumberOne?
    /// nil without a rival.
    let firstWeekAtNumberOne: FirstWeekAtNumberOne?
    /// In the order best day, best week, longest streak.
    let setToday: [Broken]
    /// Whether the longest streak is still alive: its run reaches today, or yesterday while today
    /// has nothing yet (as `currentStreak` counts it).
    let longestStreakIsOngoing: Bool

    /// The smallest old best a record card or notification celebrates. A best week only needs an
    /// old best to name.
    static func minimumOldBest(_ kind: Kind) -> Int {
        switch kind {
        case .bestDay: 5
        case .longestStreak: 7
        default: 1
        }
    }

    /// The record the Board's card shows: the first one broken today that meets its minimum and
    /// hasn't been dismissed.
    func card(dismissed: Set<String> = []) -> Broken? {
        setToday.first { $0.meetsMinimum && !dismissed.contains($0.id) }
    }

    // MARK: Derivation

    /// Your records as of `reference`, from your calendar and the calendars of the people on your
    /// board now (`rivals`), in your calendar's time zone.
    static func derive(you: ContributionHistory, rivals: [ContributionHistory], asOf reference: Date)
        -> PersonalRecords {
        let calendar = you.calendar
        let todayDate = calendar.startOfDay(for: reference)
        let today = ContributionHistory.key(for: todayDate, in: calendar)
        let days = Self.days(of: you, through: todayDate, calendar: calendar)
        let counts = days.map { you.days[$0.key] ?? 0 }
        let last = days.count - 1
        let todayCount = counts.last ?? 0

        // Best day.
        let bestDayIndex = earliestMax(counts.indices.map { ($0, counts[$0]) })
        let bestDay = bestDayIndex.map {
            Record(value: counts[$0], span: Span(first: days[$0].key, last: days[$0].key), isNew: days[$0].key == today)
        }

        // Weeks, in order, each over its days in the calendar through today.
        var weeks: [(week: FixedWeek, indices: [Int])] = []
        for (index, day) in days.enumerated() {
            if let current = weeks.last, current.week.contains(day.key) {
                weeks[weeks.count - 1].indices.append(index)
            } else {
                weeks.append((FixedWeek(containing: day.date, in: calendar), [index]))
            }
        }
        let weekTotals = weeks.map { $0.indices.reduce(0) { $0 + counts[$1] } }
        let thisWeek = FixedWeek(containing: todayDate, in: calendar)
        let bestWeekIndex = earliestMax(weekTotals.indices.map { ($0, weekTotals[$0]) })
        let bestWeek = bestWeekIndex.map {
            Record(value: weekTotals[$0], span: Span(first: weeks[$0].week.first, last: weeks[$0].week.last),
                   isNew: weeks[$0].week == thisWeek)
        }

        // Runs of days with a contribution.
        var runs: [ClosedRange<Int>] = []
        var runStart: Int?
        for index in counts.indices {
            if counts[index] > 0 {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                runs.append(start...(index - 1))
                runStart = nil
            }
        }
        if let start = runStart { runs.append(start...last) }
        let longestIndex = earliestMax(runs.indices.map { ($0, runs[$0].count) })
        let longestStreak = longestIndex.map {
            Record(value: runs[$0].count,
                   span: Span(first: days[runs[$0].lowerBound].key, last: days[runs[$0].upperBound].key),
                   isNew: days[runs[$0].upperBound].key == today)
        }
        // Still alive: the run reaches today, or yesterday while today has nothing yet.
        let longestStreakIsOngoing = longestIndex.map {
            runs[$0].upperBound == last || (runs[$0].upperBound == last - 1 && todayCount == 0)
        } ?? false

        // Best 30 days: every window of 30 days ending on a day through today.
        var prefix = [0]
        for count in counts { prefix.append(prefix[prefix.count - 1] + count) }
        let windowTotals = counts.indices.map { prefix[$0 + 1] - prefix[max(0, $0 - 29)] }
        let best30Index = earliestMax(windowTotals.indices.map { ($0, windowTotals[$0]) })
        let best30Days = best30Index.map { index in
            let start = calendar.date(byAdding: .day, value: -29, to: days[index].date) ?? days[index].date
            return Record(value: windowTotals[index],
                          span: Span(first: ContributionHistory.key(for: start, in: calendar), last: days[index].key),
                          isNew: days[index].key == today)
        }

        // Against the board.
        var daysAtNumberOne: DaysAtNumberOne?
        var firstWeekAtNumberOne: FirstWeekAtNumberOne?
        if !rivals.isEmpty {
            func leads(_ yours: Int, _ theirs: [Int]) -> Bool { yours > 0 && theirs.allSatisfy { yours >= $0 } }
            let ledDays = days.indices.filter { index in
                leads(counts[index], rivals.map { $0.days[days[index].key] ?? 0 })
            }
            daysAtNumberOne = DaysAtNumberOne(count: ledDays.count, mostRecent: ledDays.last.map { days[$0].key })

            func rivalTotals(_ indices: [Int]) -> [Int] {
                rivals.map { rival in indices.reduce(0) { $0 + (rival.days[days[$1].key] ?? 0) } }
            }
            let firstLed = weeks.indices.first { index in
                weeks[index].week.last < today && leads(weekTotals[index], rivalTotals(weeks[index].indices))
            }
            let current = weeks.indices.last.flatMap { weeks[$0].week == thisWeek ? $0 : nil }
            let yoursThisWeek = current.map { weekTotals[$0] } ?? 0
            let theirsThisWeek = current.map { rivalTotals(weeks[$0].indices) } ?? rivals.map { _ in 0 }
            firstWeekAtNumberOne = FirstWeekAtNumberOne(
                week: firstLed.map { Span(first: weeks[$0].week.first, last: weeks[$0].week.last) },
                isNew: firstLed.map { weeks[$0].week == thisWeek.previous(in: calendar) } ?? false,
                rankThisWeek: 1 + theirsThisWeek.filter { $0 > yoursThisWeek }.count
            )
        }

        // Broken today.
        var setToday: [Broken] = []
        if days.last?.key == today {
            // Best day: today beat every earlier day.
            let earlier = earliestMax(counts.indices.dropLast().map { ($0, counts[$0]) })
            let old = earlier.map { Broken.Old(value: counts[$0], span: Span(first: days[$0].key, last: days[$0].key)) }
            if todayCount > (old?.value ?? 0) {
                setToday.append(Broken(kind: .bestDay, value: todayCount, oldBest: old,
                                       meetsMinimum: (old?.value ?? 0) >= minimumOldBest(.bestDay),
                                       id: "bestDay:\(today)"))
            }
            // Best week: this week passed the best earlier week today.
            if let current = weeks.indices.last, weeks[current].week == thisWeek {
                let earlierWeek = earliestMax(weeks.indices.dropLast().map { ($0, weekTotals[$0]) })
                let old = earlierWeek.map {
                    Broken.Old(value: weekTotals[$0], span: Span(first: weeks[$0].week.first, last: weeks[$0].week.last))
                }
                let oldValue = old?.value ?? 0
                let total = weekTotals[current]
                if total - todayCount <= oldValue, total > oldValue {
                    setToday.append(Broken(kind: .bestWeek, value: total, oldBest: old,
                                           meetsMinimum: oldValue >= minimumOldBest(.bestWeek),
                                           id: "bestWeek:\(thisWeek.first)"))
                }
            }
            // Longest streak: today's run became one day longer than any before it.
            if todayCount > 0, let run = runs.last {
                let earlierRun = earliestMax(runs.indices.dropLast().map { ($0, runs[$0].count) })
                let old = earlierRun.map {
                    Broken.Old(value: runs[$0].count,
                               span: Span(first: days[runs[$0].lowerBound].key, last: days[runs[$0].upperBound].key))
                }
                let oldValue = old?.value ?? 0
                if run.count == oldValue + 1 {
                    setToday.append(Broken(kind: .longestStreak, value: run.count, oldBest: old,
                                           meetsMinimum: oldValue >= minimumOldBest(.longestStreak),
                                           id: "longestStreak:\(days[run.lowerBound].key)"))
                }
            }
        }

        return PersonalRecords(today: today, bestDay: bestDay, bestWeek: bestWeek, longestStreak: longestStreak,
                               best30Days: best30Days, daysAtNumberOne: daysAtNumberOne,
                               firstWeekAtNumberOne: firstWeekAtNumberOne, setToday: setToday,
                               longestStreakIsOngoing: longestStreakIsOngoing)
    }

    /// Each day of `history` from its first through `today`, oldest first; none when it has no days
    /// or starts later. Bounded like `ContributionHistory`'s own walks.
    private static func days(of history: ContributionHistory, through today: Date, calendar: Calendar)
        -> [(key: String, date: Date)] {
        guard let earliest = history.days.keys.min(),
              var day = ContributionHistory.date(forKey: earliest, in: calendar) else { return [] }
        var result: [(key: String, date: Date)] = []
        while day <= today, result.count < 3_660 {
            result.append((ContributionHistory.key(for: day, in: calendar), day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// The index of the earliest largest value above 0, or nil when every value is 0.
    private static func earliestMax(_ values: [(Int, Int)]) -> Int? {
        var best: (index: Int, value: Int)?
        for (index, value) in values where value > (best?.value ?? 0) {
            best = (index, value)
        }
        return best?.index
    }
}

// MARK: - Copy

extension PersonalRecords {
    /// One tile of the grid: a number and when, or a dashed "Not yet" when `value` is nil.
    struct Tile: Identifiable, Equatable, Sendable {
        let kind: Kind
        /// nil: not reached yet.
        let value: String?
        let caption: String
        let isNew: Bool
        /// The tile read aloud, after its title.
        let spokenValue: String
        /// Days at #1 and the first week at #1 depend on who's on your board.
        let hint: String?

        var id: Kind { kind }
        var title: String { kind.title }
    }

    /// The six tiles, in the grid's order.
    var tiles: [Tile] {
        Kind.allCases.map(tile)
    }

    func tile(_ kind: Kind) -> Tile {
        switch kind {
        case .bestDay:
            guard let bestDay else { return Self.nothingYet(kind) }
            let when = bestDay.span.last == today ? "Today" : Self.shortDate(bestDay.span.first)
            let spokenWhen = bestDay.span.last == today ? "today" : "on \(Self.longDate(bestDay.span.first))"
            return Tile(kind: kind, value: bestDay.value.formatted(), caption: when, isNew: bestDay.isNew,
                        spokenValue: "\(PersonSummary.plural(bestDay.value, "contribution")), \(spokenWhen)", hint: nil)
        case .bestWeek:
            guard let bestWeek else { return Self.nothingYet(kind) }
            let thisWeek = bestWeek.isNew
            return Tile(kind: kind, value: bestWeek.value.formatted(),
                        caption: thisWeek ? "This week" : Self.weekRange(bestWeek.span), isNew: bestWeek.isNew,
                        spokenValue: "\(PersonSummary.plural(bestWeek.value, "contribution")), "
                            + (thisWeek ? "this week" : "the week of \(Self.longDate(bestWeek.span.first))"),
                        hint: nil)
        case .longestStreak:
            guard let longestStreak else { return Self.nothingYet(kind) }
            let ongoing = longestStreakIsOngoing
            return Tile(kind: kind, value: PersonSummary.streakText(longestStreak.value),
                        caption: ongoing ? "Still going" : "Ended \(Self.shortDate(longestStreak.span.last))",
                        isNew: longestStreak.isNew,
                        spokenValue: "\(StreakLabel.spokenDays(longestStreak.value)), "
                            + (ongoing ? "still going" : "ended \(Self.longDate(longestStreak.span.last))"),
                        hint: nil)
        case .daysAtNumberOne:
            let hint = "Counts only the people on your board now. Hiding someone changes it."
            guard let daysAtNumberOne else {
                return Tile(kind: kind, value: nil, caption: "Needs a rival", isNew: false,
                            spokenValue: "Not yet. Needs a rival", hint: hint)
            }
            guard let mostRecent = daysAtNumberOne.mostRecent else {
                return Tile(kind: kind, value: nil, caption: "Lead a day to start", isNew: false,
                            spokenValue: "Not yet", hint: hint)
            }
            let when = mostRecent == today ? "today" : Self.shortDate(mostRecent)
            let spokenWhen = mostRecent == today ? "today" : Self.longDate(mostRecent)
            return Tile(kind: kind, value: PersonSummary.plural(daysAtNumberOne.count, "day"),
                        caption: "Most recent: \(when)", isNew: false,
                        spokenValue: "\(PersonSummary.plural(daysAtNumberOne.count, "day")), most recent \(spokenWhen)",
                        hint: hint)
        case .best30Days:
            guard let best30Days else { return Self.nothingYet(kind) }
            let current = best30Days.span.last == today
            return Tile(kind: kind, value: best30Days.value.formatted(),
                        caption: current ? "Through today" : "Ended \(Self.shortDate(best30Days.span.last))",
                        isNew: best30Days.isNew,
                        spokenValue: "\(PersonSummary.plural(best30Days.value, "contribution")), "
                            + (current ? "through today" : "ended \(Self.longDate(best30Days.span.last))"),
                        hint: nil)
        case .firstWeekAtNumberOne:
            let hint = "Counts only the people on your board now. Hiding someone changes it."
            guard let firstWeekAtNumberOne else {
                return Tile(kind: kind, value: nil, caption: "Needs a rival", isNew: false,
                            spokenValue: "Not yet. Needs a rival", hint: hint)
            }
            guard let week = firstWeekAtNumberOne.week else {
                let rank = "You’re #\(firstWeekAtNumberOne.rankThisWeek) this week"
                return Tile(kind: kind, value: nil, caption: rank, isNew: false,
                            spokenValue: "Not yet. \(rank)", hint: hint)
            }
            return Tile(kind: kind, value: Self.weekRange(week),
                        caption: firstWeekAtNumberOne.isNew ? "Last week" : "Your first week leading",
                        isNew: firstWeekAtNumberOne.isNew,
                        spokenValue: "The week of \(Self.longDate(week.first))", hint: hint)
        }
    }

    private static func nothingYet(_ kind: Kind) -> Tile {
        Tile(kind: kind, value: nil, caption: "Nothing in the past year", isNew: false,
             spokenValue: "Not yet. Nothing in the past year", hint: nil)
    }

    // MARK: Dates

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]

    private static func parts(_ key: String) -> (month: Int, day: Int) {
        let numbers = key.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3, (1...12).contains(numbers[1]) else { return (1, 1) }
        return (numbers[1], numbers[2])
    }

    /// "November 4".
    static func longDate(_ key: String) -> String {
        let (month, day) = parts(key)
        return "\(monthNames[month - 1]) \(day)"
    }

    /// "Nov 4".
    static func shortDate(_ key: String) -> String {
        let (month, day) = parts(key)
        return "\(monthNames[month - 1].prefix(3)) \(day)"
    }

    /// "Nov 2 – 8", or "Oct 26 – Nov 1" across a month's end.
    static func weekRange(_ span: Span) -> String {
        let (firstMonth, _) = parts(span.first)
        let (lastMonth, lastDay) = parts(span.last)
        return firstMonth == lastMonth
            ? "\(shortDate(span.first)) – \(lastDay)"
            : "\(shortDate(span.first)) – \(shortDate(span.last))"
    }
}

extension PersonalRecords.Kind {
    var title: String {
        switch self {
        case .bestDay: "Best day"
        case .bestWeek: "Best week"
        case .longestStreak: "Longest streak"
        case .daysAtNumberOne: "Days at #1"
        case .best30Days: "Best 30 days"
        case .firstWeekAtNumberOne: "First week at #1"
        }
    }
}

extension PersonalRecords.Broken {
    /// The card's eyebrow.
    static let eyebrow = "New record"

    /// "41 today. Your best day in the past year."
    var title: String {
        switch kind {
        case .bestWeek: "\(value.formatted()) this week. Your best week in the past year."
        case .longestStreak: "\(value.formatted()) days in a row. Your longest streak in the past year."
        default: "\(value.formatted()) today. Your best day in the past year."
        }
    }

    /// "Your old best was 33, on March 4."
    var detail: String? {
        guard let oldBest else { return nil }
        switch kind {
        case .bestWeek:
            return "Your old best was \(oldBest.value.formatted()), the week of \(PersonalRecords.longDate(oldBest.span.first))."
        case .longestStreak:
            return "Your old best was \(PersonSummary.plural(oldBest.value, "day")), ending \(PersonalRecords.longDate(oldBest.span.last))."
        default:
            return "Your old best was \(oldBest.value.formatted()), on \(PersonalRecords.longDate(oldBest.span.first))."
        }
    }
}

extension StandingsStore {
    /// Your records as of `reference`, against the people on your board now (hidden people are left
    /// out, and anyone whose calendar hasn't loaded). nil until your own calendar loads.
    func records(asOf reference: Date) -> PersonalRecords? {
        guard let me = selfCompetitor?.username, let mine = history(for: me) else { return nil }
        return PersonalRecords.derive(you: mine, rivals: rivals.compactMap { history(for: $0.username) },
                                      asOf: reference)
    }
}
