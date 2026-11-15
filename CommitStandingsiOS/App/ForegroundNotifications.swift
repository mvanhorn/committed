import UserNotifications

/// iOS hides a notification that arrives while its app is open unless the app says otherwise.
/// Pass notifications show as a banner even while Committed is open, whether the app posted
/// them or the Committed relay sent them. Tapping one opens Committed where it points: a pass opens
/// that person's view. The Mac app doesn't need this.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundNotificationPresenter()

    /// The notification center keeps its delegate weakly; `shared` keeps this one alive. Installed
    /// at launch, so a tap that launched the app is delivered too.
    @MainActor
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    /// Where taps go. A tap that arrives before the app attaches it (a cold launch) waits for it.
    @MainActor
    static var open: ((DeepLink) -> Void)? {
        didSet {
            if let open, let pending = pendingLink {
                pendingLink = nil
                open(pending)
            }
        }
    }

    @MainActor private static var pendingLink: DeepLink?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let link = DeepLink(notification: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            if let open = Self.open {
                open(link)
            } else {
                Self.pendingLink = link
            }
        }
    }
}
