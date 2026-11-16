import SwiftUI
import UIKit

/// The top of the Notifications screen when iOS Settings has notifications off for Committed:
/// what that means, and a link there. Nothing otherwise.
struct NotificationPermissionSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        if model.notificationsDeniedInSettings {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications are off for Committed")
                        .font(.body.weight(.semibold))
                    Text("Turn them on in iOS Settings to hear about passes.")
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                }
                .accessibilityElement(children: .combine)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    OutboundLabel("Open iOS Settings")
                }
            }
        }
    }
}
