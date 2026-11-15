import SwiftUI

/// Shown once before Live rank first turns on with the Committed relay: what the relay receives
/// (public usernames) and what it never receives (the GitHub token), and that it also sends relay
/// notifications (`RelayConsent.currentVersion`). "Not Now" leaves Live rank off.
struct LiveRankDisclosureView: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TrophyMark(size: 40)
                        .shadow(color: Color.lime.opacity(0.45), radius: 12)
                    Text("Keep Live rank on all day.")
                        .font(CommittedType.display(34, relativeTo: .largeTitle))
                        .displayTracking(34)
                        .accessibilityAddTraits(.isHeader)
                    Text("The Committed relay checks public contribution graphs every 5 minutes and updates Live rank, even with Committed closed.")
                        .foregroundStyle(Color.soft)
                    VStack(alignment: .leading, spacing: 0) {
                        point("It receives your GitHub username and the usernames on your board. These are public.",
                              systemImage: "person.2")
                        Divider().overlay(Color.hairline)
                        point("It never receives your GitHub token. That's sent only to GitHub.",
                              systemImage: "lock")
                        Divider().overlay(Color.hairline)
                        point("It also gets your Live rank Window, time zone, and the tokens that update Live rank on this iPhone.",
                              systemImage: "clock")
                        Divider().overlay(Color.hairline)
                        point(Text("**Notifications:** the relay checks the same public counts and tells you when someone passes you, even with Committed closed."),
                              systemImage: "bell")
                    }
                    .padding(.horizontal, 16)
                    .tileCard()
                    Text("Turning off Live rank and Leaderboard Notifications, or disconnecting GitHub, deletes this iPhone's registration from the relay.")
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
                        .frame(height: 260)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        choose { await model.acceptLiveRankDisclosure() }
                    } label: {
                        Text("Turn On Live Rank")
                    }
                    .buttonStyle(LimeButtonStyle())
                    Button("Not Now") {
                        choose { await model.declineLiveRankDisclosure() }
                    }
                    .buttonStyle(TileButtonStyle())
                }
                .disabled(isWorking)
                .padding()
                // Ink with a hairline, and the scroll content fading into it above, instead of
                // the system's gray bar cutting the card mid-sentence.
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
            .navigationTitle("Live rank")
            .navigationBarTitleDisplayMode(.inline)
        }
        // A choice is required: dismissing by swipe would leave "never chosen" and ask again.
        .interactiveDismissDisabled()
    }

    private func point(_ text: String, systemImage: String) -> some View {
        point(Text(text), systemImage: systemImage)
    }

    private func point(_ text: Text, systemImage: String) -> some View {
        RelayPoint(text: text, systemImage: systemImage, iconWidth: iconWidth)
    }

    private func choose(_ action: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}

/// One line of what the Committed relay receives or does, with its lime icon.
struct RelayPoint: View {
    let text: Text
    let systemImage: String
    let iconWidth: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.lime)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            text
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Where the relay sheets open: the top, or the end for fixture captures (`-ScreenshotSheetEnd`).
@MainActor
var relaySheetScrollAnchor: UnitPoint {
    #if DEBUG
    if ScreenshotFixture.sheetScrolledToEnd { return .bottom }
    #endif
    return .top
}
