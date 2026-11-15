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

    /// VoiceOver reads a rival's row as one line, the gap after their count.
    @Test func voiceOverReadsTheGapOnARivalsRow() {
        let row = StandingRow(rank: 2, competitor: Competitor(username: "odile-m", isSelf: false),
                              standing: Standing(username: "odile-m", contributions: 9, window: .daily,
                                                 lastUpdated: .now, state: .loaded),
                              window: .daily, streak: 400, caption: "2 to pass")
        #expect(row.accessibilityDescription
                == "rank 2, odile-m, 9 contributions for today, 2 to pass, 365-plus-day streak")
        let level = StandingRow(rank: 4, competitor: Competitor(username: "bram-ott", isSelf: false),
                                standing: Standing(username: "bram-ott", contributions: 7, window: .daily,
                                                   lastUpdated: .now, state: .loaded),
                                window: .daily, caption: "Level")
        #expect(level.accessibilityDescription == "rank 4, bram-ott, 7 contributions for today, level")
    }

    /// A rival's row carries your weekly record against them, from both calendars, as of the
    /// date the Board passes (the app's clock); nil until you both have a finished week.
    @Test func rowsCarryYourWeeklyRecord() {
        let store = board(["me": 3, "ada": 5, "bo": 1])
        let utc = TimeZone.gmt
        store.updateHistories([
            // Monday November 2 through Wednesday November 18: two finished weeks.
            "me": ContributionHistory(days: ["2026-11-02": 4, "2026-11-09": 1, "2026-11-18": 3], timeZone: utc),
            "ada": ContributionHistory(days: ["2026-11-02": 0, "2026-11-10": 2], timeZone: utc),
            // Bo's calendar starts this week: no finished week yet.
            "bo": ContributionHistory(days: ["2026-11-16": 1], timeZone: utc),
        ])
        store.setPinned(true, username: "ada")
        store.setPinned(true, username: "bo")
        let today = Date(timeIntervalSince1970: 1_795_003_200) // Wednesday November 18, noon UTC
        let rows = YourRivals.rows(ranked: ranked(store), store: store, asOf: today)
        #expect(rows.map(\.entry.competitor.username) == ["ada", "bo"])
        #expect(rows.map { $0.record?.text } == ["1–1", nil])
        #expect(rows.first?.record?.spoken(against: "ada") == "You’ve won 1 of the last 2 weeks against ada")
    }

    /// The record takes the streak's place, and VoiceOver reads it as a sentence there.
    @Test func voiceOverReadsTheRecordOnARivalsRow() {
        let row = StandingRow(rank: 2, competitor: Competitor(username: "ezra-q", isSelf: false),
                              standing: Standing(username: "ezra-q", contributions: 9, window: .daily,
                                                 lastUpdated: .now, state: .loaded),
                              window: .daily, streak: 12, caption: "2 to pass", record: "7–5",
                              recordSpoken: "You’ve won 7 of the last 12 weeks against ezra-q")
        #expect(row.accessibilityDescription
                == "rank 2, ezra-q, 9 contributions for today, 2 to pass, you’ve won 7 of the last 12 weeks against ezra-q")
    }

    @Test func everyoneHeaderCountsThePeopleOnTheBoard() {
        #expect(YourRivals.everyoneHeader(count: 5) == "Everyone · 5 people")
        #expect(YourRivals.everyoneHeader(count: 1) == "Everyone · 1 person")
    }
}
