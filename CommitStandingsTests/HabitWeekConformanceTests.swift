import Testing
import Foundation
@testable import CommitStandings

/// Runs the `weeks` and `rivalry` cases of the shared habit fixture (`fixtures/habit-conformance.json`)
/// against `FixedWeek` and `RivalryRecord`. The relay ports the same weeks for last week's final
/// (#131), so the two can't drift.
struct HabitWeekConformanceTests {

    struct Fixture: Decodable {
        let weeks: [WeekCase]
        let rivalry: [RivalryCase]
    }

    struct Week: Decodable, Equatable, CustomStringConvertible {
        let first: String
        let last: String
        var description: String { "\(first) … \(last)" }
    }

    struct WeekCase: Decodable {
        struct Input: Decodable {
            let timeZone: String
            let now: Int
        }
        struct Expected: Decodable {
            let thisWeek: Week
            let lastWeek: Week
        }
        let name: String
        let input: Input
        let expected: Expected
    }

    struct RivalryCase: Decodable {
        struct Input: Decodable {
            let timeZone: String
            let now: Int
            let you: [String: Int]
            let them: [String: Int]
        }
        struct Expected: Decodable {
            let weeks: [String]
            let wins: Int
            let losses: Int
            let longestRun: Int
            let text: String
        }
        let name: String
        let input: Input
        let expected: Expected?
    }

    /// The fixture lives at the repo root, found from this source file so no bundle resource is needed.
    static func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/habit-conformance.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    @Test func fixtureHasCases() throws {
        let fixture = try Self.loadFixture()
        #expect(!fixture.weeks.isEmpty)
        #expect(!fixture.rivalry.isEmpty)
    }

    @Test(arguments: try loadFixture().weeks.map(\.name))
    func week(_ name: String) throws {
        let item = try #require(try Self.loadFixture().weeks.first { $0.name == name })
        let calendar = try Self.calendar(item.input.timeZone)
        let now = Date(timeIntervalSince1970: TimeInterval(item.input.now))
        let thisWeek = FixedWeek(containing: now, in: calendar)
        let lastWeek = thisWeek.previous(in: calendar)
        #expect(Week(first: thisWeek.first, last: thisWeek.last) == item.expected.thisWeek)
        #expect(Week(first: lastWeek.first, last: lastWeek.last) == item.expected.lastWeek)
    }

    @Test(arguments: try loadFixture().rivalry.map(\.name))
    func rivalry(_ name: String) throws {
        let item = try #require(try Self.loadFixture().rivalry.first { $0.name == name })
        let zone = try #require(TimeZone(identifier: item.input.timeZone))
        let record = RivalryRecord.between(
            you: ContributionHistory(days: item.input.you, timeZone: zone),
            them: ContributionHistory(days: item.input.them, timeZone: zone),
            asOf: Date(timeIntervalSince1970: TimeInterval(item.input.now))
        )
        guard let expected = item.expected else {
            #expect(record == nil)
            return
        }
        let found = try #require(record)
        #expect(found.weeks.map(\.rawValue) == expected.weeks)
        #expect(found.wins == expected.wins)
        #expect(found.losses == expected.losses)
        #expect(found.longestRun == expected.longestRun)
        #expect(found.text == expected.text)
    }
}
