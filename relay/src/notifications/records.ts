import type { InstallationRow } from "../db";
import { localDate, type Days } from "../parser";
import { addDays } from "../ranking";
import { sendAlert } from "./alerts";
import type { NotificationContext, NotificationDeps } from "./index";
import { isQuietHours } from "./quietHours";
import type { NotificationState } from "./state";

/**
 * Records (#134): a TypeScript port of the best day, best week and longest streak in
 * `PersonalRecords.derive` (CommitStandings/Store/PersonalRecords.swift, #127), and of the
 * records it says were broken today. Keep them in lockstep: both run the shared `records` cases
 * in fixtures/habit-conformance.json. The rules:
 *
 * - Only your calendar's days from its first day through today count. A missing day is 0 and a
 *   later day never counts.
 * - A week is Monday to Sunday (`FixedWeek`); this week counts so far.
 * - Equalling a best is never a record, and the earliest holds a tie.
 * - Broken today: today beat every earlier day; this week passed the best earlier week today;
 *   today's run became one day longer than any run before it.
 * - A notification needs an old best big enough to celebrate (`MINIMUM_OLD_BEST`).
 */

export type RecordKind = "bestDay" | "bestWeek" | "longestStreak";

/** A best, the earliest to reach it, as day keys. */
export interface RecordBest {
  value: number;
  first: string;
  last: string;
  /** The app's New badge: ends today, or this week for the best week. */
  isNew: boolean;
}

export interface BrokenRecord {
  kind: RecordKind;
  value: number;
  /** The best it beat; null when there was none. */
  oldBest: { value: number; first: string; last: string } | null;
  meetsMinimum: boolean;
  /** Which record this is, the same id the app's record card uses: the kind and today, this
   *  week's Monday, or the run's first day. */
  id: string;
}

export interface Records {
  today: string;
  bestDay: RecordBest | null;
  bestWeek: RecordBest | null;
  longestStreak: RecordBest | null;
  /** Broken today, in the order best day, best week, longest streak. */
  set: BrokenRecord[];
}

/** The smallest old best a record notification (or the app's card) celebrates. */
export const MINIMUM_OLD_BEST: Record<RecordKind, number> = { bestDay: 5, bestWeek: 1, longestStreak: 7 };

/** The Monday (`YYYY-MM-DD`) of the week containing the civil day `date`. */
export function mondayOf(date: string): string {
  const [year, month, day] = date.split("-").map(Number);
  const weekday = new Date(Date.UTC(year!, month! - 1, day!)).getUTCDay(); // Sunday 0
  return addDays(date, -((weekday + 6) % 7));
}

/** Your best day, week and streak as of the local day `today`, and the ones broken today. */
export function deriveRecords(you: Days, today: string): Records {
  const keys = Object.keys(you).sort();
  const days: string[] = [];
  // Bounded like `ContributionHistory`'s own walks.
  for (let day = keys[0]; day !== undefined && day <= today && days.length < 3_660; day = addDays(day, 1)) {
    days.push(day);
  }
  const counts = days.map((day) => you[day] ?? 0);
  const last = days.length - 1;
  const todayCount = counts[last] ?? 0;

  // Best day.
  const bestDayIndex = earliestMax(counts);
  const bestDay =
    bestDayIndex === null
      ? null
      : { value: counts[bestDayIndex]!, first: days[bestDayIndex]!, last: days[bestDayIndex]!, isNew: days[bestDayIndex] === today };

  // Weeks, in order, each over its days through today.
  const weeks: { monday: string; total: number }[] = [];
  days.forEach((day, index) => {
    const monday = mondayOf(day);
    const current = weeks.at(-1);
    if (current && current.monday === monday) current.total += counts[index]!;
    else weeks.push({ monday, total: counts[index]! });
  });
  const thisMonday = mondayOf(today);
  const weekTotals = weeks.map((week) => week.total);
  const bestWeekIndex = earliestMax(weekTotals);
  const span = (monday: string) => ({ first: monday, last: addDays(monday, 6) });
  const bestWeek =
    bestWeekIndex === null
      ? null
      : { value: weekTotals[bestWeekIndex]!, ...span(weeks[bestWeekIndex]!.monday), isNew: weeks[bestWeekIndex]!.monday === thisMonday };

  // Runs of days with a contribution, as [first, last] indices.
  const runs: [number, number][] = [];
  let runStart: number | null = null;
  counts.forEach((count, index) => {
    if (count > 0) runStart ??= index;
    else if (runStart !== null) {
      runs.push([runStart, index - 1]);
      runStart = null;
    }
  });
  if (runStart !== null) runs.push([runStart, last]);
  const length = ([first, end]: [number, number]) => end - first + 1;
  const longestIndex = earliestMax(runs.map(length));
  const longestRun = longestIndex === null ? null : runs[longestIndex]!;
  const longestStreak = longestRun && {
    value: length(longestRun),
    first: days[longestRun[0]]!,
    last: days[longestRun[1]]!,
    isNew: days[longestRun[1]] === today,
  };

  // Broken today.
  const set: BrokenRecord[] = [];
  if (days[last] === today) {
    const earlierDay = earliestMax(counts.slice(0, -1));
    const oldDay = earlierDay === null ? null : { value: counts[earlierDay]!, first: days[earlierDay]!, last: days[earlierDay]! };
    if (todayCount > (oldDay?.value ?? 0)) {
      set.push(broken("bestDay", todayCount, oldDay, `bestDay:${today}`));
    }

    const current = weeks.at(-1);
    if (current && current.monday === thisMonday) {
      const earlierWeek = earliestMax(weekTotals.slice(0, -1));
      const oldWeek = earlierWeek === null ? null : { value: weekTotals[earlierWeek]!, ...span(weeks[earlierWeek]!.monday) };
      const oldValue = oldWeek?.value ?? 0;
      if (current.total - todayCount <= oldValue && current.total > oldValue) {
        set.push(broken("bestWeek", current.total, oldWeek, `bestWeek:${thisMonday}`));
      }
    }

    const run = runs.at(-1);
    if (todayCount > 0 && run) {
      const earlierRun = earliestMax(runs.slice(0, -1).map(length));
      const oldRun =
        earlierRun === null
          ? null
          : { value: length(runs[earlierRun]!), first: days[runs[earlierRun]![0]]!, last: days[runs[earlierRun]![1]]! };
      if (length(run) === (oldRun?.value ?? 0) + 1) {
        set.push(broken("longestStreak", length(run), oldRun, `longestStreak:${days[run[0]]}`));
      }
    }
  }

  return { today, bestDay, bestWeek, longestStreak, set };
}

function broken(kind: RecordKind, value: number, oldBest: BrokenRecord["oldBest"], id: string): BrokenRecord {
  return { kind, value, oldBest, meetsMinimum: (oldBest?.value ?? 0) >= MINIMUM_OLD_BEST[kind], id };
}

/** The index of the earliest largest value above 0, or null when every value is 0. */
function earliestMax(values: readonly number[]): number | null {
  let best: number | null = null;
  values.forEach((value, index) => {
    if (value > (best === null ? 0 : values[best]!)) best = index;
  });
  return best;
}

// MARK: - Notifications

/** A record due to be announced: found broken, not sent yet. */
export interface DueRecord {
  id: string;
  kind: RecordKind;
  /** The local day it was broken. */
  day: string;
  /** The day's latest number: a held record keeps climbing with the day or week until it's sent. */
  value: number;
  oldBest: { value: number; first: string; last: string };
}

/** `notification_state.records`. */
export interface RecordsState {
  /** Ids of records already announced (the app's record ids), newest last, a few kept. */
  sent: string[];
  /** Records found but not sent yet: waiting for quiet hours to end. */
  held: DueRecord[];
}

/** Sent ids kept: far more than can be broken in the days a held record waits. */
const SENT_KEPT = 12;

/**
 * Records (spec #124, "Relay: the notification cycle"): best day, best week and longest streak,
 * each announced the first time it's broken in its day or week, when its old best meets the
 * minimum. Records due during quiet hours wait until they end, then go out with the day's latest
 * number. With Records off, nothing is found and anything held is dropped.
 *
 * Finding them (here) and sending them (`sendRecordsNow`) are separate steps, so the evening
 * summary (#135) can take the due records instead of sending them right away.
 */
export async function notifyRecords(
  context: NotificationContext,
  state: NotificationState,
  save: (state: NotificationState) => Promise<void>,
  deps: NotificationDeps,
): Promise<NotificationState> {
  const { row, preferences, data, now } = context;
  const last = parseRecordsState(state.records);
  const today = localDate(now, row.time_zone);
  const mine = data.get(row.login)?.days;

  let records: RecordsState;
  if (!preferences.records) {
    records = { sent: last.sent, held: [] };
  } else {
    const sent = [...last.sent];
    const held = [...last.held];
    for (const broken of mine ? deriveRecords(mine, today).set : []) {
      if (!broken.meetsMinimum || !broken.oldBest || sent.includes(broken.id)) continue;
      sent.push(broken.id);
      held.push({ id: broken.id, kind: broken.kind, day: today, value: broken.value, oldBest: broken.oldBest });
    }
    records = { sent: sent.slice(-SENT_KEPT), held: mine ? held.map((record) => latest(record, mine, today)) : held };
  }

  const due = records.held.length > 0 && !isQuietHours(now, row.time_zone, preferences.quietHours) ? records.held : [];
  if (due.length > 0) records = { ...records, held: [] };

  const next = { ...state, records };
  if (JSON.stringify(next.records) !== JSON.stringify(state.records ?? { sent: [], held: [] })) await save(next);
  await sendRecordsNow(row, due, today, deps);
  return next;
}

/** Sends each due record as its own alert, now. */
export async function sendRecordsNow(
  row: InstallationRow,
  records: readonly DueRecord[],
  today: string,
  deps: NotificationDeps,
): Promise<void> {
  for (const record of records) {
    if (!row.alert_token) break;
    await sendAlert(
      row,
      {
        aps: { alert: recordCopy(record, today), sound: "default", "thread-id": "records" },
        kind: "record",
        // Tapping it opens your own view.
        login: row.login,
      },
      deps,
      { collapseId: `record.${record.id}` },
    );
  }
}

/**
 * The record's copy as of the local day `today`. A record held overnight by quiet hours says when
 * it was set: "yesterday", or "last week" for a week that has ended.
 */
export function recordCopy(record: DueRecord, today: string): { title: string; body: string } {
  const value = record.value.toLocaleString("en-US");
  const old = record.oldBest.value.toLocaleString("en-US");
  switch (record.kind) {
    case "bestDay": {
      const when =
        record.day === today ? "today" : record.day === addDays(today, -1) ? "yesterday" : `on ${longDate(record.day)}`;
      return { title: "New best day", body: `${value} ${when}. Your old best was ${old}, on ${longDate(record.oldBest.first)}.` };
    }
    case "bestWeek": {
      const monday = mondayOf(record.day);
      const when =
        monday === mondayOf(today)
          ? "so far this week"
          : monday === addDays(mondayOf(today), -7)
            ? "last week"
            : `the week of ${longDate(monday)}`;
      return { title: "New best week", body: `${value} ${when}. Your old best was ${old}.` };
    }
    case "longestStreak":
      return { title: "Your longest streak yet", body: `${value} days, past your old best of ${old}.` };
  }
}

/** A held record's number brought up to date: its day's count, or its week's total through today. */
function latest(record: DueRecord, days: Days, today: string): DueRecord {
  let value = record.value;
  if (record.kind === "bestDay") value = Math.max(value, days[record.day] ?? 0);
  if (record.kind === "bestWeek") {
    const monday = mondayOf(record.day);
    const end = addDays(monday, 6) < today ? addDays(monday, 6) : today;
    let total = 0;
    for (let day = monday; day <= end; day = addDays(day, 1)) total += days[day] ?? 0;
    value = Math.max(value, total);
  }
  return value === record.value ? record : { ...record, value };
}

function parseRecordsState(raw: unknown): RecordsState {
  const value = (typeof raw === "object" && raw !== null ? raw : {}) as Partial<RecordsState>;
  return {
    sent: Array.isArray(value.sent) ? value.sent.filter((id): id is string => typeof id === "string") : [],
    held: Array.isArray(value.held) ? value.held : [],
  };
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December"];

/** "March 4", as the app's `PersonalRecords.longDate`. */
function longDate(date: string): string {
  const [, month, day] = date.split("-").map(Number);
  return `${MONTHS[(month ?? 1) - 1]} ${day}`;
}
