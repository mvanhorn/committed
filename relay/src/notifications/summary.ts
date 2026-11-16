import { competitorsOf } from "../board";
import { localDate } from "../parser";
import { sendAlert } from "./alerts";
import { closeCallSummaryLines } from "./closeCalls";
import { formatCount } from "./format";
import type { NotificationContext, NotificationDeps } from "./index";
import type { NotificationPreferences } from "./preferences";
import { EARLIEST_MINUTES, isQuietHours, localMinutes, timeMinutes } from "./quietHours";
import { recordSummaryLines } from "./records";
import { finish } from "./results";
import type { NotificationState } from "./state";
import { streakReminderSummaryLine } from "./streakReminder";
import { holdsForSummary, readSummary, type SummaryState } from "./summaryHold";

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
 *   except a record set yesterday (quiet hours held it overnight) or a best week still in its week
 *   (`isStillDue`), and any kind switched off. With
 *   nothing left, no summary is sent.
 *
 * Owns the `summary` key of the notification state (`SummaryState`, in summaryHold.ts with the
 * calls the kinds make to hold something).
 */

/** 9 PM, in minutes since local midnight. */
export const SUMMARY_MINUTES = 21 * 60;

export const SUMMARY_TITLE = "Your day so far";

/**
 * When today's summary goes out, in minutes since local midnight: 9 PM, or when quiet hours start
 * if that's earlier in the afternoon or evening.
 */
export function summaryMinutes(quietHours: NotificationPreferences["quietHours"]): number {
  if (!quietHours || quietHours.start === quietHours.end) return SUMMARY_MINUTES;
  const start = timeMinutes(quietHours.start);
  return start >= EARLIEST_MINUTES && start < SUMMARY_MINUTES ? start : SUMMARY_MINUTES;
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

/**
 * The body's lines as of `today`, or none when nothing held is still worth saying. Each kind
 * renders its own lines, brought up to date (records.ts, closeCalls.ts, streakReminder.ts).
 */
export function summaryLines(context: NotificationContext, summary: SummaryState, today: string): string[] {
  const { row, preferences, data } = context;
  const items: string[] = [
    ...(preferences.records ? recordSummaryLines(summary.records, data.get(row.login)?.days, today) : []),
    ...(preferences.closeCalls ? closeCallSummaryLines(context, summary.closeCalls, today) : []),
  ];
  const streak = preferences.streakReminder ? streakReminderSummaryLine(context, summary.streak, today) : null;
  if (streak) items.push(streak);

  if (items.length === 0) return [];
  const standing = finish(competitorsOf(row), row.login, data, "daily", today);
  return standing ? [`#${standing.rank} today with ${formatCount(standing.mine)}`, ...items] : items;
}
