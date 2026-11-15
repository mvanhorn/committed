import SwiftUI

/// About you: notifications about your own numbers. **Records** (#134, on by default) tells you
/// when you set a new best day, best week or longest streak, with the same rules and minimums as
/// the Board's record card. The relay sends them, even with Committed closed; one that lands
/// during quiet hours waits until they end. Tapping one opens your own view.
///
/// **Streak reminder** (#133, off by default), below Records: the relay reminds you at 8 PM, or an
/// hour before quiet hours if that's earlier, when your streak is at least 2 days and you haven't
/// contributed yet today (relay/src/notifications/streakReminder.ts). Its line under the switch
/// says when; tapping it opens your own view.
struct AboutYouSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle("Records", isOn: model.notificationChoice(\.records))
            Toggle(isOn: model.notificationChoice(\.streakReminder)) {
                Text("Streak reminder")
                Text("At 8 PM, or an hour before quiet hours if that's earlier, when your streak is 2 days or more and you haven't contributed yet today.")
            }
        } header: {
            FolioHeader("About you")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let choices = model.notificationChoices
        guard choices.records else { return "Turn on to hear when you set a new best day, best week or longest streak." }
        let when = "When you set a new best day, best week or longest streak."
        return choices.quietHours == nil ? when : "\(when) One set during quiet hours waits until they end."
    }
}
