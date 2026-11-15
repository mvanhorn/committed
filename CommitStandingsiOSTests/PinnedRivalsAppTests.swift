import Foundation
import Testing
@testable import CommitStandingsiOS

/// Pinned rivals through the app model: saved on this iPhone per GitHub account, kept through
/// Disconnect GitHub and a relaunch, unpinned by hiding, and never saved from the Sample board.
@MainActor
@Suite(.serialized)
struct PinnedRivalsAppTests {
    let clock = TestClock()
    let widgets = RecordingWidgets()
    /// This test's own UserDefaults, standing in for `.standard` across "launches".
    let defaults = UserDefaults(suiteName: "PinnedRivalsAppTests-\(UUID().uuidString)")!

    /// One launch of the app, its visibility and pins saved in `defaults` as the shipping app's are.
    /// Connect GitHub signs in as `me`, whose board is ada and grace.
    private func launch(token: String? = nil) -> AppModel {
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ApprovingGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let services = CommittedServices(
            store: StandingsStore(
                persistence: InMemoryCompetitorPersistence(),
                hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence(defaults: defaults),
                pinnedRivalsPersistence: UserDefaultsPinnedRivalsPersistence(defaults: defaults)
            ),
            credentials: InMemoryGitHubCredentialStore(token: token),
            contributions: FakeContributions(["me": 3, "ada": 5, "grace": 1]),
            gitHubAuth: GitHubAuth(clientID: "test", session: session, sleep: { _ in }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada", "grace"]),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        return AppModel(
            services: services,
            sampleServices: { [clock] in SampleServices.make(now: { clock.now }) },
            defaults: defaults,
            backgroundTime: FakeBackgroundTime(),
            widgets: widgets.publisher,
            now: { [clock] in clock.now }
        )
    }

    private func pinned(_ model: AppModel) -> [String] {
        model.store.pinnedRivals.map(\.username)
    }

    @Test func pinsSurviveDisconnectConnectAndARelaunch() async {
        let model = launch()
        await model.connectGitHub()
        #expect(model.mode == .connected)
        #expect(model.store.setPinned(true, username: "ada"))
        #expect(pinned(model) == ["ada"])

        model.auth.signOut() // Disconnect GitHub
        #expect(model.store.competitors.isEmpty)
        #expect(pinned(model).isEmpty)

        await model.connectGitHub()
        #expect(model.mode == .connected)
        #expect(pinned(model) == ["ada"])

        let relaunched = launch(token: "gho_new")
        await relaunched.sceneDidBecomeActive()
        #expect(pinned(relaunched) == ["ada"])
    }

    @Test func hidingAPinnedRivalInPeopleUnpinsThem() async {
        let model = launch()
        await model.connectGitHub()
        model.store.setPinned(true, username: "ada")
        model.store.setPinned(true, username: "grace")

        model.store.setHidden(true, username: "ada")
        await model.visibilityDidChange()

        #expect(pinned(model) == ["grace"])
        #expect(UserDefaultsPinnedRivalsPersistence(defaults: defaults).load()["me"] == ["grace"])
    }

    @Test func pinsOnTheSampleBoardLastUntilYouLeaveIt() async {
        let model = launch()
        await model.startSampleBoard()
        #expect(model.store.setPinned(true, username: "ezra-q"))
        #expect(model.store.setPinned(true, username: "odile-m"))
        #expect(pinned(model) == ["ezra-q", "odile-m"])

        await model.leaveSampleBoard()
        await model.startSampleBoard()

        #expect(pinned(model).isEmpty)
        #expect(UserDefaultsPinnedRivalsPersistence(defaults: defaults).load().isEmpty)
    }

    @Test func connectingFromTheSampleBoardLeavesNoSamplePins() async {
        let model = launch()
        await model.startSampleBoard()
        model.store.setPinned(true, username: "ezra-q")

        await model.connectGitHub()

        #expect(model.mode == .connected)
        #expect(pinned(model).isEmpty)
        #expect(UserDefaultsPinnedRivalsPersistence(defaults: defaults).load().isEmpty)
    }
}
