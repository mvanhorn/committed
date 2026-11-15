import SwiftUI

/// About your rivals: **Passes** (a notification when someone passes you or you pass them), who
/// they cover (**Everyone** or **Pinned rivals**), **Close calls** (a few contributions behind a
/// pinned rival, or the person just above you), and the **Window** both are judged on.
///
/// The Passes switch is the one Leaderboard Notifications was. Turning it on takes the step every
/// switch takes (the iOS permission prompt, switching back off if it's denied, then relay consent in
/// a relay build); off, with the relay's choices, it sends `passes: "off"` and leaves the other
/// kinds on. Without the relay choices (no relay, the Sample board, or Not Now) it's alone.
struct AboutYourRivalsSection: View {
    @Environment(AppModel.self) private var model
    /// Shows the switch on while iOS's prompt is up, as it did before.
    @State private var requestingAuthorization = false

    var body: some View {
        let showsChoices = model.showsRelayNotificationChoices
        let passesOn = model.passesOn || requestingAuthorization
        Section {
            Toggle("Passes", isOn: Binding(
                get: { passesOn },
                set: { enabled in
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
            .disabled(requestingAuthorization || model.isTurningOnNotifications)
            if showsChoices {
                if model.passesOn {
                    Picker("People", selection: model.notificationChoice(\.passes)) {
                        Text("Everyone").tag(NotificationPreferences.Passes.everyone)
                        Text("Pinned rivals").tag(NotificationPreferences.Passes.rivals)
                    }
                }
                Toggle(isOn: model.notificationChoice(\.closeCalls)) {
                    Text("Close calls")
                    Text(closeCallsDetail)
                }
                Picker("Window", selection: model.notificationChoice(\.window)) {
                    ForEach(ContributionWindow.allCases) { window in
                        Text(window.shortTitle).tag(window)
                    }
                }
            }
        } header: {
            FolioHeader("About your rivals")
        } footer: {
            Text(footer(showsChoices: showsChoices, passesOn: passesOn))
        }
    }

    /// Close calls (#132) are about your pinned rivals, or the person just above you when none are.
    private var closeCallsDetail: String {
        let rivals = model.store.pinnedRivals.map(\.username)
        guard !rivals.isEmpty else { return "When you're a few contributions behind the person just above you." }
        return "When you're a few contributions behind \(rivals.formatted(.list(type: .or)))."
    }

    private func footer(showsChoices: Bool, passesOn: Bool) -> String {
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
