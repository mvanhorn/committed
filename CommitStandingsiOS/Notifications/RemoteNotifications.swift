import Foundation
import os
import UIKit

/// Asks iOS for this iPhone's ordinary APNs device token, which the Committed relay sends relay
/// notifications to. A seam over `UIApplication.registerForRemoteNotifications`, so nothing touches
/// UIKit in a unit-test host. The token arrives in `CommittedAppDelegate`.
@MainActor
protocol RemoteNotificationRegistering: AnyObject {
    func register()
}

/// Tests, previews, and builds without a relay: never asks.
@MainActor
final class NoRemoteNotifications: RemoteNotificationRegistering {
    private(set) var requests = 0
    func register() { requests += 1 }
}

@MainActor
final class UIApplicationRemoteNotifications: RemoteNotificationRegistering {
    /// Apple recommends asking on every launch: the token can change.
    func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// Receives the APNs device token for alert notifications.
@MainActor
protocol AlertTokenReceiving: AnyObject {
    func alertTokenDidChange(_ token: Data) async
}

/// The app delegate, only for what SwiftUI's `App` has no hook for: the remote-notification token.
final class CommittedAppDelegate: NSObject, UIApplicationDelegate {
    /// The relay registrar, when the build has a relay.
    @MainActor static weak var alertTokens: (any AlertTokenReceiving)?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        LiveRankLog.relay.info("alert token \(deviceToken.lowercaseHex.prefix(8), privacy: .public)…")
        Task { @MainActor in await Self.alertTokens?.alertTokenDidChange(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Relay notifications wait; local crossing notifications keep going until a token arrives.
        LiveRankLog.relay.error("no alert token: \(String(describing: error), privacy: .public)")
    }
}
