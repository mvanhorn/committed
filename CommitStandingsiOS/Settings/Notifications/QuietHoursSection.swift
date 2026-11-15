import SwiftUI

/// Quiet hours: on by default, 10 PM to 8 AM, with editable start and end times. During them,
/// passes still arrive, but without a sound and without lighting up the screen.
struct QuietHoursSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let quietHours = model.notificationChoices.quietHours
        Section {
            Toggle("Quiet hours", isOn: Binding(
                get: { quietHours != nil },
                set: { on in Task { await model.setQuietHoursOn(on) } }
            ))
            if let quietHours {
                DatePicker("Start", selection: time(quietHours.start, \.start), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: time(quietHours.end, \.end), displayedComponents: .hourAndMinute)
            }
        } header: {
            FolioHeader("Quiet hours")
        } footer: {
            Text(quietHours == nil
                 ? "Notifications can make a sound at any hour."
                 : "Passes still arrive, without a sound or lighting up the screen.")
        }
    }

    /// One end of quiet hours as a time picker's date; a change is saved as 24-hour "HH:MM".
    private func time(
        _ current: String,
        _ end: WritableKeyPath<NotificationPreferences.QuietHours, String>
    ) -> Binding<Date> {
        Binding(
            get: { NotificationPreferences.QuietHours.date(for: current) ?? Date() },
            set: { date in
                let time = NotificationPreferences.QuietHours.time(from: date)
                guard time != current else { return }
                Task { await model.updateNotificationChoices { $0.quietHours?[keyPath: end] = time } }
            }
        )
    }
}
