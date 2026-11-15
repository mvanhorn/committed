import SwiftUI

/// Your records (#127), under your summary in your own person view: your bests over the past year
/// of GitHub's calendar in a two-column grid, from `PersonalRecords`. A record set today (this week
/// for the week records) wears a lime outline and a New badge; one you haven't reached is a dashed
/// "Not yet" tile saying what it needs. At accessibility text sizes the tiles stack in one column.
struct YourRecordsSection: View {
    let records: PersonalRecords
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Your records")
                    .font(CommittedType.display(19, relativeTo: .headline))
                    .displayTracking(19)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("Past year")
                    .eyebrow()
                    .foregroundStyle(Color.muted)
                    .accessibilityLabel("Over the past year")
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(rows, id: \.first?.kind) { row in
                    GridRow {
                        ForEach(row) { tile in
                            RecordTile(tile: tile)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Two tiles a row, or one at accessibility text sizes.
    private var rows: [[PersonalRecords.Tile]] {
        let tiles = records.tiles
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return stride(from: 0, to: tiles.count, by: perRow).map { Array(tiles[$0..<min($0 + perRow, tiles.count)]) }
    }
}

/// One record: its name, the number, and when. Not reached yet, it's a dashed outline reading
/// "Not yet" over what it needs; new today, a lime outline and a New badge.
struct RecordTile: View {
    let tile: PersonalRecords.Tile

    private var reached: Bool { tile.value != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tile.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if tile.isNew {
                    NewRecordBadge()
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.value ?? "Not yet")
                    .font(CommittedType.display(reached ? 20 : 17, relativeTo: .title3))
                    .foregroundStyle(reached ? Color.white : Color.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tile.caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tile.isNew ? Color.lime : Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background {
            if reached {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.tile)
            }
        }
        .overlay {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            if tile.isNew {
                shape.strokeBorder(Color.lime, lineWidth: 1.5)
            } else if !reached {
                shape.strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.isNew ? "New record. \(tile.spokenValue)" : tile.spokenValue)
        .accessibilityHint(tile.hint ?? "")
    }
}

/// "New", in ink on a lime capsule, as the Board's "you" badge.
struct NewRecordBadge: View {
    var body: some View {
        Text("New")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Color.onLime)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Color.lime, in: Capsule())
            .accessibilityHidden(true)
    }
}
