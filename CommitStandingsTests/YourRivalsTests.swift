import Foundation
import Testing
@testable import CommitStandings

/// Your rivals on the iPhone Board: each pinned rival's rank in the Window and the gap in the
/// Board's words, from the same ranking as the list under it.
@MainActor
struct YourRivalsTests {
    private func board(_ counts: [String: Int], window: ContributionWindow = .daily) -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: counts.keys.filter { $0 != "me" })
        for (login, count) in counts {
            store.updateStanding(Standing(username: login, contributions: count, window: window,
                                          lastUpdated: .now, state: .loaded))
        }
        store.selectedWindow = window
        return store
    }

    private func ranked(_ store: StandingsStore) -> [Ranking.Entry] {
        Ranking.order(competitors: store.visibleCompetitors,
                      standings: store.standings(for: store.selectedWindow), window: store.selectedWindow)
    }

    @Test func rowsKeepTheBoardsRanksAndOrderWithTheGap() {
        let store = board(["me": 30, "ines-volk": 41, "odile-m": 33, "ezra-q": 18, "bram-ott": 30])
        store.setPinned(true, username: "ezra-q")
        store.setPinned(true, username: "ines-volk")
        store.setPinned(true, username: "bram-ott")

        let rows = YourRivals.rows(ranked: ranked(store), store: store)

        // Board order, not pin order; a level count puts you first, as on the Board.
        #expect(rows.map(\.entry.competitor.username) == ["ines-volk", "bram-ott", "ezra-q"])
        #expect(rows.map(\.entry.rank) == [1, 4, 5])
        #expect(rows.map(\.gap) == ["11 to pass", "Level", "12 ahead"])
    }

    @Test func noPinsNoRows() {
        let store = board(["me": 3, "ada": 5])
        #expect(YourRivals.rows(ranked: ranked(store), store: store).isEmpty)
    }

    @Test func theGapWaitsForBothCounts() {
        let store = board(["me": 3, "ada": 5])
        store.setPinned(true, username: "ada")
        store.updateStanding(Standing(username: "me", contributions: 0, window: .daily,
                                      lastUpdated: .distantPast, state: .failed("Offline")))
        let rows = YourRivals.rows(ranked: ranked(store), store: store)
        #expect(rows.map(\.entry.competitor.username) == ["ada"])
        #expect(rows.map(\.gap) == [nil])
    }

    @Test func theGapIsTheSelectedWindows() {
        let store = board(["me": 120, "ada": 90], window: .monthly)
        store.updateStanding(Standing(username: "me", contributions: 2, window: .daily, lastUpdated: .now, state: .loaded))
        store.updateStanding(Standing(username: "ada", contributions: 9, window: .daily, lastUpdated: .now, state: .loaded))
        store.setPinned(true, username: "ada")
        #expect(YourRivals.rows(ranked: ranked(store), store: store).map(\.gap) == ["30 ahead"])
        store.selectedWindow = .daily
        #expect(YourRivals.rows(ranked: ranked(store), store: store).map(\.gap) == ["7 to pass"])
    }

    @Test func bigGapsReadWhole() {
        #expect(YourRivals.gapLine(yours: 12, theirs: 1_240) == "1,228 to pass")
        #expect(YourRivals.gapLine(yours: 5, theirs: 5) == "Level")
        #expect(YourRivals.gapLine(yours: nil, theirs: 5) == nil)
    }

    @Test func everyoneHeaderCountsThePeopleOnTheBoard() {
        #expect(YourRivals.everyoneHeader(count: 5) == "Everyone · 5 people")
        #expect(YourRivals.everyoneHeader(count: 1) == "Everyone · 1 person")
    }
}
