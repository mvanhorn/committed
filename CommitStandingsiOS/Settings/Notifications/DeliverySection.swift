import SwiftUI

/// Delivery (#135): **Right away**, or **Passes now, the rest at 9 PM** (the default). The second
/// is the evening summary: the relay holds close calls, records and the streak reminder, and sends
/// one "Your day so far" at 9 PM, or when quiet hours start if that's earlier
/// (`NotificationPreferences.summaryTime`, the relay's rule). Passes and results never wait.
///
/// Delivery isn't a kind of notification, so choosing it turns nothing on: until a kind is on
/// (`AppModel.relayNotificationsOn`) the choice is disabled, since the first switch on brings the
/// defaults, this one included.
struct DeliverySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let choices = model.notificationChoices
        Section {
            Picker("Delivery", selection: model.notificationChoice(\.delivery)) {
                Text("Right away").tag(NotificationPreferences.Delivery.immediate)
                Text("Passes now, the rest at 9 PM").tag(NotificationPreferences.Delivery.summary)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(!model.relayNotificationsOn)
        } header: {
            FolioHeader("Delivery")
        } footer: {
            Text(Self.footer(choices, on: model.relayNotificationsOn))
        }
    }

    static func footer(_ choices: NotificationPreferences, on: Bool) -> String {
        guard on else { return "Turn on a notification to choose how they arrive." }
        guard choices.delivery == .summary else { return "Each notification arrives as it happens." }
        let summaryTime = choices.summaryTime
        let when = summaryTime == "21:00"
            ? "at 9 PM"
            : "at \(Self.time(summaryTime)), when quiet hours start"
        return "Passes and results arrive as they happen. Close calls, records and the streak reminder come together in one summary \(when)."
    }

    /// "20:30" as the iPhone shows times ("8:30 PM").
    private static func time(_ time: String) -> String {
        NotificationPreferences.QuietHours.date(for: time)?.formatted(date: .omitted, time: .shortened) ?? time
    }
}
