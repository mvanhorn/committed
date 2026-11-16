import type { CloseCall } from "./closeCalls";
import type { NotificationPreferences } from "./preferences";
import type { DueRecord } from "./records";
import type { NotificationState } from "./state";
import type { StreakReminder } from "./streakReminder";

/**
 * What the evening summary (#135, summary.ts) holds: the `summary` key of the notification state,
 * and the calls each kind's send step makes to hold something instead of sending it. Kept apart
 * from summary.ts, which renders and sends, so the kinds can hold without importing it (and it can
 * import their lines without a cycle).
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

/** True when the kinds' send steps should hold for the summary instead of sending. */
export function holdsForSummary(preferences: NotificationPreferences): boolean {
  return preferences.delivery === "summary";
}

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

export function readSummary(raw: unknown): SummaryState {
  const value = (typeof raw === "object" && raw !== null ? raw : {}) as Partial<SummaryState>;
  return {
    settled: typeof value.settled === "string" ? value.settled : null,
    closeCalls: Array.isArray(value.closeCalls) ? value.closeCalls : [],
    streak: typeof value.streak === "object" && value.streak !== null ? value.streak : null,
    records: Array.isArray(value.records) ? value.records : [],
  };
}
