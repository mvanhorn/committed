import SwiftUI

/// About you: notifications about your own numbers. **Records** (#134, on by default) tells you
/// when you set a new best day, best week or longest streak, with the same rules and minimums as
/// the Board's record card. The relay sends them, even with Committed closed; one that lands
/// during quiet hours waits until they end. Tapping one opens your own view.
///
/// The streak reminder (#133) joins it, below Records.
struct AboutYouSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle("Records", isOn: model.notificationChoice(\.records))
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
