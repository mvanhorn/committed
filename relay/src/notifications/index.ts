import type { ApnsSender } from "../apns";
import type { LoginData } from "../board";
import type { InstallationRow, Store } from "../db";
import type { Log } from "../relay";
import { notifyCloseCalls } from "./closeCalls";
import { notifyPasses } from "./passes";
import { notifyRecords } from "./records";
import { parsePreferences, type NotificationPreferences } from "./preferences";
import { notifyResults, settleResultsOnEnable } from "./results";
import { parseState, type NotificationState } from "./state";
import { notifyStreakReminder } from "./streakReminder";
import { notifySummary } from "./summary";

/**
 * Relay notifications (spec #124): what the cron cycle sends each installation that has
 * notification preferences, after Live rank's pushes and from the same contribution data.
 *
 * One function per kind, each in its own file (`notifyPasses` in passes.ts; close calls, results,
 * records and the streak reminder join it), each reading and returning its own part of the state.
 * Each kind checks its own choice and returns early when off: `passes: "off"` (the iPhone's
 * Passes switch off with another kind on) skips passes only, and the kinds after it still run.
 */
export interface NotificationDeps {
  store: Store;
  apns: ApnsSender;
  log: Log;
}

export interface NotificationContext {
  row: InstallationRow;
  preferences: NotificationPreferences;
  data: ReadonlyMap<string, LoginData>;
  /** Unix seconds of this cycle. */
  now: number;
  /** Rivals a pass notification was sent about in this cycle: no close call repeats it. */
  passedThisCycle: Set<string>;
}

export async function runNotifications(
  row: InstallationRow,
  data: ReadonlyMap<string, LoginData>,
  deps: NotificationDeps,
  now: number,
): Promise<void> {
  if (!row.notifications_json || !row.alert_token) return;
  const preferences = parsePreferences(JSON.parse(row.notifications_json));
  if (typeof preferences === "string") return;
  const context: NotificationContext = { row, preferences, data, now, passedThisCycle: new Set() };
  let state: NotificationState = parseState(row.notification_state);

  state = await notifyPasses(context, state, (next) => saveState(row, next, deps), deps);
  state = await notifyCloseCalls(context, state, (next) => saveState(row, next, deps), deps);
  state = await notifyRecords(context, state, (next) => saveState(row, next, deps), deps);
  state = await notifyStreakReminder(context, state, (next) => saveState(row, next, deps), deps);
  state = await notifyResults(context, state, (next) => saveState(row, next, deps), deps);
  // Last, so anything held in this cycle can go out in it.
  state = await notifySummary(context, state, (next) => saveState(row, next, deps), deps);
}

/**
 * The notification state a registration leaves, as JSON, or null when it doesn't change it. Turning
 * results on (with relay notifications, or by its own switch) settles a morning already past, so
 * re-enabling in the afternoon doesn't send that morning's result late.
 */
export function stateOnRegistration(
  existing: InstallationRow,
  next: NotificationPreferences | null,
  timeZone: string,
  now: number,
): string | null {
  if (!next?.results) return null;
  const previous = existing.notifications_json ? parsePreferences(JSON.parse(existing.notifications_json)) : null;
  if (previous !== null && typeof previous !== "string" && previous.results) return null;
  const state = parseState(existing.notification_state);
  const settled = settleResultsOnEnable(state, timeZone, next, now);
  return settled === state ? null : JSON.stringify(settled);
}

/** State is saved before anything is sent, so a failure mid-send can't send the same thing twice. */
async function saveState(row: InstallationRow, state: NotificationState, deps: NotificationDeps): Promise<void> {
  const json = JSON.stringify(state);
  row.notification_state = json;
  await deps.store.saveNotificationState(row.id, json);
}
