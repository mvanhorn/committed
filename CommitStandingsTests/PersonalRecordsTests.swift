import Testing
import Foundation
@testable import CommitStandings

/// Your records as the iPhone shows them: the grid's six tiles, the Board's record card, and how
/// the board you see now feeds Days at #1. The rules themselves are held to the shared fixture
/// (`HabitRecordConformanceTests`); these check the store's inputs and the words.
@MainActor
struct PersonalRecordsTests {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Noon UTC on `day` ("YYYY-MM-DD").
    static func noon(_ day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    static func history(_ days: [String: Int]) -> ContributionHistory {
        ContributionHistory(days: days, timeZone: .gmt)
    }

    /// Every day from `first` through `last` at `count`.
    static func run(_ first: String, _ last: String, _ count: Int = 1) -> [String: Int] {
        var days: [String: Int] = [:]
        var day = noon(first)
        while day <= noon(last) {
            days[ContributionHistory.key(for: day, in: utc)] = count
            day = utc.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    static func store(rivals: [String: ContributionHistory], you: ContributionHistory) -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: Array(rivals.keys))
        store.updateHistories(rivals.merging(["me": you]) { $1 })
        return store
    }

    // MARK: The board you see now

    @Test func daysAtNumberOneCountOnlyThePeopleOnYourBoard() throws {
        let you = Self.history(["2026-11-09": 5, "2026-11-10": 5, "2026-11-11": 5])
        let ana = Self.history(["2026-11-09": 9, "2026-11-10": 9, "2026-11-11": 9])
        let ben = Self.history(["2026-11-10": 1])
        let store = Self.store(rivals: ["ana": ana, "ben": ben], you: you)

        let all = try #require(store.records(asOf: Self.noon("2026-11-11")))
        #expect(all.daysAtNumberOne == .init(count: 0, mostRecent: nil))

        store.setHidden(true, username: "ana")
        let withoutAna = try #require(store.records(asOf: Self.noon("2026-11-11")))
        #expect(withoutAna.daysAtNumberOne == .init(count: 3, mostRecent: "2026-11-11"))

        store.setHidden(true, username: "ben")
        let alone = try #require(store.records(asOf: Self.noon("2026-11-11")))
        #expect(alone.daysAtNumberOne == nil)
        #expect(alone.firstWeekAtNumberOne == nil)
    }

    @Test func aRivalWithoutACalendarIsLeftOut() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["ana"])
        store.updateHistories(["me": Self.history(["2026-11-11": 3])])

        let records = try #require(store.records(asOf: Self.noon("2026-11-11")))
        #expect(records.daysAtNumberOne == nil)
    }

    @Test func noRecordsBeforeYourCalendarLoads() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["ana"])
        #expect(store.records(asOf: Self.noon("2026-11-11")) == nil)
    }

    // MARK: Tiles

    @Test func tilesSayTheNumberAndWhen() throws {
        var days = Self.run("2026-10-12", "2026-10-18", 4)   // 7 days, a 28 week
        days.merge(Self.run("2026-11-02", "2026-11-04", 2)) { $1 }
        days["2026-11-04"] = 33                             // best day
        days.merge(Self.run("2026-11-10", "2026-11-12", 3)) { $1 }
        let you = Self.history(days)
        let ana = Self.history(["2026-11-10": 20, "2026-11-11": 20])
        let ben = Self.history(["2026-11-12": 30])
        let records = PersonalRecords.derive(you: you, rivals: [ana, ben], asOf: Self.noon("2026-11-12"))
        let tiles = Dictionary(uniqueKeysWithValues: records.tiles.map { ($0.kind, $0) })

        #expect(records.tiles.map(\.title) == ["Best day", "Best week", "Longest streak", "Days at #1",
                                                 "Best 30 days", "First week at #1"])
        #expect(tiles[.bestDay]?.value == "33")
        #expect(tiles[.bestDay]?.caption == "Nov 4")
        #expect(tiles[.bestDay]?.spokenValue == "33 contributions, on November 4")
        #expect(tiles[.bestWeek]?.value == "37")
        #expect(tiles[.bestWeek]?.caption == "Nov 2 – 8")
        #expect(tiles[.bestWeek]?.isNew == false)
        #expect(tiles[.longestStreak]?.value == "7 days")
        #expect(tiles[.longestStreak]?.caption == "Ended Oct 18")
        #expect(tiles[.daysAtNumberOne]?.value == "10 days")
        #expect(tiles[.daysAtNumberOne]?.caption == "Most recent: Nov 4")
        #expect(tiles[.daysAtNumberOne]?.hint == "Counts only the people on your board now. Hiding someone changes it.")
        #expect(tiles[.best30Days]?.value == "68")
        #expect(tiles[.best30Days]?.caption == "Ended Nov 10")
        #expect(tiles[.firstWeekAtNumberOne]?.value == "Oct 12 – 18")
        #expect(tiles[.firstWeekAtNumberOne]?.caption == "Your first week leading")
        #expect(tiles[.firstWeekAtNumberOne]?.hint != nil)
    }

    @Test func tilesOnARecordDay() throws {
        var days = Self.run("2026-10-26", "2026-11-12", 2)
        days["2026-11-12"] = 41
        var ana = Self.run("2026-10-26", "2026-11-11", 3)
        ana["2026-11-12"] = 50
        let records = PersonalRecords.derive(you: Self.history(days), rivals: [Self.history(ana)],
                                             asOf: Self.noon("2026-11-12"))
        let tiles = Dictionary(uniqueKeysWithValues: records.tiles.map { ($0.kind, $0) })

        #expect(tiles[.bestDay]?.caption == "Today")
        #expect(tiles[.bestDay]?.isNew == true)
        #expect(tiles[.bestWeek]?.caption == "This week")
        #expect(tiles[.bestWeek]?.isNew == true)
        #expect(tiles[.longestStreak]?.value == "18 days")
        #expect(tiles[.longestStreak]?.caption == "Still going")
        #expect(tiles[.longestStreak]?.isNew == true)
        #expect(tiles[.best30Days]?.caption == "Through today")
        #expect(tiles[.daysAtNumberOne]?.value == nil)
        #expect(tiles[.daysAtNumberOne]?.caption == "Lead a day to start")
        // Not yet: the dashed tile, with where you stand this week.
        #expect(tiles[.firstWeekAtNumberOne]?.value == nil)
        #expect(tiles[.firstWeekAtNumberOne]?.caption == "You’re #2 this week")
        #expect(tiles[.firstWeekAtNumberOne]?.spokenValue == "Not yet. You’re #2 this week")
    }

    @Test func aStreakStillGoesWhileTodayHasNothingYet() {
        let records = PersonalRecords.derive(you: Self.history(Self.run("2026-11-01", "2026-11-11")), rivals: [],
                                             asOf: Self.noon("2026-11-12"))
        #expect(records.tile(.longestStreak).caption == "Still going")
        #expect(records.tile(.longestStreak).isNew == false)
    }

    @Test func emptyTilesSayNotYet() {
        let records = PersonalRecords.derive(you: Self.history(["2026-11-01": 0]), rivals: [],
                                             asOf: Self.noon("2026-11-12"))
        for tile in records.tiles {
            #expect(tile.value == nil, "\(tile.title)")
        }
        #expect(records.tile(.bestDay).caption == "Nothing in the past year")
        #expect(records.tile(.daysAtNumberOne).caption == "Needs a rival")
        #expect(records.tile(.firstWeekAtNumberOne).caption == "Needs a rival")
    }

    @Test func weekRangesCrossingAMonthNameBothMonths() {
        #expect(PersonalRecords.weekRange(.init(first: "2026-10-26", last: "2026-11-01")) == "Oct 26 – Nov 1")
        #expect(PersonalRecords.weekRange(.init(first: "2026-11-02", last: "2026-11-08")) == "Nov 2 – 8")
    }

    // MARK: The record card

    @Test func theCardSaysWhatTheOldBestWas() throws {
        var days = Self.run("2026-11-08", "2026-11-11", 2)
        days["2026-03-04"] = 33
        days["2026-11-12"] = 41
        let records = PersonalRecords.derive(you: Self.history(days), rivals: [], asOf: Self.noon("2026-11-12"))
        let card = try #require(records.card())

        #expect(card.kind == .bestDay)
        #expect(PersonalRecords.Broken.eyebrow == "New record")
        #expect(card.title == "41 today. Your best day in the past year.")
        #expect(card.detail == "Your old best was 33, on March 4.")
        #expect(card.id == "bestDay:2026-11-12")
    }

    @Test func weekAndStreakCardsNameTheirOldBests() throws {
        var days = Self.run("2026-10-05", "2026-10-11", 1)         // 7-day streak, a 7 week
        days.merge(Self.run("2026-11-05", "2026-11-12", 1)) { $1 } // 8-day streak today
        let records = PersonalRecords.derive(you: Self.history(days), rivals: [], asOf: Self.noon("2026-11-12"))

        #expect(records.setToday.map(\.kind) == [.longestStreak])
        let streak = try #require(records.card())
        #expect(streak.title == "8 days in a row. Your longest streak in the past year.")
        #expect(streak.detail == "Your old best was 7 days, ending October 11.")
        #expect(streak.id == "longestStreak:2026-11-05")

        let week = PersonalRecords.Broken(kind: .bestWeek, value: 186,
                                          oldBest: .init(value: 171, span: .init(first: "2026-10-05", last: "2026-10-11")),
                                          meetsMinimum: true, id: "bestWeek:2026-11-09")
        #expect(week.title == "186 this week. Your best week in the past year.")
        #expect(week.detail == "Your old best was 171, the week of October 5.")
    }

    @Test func theCardSkipsRecordsUnderTheMinimumAndDismissedOnes() throws {
        var days = Self.run("2026-11-02", "2026-11-04", 9)  // old best day 9, old best week 27
        days["2026-11-12"] = 41
        let records = PersonalRecords.derive(you: Self.history(days), rivals: [], asOf: Self.noon("2026-11-12"))

        #expect(records.setToday.map(\.kind) == [.bestDay, .bestWeek])
        #expect(records.card()?.kind == .bestDay)
        #expect(records.card(dismissed: ["bestDay:2026-11-12"])?.kind == .bestWeek)
        #expect(records.card(dismissed: ["bestDay:2026-11-12", "bestWeek:2026-11-09"]) == nil)

        let small = PersonalRecords.derive(you: Self.history(["2026-11-03": 4, "2026-11-04": 4, "2026-11-12": 9]),
                                           rivals: [], asOf: Self.noon("2026-11-12"))
        #expect(small.setToday.first?.kind == .bestDay)
        #expect(small.setToday.first?.meetsMinimum == false)
        #expect(small.card()?.kind == .bestWeek)
    }
}
