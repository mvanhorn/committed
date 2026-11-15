import SwiftUI

/// Settings ▸ Notifications: one row that opens the Notifications screen (#130), in place of the
/// Leaderboard Notifications switch.
struct NotificationsSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(NotificationService.enabledDefaultsKey) private var passesOn = false

    var body: some View {
        Section {
            NavigationLink(value: SettingsRoute.notifications) {
                LabeledContent("Notifications", value: passesOn ? "On" : "Off")
            }
        } header: {
            FolioHeader("Notifications")
        } footer: {
            Text(model.relayNotificationsOn
                 ? "Passes, the Window they're judged on, and quiet hours. The Committed relay sends them, even with Committed closed."
                 : "Get notified when someone passes you or you pass them.")
        }
    }
}

/// Screens pushed from Settings.
enum SettingsRoute: Hashable {
    case notifications
}
