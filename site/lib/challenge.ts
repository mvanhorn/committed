/**
 * The challenge page (gitcommitted.app/vs/<challenger>/<friend>): the race the challenger shared
 * from Committed for iPhone, told from the side of the friend who opens the link. The race comes
 * from the Committed relay's public `GET /v1/race` (relay/README.md); github.com's calendars can't
 * be read from here directly. Plain TypeScript with relative imports, so `node --test` runs it.
 */

/** `GET /v1/race`'s body. */
export interface Race {
  login: string;
  rival: string;
  dates: string[];
  days: Record<string, number[]>;
  totals: Record<string, number>;
  latestLeadChange: { date: string; login: string; kind: "pulledAhead" | "passed" | "caught" } | null;
  leadChanges: number;
  updatedAt: number;
}

export const RACE_ERROR = "We couldn't load this race right now.";
const EYEBROW = "You've been challenged";

export interface Racer {
  /** "You" for the friend, the login for the challenger. */
  name: string;
  login: string;
  /** The 30-day total, grouped: "1,204". */
  total: string;
  /** Running totals, one per raced day. */
  running: number[];
  you: boolean;
}

interface Common {
  eyebrow: string;
  /** The page's `<title>` and the link preview's title. */
  title: string;
  /** The challenger, normalized; null when the URL's login isn't one. */
  challenger: string | null;
}

export type ChallengeView =
  | (Common & {
      ok: true;
      challenger: string;
      headline: string;
      subline: string;
      /** The friend first. */
      racers: [Racer, Racer];
      leadLine: string;
      /** The day the chart marks, an index into the race's days: the latest change of lead, or null. */
      markDay: number | null;
      /** The link preview's words, in the challenger's voice: "I'm 12 ahead of you, ezra-q." */
      story: string;
      /** "30 DAYS · 412 – 400": the challenger's total first. */
      score: string;
      followUrl: string;
      closing: { before: string; link: string; after: string };
    })
  | (Common & { ok: false; headline: string });

// GitHub logins: alphanumerics and single hyphens, 1–39 chars, as the relay normalizes them.
const LOGIN_PATTERN = /^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,38}$/;

/** A URL path segment, percent-decoded; a malformed escape is kept as typed rather than thrown. */
export function segment(raw: string): string {
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

/** The login GitHub and the relay would read from a URL segment, or null. */
export function normalizeLogin(raw: string): string | null {
  let login = raw.trim();
  if (login.startsWith("@")) login = login.slice(1);
  login = login.toLowerCase();
  return LOGIN_PATTERN.test(login) ? login : null;
}

/** The time zone the page races in. The link carries none, so page, title and image agree on UTC days. */
export const RACE_TIME_ZONE = "UTC";

/** The relay's race URL for a pair, or null when either segment isn't a login. */
export function raceUrl(relay: string, challenger: string, friend: string): string | null {
  const login = normalizeLogin(challenger);
  const rival = normalizeLogin(friend);
  if (!login || !rival || login === rival) return null;
  return `${relay}/v1/race?${new URLSearchParams({ login, rival, tz: RACE_TIME_ZONE })}`;
}

/** The page's words and numbers; `race` is null when it couldn't be read. `now` is Unix seconds. */
export function challengeView(challengerSegment: string, friendSegment: string, race: Race | null, now: number): ChallengeView {
  const challenger = normalizeLogin(challengerSegment);
  const friend = normalizeLogin(friendSegment);
  const title = challenger ? `${challenger} challenged you on Committed` : "You've been challenged on Committed";
  const failed = { ok: false as const, eyebrow: EYEBROW, title, challenger, headline: RACE_ERROR };
  if (!challenger || !friend || !race || race.login !== challenger || race.rival !== friend) return failed;
  const theirs = race.days[challenger];
  const yours = race.days[friend];
  if (!theirs || !yours) return failed;

  const theirTotal = race.totals[challenger] ?? 0;
  const yourTotal = race.totals[friend] ?? 0;
  const gap = format(Math.abs(theirTotal - yourTotal));
  const challengerAhead = theirTotal > yourTotal;
  const level = theirTotal === yourTotal;

  return {
    ok: true,
    eyebrow: EYEBROW,
    title,
    challenger,
    headline: level
      ? `You and ${challenger} are level.`
      : challengerAhead
        ? `${challenger} is ${gap} ahead of you.`
        : `You're ${gap} ahead of ${challenger}.`,
    subline: `Over the last ${race.dates.length} days, from both your public GitHub contribution graphs. Updated ${ago(now - race.updatedAt)}.`,
    racers: [
      { name: "You", login: friend, total: format(yourTotal), running: running(yours), you: true },
      { name: challenger, login: challenger, total: format(theirTotal), running: running(theirs), you: false },
    ],
    leadLine: leadLine(race, friend),
    markDay: race.latestLeadChange ? nullIfMissing(race.dates.indexOf(race.latestLeadChange.date)) : null,
    story: level
      ? `Dead level, ${friend}.`
      : challengerAhead
        ? `I'm ${gap} ahead of you, ${friend}.`
        : `You're ${gap} ahead of me, ${friend}. Not for long.`,
    score: `${race.dates.length} DAYS · ${format(theirTotal)} – ${format(yourTotal)}`,
    followUrl: `https://github.com/${challenger}`,
    closing: {
      before: `You're on ${challenger}'s board. Committed ranks people you follow on GitHub, so `,
      link: `follow ${challenger}`,
      after: " to race them back. Free, no account.",
    },
  };
}

/** Who passed whom, from the friend's side: "They" are the challenger. The app's race story words. */
function leadLine(race: Race, friend: string): string {
  const change = race.latestLeadChange;
  const span = `all ${race.dates.length} days`;
  if (!change) {
    const theirs = race.totals[race.login] ?? 0;
    const yours = race.totals[friend] ?? 0;
    if (theirs === yours) return `Level for ${span}.`;
    return theirs > yours ? `They've led for ${span}.` : `You've led for ${span}.`;
  }
  const you = change.login === friend;
  const on = `on ${longDate(change.date)}.`;
  switch (change.kind) {
    case "pulledAhead":
      return `${you ? "You" : "They"} pulled ahead ${on}`;
    case "caught":
      return `${you ? "You caught them" : "They caught you"} ${on}`;
    case "passed":
      return `${you ? "You passed them" : "They passed you"} ${on}` + (race.leadChanges > 1 ? ` The lead changed ${race.leadChanges} times.` : "");
  }
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

/** "2026-11-09" → "November 9", without a time zone shifting the day. */
function longDate(date: string): string {
  const [, month, day] = date.split("-").map(Number);
  return `${MONTHS[month! - 1]} ${day}`;
}

function ago(seconds: number): string {
  const minutes = Math.floor(Math.max(seconds, 0) / 60);
  if (minutes < 1) return "just now";
  const unit = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"} ago`;
  if (minutes < 60) return unit(minutes, "minute");
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return unit(hours, "hour");
  return unit(Math.floor(hours / 24), "day");
}

const nullIfMissing = (index: number) => (index < 0 ? null : index);

function running(counts: readonly number[]): number[] {
  let sum = 0;
  return counts.map((count) => (sum += count));
}

const format = (n: number) => n.toLocaleString("en-US");
