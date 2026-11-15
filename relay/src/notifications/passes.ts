import { competitorsOf, standingsFor } from "../board";
import { localDate } from "../parser";
import { sendAlert } from "./alerts";
import type { NotificationContext, NotificationDeps } from "./index";
import { isQuietHours } from "./quietHours";
import type { NotificationState, PassesState } from "./state";

/**
 * Passes: a TypeScript port of `RankChangeDetector.crossings` (CommitStandings/Store/
 * RankChangeDetector.swift) and the copy of `NotificationService.copy(for:)`. Keep them in
 * lockstep: both run the shared `passes` cases in fixtures/habit-conformance.json.
 */

export type PassDirection = "rivalPassedMe" | "iPassedRival";

export interface PassEvent {
  rival: string;
  direction: PassDirection;
  /** Current counts: what the notification shows. */
  rivalContributions: number;
  myContributions: number;
}

/**
 * A pass is "was at or below me, now strictly above me" (they passed you) or "was at or above me,
 * now strictly below me" (you passed them). Holding a tie, or catching up to one, fires nothing;
 * a pass that goes through a tie fires once. Compares counts, not ranks, so the board's tie-break
 * order doesn't matter. Empty without a previous snapshot or your count in both; a rival not in
 * both snapshots is ignored. Ordered by login.
 */
export function crossings(
  previous: Readonly<Record<string, number>> | null,
  current: Readonly<Record<string, number>>,
  self: string,
): PassEvent[] {
  if (!previous) return [];
  const mePrev = previous[self];
  const meNow = current[self];
  if (mePrev === undefined || meNow === undefined) return [];

  const events: PassEvent[] = [];
  for (const [rival, rivalNow] of Object.entries(current)) {
    if (rival === self) continue;
    const rivalPrev = previous[rival];
    if (rivalPrev === undefined) continue;
    if (rivalPrev <= mePrev && rivalNow > meNow) {
      events.push({ rival, direction: "rivalPassedMe", rivalContributions: rivalNow, myContributions: meNow });
    } else if (rivalPrev >= mePrev && rivalNow < meNow) {
      events.push({ rival, direction: "iPassedRival", rivalContributions: rivalNow, myContributions: meNow });
    }
  }
  return events.sort((a, b) => (a.rival < b.rival ? -1 : a.rival > b.rival ? 1 : 0));
}

/** The shipped pass copy, unchanged: the same strings as `NotificationService.copy(for:)`. */
export function passCopy(event: PassEvent): { title: string; body: string } {
  switch (event.direction) {
    case "iPassedRival":
      return {
        title: `🎉 You passed ${event.rival}!`,
        body: `You're ahead ${event.myContributions}–${event.rivalContributions}. Keep climbing!`,
      };
    case "rivalPassedMe":
      return {
        title: `😤 ${event.rival} passed you`,
        body: `They're ahead ${event.rivalContributions}–${event.myContributions}. Time to catch up!`,
      };
  }
}

/**
 * Sends a `PASS` alert for each crossing since the last look, among the visible people on the
 * board, on the preferences' Window; with `passes: "rivals"`, only your pinned rivals' crossings.
 * The first look, a new local day and a new Window take a baseline silently (as
 * `RefreshCoordinator` re-baselines across a reset). The baseline always holds everyone visible,
 * so pinning someone or switching between Everyone and Pinned rivals never replays an old pass.
 * While your own count is missing, the last baseline is kept so the next real pass still fires.
 * During quiet hours a pass still goes out, passively and with no sound.
 */
export async function notifyPasses(
  context: NotificationContext,
  state: NotificationState,
  save: (state: NotificationState) => Promise<void>,
  deps: NotificationDeps,
): Promise<NotificationState> {
  const { row, preferences, data, now } = context;
  if (preferences.passes === "off") {
    if (state.passes === undefined) return state;
    const { passes: _dropped, ...rest } = state;
    await save(rest);
    return rest;
  }
  const today = localDate(now, row.time_zone);
  const counts: Record<string, number> = {};
  for (const [login, standing] of Object.entries(standingsFor(competitorsOf(row), data, preferences.window, today))) {
    counts[login] = standing.contributions;
  }
  if (counts[row.login] === undefined) return state;

  const last = state.passes;
  const comparable = last && last.window === preferences.window && last.date === today ? last.counts : null;
  const rivals = preferences.passes === "rivals" ? new Set(JSON.parse(row.rivals_json) as string[]) : null;
  const events = crossings(comparable, counts, row.login).filter((event) => !rivals || rivals.has(event.rival));
  const quiet = isQuietHours(now, row.time_zone, preferences.quietHours);
  const passes: PassesState = { window: preferences.window, date: today, counts };
  const next = { ...state, passes };
  await save(next);

  for (const event of events) {
    if (!row.alert_token) break;
    await sendAlert(
      row,
      {
        aps: {
          alert: passCopy(event),
          ...(quiet ? { "interruption-level": "passive" as const } : { sound: "default" as const }),
          category: "PASS",
          "thread-id": "passes",
        },
        kind: "pass",
        login: event.rival,
      },
      deps,
      // The app's own crossing notifications replace per rival too ("rankchange.<login>").
      { collapseId: `pass.${event.rival}` },
    );
  }
  return next;
}
