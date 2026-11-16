import type { NotificationPreferences } from "./preferences";

/**
 * Quiet hours (spec #124): a nightly period when Committed doesn't make a sound. Judged on the
 * installation's own clock, from `start` (inclusive) to `end` (exclusive), wrapping past midnight
 * when `end` is earlier than `start` (the default, 22:00–08:00). Off (null), or the same start and
 * end, is never quiet.
 *
 * Every kind follows it: passes go out passively with no sound; later kinds hold or skip their
 * notifications (close calls and the streak reminder skip, results wait, the summary moves up).
 */
export function isQuietHours(
  unixSeconds: number,
  timeZone: string,
  quietHours: NotificationPreferences["quietHours"],
): boolean {
  if (!quietHours) return false;
  const start = timeMinutes(quietHours.start);
  const end = timeMinutes(quietHours.end);
  if (start === end) return false;
  const now = localMinutes(unixSeconds, timeZone);
  return start < end ? now >= start && now < end : now >= start || now < end;
}

/** Minutes since local midnight at `unixSeconds` in the IANA `timeZone`. */
export function localMinutes(unixSeconds: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(unixSeconds * 1000));
  const get = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0);
  // Some engines still say "24" for midnight; it's 0.
  return (get("hour") % 24) * 60 + get("minute");
}

/** "HH:MM" → minutes since midnight. */
export function timeMinutes(time: string): number {
  const [hours = 0, mins = 0] = time.split(":").map(Number);
  return hours * 60 + mins;
}

/**
 * Noon, in minutes since midnight: the earliest quiet hours can move an evening send up to (the
 * streak reminder an hour before they start, the summary to their start). Quiet hours starting in
 * the morning, or just after midnight, leave those at their usual evening time.
 */
export const EARLIEST_MINUTES = 12 * 60;
