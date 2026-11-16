import { loadContributions } from "./cycle";
import type { Store } from "./db";
import { isValidTimeZone, localDate } from "./parser";
import { addDays, windowStart } from "./ranking";
import type { GitHubFetch, Log } from "./relay";

/**
 * `GET /v1/race` (public): two people's race over the Board's 30 days Window, for the challenge
 * page (gitcommitted.app/vs/<login>/<rival>). Like `GET /v1/board`, it's unauthenticated,
 * stateless and computed on request from the shared contribution cache; it stores nothing but
 * the per-login cache, and costs at most two GitHub fetches.
 */

export interface RaceQuery {
  login: string;
  rival: string;
  timeZone: string;
}

/** How the lead last changed hands, in the app's words (`PersonSummary.Story`). */
export type LeadChangeKind = "pulledAhead" | "passed" | "caught";

export interface Race {
  login: string;
  rival: string;
  /** The 30 raced days, oldest first, ending today in `tz`. */
  dates: string[];
  /** Each login's count per day of `dates`. */
  days: Record<string, number[]>;
  /** Each login's 30-day total: what the Board ranks on 30 days. */
  totals: Record<string, number>;
  /** The latest change of lead over the running totals, or null when nobody ever took one. */
  latestLeadChange: { date: string; login: string; kind: LeadChangeKind } | null;
  /** How many times the lead changed hands. */
  leadChanges: number;
  /** Unix seconds of the older of the two counts. */
  updatedAt: number;
}

/** Parses `?login=&rival=&tz=`, or returns an error code. */
export function parseRaceQuery(params: URLSearchParams, normalizeLogin: (raw: unknown) => string | null): RaceQuery | string {
  const login = normalizeLogin(params.get("login"));
  if (!login) return "invalid_login";
  const rival = normalizeLogin(params.get("rival"));
  if (!rival || rival === login) return "invalid_rival";
  const timeZone = params.get("tz") ?? "UTC";
  if (!isValidTimeZone(timeZone)) return "invalid_time_zone";
  return { login, rival, timeZone };
}

/** The race, or null when either calendar can't be read (an unknown login, or GitHub failing with nothing cached). */
export async function raceState(
  query: RaceQuery,
  deps: { store: Store; github: GitHubFetch; log: Log; now: number },
): Promise<Race | null> {
  const data = await loadContributions([query.login, query.rival], deps, deps.now);
  const mine = data.get(query.login);
  const theirs = data.get(query.rival);
  if (!mine || !theirs) return null;

  const today = localDate(deps.now, query.timeZone);
  const first = windowStart("monthly", today);
  const dates = Array.from({ length: 30 }, (_, i) => addDays(first, i));
  const yours = dates.map((date) => mine.days[date] ?? 0);
  const rivals = dates.map((date) => theirs.days[date] ?? 0);
  const story = leadStory(running(yours), running(rivals));
  const sideLogin = (side: Side) => (side === "login" ? query.login : query.rival);

  return {
    login: query.login,
    rival: query.rival,
    dates,
    days: { [query.login]: yours, [query.rival]: rivals },
    totals: { [query.login]: total(yours), [query.rival]: total(rivals) },
    latestLeadChange: story.latest
      ? { date: dates[story.latest.day]!, login: sideLogin(story.latest.side), kind: story.latest.kind }
      : null,
    leadChanges: story.changes,
    updatedAt: Math.min(mine.fetchedAt, theirs.fetchedAt),
  };
}

type Side = "login" | "rival";

const total = (counts: readonly number[]) => counts.reduce((sum, count) => sum + count, 0);

function running(counts: readonly number[]): number[] {
  let sum = 0;
  return counts.map((count) => (sum += count));
}

/**
 * Port of `PersonSummary.Story.of` (the Windows core's `history::race_story` follows the same
 * rules). A level day keeps whoever led before it, so only a strict lead counts as passing.
 * `day` is a 0-based index into the race's dates.
 */
function leadStory(
  login: readonly number[],
  rival: readonly number[],
): { latest: { side: Side; day: number; kind: LeadChangeKind } | null; changes: number } {
  const days = Math.min(login.length, rival.length);
  const leader = (i: number): Side | null => (rival[i]! > login[i]! ? "rival" : login[i]! > rival[i]! ? "login" : null);
  let leading: Side | null = null;
  let firstLead = 0;
  let changes = 0;
  let lastChange = 0;
  for (let i = 0; i < days; i++) {
    const side = leader(i);
    if (side === null) continue;
    if (leading === null) {
      leading = side;
      firstLead = i;
    } else if (side !== leading) {
      leading = side;
      changes += 1;
      lastChange = i;
    }
  }
  if (leading === null) return { latest: null, changes };
  if (days > 0 && leader(days - 1) === null) {
    let start = days - 1;
    while (start > 0 && leader(start - 1) === null) start -= 1;
    return { latest: { side: leading === "login" ? "rival" : "login", day: start, kind: "caught" }, changes };
  }
  if (changes > 0) return { latest: { side: leading, day: lastChange, kind: "passed" }, changes };
  return { latest: firstLead === 0 ? null : { side: leading, day: firstLead, kind: "pulledAhead" }, changes };
}
