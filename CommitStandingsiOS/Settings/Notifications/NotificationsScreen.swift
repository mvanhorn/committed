import SwiftUI

/// Settings ▸ Notifications (#130): every notification choice in one place.
///
/// One section view per group, in the spec's order. Later tickets each add their own section view
/// at the marked place (Results #131, About you #133/#134, Delivery #135), or one row in
/// `AboutYourRivalsSection` (Close calls #132), and bind it with `model.notificationChoice(_:)`,
/// which saves the choice for this account and updates the relay registration right away.
///
/// Not settled yet, and needed before those switches mean anything on their own: relay
/// notifications are on only while **Passes** is (`AppModel.relayNotificationsOn` reads the Passes
/// switch), and only Passes asks for iOS permission and relay consent
/// (`leaderboardNotificationsChanged`). With Passes off, a choice is saved but the relay hears
/// `notifications: null`. A kind that should work with Passes off needs that gate widened (sending
/// `passes: "off"` instead) and one shared "a switch turned on" step for permission and consent.
///
/// In a build without the relay, on the Sample board, and after **Not Now**, only Passes shows,
/// working as it always has: in the app, while it's open (`AppModel.showsRelayNotificationChoices`).
struct NotificationsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Group {
                NotificationPermissionSection()
                AboutYourRivalsSection()
                if model.showsRelayNotificationChoices {
                    // Results (#131), About you (#133, #134) and Delivery (#135) go here, in that order.
                    QuietHoursSection()
                }
            }
            .listRowBackground(Color.tile)
            .listRowSeparatorTint(.hairline)
        }
        .listSectionSpacing(28)
        .inkScreen()
        .readableContentWidth()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.checkNotificationPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.checkNotificationPermission() } }
        }
    }
}

extension AppModel {
    /// A binding to one notification choice for a row on the Notifications screen: reads this
    /// account's choices, and saves a change and sends it to the relay right away.
    func notificationChoice<Value: Sendable>(_ keyPath: WritableKeyPath<NotificationPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { self.notificationChoices[keyPath: keyPath] },
            set: { value in
                Task { @MainActor in await self.updateNotificationChoices { $0[keyPath: keyPath] = value } }
            }
        )
    }
}
