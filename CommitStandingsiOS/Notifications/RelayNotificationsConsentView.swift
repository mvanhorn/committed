import SwiftUI

/// "Get notifications with Committed closed?": asked once, the first time relay notifications would
/// turn on for someone who hasn't agreed to them, such as after accepting the earlier relay sheet
/// (Live rank only), or turning on Leaderboard Notifications without ever seeing the relay sheet.
/// It says what the relay receives for them. **Turn On** starts relay notifications and leaves
/// Live rank as it is; **Not Now** keeps the in-app notifications.
struct RelayNotificationsConsentView: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.lime)
                        .shadow(color: Color.lime.opacity(0.45), radius: 12)
                        .accessibilityHidden(true)
                    Text("Get notifications with Committed closed?")
                        .font(CommittedType.display(30, relativeTo: .largeTitle))
                        .displayTracking(30)
                        .accessibilityAddTraits(.isHeader)
                    Text("The Committed relay checks public contribution graphs every 5 minutes and tells you when someone passes you, or you pass them, even with Committed closed.")
                        .foregroundStyle(Color.soft)
                    VStack(alignment: .leading, spacing: 0) {
                        RelayPoint(text: Text("It receives your GitHub username and the usernames on your board. These are public."),
                                   systemImage: "person.2", iconWidth: iconWidth)
                        Divider().overlay(Color.hairline)
                        RelayPoint(text: Text("It never receives your GitHub token. That's sent only to GitHub."),
                                   systemImage: "lock", iconWidth: iconWidth)
                        Divider().overlay(Color.hairline)
                        RelayPoint(text: Text("It also gets your time zone, your notification choices, and the token Apple uses to deliver notifications to this iPhone."),
                                   systemImage: "bell", iconWidth: iconWidth)
                    }
                    .padding(.horizontal, 16)
                    .tileCard()
                    Text("Not Now keeps notifications from Committed while it's open. Turning Leaderboard Notifications off or disconnecting GitHub stops relay notifications.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .defaultScrollAnchor(relaySheetScrollAnchor)
            .background {
                ZStack(alignment: .top) {
                    Color.ink
                    AnimatedSquareField(light: UnitPoint(x: 0.85, y: 0), reach: 0.6, cell: 18, tone: .disclosure)
                        .frame(height: 220)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button("Turn On") {
                        choose { await model.acceptRelayNotifications() }
                    }
                    .buttonStyle(LimeButtonStyle())
                    Button("Not Now") {
                        choose { await model.declineRelayNotifications() }
                    }
                    .buttonStyle(TileButtonStyle())
                }
                .disabled(isWorking)
                .padding()
                .background {
                    Color.ink
                        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
                        .overlay(alignment: .top) {
                            LinearGradient(colors: [.clear, .ink], startPoint: .top, endPoint: .bottom)
                                .frame(height: 28)
                                .offset(y: -28)
                                .allowsHitTesting(false)
                        }
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
        }
        // A choice is required: a swipe would leave it unasked, and it would ask again.
        .interactiveDismissDisabled()
    }

    private func choose(_ action: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}
