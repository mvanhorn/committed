import Foundation
import Testing
@testable import CommitStandings

/// Runs the shared `passes` cases in `fixtures/habit-conformance.json` against
/// `RankChangeDetector` and `NotificationService.copy(for:)`. The relay runs the same cases
/// (relay/test/habitPasses.test.ts), so a pass the app would notify about is the pass the relay
/// sends, in the same words.
struct HabitPassConformanceTests {
    struct Fixture: Decodable {
        let passes: [PassCase]
    }

    struct PassCase: Decodable {
        let name: String
        let `self`: String
        let previous: [String: Int]?
        let current: [String: Int]
        let expected: [Expected]
    }

    struct Expected: Decodable, Equatable {
        let rival: String
        let direction: String
        let rivalContributions: Int
        let myContributions: Int
        let title: String
        let body: String
    }

    /// The fixture lives at the repo root, found from this source file so no bundle resource is needed.
    static func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/habit-conformance.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureHasPassCases() throws {
        let cases = try Self.loadFixture().passes
        #expect(!cases.isEmpty)
        #expect(cases.contains { $0.expected.isEmpty })
    }

    @Test func detectorAndCopyMatchEveryCase() throws {
        for fixtureCase in try Self.loadFixture().passes {
            let events = RankChangeDetector.crossings(
                previous: fixtureCase.previous, current: fixtureCase.current, selfUsername: fixtureCase.self
            )
            let actual = events.map { event in
                let copy = NotificationService.copy(for: event)
                return Expected(
                    rival: event.rivalUsername,
                    direction: event.direction == .rivalPassedMe ? "rivalPassedMe" : "iPassedRival",
                    rivalContributions: event.rivalContributions,
                    myContributions: event.myContributions,
                    title: copy.title,
                    body: copy.body
                )
            }
            #expect(actual == fixtureCase.expected, "\(fixtureCase.name)")
        }
    }
}
