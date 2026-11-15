import SwiftUI

/// About your rivals: **Passes** (a notification when someone passes you or you pass them), who
/// they cover (**Everyone** or **Pinned rivals**), and the **Window** they're judged on.
///
/// The Passes switch is the one Leaderboard Notifications was: turning it on shows the iOS
/// permission prompt (and switches back off if it's denied), and in a relay build asks about relay
/// notifications. Without the relay choices (no relay, the Sample board, or Not Now) it's alone.
struct AboutYourRivalsSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(NotificationService.enabledDefaultsKey) private var passesOn = false
    @State private var requestingAuthorization = false

    var body: some View {
        let showsChoices = model.showsRelayNotificationChoices
        Section {
            Toggle("Passes", isOn: Binding(
                get: { passesOn },
                set: { enabled in
                    passesOn = enabled
                    guard enabled else {
                        Task { await model.leaderboardNotificationsChanged(false) }
                        return
                    }
                    requestingAuthorization = true
                    Task {
                        await model.leaderboardNotificationsChanged(true)
                        requestingAuthorization = false
                        await model.checkNotificationPermission()
                    }
                }
            ))
            .disabled(requestingAuthorization)
            if showsChoices {
                if passesOn {
                    Picker("People", selection: model.notificationChoice(\.passes)) {
                        Text("Everyone").tag(NotificationPreferences.Passes.everyone)
                        Text("Pinned rivals").tag(NotificationPreferences.Passes.rivals)
                    }
                }
                // Close calls (#132) go here, between People and Window.
                Picker("Window", selection: model.notificationChoice(\.window)) {
                    ForEach(ContributionWindow.allCases) { window in
                        Text(window.shortTitle).tag(window)
                    }
                }
            }
        } header: {
            FolioHeader("About your rivals")
        } footer: {
            Text(footer(showsChoices: showsChoices))
        }
    }

    private func footer(showsChoices: Bool) -> String {
        guard passesOn else { return "Turn on to hear when someone passes you or you pass them." }
        guard showsChoices else { return "When someone passes you or you pass them, while Committed is open." }
        let window = model.notificationChoices.window.shortTitle
        // Before relay notifications are agreed to, the app's own ones are all there is.
        let closed = model.relayNotificationsOn ? ", even with Committed closed" : ""
        guard model.notificationChoices.passes == .rivals else {
            return "When anyone on your board passes you or you pass them, judged on \(window)\(closed)."
        }
        let rivals = model.store.pinnedRivals.map(\.username)
        guard !rivals.isEmpty else {
            return "Pin up to \(StandingsStore.maxPinnedRivals) rivals with Rival in their view. Until then, no passes are sent."
        }
        return "When \(rivals.formatted(.list(type: .or))) passes you or you pass them, judged on \(window)\(closed)."
    }
}
