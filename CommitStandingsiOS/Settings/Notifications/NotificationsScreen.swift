import SwiftUI

/// Settings ▸ Notifications (#130): every notification choice in one place.
///
/// One section view per group, in the spec's order (About your rivals, Results #131, About you
/// #133/#134, Delivery #135, Quiet hours); Close calls (#132) is a row in `AboutYourRivalsSection`.
/// Each row binds with `model.notificationChoice(_:)`, which saves the choice for this account and
/// updates the relay registration right away.
///
/// The gate (`AppModel.relayNotificationsOn`): relay notifications are on with relay consent, iOS
/// permission, and any kind on; Passes off sends `passes: "off"`, and only every kind off sends
/// `notifications: null`. A `Bool` choice turned on through `notificationChoice` takes the shared
/// step (`AppModel.setNotificationChoice`): iOS's permission prompt the first time, then relay
/// consent, then the spec defaults with that switch on. Until then every switch reads off. New
/// switches need nothing more than the binding.
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
                    ResultsSection()
                    AboutYouSection()
                    DeliverySection()
                    QuietHoursSection()
                }
            }
            .listRowBackground(Color.tile)
            .listRowSeparatorTint(.hairline)
        }
        .listSectionSpacing(28)
        #if DEBUG
        .defaultScrollAnchor(ScreenshotFixture.notificationsScrolledToEnd ? .bottom : nil)
        #endif
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
                Task { @MainActor in await self.setNotificationChoice(keyPath, value) }
            }
        )
    }
}
