import Foundation
import Testing
import UIKit
@testable import CommitStandingsiOS

/// The Board's record card and Your records, through `AppModel`: the card shows on the day you set
/// a record, See your records opens your view, a dismissed card stays gone for that record across
/// launches, and the card goes when the day ends.
@MainActor
struct RecordCardAppTests {
    /// A clock the test moves.
    final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func noon(_ day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    /// Your calendar: 33 on March 4, a little most days since, and 41 today (November 12): a best
    /// day over an old best of 33, and a best week.
    static let you = ContributionHistory(days: [
        "2026-03-04": 33, "2026-11-09": 2, "2026-11-10": 2, "2026-11-11": 2, "2026-11-12": 41,
    ], timeZone: .gmt)
    static let ada = ContributionHistory(days: ["2026-11-12": 3], timeZone: .gmt)

    let clock = Clock(RecordCardAppTests.noon("2026-11-12"))
    let defaults = UserDefaults(suiteName: "RecordCardAppTests-\(UUID().uuidString)")!
    let services: CommittedServices

    init() {
        services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "gho_test")
        )
        services.store.replaceRoster(owner: "me", members: ["ada"])
        services.store.updateHistories(["me": Self.you, "ada": Self.ada])
    }

    /// One launch of the app on the same saved settings.
    private func launch() -> AppModel {
        let clock = clock
        return AppModel(services: services, defaults: defaults, backgroundTime: FakeBackgroundTime(),
                        now: { clock.now })
    }

    @Test func theCardShowsOnTheDayYouSetARecord() throws {
        let model = launch()
        let card = try #require(model.recordCard)
        #expect(card.title == "41 today. Your best day in the past year.")
        #expect(card.detail == "Your old best was 33, on March 4.")
    }

    @Test func seeYourRecordsOpensYourViewWithYourRecords() throws {
        let model = launch()
        model.selectedTab = .people
        model.showYourRecords()
        #expect(model.selectedTab == .board)
        #expect(model.shownPerson?.isYou == true)
        let records = try #require(model.yourRecords)
        #expect(records.bestDay?.value == 41)
        #expect(records.tile(.bestDay).isNew)
        #expect(records.daysAtNumberOne?.count == 5)
    }

    @Test func aDismissedCardStaysGoneForThatRecordAcrossLaunches() throws {
        let model = launch()
        let bestDay = try #require(model.recordCard)
        model.dismissRecordCard(bestDay)
        // The week's record was set today too, and it's a different record.
        let bestWeek = try #require(model.recordCard)
        #expect(bestWeek.kind == .bestWeek)
        model.dismissRecordCard(bestWeek)
        #expect(model.recordCard == nil)

        #expect(launch().recordCard == nil)
    }

    @Test func theCardGoesWhenTheDayEnds() {
        let model = launch()
        #expect(model.recordCard != nil)
        clock.now = Self.noon("2026-11-13")
        #expect(model.recordCard == nil)
        // The week record stays New on its tile.
        #expect(model.yourRecords?.tile(.bestWeek).isNew == true)
    }

    @Test func shareMakesASquareImageOfTheCard() throws {
        let card = try #require(launch().recordCard)
        let image = try #require(RecordShareRenderer.image(card, login: "me"))
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1080)
        let url = try RecordShareRenderer.file(card, login: "me")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
