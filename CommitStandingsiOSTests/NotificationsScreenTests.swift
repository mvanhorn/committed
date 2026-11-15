import Foundation
import Testing
import UserNotifications
@testable import CommitStandingsiOS

/// Settings ▸ Notifications (#130): what the screen offers in each kind of build, choices saved per
/// account that reach the relay right away, pinned rivals sent as `rivals`, and the permission state.
@MainActor
struct NotificationsScreenTests {
    let clock = TestClock()
    let activities = FakeLiveRankActivities()
    let relay = FakeLiveRankRelay()
    let preferences = InMemoryLiveRankPreferences()
    let choices = InMemoryNotificationPreferences()
    let defaults = UserDefaults(suiteName: "NotificationsScreenTests.\(UUID().uuidString)")!

    init() {
        relay.pushUpdates = .token
    }

    private func makeModel(
        signedIn: Bool = true,
        notificationsOn: Bool = true,
        authorization: UNAuthorizationStatus = .authorized
    ) -> AppModel {
        defaults.set(notificationsOn, forKey: NotificationService.enabledDefaultsKey)
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ApprovingGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: signedIn ? "gho_test" : nil),
            contributions: FakeContributions(["me": 3, "ada": 5, "bo": 1]),
            notifications: NotificationService(defaults: defaults, authorize: { true }, sink: { _ in }),
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
        return AppModel(
            services: services,
            sampleServices: { [clock] in SampleServices.make(now: { clock.now }) },
            backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities, liveRankPreferences: preferences, liveRankRelay: relay,
            notificationPreferences: choices,
            notificationAuthorization: { authorization },
            now: { clock.now }
        )
    }

    /// Relay notifications agreed to, Live rank off.
    private func agreedToRelayNotifications() {
        preferences.save(LiveRankPreferences(isEnabled: false, relayDisclosureAccepted: true, relayNotifications: true))
    }

    private var lastNotifications: RelayNotificationsConfiguration? {
        relay.notifications.last ?? nil
    }

    // MARK: What the screen shows

    @Test func aRelayBuildShowsEveryChoice() async {
        agreedToRelayNotifications()
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(model.showsRelayNotificationChoices)
    }

    @Test func aBuildWithoutTheRelayShowsOnlyPasses() async {
        relay.pushUpdates = .none
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(!model.showsRelayNotificationChoices)
    }

    @Test func theSampleBoardShowsOnlyPasses() async {
        agreedToRelayNotifications()
        let model = makeModel(signedIn: false)
        await model.startSampleBoard()
        #expect(model.mode == .sampleBoard)
        #expect(!model.showsRelayNotificationChoices)
    }

    @Test func notNowShowsOnlyPassesWithTheInAppBehavior() async {
        preferences.save(LiveRankPreferences(isEnabled: false, relayDisclosureAccepted: true, relayNotifications: false))
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(!model.showsRelayNotificationChoices)
    }

    // MARK: Saving

    @Test func aChoiceIsSavedForThisAccountAndReachesTheRelayRightAway() async {
        agreedToRelayNotifications()
        let model = makeModel()
        await model.sceneDidBecomeActive()

        await model.updateNotificationChoices { $0.passes = .rivals }
        await model.updateNotificationChoices { $0.window = .monthly }
        await model.updateNotificationChoices { $0.quietHours = .init(start: "23:30", end: "07:00") }

        var expected = NotificationPreferences()
        expected.passes = .rivals
        expected.window = .monthly
        expected.quietHours = .init(start: "23:30", end: "07:00")
        #expect(model.notificationChoices == expected)
        #expect(choices.load(account: "me") == expected)
        #expect(choices.load(account: "someone-else") == NotificationPreferences())
        #expect(lastNotifications?.preferences == expected)
    }

    @Test func quietHoursOffReachTheRelayAsNull() async {
        agreedToRelayNotifications()
        let model = makeModel()
        await model.sceneDidBecomeActive()

        await model.setQuietHoursOn(false)
        #expect(lastNotifications?.preferences.quietHours == nil)

        await model.setQuietHoursOn(true)
        #expect(lastNotifications?.preferences.quietHours == .init(start: "22:00", end: "08:00"))
    }

    @Test func closeCallsStartOffAndTurningThemOnIsSavedAndReachesTheRelay() async {
        agreedToRelayNotifications()
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(model.notificationChoices.closeCalls == false)

        await model.updateNotificationChoices { $0.closeCalls = true }

        #expect(model.notificationChoices.closeCalls)
        #expect(choices.load(account: "me").closeCalls)
        #expect(lastNotifications?.preferences.closeCalls == true)
    }

    /// Before any switch is turned on (no permission asked yet), a choice such as the Window is
    /// saved, but it turns nothing on: the relay hears notifications off.
    @Test func aChoiceBeforeAnySwitchIsOnTurnsNothingOn() async {
        agreedToRelayNotifications()
        let model = makeModel(notificationsOn: false)
        await model.sceneDidBecomeActive()

        await model.updateNotificationChoices { $0.window = .weekly }

        #expect(model.notificationChoices.window == .weekly)
        #expect(relay.notifications.last == .some(nil))
    }

    @Test func theSampleBoardSavesNoChoices() async {
        agreedToRelayNotifications()
        let model = makeModel(signedIn: false)
        await model.startSampleBoard()

        await model.updateNotificationChoices { $0.passes = .rivals }

        #expect(model.notificationChoices == NotificationPreferences())
        #expect(relay.notifications.compactMap { $0 }.isEmpty)
    }

    // MARK: Pinned rivals

    @Test func pinningAndUnpinningReRegistersTheRivals() async {
        agreedToRelayNotifications()
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(lastNotifications?.rivals == [])

        #expect(await model.setRivalPinned(true, username: "ada"))
        #expect(lastNotifications?.rivals == ["ada"])
        #expect(await model.setRivalPinned(true, username: "bo"))
        #expect(lastNotifications?.rivals == ["ada", "bo"])

        #expect(await model.setRivalPinned(false, username: "ada"))
        #expect(lastNotifications?.rivals == ["bo"])
    }

    @Test func hidingAPinnedRivalReRegistersWithoutThem() async {
        agreedToRelayNotifications()
        let model = makeModel()
        await model.sceneDidBecomeActive()
        await model.setRivalPinned(true, username: "ada")

        model.store.setHidden(true, username: "ada")
        await model.visibilityDidChange()

        #expect(lastNotifications?.rivals == [])
    }

    @Test func pinningWithRelayNotificationsOffTellsTheRelayNothing() async {
        relay.pushUpdates = .none
        let model = makeModel()
        await model.sceneDidBecomeActive()

        #expect(await model.setRivalPinned(true, username: "ada"))

        #expect(model.store.isPinned("ada"))
        #expect(relay.notifications.compactMap { $0 }.isEmpty)
    }

    // MARK: Permission

    @Test func permissionDeniedInIOSSettingsIsShown() async {
        let model = makeModel(authorization: .denied)
        await model.checkNotificationPermission()
        #expect(model.notificationsDeniedInSettings)
    }

    @Test func permissionGrantedIsNotDenied() async {
        let model = makeModel(authorization: .authorized)
        await model.checkNotificationPermission()
        #expect(!model.notificationsDeniedInSettings)
    }
}

/// Quiet hours' "HH:MM" times, as the relay reads them, from any clock the iPhone shows.
struct QuietHoursTimeTests {
    @Test func formatsTwentyFourHourTimesWithLeadingZeros() {
        #expect(NotificationPreferences.QuietHours.time(hour: 22, minute: 0) == "22:00")
        #expect(NotificationPreferences.QuietHours.time(hour: 8, minute: 5) == "08:05")
        #expect(NotificationPreferences.QuietHours.time(hour: 0, minute: 0) == "00:00")
        #expect(NotificationPreferences.QuietHours.time(hour: 23, minute: 59) == "23:59")
    }

    @Test func readsTimesBack() {
        #expect(NotificationPreferences.QuietHours.hourAndMinute("22:00") == .init(hour: 22, minute: 0))
        #expect(NotificationPreferences.QuietHours.hourAndMinute("07:30") == .init(hour: 7, minute: 30))
        #expect(NotificationPreferences.QuietHours.hourAndMinute("nonsense") == nil)
    }

    @Test func aDatePickersDateBecomesItsLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 2026-11-05T14:30:00Z is 23:30 in Tokyo, whatever the device's 12- or 24-hour setting.
        let date = Date(timeIntervalSince1970: 1_793_889_000)
        #expect(NotificationPreferences.QuietHours.time(from: date, calendar: calendar) == "23:30")
        let back = try #require(NotificationPreferences.QuietHours.date(for: "23:30", calendar: calendar))
        #expect(calendar.dateComponents([.hour, .minute], from: back) == DateComponents(hour: 23, minute: 30))
    }
}
