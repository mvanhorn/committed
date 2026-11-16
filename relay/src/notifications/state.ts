import type { Window } from "../ranking";

/**
 * Per-installation notification state, stored as one JSON object in `notification_state`. Each
 * kind owns its own key; code that updates one kind must keep the keys it doesn't own, so later
 * kinds (close calls, results, records, the streak reminder, the evening summary) extend this shape
 * without a migration. It never holds tokens.
 */
export interface NotificationState {
  passes?: PassesState;
  closeCalls?: CloseCallsState;
  /** Keys added by later kinds, kept as they are. */
  [kind: string]: unknown;
}

/** The last counts passes were judged on. */
export interface PassesState {
  window: Window;
  /** The installation's local date (`YYYY-MM-DD`) of the snapshot: a new day takes a fresh baseline. */
  date: string;
  /** Login → contributions in `window`, for the visible people with data, you included. */
  counts: Record<string, number>;
}

/** Who got a close call today: at most one per person per local day. */
export interface CloseCallsState {
  /** The installation's local date (`YYYY-MM-DD`) the markers are for. */
  date: string;
  /** Logins sent a close call on `date`. */
  sent: string[];
}

export function parseState(raw: string | null): NotificationState {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as unknown;
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed) ? (parsed as NotificationState) : {};
  } catch {
    return {};
  }
}
