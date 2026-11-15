import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

/// Challenge in someone else's person view: your 30-day race with them, told in your voice, as a
/// 9:16 story image and a message with the link to their side of it (gitcommitted.app/vs/…). The
/// headline follows the totals the way the challenge page does (`site/lib/challenge.ts`): equal
/// totals are "Dead level", not a lead for you as on the Board. With `RENDER_DIR` set
/// (`TEST_RUNNER_RENDER_DIR=/path`), the images are also saved there as PNGs, for review.
@MainActor
@Suite(.serialized)
struct ChallengeShareTests {
    private let renderDirectory = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:))
    private static let english = Locale(identifier: "en_US")

    // MARK: Words

    @Test func youAheadSaysSo() {
        let challenge = Challenge(you: "addisonk", friend: "ezra-q", yourTotal: 412, theirTotal: 400, locale: Self.english)
        #expect(challenge.variant == .ahead)
        #expect(challenge.headline == "I’m 12 ahead of you, ezra-q.")
        #expect(challenge.message == "ezra-q, I’m 12 ahead of you on Committed: https://gitcommitted.app/vs/addisonk/ezra-q")
    }

    @Test func themAheadPromisesToCatchUp() {
        let challenge = Challenge(you: "addisonk", friend: "ezra-q", yourTotal: 388, theirTotal: 400, locale: Self.english)
        #expect(challenge.variant == .behind)
        #expect(challenge.headline == "You’re 12 ahead of me, ezra-q. Not for long.")
        #expect(challenge.message == "ezra-q, you’re 12 ahead of me on Committed. Not for long: https://gitcommitted.app/vs/addisonk/ezra-q")
    }

    @Test func equalTotalsAreDeadLevel() {
        // The Board counts a tie for you; the challenge, like its page, calls it level.
        let challenge = Challenge(you: "addisonk", friend: "ezra-q", yourTotal: 400, theirTotal: 400, locale: Self.english)
        #expect(challenge.variant == .level)
        #expect(challenge.headline == "Dead level, ezra-q.")
        #expect(challenge.message == "ezra-q, we’re dead level on Committed: https://gitcommitted.app/vs/addisonk/ezra-q")
    }

    @Test func bigGapsAreGrouped() {
        let challenge = Challenge(you: "addisonk", friend: "ezra-q", yourTotal: 2_416, theirTotal: 1_212, locale: Self.english)
        #expect(challenge.headline == "I’m 1,204 ahead of you, ezra-q.")
    }

    @Test func linkPutsYouFirstInTheLoginsThePageReads() {
        // GitHub logins are case-insensitive; the page reads them lowercased.
        let challenge = Challenge(you: "AddisonK", friend: "Ezra-Q", yourTotal: 1, theirTotal: 0, locale: Self.english)
        #expect(challenge.url.absoluteString == "https://gitcommitted.app/vs/addisonk/ezra-q")
        #expect(challenge.linkText == "gitcommitted.app/vs/addisonk/ezra-q")
        // The words keep their login as GitHub shows it.
        #expect(challenge.headline == "I’m 1 ahead of you, Ezra-Q.")
    }

    @Test func storyLines() {
        #expect(Challenge.eyebrow == "A challenge · 30 days")
        #expect(Challenge.prompt == "Think you can catch me?")
    }

    // MARK: Where it shows

    @Test func someoneElsesLoadedRaceCanBeChallenged() async throws {
        let model = await connectedBoard()
        model.showPerson("ezra-q")
        let person = try #require(model.shownPerson)
        let race = try #require(person.race)
        let challenge = try #require(model.challenge(for: person))
        #expect(challenge.you == SampleServices.owner)
        #expect(challenge.friend == "ezra-q")
        #expect(challenge.yourTotal == race.yourTotal)
        #expect(challenge.theirTotal == race.theirTotal)
    }

    @Test func yourOwnViewHasNoChallenge() async throws {
        let model = await connectedBoard()
        model.showPerson(SampleServices.owner)
        let person = try #require(model.shownPerson)
        #expect(model.challenge(for: person) == nil)
    }

    @Test func noChallengeBeforeTheRaceLoads() async throws {
        let model = await connectedBoard(refreshed: false)
        model.showPerson("ezra-q")
        let person = try #require(model.shownPerson)
        #expect(person.race == nil)
        #expect(model.challenge(for: person) == nil)
    }

    @Test func theSampleBoardHasNoChallenge() async throws {
        let model = await sampleBoard()
        model.showPerson("ezra-q")
        let person = try #require(model.shownPerson)
        #expect(person.race != nil)
        #expect(model.challenge(for: person) == nil)
    }

    // MARK: Asked for from outside (a notification's Share your race, #137)

    @Test func askingForAChallengeOpensTheirViewAndHandsItOverOnce() async throws {
        let model = await connectedBoard()
        model.selectedTab = .settings
        model.requestChallenge("ezra-q")
        #expect(model.selectedTab == .board)
        #expect(model.selectedPerson == "ezra-q")
        let person = try #require(model.shownPerson)
        #expect(model.takeRequestedChallenge(for: person)?.friend == "ezra-q")
        #expect(model.takeRequestedChallenge(for: person) == nil)
    }

    @Test func aRequestWaitsForTheRaceToLoad() async throws {
        let model = await connectedBoard(refreshed: false)
        model.requestChallenge("ezra-q")
        let waiting = try #require(model.shownPerson)
        #expect(model.takeRequestedChallenge(for: waiting) == nil)
        await model.refresh.refreshAll(reason: .manual)
        let loaded = try #require(model.shownPerson)
        #expect(model.takeRequestedChallenge(for: loaded)?.friend == "ezra-q")
    }

    @Test func aRequestIsDroppedWhenSomeoneElseIsShown() async throws {
        let model = await connectedBoard()
        model.requestChallenge("ezra-q")
        model.showPerson("odile-m")
        model.showPerson("ezra-q")
        let person = try #require(model.shownPerson)
        #expect(model.takeRequestedChallenge(for: person) == nil)
    }

    @Test func aRequestOnTheSampleBoardIsDropped() async throws {
        let model = await sampleBoard()
        model.requestChallenge("ezra-q")
        let person = try #require(model.shownPerson)
        #expect(model.takeRequestedChallenge(for: person) == nil)
    }

    // MARK: The image

    @Test(arguments: [Challenge.Variant.ahead, .behind, .level])
    func storyRendersAt1080By1920(variant: Challenge.Variant) throws {
        let challenge = Self.challenge(variant)
        let image = try #require(ChallengeShareRenderer.image(challenge, savedAvatars: nil))
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1920)
        if let renderDirectory {
            try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
            try #require(image.pngData()).write(to: renderDirectory.appendingPathComponent("challenge-\(variant)-story.png"))
        }
    }

    @Test func fileIsAPNGNamedForTheRace() throws {
        let url = try ChallengeShareRenderer.file(Self.challenge(.ahead), savedAvatars: nil)
        #expect(url.lastPathComponent == "Committed-challenge-addisonk-vs-ezra-q.png")
        #expect(try Data(contentsOf: url).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func shareCarriesTheImageAndTheMessage() throws {
        let challenge = Self.challenge(.behind)
        let share = try ChallengeShare(challenge, savedAvatars: nil)
        #expect(share.message == challenge.message)
        #expect(share.image.lastPathComponent == "Committed-challenge-addisonk-vs-ezra-q.png")
    }

    // MARK: Fixtures

    static func challenge(_ variant: Challenge.Variant) -> Challenge {
        let theirs = 400
        let yours = switch variant {
        case .ahead: 412
        case .behind: 388
        case .level: 400
        }
        return Challenge(you: "addisonk", friend: "ezra-q", yourTotal: yours, theirTotal: theirs, locale: english)
    }

    nonisolated static let november10 = PersonViewAppTests.november10
    let widgets = RecordingWidgets()

    /// The Sample board's people and counts as a connected board (the screenshot fixture's graph),
    /// loaded unless `refreshed` is false.
    private func connectedBoard(refreshed: Bool = true) async -> AppModel {
        let now: @Sendable () -> Date = { Self.november10 }
        let model = AppModel(
            services: SampleServices.make(now: now),
            backgroundTime: FakeBackgroundTime(),
            liveRankActivities: FakeLiveRankActivities(),
            widgets: widgets.publisher,
            now: now
        )
        await model.auth.refreshIdentity()
        await model.roster.refresh(force: true)
        if refreshed { await model.refresh.refreshAll(reason: .manual) }
        return model
    }

    private func sampleBoard() async -> AppModel {
        let notConnected = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: nil)
        )
        let now: @Sendable () -> Date = { Self.november10 }
        let model = AppModel(
            services: notConnected,
            sampleServices: { SampleServices.make(now: now) },
            backgroundTime: FakeBackgroundTime(),
            liveRankActivities: FakeLiveRankActivities(),
            widgets: widgets.publisher,
            now: now
        )
        await model.startSampleBoard()
        return model
    }
}
