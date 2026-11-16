import SwiftUI

/// About you: notifications about your own numbers. **Records** (#134, on by default) tells you
/// when you set a new best day, best week or longest streak, with the same rules and minimums as
/// the Board's record card. **Streak reminder** (#133, off by default) reminds you when your streak
/// is at least 2 days and you haven't contributed yet today (relay/src/notifications/
/// streakReminder.ts). The relay sends both, even with Committed closed; tapping one opens your own
/// view.
///
/// Each switch's line says when it arrives, which depends on Delivery: in the evening summary
/// (`NotificationPreferences.summaryTime`, as the Delivery footer says), or right away. Each line
/// sits under its own switch and the section has no footer, so nothing reads as describing the
/// switch above it.
struct AboutYouSection: View {
    @Environment(AppModel.self) private var model

    static let id = "about-you"

    var body: some View {
        let choices = model.notificationChoices
        Section {
            Toggle(isOn: model.notificationChoice(\.records)) {
                Text("Records")
                Text(Self.recordsDetail(choices))
            }
            Toggle(isOn: model.notificationChoice(\.streakReminder)) {
                Text("Streak reminder")
                Text(Self.streakReminderDetail(choices))
            }
        } header: {
            FolioHeader("About you")
        }
    }

    /// Records' line: what sets one off, and when it arrives.
    static func recordsDetail(_ choices: NotificationPreferences) -> String {
        let what = "When you set a new best day, best week or longest streak"
        if choices.delivery == .summary { return "\(what), in the summary at \(DeliverySection.summaryClock(choices))." }
        return choices.quietHours == nil ? "\(what)." : "\(what). One set during quiet hours comes when they end."
    }

    /// Streak reminder's line: when it arrives, and when it's due at all.
    static func streakReminderDetail(_ choices: NotificationPreferences) -> String {
        let condition = "when your streak is 2 days or more and you haven't contributed yet today."
        if choices.delivery == .summary { return "In the summary at \(DeliverySection.summaryClock(choices)), \(condition)" }
        return "At 8 PM, or an hour before quiet hours if that's earlier, \(condition)"
    }
}
