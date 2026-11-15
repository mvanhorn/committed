import UserNotifications

/// iOS hides a notification that arrives while its app is open unless the app says otherwise.
/// Pass notifications show as a banner even while Committed is open, whether the app posted
/// them or the Committed relay sent them. Tapping one opens Committed where it points: a pass opens
/// that person's view, and a relay pass's actions (#137) open it with the Challenge share (Share
/// your race) or open the Board (Open Board). The Mac app doesn't need this.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundNotificationPresenter()

    /// The notification center keeps its delegate weakly; `shared` keeps this one alive. Installed
    /// at launch, with the categories, so a tap or action that launched the app is delivered too.
    @MainActor
    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        center.setNotificationCategories(categories)
    }

    /// The relay's pass notifications carry `PASS`: Share your race and Open Board, each opening
    /// Committed (the in-app crossing notifications have no category, so no actions).
    static var categories: Set<UNNotificationCategory> {
        let shareRace = UNNotificationAction(
            identifier: DeepLink.shareRaceAction, title: "Share your race", options: .foreground)
        let openBoard = UNNotificationAction(
            identifier: DeepLink.openBoardAction, title: "Open Board", options: .foreground)
        return [UNNotificationCategory(
            identifier: DeepLink.passCategory, actions: [shareRace, openBoard], intentIdentifiers: [])]
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
        let userInfo = response.notification.request.content.userInfo
        guard let link = DeepLink(notification: userInfo, action: response.actionIdentifier) else { return }
        await MainActor.run { Self.receive(link) }
    }

    /// Opens `link` now, or once the app attaches `open` (a cold launch). Debug screenshot
    /// launches feed a pass response through here too (`ScreenshotFixture.notificationResponse`).
    @MainActor
    static func receive(_ link: DeepLink) {
        if let open {
            open(link)
        } else {
            pendingLink = link
        }
    }
}
