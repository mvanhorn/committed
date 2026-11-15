import SwiftUI

/// Weekly record, under Your race in someone else's person view on iPhone: your wins–losses against
/// them over the last 12 finished weeks ("7–5"), one square per week (lime for your win, dim for
/// theirs, an outline for a week before either calendar starts), and your longest run of wins.
/// `PersonViewContent` draws it on iOS only; the Mac shows nothing new.
struct WeeklyRecordCard: View {
    let record: RivalryRecord
    let login: String
    @Environment(\.personViewStyle) private var style

    private var secondary: AnyShapeStyle {
        style.secondaryColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary)
    }

    private var winColor: Color { style.dataColor ?? .contributionGreen }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly record")
                .font(style.captionFont.weight(.semibold))
                .foregroundStyle(secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
            headline
                .font(style.raceFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            WeekSquares(weeks: record.weeks, win: winColor, loss: style.pastBarColor)
                .padding(.top, 8)
            HStack {
                Text("12 weeks ago")
                Spacer(minLength: 8)
                Text("Last week")
            }
            .font(.caption2)
            .foregroundStyle(secondary)
            Text(record.runCaption)
                .font(style.captionFont)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(style.cardColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary.opacity(0.5)))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly record")
        .accessibilityValue("\(record.spoken(against: login)). \(record.runCaption).")
    }

    /// "7–5" with your wins in the win squares' lime.
    private var headline: Text {
        Text("\(Text(record.wins.formatted()).foregroundStyle(winColor))–\(record.losses.formatted())")
    }
}

/// One square per week, oldest first, sharing the width evenly.
private struct WeekSquares: View {
    let weeks: [RivalryRecord.Week]
    let win: Color
    let loss: Color

    var body: some View {
        HStack(spacing: 4) {
            // A week's place is its identity: the record always has 12.
            ForEach(0..<weeks.count, id: \.self) { index in
                square(weeks[index])
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func square(_ week: RivalryRecord.Week) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        switch week {
        case .win: shape.fill(win)
        case .loss: shape.fill(loss)
        case .none: shape.strokeBorder(loss, lineWidth: 1)
        }
    }
}
