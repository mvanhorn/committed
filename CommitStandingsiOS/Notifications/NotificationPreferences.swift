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

/// The "any switch" gate (#130): the kinds of notification, and the choices on first opt-in.
extension NotificationPreferences {
    /// Each kind's switch besides Passes.
    static var kindSwitches: [WritableKeyPath<NotificationPreferences, Bool>] {
        [\.closeCalls, \.results, \.records, \.streakReminder]
    }

    /// At least one kind of notification is on: relay notifications are on only then.
    var anyKindOn: Bool {
        passes != .off || Self.kindSwitches.contains { self[keyPath: $0] }
    }

    /// Every kind off (Passes too), as the switches read before any is turned on.
    mutating func turnEveryKindOff() {
        passes = .off
        for kind in Self.kindSwitches { self[keyPath: kind] = false }
    }

    /// The spec defaults that turning on the first switch brings (passes for everyone, results and
    /// records on, close calls and the streak reminder off, delivery summary, quiet hours 10 PM to
    /// 8 AM), keeping the Window already chosen, which isn't a kind of notification.
    var turnedOnDefaults: NotificationPreferences {
        var defaults = NotificationPreferences()
        defaults.window = window
        return defaults
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

/// Quiet hours' times as the relay reads them: 24-hour "HH:MM", built from numbers rather than a
/// date formatter, so a 12-hour clock or another locale on the iPhone can't change them.
extension NotificationPreferences.QuietHours {
    struct HourAndMinute: Equatable, Sendable {
        var hour: Int
        var minute: Int
    }

    static func time(hour: Int, minute: Int) -> String {
        let pad = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return "\(pad(hour)):\(pad(minute))"
    }

    /// Nil for anything that isn't "HH:MM".
    static func hourAndMinute(_ time: String) -> HourAndMinute? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return HourAndMinute(hour: hour, minute: minute)
    }

    /// A time picker's date, as its local time on `calendar`.
    static func time(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return time(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// A date at `time` today on `calendar`, for a time picker.
    static func date(for time: String, calendar: Calendar = .current, now: Date = Date()) -> Date? {
        guard let value = hourAndMinute(time) else { return nil }
        return calendar.date(bySettingHour: value.hour, minute: value.minute, second: 0, of: now)
    }
}
