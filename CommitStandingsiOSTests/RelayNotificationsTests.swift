import Foundation
import Testing
import UserNotifications
@testable import CommitStandingsiOS

/// Relay notifications on iPhone (spec #124, #126): consent, what the relay is told, one source of
/// crossing notifications at a time, and where a tapped pass goes.
@MainActor
struct RelayNotificationsTests {
    let clock = TestClock()
    let activities = FakeLiveRankActivities()
    let relay = FakeLiveRankRelay()
    let preferences = InMemoryLiveRankPreferences()
    let choices = InMemoryNotificationPreferences()
    let remote = NoRemoteNotifications()
    let defaults = UserDefaults(suiteName: "RelayNotificationsTests.\(UUID().uuidString)")!
    let posted = PostedCrossings()

    init() {
        relay.pushUpdates = .token
    }

    private func makeModel(
        signedIn: Bool = true, notificationsOn: Bool = false, saved: [Competitor] = []
    ) -> (AppModel, FakeContributions) {
        defaults.set(notificationsOn, forKey: NotificationService.enabledDefaultsKey)
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ApprovingGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let posted = posted
        let contributions = FakeContributions(["me": 3, "ada": 5, "bo": 1])
        let people = InMemoryCompetitorPersistence()
        people.save(saved)
        let services = CommittedServices(
            store: StandingsStore(persistence: people),
            credentials: InMemoryGitHubCredentialStore(token: signedIn ? "gho_test" : nil),
            contributions: contributions,
            notifications: NotificationService(defaults: defaults, authorize: { true }, sink: { posted.events += $0 }),
            gitHubAuth: GitHubAuth(clientID: "test", session: session, sleep: { _ in }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada", "bo"]),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        let model = AppModel(
            services: services, backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities, liveRankPreferences: preferences, liveRankRelay: relay,
            notificationPreferences: choices, remoteNotifications: remote, now: { clock.now }
        )
        return (model, contributions)
    }

    /// The 1.0.x state: the earlier relay sheet accepted, Live rank on.
    private func acceptedEarlierSheet() {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
    }

    private var lastNotifications: RelayNotificationsConfiguration?? { relay.notifications.last }

    // MARK: Consent

    @Test func earlierSheetWithNotificationsOnAsksOnce() async {
        acceptedEarlierSheet()
        let (model, _) = makeModel(notificationsOn: true)
        await model.sceneDidBecomeActive()

        #expect(model.isShowingRelayNotificationsConsent)
        #expect(!model.isShowingLiveRankDisclosure)
        #expect(lastNotifications == .some(nil)) // not before Turn On

        await model.declineRelayNotifications()
        #expect(!model.isShowingRelayNotificationsConsent)
        #expect(model.liveRank.isEnabled) // Live rank untouched

        let (relaunched, _) = makeModel(notificationsOn: true)
        await relaunched.sceneDidBecomeActive()
        #expect(!relaunched.isShowingRelayNotificationsConsent)
    }

    @Test func earlierSheetWithNotificationsOffAsksWhenTheSwitchTurnsOn() async {
        acceptedEarlierSheet()
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        #expect(!model.isShowingRelayNotificationsConsent)

        await model.leaderboardNotificationsChanged(true)

        #expect(model.isShowingRelayNotificationsConsent)
        await model.acceptRelayNotifications()
        #expect(!model.isShowingRelayNotificationsConsent)
        #expect(model.relayNotificationsOn)
        #expect(lastNotifications == .some(RelayNotificationsConfiguration(preferences: NotificationPreferences())))
        #expect(remote.requests > 0)
    }

    @Test func turnOnNeverTurnsLiveRankOn() async {
        // Never saw the relay sheet: declined Live rank in it.
        preferences.save(LiveRankPreferences(isEnabled: false))
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()

        await model.leaderboardNotificationsChanged(true)
        #expect(model.isShowingRelayNotificationsConsent)
        await model.acceptRelayNotifications()

        #expect(!model.liveRank.isEnabled)
        #expect(activities.running.isEmpty)
        #expect(relay.configurations.last == .some(LiveRankConfiguration(
            selfLogin: "me", competitors: ["me", "ada", "bo"], window: .daily, liveRank: false
        )))
        #expect(lastNotifications == .some(RelayNotificationsConfiguration(preferences: NotificationPreferences())))
    }

    @Test func notNowAfterTheSwitchAsksAgainOnlyWhenTurnedOnAgain() async {
        acceptedEarlierSheet()
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        await model.leaderboardNotificationsChanged(true)
        await model.declineRelayNotifications()
        #expect(!model.relayNotificationsOn)
        #expect(model.services.notifications.isEnabled) // the in-app ones stay on

        await model.leaderboardNotificationsChanged(false)
        await model.leaderboardNotificationsChanged(true)
        #expect(model.isShowingRelayNotificationsConsent)
    }

    @Test func firstConnectShowsOnlyTheRelaySheet() async {
        let (model, _) = makeModel(notificationsOn: true)
        await model.sceneDidBecomeActive()

        #expect(model.isShowingLiveRankDisclosure)
        #expect(!model.isShowingRelayNotificationsConsent)

        // The relay sheet carries the notifications line, so accepting it agrees to both.
        await model.acceptLiveRankDisclosure()
        #expect(!model.isShowingRelayNotificationsConsent)
        #expect(model.relayNotificationsOn)
        #expect(preferences.load().relayDisclosureVersion == RelayConsent.currentVersion)
        // The relay hears about notifications straight away, not at the next refresh.
        #expect(lastNotifications == .some(RelayNotificationsConfiguration(preferences: NotificationPreferences())))
        #expect(remote.requests > 0)
    }

    @Test func notNowInTheRelaySheetDoesntAskAgainStraightAway() async {
        let (model, _) = makeModel(notificationsOn: true)
        await model.sceneDidBecomeActive()
        await model.declineLiveRankDisclosure()

        #expect(!model.isShowingLiveRankDisclosure)
        #expect(!model.isShowingRelayNotificationsConsent)
        #expect(!model.relayNotificationsOn)
    }

    @Test func noRelayNeverAsks() async {
        relay.pushUpdates = .none
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        await model.leaderboardNotificationsChanged(true)

        #expect(!model.isShowingRelayNotificationsConsent)
        #expect(!model.relayNotificationsOn)
    }

    @Test func theSampleBoardNeverAsksOrRegisters() async {
        acceptedEarlierSheet()
        let (model, _) = makeModel(signedIn: false, notificationsOn: true)
        await model.startSampleBoard()
        // (The Sample board's own switch would show the real iOS permission prompt, which a test
        // host can't answer, so this checks what the switch leads to without flipping it.)
        await model.syncRelayNotifications()

        #expect(!model.isShowingRelayNotificationsConsent)
        #expect(!model.isShowingLiveRankDisclosure)
        #expect(relay.notifications.compactMap { $0 }.isEmpty)
        #expect(remote.requests == 0)
    }

    @Test func disconnectTurnsRelayNotificationsOff() async {
        preferences.save(LiveRankPreferences(isEnabled: false, relayDisclosureAccepted: true, relayNotifications: true))
        let (model, _) = makeModel(notificationsOn: true)
        await model.sceneDidBecomeActive()
        #expect(lastNotifications != .some(nil))

        model.auth.signOut()
        await model.liveRank.idle()
        await model.sceneDidBecomeActive()

        #expect(relay.configurations.last == .some(nil))
        #expect(lastNotifications == .some(nil))
    }

    @Test func choicesAreThisAccountsOwn() async {
        var mine = NotificationPreferences()
        mine.window = .weekly
        choices.save(mine, account: "me")
        choices.save(NotificationPreferences(), account: "someone-else")
        preferences.save(LiveRankPreferences(isEnabled: false, relayDisclosureAccepted: true, relayNotifications: true))
        let (model, _) = makeModel(notificationsOn: true)

        await model.sceneDidBecomeActive()

        #expect(lastNotifications == .some(RelayNotificationsConfiguration(preferences: mine)))
    }

    // MARK: One source at a time

    @Test func noLocalCrossingWhileTheRelayDelivers() async {
        preferences.save(LiveRankPreferences(isEnabled: false, relayDisclosureAccepted: true, relayNotifications: true))
        relay.deliversNotifications = true
        let (model, contributions) = makeModel(notificationsOn: true)
        await model.sceneDidBecomeActive()

        await contributions.set("bo", 9)
        clock.advance(300)
        await model.pullToRefresh()

        #expect(posted.events.isEmpty)
    }

    @Test func localCrossingsUntilTheRelayHasARegistration() async {
        preferences.save(LiveRankPreferences(isEnabled: false, relayDisclosureAccepted: true, relayNotifications: true))
        relay.deliversNotifications = false // for example, no alert token yet
        let (model, contributions) = makeModel(notificationsOn: true)
        await model.sceneDidBecomeActive()

        await contributions.set("bo", 9)
        clock.advance(300)
        await model.pullToRefresh()

        #expect(posted.events.map(\.rivalUsername) == ["bo"])
    }

    // MARK: Taps

    @Test func aTappedPassOpensThatPersonsView() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.selectedTab = .settings

        let link = DeepLink(notification: ["kind": "pass", "login": "ada", "aps": ["category": "PASS"]])
        #expect(link == .person(login: "ada"))
        model.open(link!)

        #expect(model.selectedTab == .board)
        #expect(model.selectedPerson == "ada")
        #expect(model.shownPerson?.competitor.username == "ada")
    }

    @Test func aPassAboutSomeoneNoLongerOnTheBoardOpensTheBoard() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.store.setHidden(true, username: "bo")
        model.selectedTab = .people

        model.open(.person(login: "bo"))

        #expect(model.selectedTab == .board)
        #expect(model.selectedPerson == nil)
    }

    @Test func personLinksRoundTrip() {
        #expect(DeepLink.person(login: "ada").url.absoluteString == "committed://person/ada")
        #expect(DeepLink(url: URL(string: "committed://person/Ada")!) == .person(login: "ada"))
        #expect(DeepLink(url: URL(string: "committed://person/")!) == nil)
        #expect(DeepLink(url: URL(string: "committed://person/a/b")!) == nil)
        #expect(DeepLink(notification: ["kind": "result"]) == nil)
    }

    // MARK: Pass actions (#137)

    @Test func challengeLinksRoundTrip() {
        #expect(DeepLink.challenge(login: "ada").url.absoluteString == "committed://challenge/ada")
        #expect(DeepLink(url: URL(string: "committed://challenge/Ada")!) == .challenge(login: "ada"))
        #expect(DeepLink(url: URL(string: "committed://challenge/")!) == nil)
        #expect(DeepLink(url: URL(string: "committed://challenge/a/b")!) == nil)
    }

    private let pass: [AnyHashable: Any] = ["kind": "pass", "login": "Ada", "aps": ["category": "PASS"]]

    @Test func eachPassActionHasItsOwnDestination() {
        // What iOS hands the app: the system's identifier for a body tap, or the action's.
        #expect(DeepLink(notification: pass, action: "com.apple.UNNotificationDefaultActionIdentifier")
            == .person(login: "ada"))
        #expect(DeepLink(notification: pass, action: "SHARE_RACE") == .challenge(login: "ada"))
        #expect(DeepLink(notification: pass, action: "OPEN_BOARD") == .board(window: nil))
    }

    @Test func passActionsWithoutAUsableLogin() {
        let noLogin: [AnyHashable: Any] = ["kind": "pass", "aps": ["category": "PASS"]]
        #expect(DeepLink(notification: noLogin, action: "SHARE_RACE") == nil)
        #expect(DeepLink(notification: noLogin, action: "OPEN_BOARD") == .board(window: nil))
    }

    @Test func otherResponsesGoNowhere() {
        #expect(DeepLink(notification: pass, action: "com.apple.UNNotificationDismissActionIdentifier") == nil)
        #expect(DeepLink(notification: pass, action: "SOMETHING_ELSE") == nil)
        #expect(DeepLink(notification: ["kind": "result"], action: "OPEN_BOARD") == nil)
    }

    @Test func passNotificationsOfferShareYourRaceAndOpenBoard() throws {
        let category = try #require(ForegroundNotificationPresenter.categories.first { $0.identifier == "PASS" })
        #expect(category.actions.map(\.identifier) == ["SHARE_RACE", "OPEN_BOARD"])
        #expect(category.actions.map(\.title) == ["Share your race", "Open Board"])
        // Both open Committed, from a locked phone too.
        #expect(category.actions.allSatisfy { $0.options.contains(.foreground) })
        #expect(ForegroundNotificationPresenter.categories.count == 1)
    }

    @Test func shareYourRaceOpensTheirViewAndAsksForTheChallenge() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.selectedTab = .settings

        model.open(DeepLink(notification: pass, action: "SHARE_RACE")!)

        #expect(model.selectedTab == .board)
        #expect(model.selectedPerson == "ada")
        #expect(model.requestedChallenge == "ada")
    }

    @Test func shareYourRaceAboutSomeoneNoLongerOnTheBoardOpensTheBoard() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.store.setHidden(true, username: "ada")
        model.selectedTab = .people

        model.open(DeepLink(notification: pass, action: "SHARE_RACE")!)

        #expect(model.selectedTab == .board)
        #expect(model.selectedPerson == nil)
        #expect(model.requestedChallenge == nil)
    }

    @Test func openBoardOpensTheBoardOnItsWindow() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.store.selectedWindow = .weekly
        model.showPerson("bo")
        model.selectedTab = .settings

        model.open(DeepLink(notification: pass, action: "OPEN_BOARD")!)

        #expect(model.selectedTab == .board)
        #expect(model.store.selectedWindow == .weekly)
    }

    @Test func shareYourRaceFromAColdLaunchWaitsForTheRace() async {
        // Committed was closed: the action arrives before the first refresh, with only the people
        // saved last time.
        let (model, _) = makeModel(saved: [Competitor(username: "me", isSelf: true),
                                           Competitor(username: "ada", isSelf: false)])

        model.open(DeepLink(notification: pass, action: "SHARE_RACE")!)
        #expect(model.selectedTab == .board)
        #expect(model.selectedPerson == "ada")

        await model.sceneDidBecomeActive()
        #expect(model.selectedPerson == "ada")
        #expect(model.requestedChallenge == "ada")
    }
}

/// What the app would have posted as local crossing notifications.
@MainActor
final class PostedCrossings {
    var events: [RankChangeEvent] = []
}

/// Notification choices: their encoding for the relay, defaults, and storage per account.
struct NotificationPreferencesTests {
    @Test func defaultsEncodeToTheRelaysObject() throws {
        let data = try JSONEncoder().encode(NotificationPreferences())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["window"] as? String == "daily")
        #expect(object["passes"] as? String == "everyone")
        #expect(object["closeCalls"] as? Bool == false)
        #expect(object["results"] as? Bool == true)
        #expect(object["records"] as? Bool == true)
        #expect(object["streakReminder"] as? Bool == false)
        #expect(object["delivery"] as? String == "summary")
        #expect(object["quietHours"] as? [String: String] == ["start": "22:00", "end": "08:00"])
        #expect(object.count == 8)
    }

    @Test func quietHoursOffIsAnExplicitNull() throws {
        var preferences = NotificationPreferences()
        preferences.quietHours = nil
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any]
        )
        #expect(object["quietHours"] is NSNull)
        #expect(try JSONDecoder().decode(NotificationPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }

    @Test func missingChoicesTakeTheirDefaults() throws {
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: Data(#"{"passes":"rivals"}"#.utf8))
        var expected = NotificationPreferences()
        expected.passes = .rivals
        #expect(decoded == expected)
    }

    @Test @MainActor func savedPerAccount() {
        let defaults = UserDefaults(suiteName: "NotificationPreferencesTests.\(UUID().uuidString)")!
        var mine = NotificationPreferences()
        mine.window = .monthly
        UserDefaultsNotificationPreferences(defaults: defaults).save(mine, account: "me")

        let reloaded = UserDefaultsNotificationPreferences(defaults: defaults)
        #expect(reloaded.load(account: "me") == mine)
        #expect(reloaded.load(account: "ada") == NotificationPreferences())
    }

    @Test func relayConsentFrom105ReadsAsTheEarlierSheet() throws {
        let saved = Data(#"{"isEnabled":true,"window":"daily","relayDisclosureAccepted":true}"#.utf8)
        let decoded = try JSONDecoder().decode(LiveRankPreferences.self, from: saved)
        #expect(decoded.isEnabled == true)
        #expect(decoded.relayDisclosureAccepted)
        #expect(decoded.relayDisclosureVersion == 1)
        #expect(decoded.relayNotifications == nil)
    }
}
