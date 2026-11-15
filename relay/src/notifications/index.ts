import type { ApnsSender } from "../apns";
import type { LoginData } from "../board";
import type { InstallationRow, Store } from "../db";
import type { Log } from "../relay";
import { notifyPasses } from "./passes";
import { notifyRecords } from "./records";
import { parsePreferences, type NotificationPreferences } from "./preferences";
import { parseState, type NotificationState } from "./state";

/**
 * Relay notifications (spec #124): what the cron cycle sends each installation that has
 * notification preferences, after Live rank's pushes and from the same contribution data.
 *
 * One function per kind, each in its own file (`notifyPasses` in passes.ts; close calls, results,
 * records and the streak reminder join it), each reading and returning its own part of the state.
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
  const context: NotificationContext = { row, preferences, data, now };
  let state: NotificationState = parseState(row.notification_state);

  state = await notifyPasses(context, state, (next) => saveState(row, next, deps), deps);
  state = await notifyRecords(context, state, (next) => saveState(row, next, deps), deps);
}

/** State is saved before anything is sent, so a failure mid-send can't send the same thing twice. */
async function saveState(row: InstallationRow, state: NotificationState, deps: NotificationDeps): Promise<void> {
  const json = JSON.stringify(state);
  row.notification_state = json;
  await deps.store.saveNotificationState(row.id, json);
}
