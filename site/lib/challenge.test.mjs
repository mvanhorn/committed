import assert from "node:assert/strict";
import { test } from "node:test";
import { challengeView, RACE_ERROR, segment } from "./challenge.ts";

// 2026-11-15 12:00 UTC.
const NOW = 1_794_744_000;

const DATES = Array.from({ length: 30 }, (_, i) => {
  const date = new Date(Date.UTC(2026, 9, 17 + i));
  return date.toISOString().slice(0, 10);
});

/** A /v1/race body: addisonk challenged ezra-q. Each total lands on the first day. */
function race({ addisonk, ezra, latestLeadChange = null, leadChanges = 0, updatedAt = NOW - 180 }) {
  const days = (total) => [total, ...Array(29).fill(0)];
  return {
    login: "addisonk",
    rival: "ezra-q",
    dates: DATES,
    days: { addisonk: days(addisonk), "ezra-q": days(ezra) },
    totals: { addisonk, "ezra-q": ezra },
    latestLeadChange,
    leadChanges,
    updatedAt,
  };
}

test("the challenger ahead: told from the friend's side", () => {
  const view = challengeView("addisonk", "ezra-q", race({ addisonk: 412, ezra: 400 }), NOW);
  assert.equal(view.eyebrow, "You've been challenged");
  assert.equal(view.headline, "addisonk is 12 ahead of you.");
  assert.equal(view.subline, "Over the last 30 days, from both your public GitHub contribution graphs. Updated 3 minutes ago.");
  assert.equal(view.title, "addisonk challenged you on Committed");
  assert.equal(view.story, "I'm 12 ahead of you, ezra-q.");
  assert.equal(view.score, "30 DAYS · 412 – 400");
});

test("the friend ahead", () => {
  const view = challengeView("addisonk", "ezra-q", race({ addisonk: 395, ezra: 400 }), NOW);
  assert.equal(view.headline, "You're 5 ahead of addisonk.");
  assert.equal(view.story, "You're 5 ahead of me, ezra-q. Not for long.");
  assert.equal(view.score, "30 DAYS · 395 – 400");
});

test("level", () => {
  const view = challengeView("addisonk", "ezra-q", race({ addisonk: 400, ezra: 400 }), NOW);
  assert.equal(view.headline, "You and addisonk are level.");
  assert.equal(view.story, "Dead level, ezra-q.");
});

test("big gaps are grouped", () => {
  const view = challengeView("addisonk", "ezra-q", race({ addisonk: 2412, ezra: 400 }), NOW);
  assert.equal(view.headline, "addisonk is 2,012 ahead of you.");
  assert.equal(view.score, "30 DAYS · 2,412 – 400");
});

test("the race card: You first, with both totals and running totals", () => {
  const view = challengeView("addisonk", "ezra-q", race({ addisonk: 412, ezra: 400 }), NOW);
  assert.deepEqual(
    view.racers.map(({ name, login, total, you }) => ({ name, login, total, you })),
    [
      { name: "You", login: "ezra-q", total: "400", you: true },
      { name: "addisonk", login: "addisonk", total: "412", you: false },
    ],
  );
  assert.equal(view.racers[0].running.length, 30);
  assert.equal(view.racers[0].running.at(-1), 400);
  assert.equal(view.racers[1].running[0], 412);
  assert.equal(view.followUrl, "https://github.com/addisonk");
});

test("the lead line, from the friend's side", () => {
  const cases = [
    [{ date: "2026-11-09", login: "addisonk", kind: "passed" }, 1, "They passed you on November 9."],
    [{ date: "2026-11-09", login: "ezra-q", kind: "passed" }, 1, "You passed them on November 9."],
    [{ date: "2026-11-09", login: "addisonk", kind: "passed" }, 3, "They passed you on November 9. The lead changed 3 times."],
    [{ date: "2026-10-21", login: "addisonk", kind: "pulledAhead" }, 0, "They pulled ahead on October 21."],
    [{ date: "2026-10-21", login: "ezra-q", kind: "pulledAhead" }, 0, "You pulled ahead on October 21."],
    [{ date: "2026-11-01", login: "addisonk", kind: "caught" }, 0, "They caught you on November 1."],
    [{ date: "2026-11-01", login: "ezra-q", kind: "caught" }, 0, "You caught them on November 1."],
  ];
  for (const [latestLeadChange, leadChanges, line] of cases) {
    const view = challengeView("addisonk", "ezra-q", race({ addisonk: 412, ezra: 400, latestLeadChange, leadChanges }), NOW);
    assert.equal(view.leadLine, line);
  }
  assert.equal(challengeView("addisonk", "ezra-q", race({ addisonk: 412, ezra: 400 }), NOW).leadLine, "They've led for all 30 days.");
  assert.equal(challengeView("addisonk", "ezra-q", race({ addisonk: 1, ezra: 400 }), NOW).leadLine, "You've led for all 30 days.");
  assert.equal(challengeView("addisonk", "ezra-q", race({ addisonk: 0, ezra: 0 }), NOW).leadLine, "Level for all 30 days.");
});

test("how long ago the counts were read", () => {
  const updated = (seconds) => challengeView("addisonk", "ezra-q", race({ addisonk: 1, ezra: 1, updatedAt: NOW - seconds }), NOW).subline;
  assert.match(updated(20), /Updated just now\.$/);
  assert.match(updated(60), /Updated 1 minute ago\.$/);
  assert.match(updated(59 * 60), /Updated 59 minutes ago\.$/);
  assert.match(updated(2 * 3600 + 5), /Updated 2 hours ago\.$/);
  assert.match(updated(3 * 86_400), /Updated 3 days ago\.$/);
});

test("the closing copy names the challenger", () => {
  const view = challengeView("addisonk", "ezra-q", race({ addisonk: 412, ezra: 400 }), NOW);
  assert.deepEqual(view.closing, {
    before: "You're on addisonk's board. Committed ranks people you follow on GitHub, so ",
    link: "follow addisonk",
    after: " to race them back. Free, no account.",
  });
});

test("the URL's logins are read like GitHub reads them", () => {
  const view = challengeView("AddisonK", "@Ezra-Q", race({ addisonk: 412, ezra: 400 }), NOW);
  assert.equal(view.ok, true);
  assert.equal(view.headline, "addisonk is 12 ahead of you.");
});

test("a failed read still names the challenger and offers the download", () => {
  const view = challengeView("addisonk", "ezra-q", null, NOW);
  assert.equal(view.ok, false);
  assert.equal(view.eyebrow, "You've been challenged");
  assert.equal(view.headline, RACE_ERROR);
  assert.equal(RACE_ERROR, "We couldn't load this race right now.");
  assert.equal(view.title, "addisonk challenged you on Committed");
});

test("a race for other logins than the URL's is a failed read", () => {
  const view = challengeView("someone", "ezra-q", race({ addisonk: 412, ezra: 400 }), NOW);
  assert.equal(view.ok, false);
});

test("a malformed login is a failed read with a generic title", () => {
  const view = challengeView("not a login!", "ezra-q", null, NOW);
  assert.equal(view.ok, false);
  assert.equal(view.title, "You've been challenged on Committed");
});

test("the chart marks the day the lead last changed", () => {
  const passed = race({ addisonk: 412, ezra: 400, latestLeadChange: { date: "2026-11-09", login: "addisonk", kind: "passed" }, leadChanges: 1 });
  assert.equal(challengeView("addisonk", "ezra-q", passed, NOW).markDay, 23);
  assert.equal(challengeView("addisonk", "ezra-q", race({ addisonk: 412, ezra: 400 }), NOW).markDay, null);
});

test("a URL segment decodes, and a malformed one never throws", () => {
  assert.equal(segment("%40ezra-q"), "@ezra-q");
  assert.equal(segment("%"), "%");
  assert.equal(segment("%E0%A4%A"), "%E0%A4%A");
  assert.equal(challengeView(segment("%"), "ezra-q", null, NOW).ok, false);
});
