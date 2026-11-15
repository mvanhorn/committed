import { competitorsOf, standingsFor } from "../board";
import { currentStreak, localDate, sum } from "../parser";
import { addDays } from "../ranking";
import { sendAlert } from "./alerts";
import { closeCallMargin, type CloseCall } from "./closeCalls";
import type { NotificationContext, NotificationDeps } from "./index";
import type { NotificationPreferences } from "./preferences";
import { isQuietHours, localMinutes } from "./quietHours";
import { latestRecord, mondayOf, type DueRecord } from "./records";
import { finish } from "./results";
import type { NotificationState } from "./state";
import type { StreakReminder } from "./streakReminder";

/**
 * The evening summary (#135, spec #124): with delivery "summary" (the default, "Passes now, the
 * rest at 9 PM"), close calls, records and the streak reminder are held at their send steps
 * instead of going out, and one "Your day so far" collects them at 9 PM local, or when quiet hours
 * start if that's earlier. Passes and results are unaffected. Tapping it opens the Board.
 *
 * The body is short lines joined with " · ", for example "#2 today with 41 · New best day: 41 ·
 * Close call: 2 to pass odile-m", or "#3 today with 0 · Your 40-day streak needs one contribution
 * by midnight":
 *
 * - First, where you stand on today's Board ("#2 today with 41"), whenever something held is
 *   still to say and you have a rank (a visible rival with data, and someone contributed today).
 *   It never makes a summary on its own.
 * - Then each record, with the day's latest number; then each close call, with today's gap; then
 *   the streak reminder.
 * - Lines are brought up to date when it's sent. Dropped: a close call you've since closed or
 *   that's no longer close, a streak reminder you've since answered, anything from an earlier day
 *   except a record set yesterday (quiet hours held it overnight), and any kind switched off. With
 *   nothing left, no summary is sent.
 *
 * Owns the `summary` key of the notification state (see `SummaryState`).
 */

/** `notification_state.summary`. */
export interface SummaryState {
  /** The last local date whose summary was settled (sent, or nothing to send). */
  settled: string | null;
  /** Close calls held, each with the local date it was found. */
  closeCalls: (CloseCall & { date: string })[];
  /** The streak reminder held, if any. */
  streak: StreakReminder | null;
  /** Records held, with the latest number seen. */
  records: DueRecord[];
}

/** 9 PM, in minutes since local midnight. */
export const SUMMARY_MINUTES = 21 * 60;
/** Quiet hours that start before noon (or after midnight) don't move the summary. */
const EARLIEST_MINUTES = 12 * 60;

export const SUMMARY_TITLE = "Your day so far";

/**
 * When today's summary goes out, in minutes since local midnight: 9 PM, or when quiet hours start
 * if that's earlier in the afternoon or evening.
 */
export function summaryMinutes(quietHours: NotificationPreferences["quietHours"]): number {
  if (!quietHours || quietHours.start === quietHours.end) return SUMMARY_MINUTES;
  const [hours = 0, minutes = 0] = quietHours.start.split(":").map(Number);
  const start = hours * 60 + minutes;
  return start >= EARLIEST_MINUTES && start < SUMMARY_MINUTES ? start : SUMMARY_MINUTES;
}

/** True when the kinds' send steps should hold for the summary instead of sending. */
export function holdsForSummary(preferences: NotificationPreferences): boolean {
  return preferences.delivery === "summary";
}

// MARK: - Holding

export function holdCloseCalls(state: NotificationState, calls: readonly CloseCall[], date: string): NotificationState {
  const summary = readSummary(state.summary);
  const held = summary.closeCalls.filter((call) => !calls.some((next) => next.rival === call.rival));
  return { ...state, summary: { ...summary, closeCalls: [...held, ...calls.map((call) => ({ ...call, date }))] } };
}

export function holdStreakReminder(state: NotificationState, reminder: StreakReminder): NotificationState {
  return { ...state, summary: { ...readSummary(state.summary), streak: reminder } };
}

export function holdRecords(state: NotificationState, records: readonly DueRecord[]): NotificationState {
  const summary = readSummary(state.summary);
  const held = [...summary.records];
  for (const record of records) {
    const index = held.findIndex((existing) => existing.id === record.id);
    if (index === -1) held.push(record);
    else held[index] = { ...record, value: Math.max(record.value, held[index]!.value) };
  }
  return { ...state, summary: { ...summary, records: held } };
}

// MARK: - Sending

/**
 * The summary's step in the cycle, run after every kind. Once a local day, from its time on: what's
 * held is settled and saved, then sent if anything is left to say. It isn't held back by quiet
 * hours, whose start can be its time; a late cycle well into quiet hours sends it without a sound.
 * Anything held in Right away (switched after holding) still goes out tonight.
 */
export async function notifySummary(
  context: NotificationContext,
  state: NotificationState,
  save: (state: NotificationState) => Promise<void>,
  deps: NotificationDeps,
): Promise<NotificationState> {
  const { row, preferences, now } = context;
  if (!row.alert_token) return state;
  const summary = readSummary(state.summary);
  const anythingHeld = summary.closeCalls.length > 0 || summary.streak !== null || summary.records.length > 0;
  if (!anythingHeld && !holdsForSummary(preferences)) return state;
  const today = localDate(now, row.time_zone);
  // Settled today, or later (a time zone change can move the local date back): nothing to send.
  if (summary.settled !== null && summary.settled >= today) return state;
  if (localMinutes(now, row.time_zone) < summaryMinutes(preferences.quietHours)) return state;

  const lines = summaryLines(context, summary, today);
  const next: NotificationState = {
    ...state,
    summary: { settled: today, closeCalls: [], streak: null, records: [] } satisfies SummaryState,
  };
  await save(next);
  if (lines.length === 0) return next;

  // Quiet hours that began well before this cycle (a late run): no sound.
  const quiet = isQuietHours(now - 10 * 60, row.time_zone, preferences.quietHours);
  await sendAlert(
    row,
    {
      aps: {
        alert: { title: SUMMARY_TITLE, body: lines.join(" · ") },
        ...(quiet ? { "interruption-level": "passive" as const } : { sound: "default" as const }),
        "thread-id": "summary",
      },
      kind: "summary",
    },
    deps,
    { collapseId: "summary" },
  );
  return next;
}

/** The body's lines as of `today`, or none when nothing held is still worth saying. */
export function summaryLines(context: NotificationContext, summary: SummaryState, today: string): string[] {
  const { row, preferences, data } = context;
  const mine = data.get(row.login);
  const yesterday = addDays(today, -1);
  const items: string[] = [];

  if (preferences.records) {
    for (const held of summary.records) {
      if (held.day < yesterday) continue;
      const record = mine ? latestRecord(held, mine.days, today) : held;
      items.push(recordLine(record, today));
    }
  }

  if (preferences.closeCalls) {
    const competitors = competitorsOf(row);
    const counts: Record<string, Record<string, number>> = {};
    const countsIn = (window: CloseCall["window"]) => {
      counts[window] ??= Object.fromEntries(
        Object.entries(standingsFor(competitors, data, window, today)).map(([login, standing]) => [login, standing.contributions]),
      );
      return counts[window]!;
    };
    for (const call of summary.closeCalls) {
      if (call.date !== today) continue;
      const current = countsIn(call.window);
      const theirs = current[call.rival] ?? call.rivalContributions;
      const yours = current[row.login] ?? call.myContributions;
      const toPass = theirs - yours;
      // Still behind, and still close.
      if (toPass >= 1 && toPass <= closeCallMargin(theirs)) items.push(`Close call: ${toPass} to pass ${call.rival}`);
    }
  }

  const streak = summary.streak;
  if (preferences.streakReminder && streak && streak.date === today) {
    const contributedSince = mine ? sum(mine.days, "daily", today) > 0 : false;
    if (!contributedSince) {
      const days = mine ? Math.max(currentStreak(mine.days, today), streak.streak) : streak.streak;
      items.push(`Your ${days}-day streak needs one contribution by midnight`);
    }
  }

  if (items.length === 0) return [];
  const standing = finish(competitorsOf(row), row.login, data, "daily", today);
  return standing ? [`#${standing.rank} today with ${standing.mine.toLocaleString("en-US")}`, ...items] : items;
}

/** "New best day: 41", "New best week: 186", "Your longest streak yet: 53 days". */
function recordLine(record: DueRecord, today: string): string {
  const value = record.value.toLocaleString("en-US");
  switch (record.kind) {
    case "bestDay":
      return record.day === today ? `New best day: ${value}` : `New best day: ${value} yesterday`;
    case "bestWeek":
      return mondayOf(record.day) === mondayOf(today) ? `New best week: ${value}` : `New best week: ${value} last week`;
    case "longestStreak":
      return `Your longest streak yet: ${value} days`;
  }
}

function readSummary(raw: unknown): SummaryState {
  const value = (typeof raw === "object" && raw !== null ? raw : {}) as Partial<SummaryState>;
  return {
    settled: typeof value.settled === "string" ? value.settled : null,
    closeCalls: Array.isArray(value.closeCalls) ? value.closeCalls : [],
    streak: typeof value.streak === "object" && value.streak !== null ? value.streak : null,
    records: Array.isArray(value.records) ? value.records : [],
  };
}
