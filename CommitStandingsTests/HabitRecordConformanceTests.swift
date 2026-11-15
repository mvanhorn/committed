import Testing
import Foundation
@testable import CommitStandings

/// Runs the `records` cases in `fixtures/habit-conformance.json` against `PersonalRecords.derive`:
/// Your records (best day, best week, longest streak, best 30 days, days at #1 and first week at
/// #1), the New badges, and which records were broken today with their old bests and minimums. The
/// relay's record notifications (#134) run the same cases, so the app and the relay agree on what a
/// record is.
struct HabitRecordConformanceTests {

    struct Fixture: Decodable {
        let records: [Case]
    }

    struct Case: Decodable {
        let name: String
        let input: Input
        let expected: Expected
    }

    struct Input: Decodable {
        let timeZone: String
        let now: Int
        let asOf: String
        let you: [String: Int]
        let rivals: [String: [String: Int]]

        var date: Date { Date(timeIntervalSince1970: TimeInterval(now)) }
        var zone: TimeZone { TimeZone(identifier: timeZone)! }
        var yours: ContributionHistory { ContributionHistory(days: you, timeZone: zone) }
        var rivalHistories: [ContributionHistory] {
            rivals.keys.sorted().map { ContributionHistory(days: rivals[$0]!, timeZone: zone) }
        }
    }

    struct Span: Decodable, Equatable {
        let first: String
        let last: String
    }

    struct Record: Decodable, Equatable {
        let value: Int
        let first: String
        let last: String
        let new: Bool
    }

    struct DaysAtNumberOne: Decodable, Equatable {
        let value: Int
        let last: String?
    }

    struct FirstWeekAtNumberOne: Decodable, Equatable {
        let week: Span?
        let new: Bool
        let rankThisWeek: Int
    }

    struct OldBest: Decodable, Equatable {
        let value: Int
        let first: String
        let last: String
    }

    struct Broken: Decodable, Equatable {
        let record: String
        let value: Int
        let oldBest: OldBest?
        let meetsMinimum: Bool
    }

    struct Expected: Decodable {
        let bestDay: Record?
        let bestWeek: Record?
        let longestStreak: Record?
        let best30Days: Record?
        let daysAtNumberOne: DaysAtNumberOne?
        let firstWeekAtNumberOne: FirstWeekAtNumberOne?
        let set: [Broken]
    }

    /// The fixture lives at the repo root, found from this source file so no bundle resource is needed.
    static func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/habit-conformance.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func names() -> [String] {
        (try? loadFixture().records.map(\.name)) ?? []
    }

    static func derive(_ name: String) throws -> (PersonalRecords, Expected) {
        let fixtureCase = try #require(try loadFixture().records.first { $0.name == name })
        let input = fixtureCase.input
        let records = PersonalRecords.derive(you: input.yours, rivals: input.rivalHistories, asOf: input.date)
        return (records, fixtureCase.expected)
    }

    static func record(_ record: PersonalRecords.Record?) -> Record? {
        record.map { Record(value: $0.value, first: $0.span.first, last: $0.span.last, new: $0.isNew) }
    }

    @Test func fixtureHasRecordCases() throws {
        let cases = try Self.loadFixture().records
        #expect(cases.count >= 10)
        // The minimums sit on both sides of their thresholds, and ties at #1 are covered.
        #expect(cases.contains { $0.expected.set.contains { $0.record == "bestDay" && !$0.meetsMinimum } })
        #expect(cases.contains { $0.expected.set.contains { $0.record == "longestStreak" && !$0.meetsMinimum } })
        #expect(cases.contains { $0.expected.set.contains { $0.record == "longestStreak" && $0.meetsMinimum } })
        #expect(cases.contains { $0.expected.daysAtNumberOne != nil })
    }

    @Test(arguments: names())
    func localDayMatchesFixture(name: String) throws {
        let input = try #require(try Self.loadFixture().records.first { $0.name == name }).input
        #expect(ContributionHistory.key(for: input.date, in: input.yours.calendar) == input.asOf)
    }

    @Test(arguments: names())
    func recordsMatchFixture(name: String) throws {
        let (records, expected) = try Self.derive(name)

        #expect(Self.record(records.bestDay) == expected.bestDay)
        #expect(Self.record(records.bestWeek) == expected.bestWeek)
        #expect(Self.record(records.longestStreak) == expected.longestStreak)
        #expect(Self.record(records.best30Days) == expected.best30Days)
    }

    @Test(arguments: names())
    func numberOneMatchesFixture(name: String) throws {
        let (records, expected) = try Self.derive(name)

        #expect(records.daysAtNumberOne.map { DaysAtNumberOne(value: $0.count, last: $0.mostRecent) }
            == expected.daysAtNumberOne)
        #expect(records.firstWeekAtNumberOne.map {
            FirstWeekAtNumberOne(week: $0.week.map { Span(first: $0.first, last: $0.last) }, new: $0.isNew,
                                 rankThisWeek: $0.rankThisWeek)
        } == expected.firstWeekAtNumberOne)
    }

    @Test(arguments: names())
    func recordsSetTodayMatchFixture(name: String) throws {
        let (records, expected) = try Self.derive(name)

        #expect(records.setToday.map {
            Broken(record: $0.kind.rawValue, value: $0.value,
                   oldBest: $0.oldBest.map { OldBest(value: $0.value, first: $0.span.first, last: $0.span.last) },
                   meetsMinimum: $0.meetsMinimum)
        } == expected.set)
    }
}
