import { WINDOWS, type Window } from "../ranking";

/**
 * What the iPhone chose to hear about from the relay (spec #124, "Relay: registration"). The
 * registration's `notifications` object; null there means relay notifications are off. Every key
 * is optional on the wire and takes its default when missing, so the app can add choices later.
 */
export interface NotificationPreferences {
  /** The Window passes and close calls are judged on. */
  window: Window;
  passes: "everyone" | "rivals" | "off";
  closeCalls: boolean;
  /** Daily and weekly results. */
  results: boolean;
  records: boolean;
  streakReminder: boolean;
  /** "summary": passes now, the rest in one 9 PM notification. */
  delivery: "immediate" | "summary";
  /** Local "HH:MM" times; null = quiet hours off. */
  quietHours: { start: string; end: string } | null;
}

export const DEFAULT_PREFERENCES: NotificationPreferences = {
  window: "daily",
  passes: "everyone",
  closeCalls: false,
  results: true,
  records: true,
  streakReminder: false,
  delivery: "summary",
  quietHours: { start: "22:00", end: "08:00" },
};

const KEYS = new Set(Object.keys(DEFAULT_PREFERENCES));
const TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

/** The preferences with defaults filled in, or an error code (`parseRegistration`'s style). */
export function parsePreferences(raw: unknown): NotificationPreferences | string {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return "invalid_notifications";
  const body = raw as Record<string, unknown>;
  for (const key of Object.keys(body)) if (!KEYS.has(key)) return `unknown_field:notifications.${key}`;
  const value = <K extends keyof NotificationPreferences>(key: K): unknown =>
    key in body ? body[key] : DEFAULT_PREFERENCES[key];

  const window = value("window");
  if (typeof window !== "string" || !WINDOWS.includes(window as Window)) return "invalid_notifications_window";
  const passes = value("passes");
  if (passes !== "everyone" && passes !== "rivals" && passes !== "off") return "invalid_notifications_passes";
  const flags = {} as Pick<NotificationPreferences, "closeCalls" | "results" | "records" | "streakReminder">;
  const flagErrors = {
    closeCalls: "invalid_notifications_close_calls",
    results: "invalid_notifications_results",
    records: "invalid_notifications_records",
    streakReminder: "invalid_notifications_streak_reminder",
  } as const;
  for (const key of Object.keys(flagErrors) as (keyof typeof flagErrors)[]) {
    const flag = value(key);
    if (typeof flag !== "boolean") return flagErrors[key];
    flags[key] = flag;
  }
  const delivery = value("delivery");
  if (delivery !== "immediate" && delivery !== "summary") return "invalid_notifications_delivery";
  const quietHours = parseQuietHours(value("quietHours"));
  if (quietHours === undefined) return "invalid_quiet_hours";

  return { window: window as Window, passes, ...flags, delivery, quietHours };
}

function parseQuietHours(raw: unknown): NotificationPreferences["quietHours"] | undefined {
  if (raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) return undefined;
  const { start, end, ...rest } = raw as Record<string, unknown>;
  if (Object.keys(rest).length > 0) return undefined;
  if (typeof start !== "string" || typeof end !== "string" || !TIME.test(start) || !TIME.test(end)) return undefined;
  return { start, end };
}
