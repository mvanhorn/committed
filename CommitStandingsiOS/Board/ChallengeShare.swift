import SwiftUI
import UIKit

// Challenge, under Your race in someone else's person view: the share sheet with a 9:16 story
// image of your 30-day race and a message with the link to the challenge page. Drawn the way Share
// board draws its images (`BoardShare.swift`): a fixed-size SwiftUI card on the board's squares,
// rendered with `ImageRenderer` at 2x.

/// The story image: the squares, "A challenge · 30 days", the headline in your voice, a card with
/// both of you and your totals, "Think you can catch me?", and Committed with the link.
struct ChallengeCard: View {
    let challenge: Challenge
    /// Saved avatars for the card: a renderer can't wait for network images.
    let savedAvatars: AvatarCache?

    static let canvas = BoardShareFormat.story.canvas

    var body: some View {
        ZStack {
            Color.ink
            BoardShareSquareField(brightness: 1)
            // The squares fade out behind the headline and under the footer, so both read.
            LinearGradient(colors: [Color.ink.opacity(0.94), Color.ink.opacity(0.8), Color.ink.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 470)
                .frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [Color.ink.opacity(0), Color.ink.opacity(0.85), Color.ink.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 0) {
                Text(Challenge.eyebrow)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.lime)
                    .padding(.top, 104)
                ChallengeHeadline(challenge: challenge)
                    .padding(.top, 22)
                Spacer(minLength: 28)
                ChallengeRaceCard(challenge: challenge)
                Text(Challenge.prompt)
                    .font(CommittedType.display(34, relativeTo: .title))
                    .displayTracking(34)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 34)
                Spacer(minLength: 28)
                ChallengeFooter(link: challenge.linkText)
                    .padding(.bottom, 72)
            }
            .padding(.horizontal, 32)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .clipped()
        // An image looks the same whatever the phone's settings, as Share board's do.
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.avatarFallbackStyle, .committed)
        .environment(\.loadsGitHubAvatars, false)
        .environment(\.savedAvatars, savedAvatars)
    }
}

/// The headline, with the gap in lime: "I'm 12 ahead of you, ezra-q."
private struct ChallengeHeadline: View {
    let challenge: Challenge

    var body: some View {
        styled
            .font(CommittedType.display(50, relativeTo: .largeTitle))
            .displayTracking(50)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(-2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
    }

    private var styled: Text {
        let headline = challenge.headline
        guard challenge.variant != .level, let range = headline.range(of: challenge.gapText) else {
            return Text(headline)
        }
        return Text("\(String(headline[..<range.lowerBound]))\(Text(challenge.gapText).foregroundStyle(Color.lime))\(String(headline[range.upperBound...]))")
    }
}

/// You and them: avatar, login and 30-day total, each with a bar against the bigger total. The
/// leader's total and bar are lime; level, both are.
private struct ChallengeRaceCard: View {
    let challenge: Challenge

    var body: some View {
        let top = max(challenge.yourTotal, challenge.theirTotal, 1)
        VStack(spacing: 22) {
            row(login: challenge.you, total: challenge.yourTotal, top: top,
                leads: challenge.variant != .behind)
            row(login: challenge.friend, total: challenge.theirTotal, top: top,
                leads: challenge.variant != .ahead)
        }
        .padding(26)
        .background(Color.ink, in: .rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    private func row(login: String, total: Int, top: Int, leads: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                AvatarView(username: login, size: 56)
                Text(login)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 12)
                Text(total.formatted(.number.locale(challenge.locale)))
                    .font(CommittedType.display(44, relativeTo: .largeTitle))
                    .displayTracking(44)
                    .foregroundStyle(leads ? Color.lime : .white)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(leads ? Color.lime : Color.soft.opacity(0.55))
                            .frame(width: max(10, proxy.size.width * CGFloat(total) / CGFloat(top)))
                    }
            }
            .frame(height: 10)
        }
    }
}

/// Committed, then the link: on its own line, so the longest logins still fit.
private struct ChallengeFooter: View {
    let link: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TrophyMark(size: 18)
                Text("Committed")
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.soft)
            }
            Text(link)
                .foregroundStyle(Color.muted)
                .minimumScaleFactor(0.5)
        }
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .lineLimit(1)
    }
}

// MARK: - Rendering

@MainActor
enum ChallengeShareRenderer {
    /// The story at 1080 × 1920.
    static func image(_ challenge: Challenge, savedAvatars: AvatarCache?) -> UIImage? {
        let renderer = ImageRenderer(content: ChallengeCard(challenge: challenge, savedAvatars: savedAvatars))
        renderer.scale = BoardShareFormat.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The story as a PNG in a temporary folder, named for the race, for the share sheet. Each
    /// render replaces the last one of the same race.
    static func file(_ challenge: Challenge, savedAvatars: AvatarCache?) throws -> URL {
        guard let data = image(challenge, savedAvatars: savedAvatars)?.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("challenge-share", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "Committed-challenge-\(challenge.url.pathComponents.suffix(2).joined(separator: "-vs-")).png"
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// What the share sheet gets: the story image and the message with the link, both frozen when
/// Challenge is tapped.
struct ChallengeShare: Identifiable {
    let image: URL
    let message: String
    var id: URL { image }

    @MainActor
    init(_ challenge: Challenge, savedAvatars: AvatarCache?) throws {
        image = try ChallengeShareRenderer.file(challenge, savedAvatars: savedAvatars)
        message = challenge.message
    }
}

// MARK: - Button

/// Challenge, under Your race: opens the share sheet with the story and the message. It also
/// opens by itself for a Challenge asked for from outside (`AppModel.requestChallenge`), once the
/// person view has settled.
struct ChallengeButton: View {
    @Environment(AppModel.self) private var model
    let challenge: Challenge
    let person: PersonSummary
    @State private var sharing: ChallengeShare?

    var body: some View {
        Button {
            share(challenge)
        } label: {
            Label("Challenge", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(LimeButtonStyle())
        .accessibilityHint("Shares your race with \(challenge.friend) as a story image and a link")
        .sheet(item: $sharing) { share in
            ShareActivity(items: [share.image, share.message])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .task(id: model.requestedChallenge) {
            guard model.requestedChallenge == person.login else { return }
            // After a push or a pane change settles, so the sheet has a screen to present from.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let requested = model.takeRequestedChallenge(for: person) else { return }
            share(requested)
        }
    }

    private func share(_ challenge: Challenge) {
        sharing = try? ChallengeShare(challenge, savedAvatars: model.savedAvatars)
    }
}

/// The system share sheet with the given items.
struct ShareActivity: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
