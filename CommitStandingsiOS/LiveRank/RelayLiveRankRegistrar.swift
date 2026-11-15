import Foundation
import os

enum LiveRankLog {
    /// `log stream --predicate 'subsystem == "com.addisonk.CommitStandings.iOS"'` shows what the app
    /// sends the relay. Tokens are logged as short prefixes; the install secret never.
    static let relay = Logger(subsystem: "com.addisonk.CommitStandings.iOS", category: "LiveRankRelay")
}

/// This iPhone's identity at the Committed relay: a random installation ID and a random secret,
/// generated once and kept in the Keychain. The relay stores only the secret's hash; the first
/// registration claims the ID.
struct RelayInstallation: Codable, Equatable, Sendable {
    struct Credentials: Equatable, Sendable {
        let id: String
        let secret: String
    }

    var id: String
    var secret: String
    /// Whether the relay may still hold a registration for this installation, so turning Live rank
    /// off or disconnecting after a relaunch still deletes it.
    var isRegistered: Bool

    var credentials: Credentials { Credentials(id: id, secret: secret) }

    static func generate() -> RelayInstallation {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return RelayInstallation(id: UUID().uuidString, secret: Data(bytes).lowercaseHex, isRegistered: false)
    }
}

protocol RelayInstallationStoring: AnyObject {
    func load() -> RelayInstallation?
    func save(_ installation: RelayInstallation)
}

final class InMemoryRelayInstallationStore: RelayInstallationStoring {
    private var installation: RelayInstallation?
    init(_ installation: RelayInstallation? = nil) { self.installation = installation }
    func load() -> RelayInstallation? { installation }
    func save(_ installation: RelayInstallation) { self.installation = installation }
}

/// Which APNs the relay pushes through, matching the app's `aps-environment` entitlement:
/// `development` builds get `sandbox`, App Store and TestFlight builds get `production`.
enum RelayAPNsEnvironment: String, Sendable {
    case sandbox
    case production
}

/// The body of `PUT /v1/installations/{id}`: exactly the keys the relay accepts.
struct RelayRegistration: Equatable, Sendable, Encodable {
    var pushToStartToken: String?
    var login: String
    var competitors: [String]
    /// Live rank's Window.
    var window: String
    var timeZone: String
    var apnsEnvironment: String
    /// Live rank on. Off, the relay never starts, updates or rotates a Live Activity.
    var liveRank: Bool = true
    /// The APNs device token relay notifications go to; nil until iOS issues one, or with them off.
    var alertToken: String?
    /// Nil = relay notifications off.
    var notifications: NotificationPreferences?
    /// Pinned rivals, each on `competitors`.
    var rivals: [String] = []

    private enum CodingKeys: String, CodingKey {
        case pushToStartToken, login, competitors, window, timeZone, apnsEnvironment
        case liveRank, alertToken, notifications, rivals
    }

    // The relay expects `null` for a token iOS hasn't issued, or notifications that are off, not a
    // missing key.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pushToStartToken, forKey: .pushToStartToken)
        try container.encode(login, forKey: .login)
        try container.encode(competitors, forKey: .competitors)
        try container.encode(window, forKey: .window)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(apnsEnvironment, forKey: .apnsEnvironment)
        try container.encode(liveRank, forKey: .liveRank)
        try container.encode(alertToken, forKey: .alertToken)
        try container.encode(notifications, forKey: .notifications)
        try container.encode(rivals, forKey: .rivals)
    }
}

/// The body of `PUT /v1/installations/{id}/activity`.
struct RelayActivityReport: Equatable, Sendable, Encodable {
    var activityId: String
    var pushToken: String
}

enum LiveRankRelayError: Error, Equatable {
    /// The relay answered with this HTTP status.
    case status(Int)
}

/// The relay's device API (see `relay/README.md`). Every call authenticates with the
/// installation's secret.
protocol LiveRankRelayAPI: Sendable {
    func register(_ registration: RelayRegistration, as installation: RelayInstallation.Credentials) async throws
    func reportActivity(_ report: RelayActivityReport, as installation: RelayInstallation.Credentials) async throws
    func unregister(_ installation: RelayInstallation.Credentials) async throws
}

/// Hands push tokens from ActivityKit to the relay client.
@MainActor
protocol LiveRankTokenReceiving: AnyObject {
    func pushToStartTokenDidChange(_ token: Data) async
    func activityPushTokenDidChange(activityID: String, token: Data) async
}

/// Phase 2: the Committed relay keeps Live rank current while the app is closed, and sends relay
/// notifications (#124).
///
/// `LiveRankController` tells it the board (`LiveRankConfiguration`, with Live rank on or off)
/// whenever it changes, and nil when GitHub disconnects. `AppModel` tells it the relay notification
/// choices. ActivityKit's token streams arrive through `LiveRankTokenReceiving`, the alert token
/// through `AlertTokenReceiving`. Everything funnels into one `flush()` that brings the relay in
/// line: register when the registration body changed (board, tokens, time zone, choices), report
/// each activity's push token once it's registered, and delete the registration when GitHub
/// disconnects or both Live rank and relay notifications are off. A failed call leaves the work
/// pending; the next trigger or `retryPendingWork()` tries again. Nothing is sent when nothing
/// changed, which keeps well inside the relay's 30 writes per 10 minutes.
@MainActor
final class RelayLiveRankRegistrar: LiveRankRegistrar, LiveRankTokenReceiving, AlertTokenReceiving {
    private let api: any LiveRankRelayAPI
    private let installations: any RelayInstallationStoring
    private let apnsEnvironment: RelayAPNsEnvironment
    private let timeZone: @Sendable () -> TimeZone
    private let backgroundTime: (any BackgroundTimeProviding)?

    /// The board to register; nil until the controller first reports (a cold launch).
    private var configuration: LiveRankConfiguration?
    /// GitHub disconnected: delete the registration.
    private var isSignedOut = false
    /// Relay notifications: `.none` until the app first says (a cold launch), then on (choices) or
    /// off (nil). With Live rank off, the registration isn't deleted until this is known.
    private var notifications: RelayNotificationsConfiguration??
    private var alertToken: String?
    private var pushToStartToken: String?
    /// The last registration the relay accepted in this process.
    private var lastRegistered: RelayRegistration?
    /// Activity push tokens waiting for a registration (activity ID → token), in arrival order.
    private var pendingActivities: [(id: String, token: String)] = []
    private var reportedActivities: [String: String] = [:]
    private var isFlushing = false
    private var flushAgain = false
    private var pending: Task<Void, Never>?
    private var timeZoneObserver: (any NSObjectProtocol)?

    init(
        api: any LiveRankRelayAPI,
        installations: any RelayInstallationStoring,
        apnsEnvironment: RelayAPNsEnvironment,
        timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        notificationCenter: NotificationCenter = .default,
        backgroundTime: (any BackgroundTimeProviding)? = nil
    ) {
        self.api = api
        self.installations = installations
        self.apnsEnvironment = apnsEnvironment
        self.timeZone = timeZone
        self.backgroundTime = backgroundTime
        // The relay computes "Today" on your local calendar, so a new time zone re-registers.
        timeZoneObserver = notificationCenter.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.timeZoneDidChange() }
            } else {
                Task { @MainActor in self?.timeZoneDidChange() }
            }
        }
    }

    var pushUpdates: LiveRankPushUpdates { .token }

    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async {
        self.configuration = configuration
        isSignedOut = configuration == nil
        if isLiveRankOff { pendingActivities.removeAll() }
        await flush()
    }

    func relayNotificationsDidChange(_ configuration: RelayNotificationsConfiguration?) async {
        notifications = .some(configuration)
        await flush()
    }

    func alertTokenDidChange(_ token: Data) async {
        alertToken = token.lowercaseHex
        await flush()
    }

    /// The relay accepted a registration with notifications and an alert token.
    private(set) var deliversNotifications = false

    private var isLiveRankOff: Bool {
        isSignedOut || configuration?.liveRank == false
    }

    func retryPendingWork() async {
        await flush()
    }

    // MARK: - Tokens

    func pushToStartTokenDidChange(_ token: Data) async {
        pushToStartToken = token.lowercaseHex
        await flush()
    }

    func activityPushTokenDidChange(activityID: String, token: Data) async {
        // Live rank is off: the relay has no activity to attach it to. Before the controller
        // has reported at all (a cold launch), hold the token until the board is known.
        guard !isLiveRankOff else { return }
        let hex = token.lowercaseHex
        guard reportedActivities[activityID] != hex else { return }
        pendingActivities.removeAll { $0.id == activityID }
        pendingActivities.append((activityID, hex))
        await flush()
    }

    private func timeZoneDidChange() {
        pending = Task { await flush() }
    }

    /// Wait for work started by a time-zone change.
    func idle() async {
        await pending?.value
    }

    // MARK: - Flush

    private func flush() async {
        if isFlushing {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        let token = backgroundTime?.begin("Committed relay")
        defer { if let token { backgroundTime?.end(token) } }
        repeat {
            flushAgain = false
            await flushOnce()
        } while flushAgain
    }

    private func flushOnce() async {
        if isSignedOut {
            await unregisterIfNeeded()
            return
        }
        if let configuration {
            if !configuration.liveRank {
                switch notifications {
                case .none:
                    // Not known yet: neither register nor delete until the app says.
                    return
                case .some(.none):
                    // Both off.
                    await unregisterIfNeeded()
                    return
                case .some(.some):
                    break
                }
            }
            guard await register(configuration) else { return }
            guard configuration.liveRank else { return }
        } else {
            // No board yet: a background launch, for example when the relay started an activity by
            // push-to-start. If the relay holds this installation from an earlier launch, report
            // the activity now (the relay counts its age from the report); otherwise wait.
            guard installations.load()?.isRegistered == true else { return }
        }
        guard var installation = installations.load() else { return }

        while let next = pendingActivities.first {
            do {
                try await api.reportActivity(
                    RelayActivityReport(activityId: next.id, pushToken: next.token), as: installation.credentials
                )
            } catch LiveRankRelayError.status(404) {
                // The relay lost the registration (deleted elsewhere, or a fresh database):
                // register again once the board is known, then report.
                lastRegistered = nil
                deliversNotifications = false
                installation.isRegistered = false
                installations.save(installation)
                return
            } catch {
                LiveRankLog.relay.error("activity report failed: \(String(describing: error), privacy: .public)")
                return
            }
            LiveRankLog.relay.info("reported activity \(next.id, privacy: .public)")
            pendingActivities.removeFirst()
            reportedActivities[next.id] = next.token
        }
    }

    /// PUT the registration when its body changed. False when the relay couldn't be reached.
    private func register(_ configuration: LiveRankConfiguration) async -> Bool {
        var installation = installations.load() ?? {
            let new = RelayInstallation.generate()
            installations.save(new)
            return new
        }()
        let notifications = self.notifications ?? nil
        let registration = RelayRegistration(
            // Live rank's tokens only while it's on, the alert token only while notifications are.
            pushToStartToken: configuration.liveRank ? pushToStartToken : nil,
            login: configuration.selfLogin,
            competitors: configuration.competitors,
            window: configuration.window.rawValue,
            timeZone: timeZone().identifier,
            apnsEnvironment: apnsEnvironment.rawValue,
            liveRank: configuration.liveRank,
            alertToken: notifications == nil ? nil : alertToken,
            notifications: notifications?.preferences,
            // Only people on the board: the relay rejects anyone else.
            rivals: (notifications?.rivals ?? []).filter { configuration.competitors.contains($0) && $0 != configuration.selfLogin }
        )
        guard registration != lastRegistered || !installation.isRegistered else { return true }
        do {
            try await api.register(registration, as: installation.credentials)
        } catch {
            LiveRankLog.relay.error("register failed: \(String(describing: error), privacy: .public)")
            return false
        }
        LiveRankLog.relay.info("registered \(registration.competitors.count) people, \(registration.window, privacy: .public), live rank \(registration.liveRank ? "on" : "off", privacy: .public), push-to-start \(registration.pushToStartToken == nil ? "none" : "yes", privacy: .public), notifications \(registration.notifications == nil ? "off" : registration.alertToken == nil ? "waiting for a token" : "on", privacy: .public)")
        lastRegistered = registration
        deliversNotifications = registration.notifications != nil && registration.alertToken != nil
        if !installation.isRegistered {
            installation.isRegistered = true
            installations.save(installation)
        }
        return true
    }

    private func unregisterIfNeeded() async {
        guard var installation = installations.load(), installation.isRegistered else { return }
        do {
            try await api.unregister(installation.credentials)
        } catch {
            LiveRankLog.relay.error("unregister failed: \(String(describing: error), privacy: .public)")
            return
        }
        LiveRankLog.relay.info("unregistered")
        installation.isRegistered = false
        installations.save(installation)
        lastRegistered = nil
        deliversNotifications = false
        reportedActivities.removeAll()
    }
}

extension Data {
    /// APNs tokens as the relay expects them: lowercase hex.
    var lowercaseHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
