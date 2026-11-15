import { STALE_AFTER_SECONDS } from "../apns";
import type { InstallationRow } from "../db";
import { currentStreak, localDate, sum } from "../parser";
import { sendAlert } from "./alerts";
import type { NotificationContext, NotificationDeps } from "./index";
import type { NotificationPreferences } from "./preferences";
import { isQuietHours, localMinutes } from "./quietHours";
import type { NotificationState } from "./state";
import { holdStreakReminder, holdsForSummary } from "./summary";

/**
 * The streak reminder (#133, spec #124): "Your 40-day streak" / "Nothing yet today. It keeps going
 * if you contribute by midnight." Sent at 8 PM in your time zone, or an hour before quiet hours
 * start when that's earlier, while your streak is at least 2 days and today has no contributions.
 * At most once a day, and never during quiet hours. Tapping it opens your own view (the payload
 * carries your login).
 *
 * Owns the `streak` key of the notification state: `{ "date": "YYYY-MM-DD" }`, the local day the
 * last reminder was sent (saved before sending).
 */

export interface StreakReminderState {
  /** The installation's local date of the last reminder. */
  date: string;
}

/** A reminder that's due now: what `sendStreakReminder` sends, or the evening summary holds (#135). */
export interface StreakReminder {
  /** Your current streak, at least 2. */
  streak: number;
  /** The installation's local date it's for. */
  date: string;
}

/** 8 PM, in minutes since local midnight. */
export const REMINDER_MINUTES = 20 * 60;
/** The hour before quiet hours counts only when it falls in the afternoon or evening. */
const EARLIEST_MINUTES = 12 * 60;

/**
 * When today's reminder is due, in minutes since local midnight: 8 PM, or an hour before quiet
 * hours start if that's earlier. Quiet hours that start in the morning (or just after midnight,
 * whose hour before is the previous evening's) never move it before noon: the reminder then stays
 * at 8 PM, and is skipped if that's inside quiet hours.
 */
export function reminderMinutes(quietHours: NotificationPreferences["quietHours"]): number {
  if (!quietHours || quietHours.start === quietHours.end) return REMINDER_MINUTES;
  const [hours = 0, minutes = 0] = quietHours.start.split(":").map(Number);
  const beforeQuiet = hours * 60 + minutes - 60;
  return beforeQuiet >= EARLIEST_MINUTES && beforeQuiet < REMINDER_MINUTES ? beforeQuiet : REMINDER_MINUTES;
}

/** The copy, in the design voice: second person, no emoji, never scolding. */
export function streakReminderCopy(streak: number): { title: string; body: string } {
  return {
    title: `Your ${streak}-day streak`,
    body: "Nothing yet today. It keeps going if you contribute by midnight.",
  };
}

/**
 * The reminder due in this cycle, or null: the switch is on, it's past today's reminder time and
 * outside quiet hours, none was sent today, your count is fresh (stale data could wrongly say
 * "nothing yet"), today has 0 and your streak is at least 2.
 */
export function streakReminderDue(context: NotificationContext, state: NotificationState): StreakReminder | null {
  const { row, preferences, data, now } = context;
  if (!preferences.streakReminder) return null;
  const today = localDate(now, row.time_zone);
  if (parseStreakState(state.streak)?.date === today) return null;
  if (localMinutes(now, row.time_zone) < reminderMinutes(preferences.quietHours)) return null;
  if (isQuietHours(now, row.time_zone, preferences.quietHours)) return null;
  const mine = data.get(row.login);
  if (!mine || now - mine.fetchedAt > STALE_AFTER_SECONDS) return null;
  if (sum(mine.days, "daily", today) > 0) return null;
  const streak = currentStreak(mine.days, today);
  return streak >= 2 ? { streak, date: today } : null;
}

/** The kind's step in the cycle: marks the day, then sends the reminder right away. */
export async function notifyStreakReminder(
  context: NotificationContext,
  state: NotificationState,
  save: (state: NotificationState) => Promise<void>,
  deps: NotificationDeps,
): Promise<NotificationState> {
  // A token cleared earlier in this run (a dead one) mustn't use up today's reminder.
  if (!context.row.alert_token) return state;
  const reminder = streakReminderDue(context, state);
  if (!reminder) return state;
  const streak: StreakReminderState = { date: reminder.date };
  // In summary delivery the evening summary (#135) holds it; otherwise it goes now.
  const summary = holdsForSummary(context.preferences);
  const next = summary ? holdStreakReminder({ ...state, streak }, reminder) : { ...state, streak };
  await save(next);
  if (!summary) await sendStreakReminder(context.row, reminder, deps);
  return next;
}

/** Sends one streak reminder now. */
export async function sendStreakReminder(
  row: InstallationRow,
  reminder: StreakReminder,
  deps: NotificationDeps,
): Promise<boolean> {
  return sendAlert(
    row,
    {
      aps: { alert: streakReminderCopy(reminder.streak), sound: "default", "thread-id": "streak" },
      kind: "streakReminder",
      // Your own login: a tap opens your own view.
      login: row.login,
    },
    deps,
    { collapseId: "streak" },
  );
}

function parseStreakState(raw: unknown): StreakReminderState | null {
  if (typeof raw !== "object" || raw === null) return null;
  const date = (raw as Record<string, unknown>).date;
  return typeof date === "string" ? { date } : null;
}
