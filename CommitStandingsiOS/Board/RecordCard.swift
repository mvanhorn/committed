import SwiftUI
import UIKit

/// The record card (#127): a lime card at the top of the Board on a day you set a best day, best
/// week or longest streak (`PersonalRecords.card`), saying what your old best was. **Share** sends
/// an image of the card through the share sheet, **See your records** opens your own view, and ×
/// dismisses it for that record. It goes by itself when the day ends.
struct RecordCardView: View {
    let record: PersonalRecords.Broken
    /// The Board's card has its buttons; the share image doesn't.
    var actions: Actions?

    struct Actions {
        let share: () -> Void
        let seeRecords: () -> Void
        let dismiss: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label {
                    Text(PersonalRecords.Broken.eyebrow)
                } icon: {
                    TrophyMark(size: 13, color: .onLime)
                }
                .eyebrow()
                .foregroundStyle(Color.onLime)
                Spacer(minLength: 8)
                if let actions {
                    Button(action: actions.dismiss) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.onLime)
                            .frame(width: 30, height: 30)
                            .background(Color.ink.opacity(0.08), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)
                    .padding(.trailing, -8)
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Hides this record’s card")
                }
            }
            Text(record.title)
                .font(CommittedType.display(22, relativeTo: .title2))
                .displayTracking(22)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail = record.detail {
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.onLime)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actions {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons(actions) }
                    VStack(alignment: .leading, spacing: 8) { buttons(actions) }
                }
                .padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lime, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func buttons(_ actions: Actions) -> some View {
        Button(action: actions.share) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(RecordCardButtonStyle(filled: true))
        .accessibilityHint("Shares an image of this card")
        Button("See your records", action: actions.seeRecords)
            .buttonStyle(RecordCardButtonStyle(filled: false))
            .accessibilityHint("Opens your view")
    }
}

/// The card's buttons on lime: an ink slab with lime text, or an ink outline.
private struct RecordCardButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(filled ? Color.lime : Color.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background {
                let shape = Capsule()
                if filled {
                    shape.fill(Color.ink)
                } else {
                    shape.strokeBorder(Color.ink.opacity(0.55), lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// The record card on the Board, with its share sheet.
struct BoardRecordCard: View {
    @Environment(AppModel.self) private var model
    let record: PersonalRecords.Broken
    @State private var sharing: SharedRecord?

    private struct SharedRecord: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        RecordCardView(record: record, actions: .init(
            share: share,
            seeRecords: { model.showYourRecords() },
            dismiss: {
                withAnimation(.snappy) { model.dismissRecordCard(record) }
            }
        ))
        // The image alone, as Share board sends it.
        .sheet(item: $sharing) { file in
            ShareActivity(items: [file.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        #if DEBUG
        .task {
            guard ScreenshotFixture.sharesRecord else { return }
            try? await Task.sleep(for: .seconds(3))
            share()
        }
        #endif
    }

    private func share() {
        sharing = (try? RecordShareRenderer.file(record, login: model.store.selfCompetitor?.username))
            .map(SharedRecord.init)
    }
}

// MARK: - Share image

/// The image Share sends: the card on the board's squares, 1080 × 1080, with your login and
/// Committed's footer, in the same fixed look as Share board's images.
struct RecordShareCard: View {
    let record: PersonalRecords.Broken
    let login: String?

    static let canvas = CGSize(width: 540, height: 540)

    var body: some View {
        ZStack {
            Color.ink
            BoardShareSquareField(brightness: 0.55)
            LinearGradient(colors: [Color.ink.opacity(0), Color.ink.opacity(0.85), Color.ink.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 170)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                if let login {
                    Text("@\(login)")
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Color.soft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                RecordCardView(record: record)
                    .environment(\.dynamicTypeSize, .xxxLarge)
                Spacer(minLength: 0)
                BoardShareFooter(peopleCount: 0)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 40)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }
}

@MainActor
enum RecordShareRenderer {
    static func image(_ record: PersonalRecords.Broken, login: String?) -> UIImage? {
        ShareImageRenderer.image(RecordShareCard(record: record, login: login))
    }

    /// The image as a PNG in a temporary folder, for the share sheet.
    static func file(_ record: PersonalRecords.Broken, login: String?) throws -> URL {
        try ShareImageRenderer.file(RecordShareCard(record: record, login: login),
                                    folder: "record-share", name: "Committed-\(record.kind.rawValue).png")
    }
}
