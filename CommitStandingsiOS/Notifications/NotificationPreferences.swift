import Foundation

/// What you hear about from the Committed relay's notifications (spec #124), saved on this iPhone
/// per GitHub account, as visibility choices are. Encodes to exactly the relay's `notifications`
/// object: every key, `quietHours` as null when off.
///
/// #126 sends the defaults (passes for everyone, on Today); the Notifications screen (#130) edits
/// the rest.
struct NotificationPreferences: Codable, Equatable, Sendable {
    enum Passes: String, Codable, Sendable {
        case everyone
        case rivals
        case off
    }

    enum Delivery: String, Codable, Sendable {
        /// Everything right away.
        case immediate
        /// Passes now, the rest in one 9 PM summary.
        case summary
    }

    /// Local "HH:MM" times.
    struct QuietHours: Codable, Equatable, Sendable {
        var start: String
        var end: String
    }

    /// The Window passes and close calls are judged on.
    var window: ContributionWindow = .daily
    var passes: Passes = .everyone
    var closeCalls = false
    /// Daily and weekly results.
    var results = true
    var records = true
    var streakReminder = false
    var delivery: Delivery = .summary
    /// Nil = quiet hours off. On by default, 10 PM to 8 AM.
    var quietHours: QuietHours? = QuietHours(start: "22:00", end: "08:00")

    init() {}

    private enum CodingKeys: String, CodingKey {
        case window, passes, closeCalls, results, records, streakReminder, delivery, quietHours
    }

    /// Anything missing (choices saved before a later version added them) takes its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotificationPreferences()
        window = try container.decodeIfPresent(ContributionWindow.self, forKey: .window) ?? defaults.window
        passes = try container.decodeIfPresent(Passes.self, forKey: .passes) ?? defaults.passes
        closeCalls = try container.decodeIfPresent(Bool.self, forKey: .closeCalls) ?? defaults.closeCalls
        results = try container.decodeIfPresent(Bool.self, forKey: .results) ?? defaults.results
        records = try container.decodeIfPresent(Bool.self, forKey: .records) ?? defaults.records
        streakReminder = try container.decodeIfPresent(Bool.self, forKey: .streakReminder) ?? defaults.streakReminder
        delivery = try container.decodeIfPresent(Delivery.self, forKey: .delivery) ?? defaults.delivery
        quietHours = container.contains(.quietHours)
            ? try container.decodeNil(forKey: .quietHours) ? nil : container.decode(QuietHours.self, forKey: .quietHours)
            : defaults.quietHours
    }

    /// Quiet hours off is an explicit null: a missing key means "the default" to the relay.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(window, forKey: .window)
        try container.encode(passes, forKey: .passes)
        try container.encode(closeCalls, forKey: .closeCalls)
        try container.encode(results, forKey: .results)
        try container.encode(records, forKey: .records)
        try container.encode(streakReminder, forKey: .streakReminder)
        try container.encode(delivery, forKey: .delivery)
        try container.encode(quietHours, forKey: .quietHours)
    }
}

/// Notification choices per GitHub account (the board owner's login).
@MainActor
protocol NotificationPreferencesStoring: AnyObject {
    func load(account: String) -> NotificationPreferences
    func save(_ preferences: NotificationPreferences, account: String)
}

final class UserDefaultsNotificationPreferences: NotificationPreferencesStoring {
    private let defaults: UserDefaults
    private let key = "notificationPreferencesByAccount.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var all: [String: NotificationPreferences] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: NotificationPreferences].self, from: $0) } ?? [:]
    }

    func load(account: String) -> NotificationPreferences {
        all[account] ?? NotificationPreferences()
    }

    func save(_ preferences: NotificationPreferences, account: String) {
        var all = all
        all[account] = preferences
        defaults.set(try? JSONEncoder().encode(all), forKey: key)
    }
}

final class InMemoryNotificationPreferences: NotificationPreferencesStoring {
    private var byAccount: [String: NotificationPreferences]

    init(_ byAccount: [String: NotificationPreferences] = [:]) {
        self.byAccount = byAccount
    }

    func load(account: String) -> NotificationPreferences { byAccount[account] ?? NotificationPreferences() }
    func save(_ preferences: NotificationPreferences, account: String) { byAccount[account] = preferences }
}

/// What relay notifications need beyond the board: the choices, and the pinned rivals (#125/#130).
struct RelayNotificationsConfiguration: Equatable, Sendable {
    var preferences: NotificationPreferences
    var rivals: [String] = []
}
