import { competitorsOf, rivalsOf, standingsFor } from "../board";
import { localDate } from "../parser";
import { order, type Window } from "../ranking";
import { sendAlert } from "./alerts";
import type { NotificationContext, NotificationDeps } from "./index";
import { isQuietHours } from "./quietHours";
import type { CloseCallsState, NotificationState } from "./state";
import { formatCount } from "./format";
import { holdCloseCalls, holdsForSummary, type SummaryState } from "./summaryHold";

/**
 * Close calls (#132): you're a few contributions behind someone directly above you, in the
 * Notifications Window. "A few" is 1 to `max(3, ceil(5% of their count))`.
 */

export interface CloseCall {
  rival: string;
  /** How far behind you are: their count minus yours, as "N to pass" says it everywhere (`gapToPass`). */
  toPass: number;
  myContributions: number;
  rivalContributions: number;
  window: Window;
}

/**
 * Who you're close behind. With rivals pinned, each pinned rival you're close behind (even with
 * someone between you); with nobody pinned, only the person directly above you on the board
 * (`Ranking.order`, you first among ties, so they're always strictly ahead). Ordered as the board is.
 */
export function findCloseCalls(
  competitors: readonly string[],
  counts: Readonly<Record<string, number>>,
  self: string,
  window: Window,
  rivals: readonly string[],
): CloseCall[] {
  const mine = counts[self];
  if (mine === undefined) return [];
  const standings = Object.fromEntries(
    Object.entries(counts).map(([login, contributions]) => [login, { contributions, window }]),
  );
  const ranked = order(competitors, standings, window).map((entry) => entry.login);
  const candidates = rivals.length > 0
    ? ranked.filter((login) => rivals.includes(login))
    : ranked.slice(Math.max(ranked.indexOf(self) - 1, 0), ranked.indexOf(self));
  const calls: CloseCall[] = [];
  for (const rival of candidates) {
    const theirs = counts[rival];
    if (rival === self || theirs === undefined) continue;
    const behind = theirs - mine;
    if (behind >= 1 && behind <= closeCallMargin(theirs)) {
      calls.push({ rival, toPass: behind, myContributions: mine, rivalContributions: theirs, window });
    }
  }
  return calls;
}

/** How far behind still counts as close: 3, or 5% of their count when that's more. */
export function closeCallMargin(theirContributions: number): number {
  return Math.max(3, Math.ceil(theirContributions / 20));
}

const WINDOW_NAMES: Record<Window, string> = { daily: "Today", weekly: "7 days", monthly: "30 days" };

/** "Close call: 2 to pass odile-m" / "You're at 31, they're at 33 · Today". */
export function closeCallCopy(call: CloseCall): { title: string; body: string } {
  return {
    title: `Close call: ${formatCount(call.toPass)} to pass ${call.rival}`,
    body: `You're at ${formatCount(call.myContributions)}, they're at ${formatCount(call.rivalContributions)} · ${WINDOW_NAMES[call.window]}`,
  };
}

/**
 * The evening summary's lines for the close calls it holds, as of `today`, each with today's gap
 * and worded as the notification's title. Left out: one found on an earlier day, someone no longer
 * on your board (hidden or removed), and one you've since closed or that's no longer close.
 */
export function closeCallSummaryLines(
  context: NotificationContext,
  held: SummaryState["closeCalls"],
  today: string,
): string[] {
  const { row, data } = context;
  const competitors = competitorsOf(row);
  const counts: Partial<Record<Window, Record<string, number>>> = {};
  const countsIn = (window: Window) => {
    counts[window] ??= Object.fromEntries(
      Object.entries(standingsFor(competitors, data, window, today)).map(([login, standing]) => [login, standing.contributions]),
    );
    return counts[window]!;
  };
  const lines: string[] = [];
  for (const call of held) {
    if (call.date !== today || !competitors.includes(call.rival)) continue;
    const current = countsIn(call.window);
    const rivalContributions = current[call.rival] ?? call.rivalContributions;
    const myContributions = current[row.login] ?? call.myContributions;
    const toPass = rivalContributions - myContributions;
    // Still behind, and still close.
    if (toPass >= 1 && toPass <= closeCallMargin(rivalContributions)) {
      lines.push(closeCallCopy({ ...call, toPass, myContributions, rivalContributions }).title);
    }
  }
  return lines;
}

/**
 * Sends a close call for each person you're close behind, on the preferences' Window, at most once
 * per person per local day, and never during quiet hours (one still close when they end goes out
 * then), nor about someone a pass was sent about in the same cycle. The day's markers are saved
 * before anything is sent.
 */
export async function notifyCloseCalls(
  context: NotificationContext,
  state: NotificationState,
  save: (state: NotificationState) => Promise<void>,
  deps: NotificationDeps,
): Promise<NotificationState> {
  const { row, preferences, data, now } = context;
  if (!preferences.closeCalls || isQuietHours(now, row.time_zone, preferences.quietHours)) return state;
  const today = localDate(now, row.time_zone);
  const competitors = competitorsOf(row);
  const counts: Record<string, number> = {};
  for (const [login, standing] of Object.entries(standingsFor(competitors, data, preferences.window, today))) {
    counts[login] = standing.contributions;
  }
  const rivals = rivalsOf(row);
  const last = state.closeCalls;
  const alreadySent = last?.date === today ? last.sent : [];
  const found = findCloseCalls(competitors, counts, row.login, preferences.window, rivals).filter(
    (call) => !alreadySent.includes(call.rival),
  );
  if (found.length === 0) return state;
  // Someone who passed you in this cycle was just named in that pass ("They're ahead 33–31"): a
  // close call about them is left out and counts as today's, so it doesn't follow a cycle later.
  const calls = found.filter((call) => !context.passedThisCycle.has(call.rival));

  const closeCalls: CloseCallsState = { date: today, sent: [...alreadySent, ...found.map((call) => call.rival)] };
  // In summary delivery the evening summary (#135) holds them; otherwise they go now.
  const summary = holdsForSummary(preferences);
  const next = summary ? holdCloseCalls({ ...state, closeCalls }, calls, today) : { ...state, closeCalls };
  await save(next);
  if (!summary) await sendCloseCallsNow(context, calls, deps);
  return next;
}

/**
 * Sends close calls right away (delivery "immediate"). In summary delivery they're held for the
 * evening summary (#135, summary.ts) instead of coming through here.
 */
export async function sendCloseCallsNow(
  context: NotificationContext,
  calls: readonly CloseCall[],
  deps: NotificationDeps,
): Promise<void> {
  for (const call of calls) {
    if (!context.row.alert_token) break;
    await sendAlert(
      context.row,
      {
        aps: { alert: closeCallCopy(call), sound: "default", "thread-id": "closeCalls" },
        kind: "closeCall",
        login: call.rival,
      },
      deps,
      { collapseId: `closeCall.${call.rival}` },
    );
  }
}
