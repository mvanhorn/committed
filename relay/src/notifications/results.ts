import { competitorsOf, standingsFor } from "../board";
import { localDate } from "../parser";
import { addDays, order, type Window } from "../ranking";
import { sendAlert } from "./alerts";
import type { NotificationContext, NotificationDeps } from "./index";
import type { NotificationPreferences } from "./preferences";
import { isQuietHours, localMinutes } from "./quietHours";
import type { NotificationState } from "./state";

/**
 * Daily and weekly results (#131): each morning, yesterday's Today standings; on Mondays also last
 * week's final, the Monday-to-Sunday standings. Sent when quiet hours end, or at 8 AM with quiet
 * hours off, in the installation's time zone. Skipped when you have no visible rivals with data, or
 * nobody on the board contributed. Tapping either opens the Board.
 */

/** A Week (spec #124): Monday through Sunday, named by its first and last day keys (`YYYY-MM-DD`). */
export interface FixedWeek {
  first: string;
  last: string;
}

/**
 * The week containing `unixSeconds` in `timeZone`, and the finished week before it: a port of
 * `FixedWeek` (CommitStandings/Store/FixedWeek.swift), held to it by the shared `weeks` cases in
 * fixtures/habit-conformance.json. It works on civil days, so a week is 7 days whatever the clocks
 * do, and which week it is depends only on the local day.
 */
export function fixedWeeks(unixSeconds: number, timeZone: string): { thisWeek: FixedWeek; lastWeek: FixedWeek } {
  const today = localDate(unixSeconds, timeZone);
  const monday = addDays(today, -daysSinceMonday(today));
  return {
    thisWeek: { first: monday, last: addDays(monday, 6) },
    lastWeek: { first: addDays(monday, -7), last: addDays(monday, -1) },
  };
}

/** 0 on a Monday through 6 on a Sunday, for a civil day key. */
function daysSinceMonday(day: string): number {
  const [year, month, date] = day.split("-").map(Number);
  return (new Date(Date.UTC(year!, month! - 1, date!)).getUTCDay() + 6) % 7;
}

/** `notification_state.results`: the last local date whose morning results were settled (sent or skipped). */
export interface ResultsState {
  date: string;
}

/** Where you finished among the visible people with data, or null when there's no result to send. */
export interface Finish {
  rank: number;
  mine: number;
  /** With rank 1, the runner-up; otherwise the winner. */
  other: { login: string; contributions: number };
}

/**
 * Your finish in `window` as of `day`, ranked as the Board ranks (`order`, you first, so a tie is
 * yours). Null with no visible rival who has data, or when nobody contributed.
 */
export function finish(
  competitors: readonly string[],
  self: string,
  data: NotificationContext["data"],
  window: Window,
  day: string,
): Finish | null {
  const standings = standingsFor(competitors, data, window, day);
  const ranked = order(competitors, standings, window).filter((entry) => standings[entry.login]);
  const me = ranked.find((entry) => entry.login === self);
  if (!me || ranked.length < 2) return null;
  if (ranked.every((entry) => standings[entry.login]!.contributions === 0)) return null;
  const other = me.rank === 1 ? ranked[1]! : ranked[0]!;
  return {
    rank: me.rank,
    mine: standings[self]!.contributions,
    other: { login: other.login, contributions: standings[other.login]!.contributions },
  };
}

/** The daily result's copy (spec #124, "Notification copy"). */
export function dailyCopy(result: Finish): { title: string; body: string } {
  if (result.rank === 1) return { title: "You won yesterday", body: lead(result) };
  return { title: `You finished #${result.rank} yesterday`, body: trail(result) };
}

/** Last week's final's copy. */
export function weeklyCopy(result: Finish): { title: string; body: string } {
  return { title: `Last week's final: #${result.rank}`, body: result.rank === 1 ? lead(result) : trail(result) };
}

/** "41 contributions, 8 ahead of odile-m." — or "level with" on a tie, which counts for you. */
function lead({ mine, other }: Finish): string {
  const count = `${mine} ${mine === 1 ? "contribution" : "contributions"}`;
  const gap = mine - other.contributions;
  return gap === 0 ? `${count}, level with ${other.login}.` : `${count}, ${gap} ahead of ${other.login}.`;
}

/** "odile-m won with 41. You had 33." */
function trail({ mine, other }: Finish): string {
  return `${other.login} won with ${other.contributions}. You had ${mine}.`;
}

/** Minutes after local midnight results go out: when quiet hours end, or 8 AM without them. */
function sendMinutes(quietHours: NotificationPreferences["quietHours"]): number {
  const time = quietHours && quietHours.start !== quietHours.end ? quietHours.end : "08:00";
  const [hours = 0, minutes = 0] = time.split(":").map(Number);
  return hours * 60 + minutes;
}

function readState(raw: unknown): string | null {
  if (typeof raw !== "object" || raw === null) return null;
  const date = (raw as Partial<ResultsState>).date;
  return typeof date === "string" ? date : null;
}

/**
 * Results just switched on (relay notifications back on after being off, or the Results switch on
 * again): a morning whose send time has already passed is settled unsent, so it never goes out late.
 * The cycle can't tell this by itself while relay notifications are off, since it doesn't run then.
 */
export function settleResultsOnEnable(
  state: NotificationState,
  timeZone: string,
  preferences: NotificationPreferences,
  now: number,
): NotificationState {
  const today = localDate(now, timeZone);
  const settled = readState(state.results);
  if (settled !== null && settled >= today) return state;
  if (localMinutes(now, timeZone) < sendMinutes(preferences.quietHours)) return state;
  return { ...state, results: { date: today } satisfies ResultsState };
}

/**
 * Sends the morning's results once per local day. Results are settled, then saved, before anything
 * is sent. The first look, or the first in more than a day (results or relay notifications were
 * off), settles a morning already past without sending, so turning results on at 3 PM doesn't send
 * yesterday's result then; before the send time it lets that morning's go out. Results wait out
 * quiet hours and a missing count of your own. Turning results off drops this kind's state.
 */
export async function notifyResults(
  context: NotificationContext,
  state: NotificationState,
  save: (state: NotificationState) => Promise<void>,
  deps: NotificationDeps,
): Promise<NotificationState> {
  const { row, preferences, data, now } = context;
  if (!preferences.results) {
    if (state.results === undefined) return state;
    const { results: _dropped, ...rest } = state;
    await save(rest);
    return rest;
  }
  const today = localDate(now, row.time_zone);
  const settled = readState(state.results);
  // Settled today, or later (a time zone change can move the local date back): nothing to send.
  if (settled !== null && settled >= today) return state;
  const yesterday = addDays(today, -1);
  const firstLook = settled === null || settled < yesterday;
  const due = localMinutes(now, row.time_zone) >= sendMinutes(preferences.quietHours);

  if (firstLook) {
    // Past the send time, this morning is settled unsent; before it, it's still to come.
    const next = { ...state, results: { date: due ? today : yesterday } satisfies ResultsState };
    await save(next);
    return next;
  }
  if (!due || isQuietHours(now, row.time_zone, preferences.quietHours) || !data.has(row.login)) return state;

  const competitors = competitorsOf(row);
  const daily = finish(competitors, row.login, data, "daily", yesterday);
  const { thisWeek, lastWeek } = fixedWeeks(now, row.time_zone);
  const weekly = thisWeek.first === today ? finish(competitors, row.login, data, "weekly", lastWeek.last) : null;
  const next = { ...state, results: { date: today } satisfies ResultsState };
  await save(next);

  const sends: [string, { title: string; body: string }][] = [];
  if (daily) sends.push(["daily", dailyCopy(daily)]);
  if (weekly) sends.push(["weekly", weeklyCopy(weekly)]);
  for (const [which, alert] of sends) {
    if (!row.alert_token) break;
    await sendAlert(
      row,
      { aps: { alert, sound: "default", "thread-id": "results" }, kind: "result" },
      deps,
      // Daily and weekly are separate notifications; a newer one of the same replaces an unread one.
      { collapseId: `result.${which}` },
    );
  }
  return next;
}
