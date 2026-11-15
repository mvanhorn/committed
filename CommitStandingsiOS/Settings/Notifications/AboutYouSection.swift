import SwiftUI

/// About you: notifications about your own contributions. **Records** (#134) and **Streak
/// reminder** (#133), each saved for this account and sent to the relay through
/// `model.notificationChoice(_:)`.
///
/// The streak reminder comes from the relay at 8 PM, or an hour before quiet hours if that's
/// earlier, when your streak is at least 2 days and you haven't contributed yet today
/// (relay/src/notifications/streakReminder.ts). Off by default.
struct AboutYouSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            // Records (#134) goes here, above Streak reminder.
            Toggle("Streak reminder", isOn: model.notificationChoice(\.streakReminder))
        } header: {
            FolioHeader("About you")
        } footer: {
            Text("**Streak reminder:** at 8 PM, or an hour before quiet hours if that's earlier, when your streak is 2 days or more and you haven't contributed yet today.")
        }
    }
}
