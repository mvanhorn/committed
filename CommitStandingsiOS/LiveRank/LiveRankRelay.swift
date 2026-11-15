import Foundation

/// What the Committed relay needs to keep Live rank current with the app closed, and to judge
/// relay notifications: who you are, who's visible on your board (in board order, for tie-breaks),
/// Live rank's Window, and whether Live rank is on.
struct LiveRankConfiguration: Equatable, Sendable {
    var selfLogin: String
    var competitors: [String]
    var window: ContributionWindow
    /// Off, the board still goes to the relay while relay notifications are on.
    var liveRank: Bool = true
}

/// The seam for the Committed relay (#45, #124). `LiveRankController` calls it whenever the board
/// changes (with `liveRank` saying whether Live rank is on), and with nil when GitHub disconnects.
/// `AppModel` tells it the relay notification choices. The registration exists while Live rank or
/// relay notifications is on. Calls are de-duplicated, so a refresh that changes nothing sends
/// nothing.
@MainActor
protocol LiveRankRegistrar: AnyObject {
    /// `.token` once a relay is configured, so new activities get a push token.
    var pushUpdates: LiveRankPushUpdates { get }
    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async
    /// Relay notifications turned on (with these choices) or off (nil).
    func relayNotificationsDidChange(_ configuration: RelayNotificationsConfiguration?) async
    /// The relay holds a registration with notifications and an alert token: it delivers passes,
    /// so the app doesn't post its own.
    var deliversNotifications: Bool { get }
    /// Try again whatever an earlier call couldn't send (offline, relay down). The app calls it on
    /// becoming active and in background refresh.
    func retryPendingWork() async
}

extension LiveRankRegistrar {
    func retryPendingWork() async {}
    func relayNotificationsDidChange(_ configuration: RelayNotificationsConfiguration?) async {}
    var deliversNotifications: Bool { false }
}

/// Phase 1: no relay. Live rank updates only when the app refreshes.
@MainActor
final class NoLiveRankRelay: LiveRankRegistrar {
    var pushUpdates: LiveRankPushUpdates { .none }
    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async {}
}
