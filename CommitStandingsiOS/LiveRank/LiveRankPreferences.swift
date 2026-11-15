import Foundation

/// Live rank's settings on this iPhone.
struct LiveRankPreferences: Codable, Equatable, Sendable {
    /// nil until the person has chosen, which phase 1 treats as on. With a relay, Live rank stays
    /// off until the disclosure is accepted.
    var isEnabled: Bool?
    var window: ContributionWindow = .daily
    /// The person accepted the Committed relay disclosure (what the relay receives). Asked once,
    /// before Live rank first turns on with a relay.
    var relayDisclosureAccepted = false
    /// Which relay sheet was accepted: 0 none, 1 the earlier sheet (Live rank only, 1.0.x),
    /// `RelayConsent.currentVersion` the sheet that also covers relay notifications.
    var relayDisclosureVersion = 0
    /// Relay notifications: nil until asked, true after **Turn On** (or accepting the current relay
    /// sheet), false after **Not Now**, which keeps the in-app notifications.
    var relayNotifications: Bool?

    init(
        isEnabled: Bool? = nil, window: ContributionWindow = .daily, relayDisclosureAccepted: Bool = false,
        relayDisclosureVersion: Int? = nil, relayNotifications: Bool? = nil
    ) {
        self.isEnabled = isEnabled
        self.window = window
        self.relayDisclosureAccepted = relayDisclosureAccepted
        self.relayDisclosureVersion = relayDisclosureVersion ?? (relayDisclosureAccepted ? 1 : 0)
        self.relayNotifications = relayNotifications
    }

    // Settings saved before the relay existed have no `relayDisclosureAccepted`; those from 1.0.x
    // have no version, so an accepted sheet was the earlier one.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        window = try container.decodeIfPresent(ContributionWindow.self, forKey: .window) ?? .daily
        relayDisclosureAccepted = try container.decodeIfPresent(Bool.self, forKey: .relayDisclosureAccepted) ?? false
        relayDisclosureVersion = try container.decodeIfPresent(Int.self, forKey: .relayDisclosureVersion)
            ?? (relayDisclosureAccepted ? 1 : 0)
        relayNotifications = try container.decodeIfPresent(Bool.self, forKey: .relayNotifications)
    }
}

enum RelayConsent {
    /// The relay sheet with the notifications line (spec #124).
    static let currentVersion = 2
}

protocol LiveRankPreferenceStoring: AnyObject {
    func load() -> LiveRankPreferences
    func save(_ preferences: LiveRankPreferences)
}

final class UserDefaultsLiveRankPreferences: LiveRankPreferenceStoring {
    private let defaults: UserDefaults
    private let key = "liveRank.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LiveRankPreferences {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LiveRankPreferences.self, from: $0) }
            ?? LiveRankPreferences()
    }

    func save(_ preferences: LiveRankPreferences) {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: key)
    }
}

final class InMemoryLiveRankPreferences: LiveRankPreferenceStoring {
    private var preferences: LiveRankPreferences

    init(_ preferences: LiveRankPreferences = LiveRankPreferences()) {
        self.preferences = preferences
    }

    func load() -> LiveRankPreferences { preferences }
    func save(_ preferences: LiveRankPreferences) { self.preferences = preferences }
}
