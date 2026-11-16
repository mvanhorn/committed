import SwiftUI

/// Results (#131): **Daily and weekly results**, on by default. Each morning, when quiet hours end
/// (or at 8 AM without them), the relay sends yesterday's Today standings, and on Mondays last
/// week's final. Tapping either opens the Board.
struct ResultsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle("Daily and weekly results", isOn: model.notificationChoice(\.results))
        } header: {
            FolioHeader("Results")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let choices = model.notificationChoices
        guard choices.results else { return "Turn on for a morning note of how yesterday went." }
        // The relay sends them when quiet hours end; off (or no length at all), at 8 AM.
        let when = choices.quietHours.flatMap { $0.start == $0.end ? nil : NotificationPreferences.QuietHours.date(for: $0.end) }
            .map { $0.formatted(date: .omitted, time: .shortened) } ?? "8 AM"
        return "Yesterday’s finish each morning at \(when), and last week’s final on Mondays."
    }
}
