import Foundation

/// Your rivals on the iPhone Board: your pinned rivals' rows, taken from the Window's ranking
/// (`Ranking.order`, as the list under them uses), so a rival's rank always matches their row in
/// Everyone. Each has the gap in the Board's words: "3 to pass", "12 ahead", "Level", and your
/// weekly record against them ("7–5", `RivalryRecord`) in the streak's place.
enum YourRivals {
    struct Row: Identifiable, Equatable {
        let entry: Ranking.Entry
        /// "3 to pass", "12 ahead" or "Level"; nil until both counts have loaded.
        let gap: String?
        /// Your weekly record against them; nil until you both have a finished week.
        var record: RivalryRecord? = nil
        var id: UUID { entry.id }
    }

    /// The pinned rivals among `ranked` (the selected Window's board), in board order, with your
    /// records as of `reference` (the app's clock, as the person view uses).
    @MainActor
    static func rows(ranked: [Ranking.Entry], store: StandingsStore, asOf reference: Date = .now) -> [Row] {
        let pinned = Set(store.pinnedRivals.map(\.username))
        guard !pinned.isEmpty else { return [] }
        let window = store.selectedWindow
        func loaded(_ login: String?) -> Int? {
            guard let login, let standing = store.standing(for: login, window: window),
                  standing.lastUpdated != .distantPast else { return nil }
            return standing.contributions
        }
        let yours = loaded(store.selfCompetitor?.username)
        return ranked.filter { pinned.contains($0.competitor.username) }.map { entry in
            Row(entry: entry, gap: gapLine(yours: yours, theirs: loaded(entry.competitor.username)),
                record: store.rivalry(with: entry.competitor.username, asOf: reference))
        }
    }

    /// The gap from your side. Ties count for you on the Board, so level reads "Level", never
    /// "0 to pass".
    static func gapLine(yours: Int?, theirs: Int?) -> String? {
        guard let yours, let theirs else { return nil }
        if theirs > yours { return "\((theirs - yours).formatted()) to pass" }
        if yours > theirs { return "\((yours - theirs).formatted()) ahead" }
        return "Level"
    }

    /// The ranked list's header under Your rivals: "Everyone · 5 people".
    static func everyoneHeader(count: Int) -> String {
        "Everyone · \(count) \(count == 1 ? "person" : "people")"
    }
}
