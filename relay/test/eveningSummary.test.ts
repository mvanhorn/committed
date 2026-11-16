import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { addDays } from "../src/ranking";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub } from "./support/fakes";

/**
 * The evening summary (#135) through the cron cycle: a fake GitHub, a fake APNs that records each
 * alert, and a fake clock stepped through the day. In delivery "summary" (the default), close
 * calls, records and the streak reminder are held, and one "Your day so far" goes out at 9 PM, or
 * when quiet hours start if that's earlier, only when something was held.
 */

const SECRET = "k".repeat(40);
const ALERT = "cd".repeat(32);
const BUNDLE = "com.example.app";
const ID = "inst-0135";
const TODAY = "2026-11-05";

/** Local time in New York (UTC−5 in November) on Thursday, November 5, 2026, as Unix seconds. */
const at = (hour: number, minute = 0, dayOffset = 0) => Date.UTC(2026, 10, 5 + dayOffset, hour + 5, minute) / 1000;

let apns: FakeApns;
let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  apns = new FakeApns();
  github = new FakeGitHub();
  clock = new Clock(at(12));
  relay = createRelay({ db: env.DB, apns, github: github.fetch, githubName: github.name, now: clock.now, bundleId: BUNDLE, log: () => {} });
});

/** A calendar with `streak` days in a row of 2 contributions ending yesterday, and `today` today. */
function calendar(streak: number, today = 0): Record<string, number> {
  const days: Record<string, number> = { [TODAY]: today, [addDays(TODAY, -streak - 1)]: 0 };
  for (let back = 1; back <= streak; back += 1) days[addDays(TODAY, -back)] = 2;
  return days;
}

/** Registers relay notifications in summary delivery (the default), passes and results off. */
async function registerAt(
  seconds: number,
  notifications: Record<string, unknown> = {},
  rivals: string[] = [],
  competitors = ["me", "odile-m", "bob"],
) {
  clock.seconds = seconds;
  const res = await relay.fetch(
    new Request(`https://relay.test/v1/installations/${ID}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: JSON.stringify({
        pushToStartToken: null,
        login: "me",
        competitors,
        window: "daily",
        timeZone: "America/New_York",
        apnsEnvironment: "production",
        liveRank: false,
        alertToken: ALERT,
        notifications: { passes: "off", results: false, ...notifications },
        rivals,
      }),
    }),
  );
  expect(res.ok).toBe(true);
}

/** Runs one cycle at `seconds`; returns every alert sent so far. */
async function cycleAt(seconds: number) {
  clock.seconds = seconds;
  await relay.runCycle();
  return apns.alerts;
}

const summaries = () => apns.alerts.filter((alert) => alert.payload.kind === "summary");

describe("evening summary", () => {
  it("holds the streak reminder and sends it in one summary at 9 PM, opening the Board", async () => {
    github.set("me", calendar(40));
    github.set("odile-m", { [TODAY]: 3 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(19, 50), { streakReminder: true });

    expect(await cycleAt(at(20, 0))).toHaveLength(0);
    expect(await cycleAt(at(20, 55))).toHaveLength(0);
    const sent = await cycleAt(at(21, 0));
    expect(sent).toHaveLength(1);
    const push = sent[0]!;
    expect(push.token).toBe(ALERT);
    expect(push.collapseId).toBe("summary");
    expect(push.payload).toEqual({
      aps: {
        alert: {
          title: "Your day so far",
          body: "#3 today with 0 · Your 40-day streak needs one contribution by midnight",
        },
        sound: "default",
        "thread-id": "summary",
      },
      kind: "summary",
    });
    // Once a day.
    expect(await cycleAt(at(21, 30))).toHaveLength(1);
  });

  it("holds records and close calls, with the day's latest numbers", async () => {
    // Earlier days of 33 and 30 make a best week of 63, so 41 is only a best day.
    const history = { "2026-10-20": 33, "2026-10-21": 30 };
    github.set("me", { ...history, [TODAY]: 41 });
    github.set("odile-m", { [TODAY]: 10 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(10), { closeCalls: true });

    expect(await cycleAt(at(10, 5))).toHaveLength(0); // the record is held

    // Later, odile-m is 2 ahead: a close call, held. You've also gone on to 47.
    github.set("me", { ...history, [TODAY]: 47 });
    github.set("odile-m", { [TODAY]: 49 });
    expect(await cycleAt(at(18))).toHaveLength(0);

    expect(await cycleAt(at(21))).toHaveLength(1);
    expect(summaries()[0]!.payload.aps.alert).toEqual({
      title: "Your day so far",
      body: "#2 today with 47 · New best day: 47 · Close call: 2 to pass odile-m",
    });
  });

  it("drops a close call you've closed by the time it's sent", async () => {
    const history = { "2026-10-20": 33, "2026-10-21": 30 };
    github.set("me", { ...history, [TODAY]: 47 });
    github.set("odile-m", { [TODAY]: 49 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(18), { closeCalls: true });
    expect(await cycleAt(at(18, 5))).toHaveLength(0);

    github.set("me", { ...history, [TODAY]: 50 });
    expect(await cycleAt(at(21))).toHaveLength(1);
    expect(summaries()[0]!.payload.aps.alert.body).toBe("#1 today with 50 · New best day: 50");
  });

  it("drops a close call that's no longer close by the time it's sent", async () => {
    github.set("me", { [TODAY]: 31 });
    github.set("odile-m", { [TODAY]: 33 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(18), { closeCalls: true, records: false });
    expect(await cycleAt(at(18, 5))).toHaveLength(0);

    // odile-m pulled 13 ahead: past the close-call margin of 3.
    github.set("odile-m", { [TODAY]: 44 });
    expect(await cycleAt(at(21))).toHaveLength(0);
  });

  it("never names someone no longer on your board", async () => {
    github.set("me", { [TODAY]: 31 });
    github.set("odile-m", { [TODAY]: 33 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(18), { closeCalls: true, records: false });
    expect(await cycleAt(at(18, 5))).toHaveLength(0);

    // You hid odile-m: the board the relay has no longer includes them.
    await registerAt(at(19), { closeCalls: true, records: false }, [], ["me", "bob"]);
    expect(await cycleAt(at(21))).toHaveLength(0);
  });

  it("says a best week with its latest number, and lists records day, week, streak", async () => {
    // A best week of 10 (Oct 26–27, its best day 6); this week reaches 11 today, with no best day.
    github.set("me", { "2026-10-26": 6, "2026-10-27": 4, "2026-11-02": 3, "2026-11-03": 3, [TODAY]: 5 });
    github.set("odile-m", { [TODAY]: 3 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(10));
    expect(await cycleAt(at(10, 5))).toHaveLength(0);
    // Later, 7 today: past the old best day of 6 too, found after the best week but listed first.
    github.set("me", { "2026-10-26": 6, "2026-10-27": 4, "2026-11-02": 3, "2026-11-03": 3, [TODAY]: 7 });
    await cycleAt(at(21));
    expect(summaries().map((alert) => alert.payload.aps.alert.body)).toEqual([
      "#1 today with 7 · New best day: 7 · New best week: 13",
    ]);
  });

  it("says a longest streak in days", async () => {
    // A 7-day run in October; today makes this run 8 days, 2 a day (no best day or week).
    const days: Record<string, number> = {};
    for (let day = 1; day <= 7; day += 1) days[`2026-10-0${day}`] = 2;
    for (let back = 0; back < 8; back += 1) days[addDays(TODAY, -back)] = 2;
    github.set("me", days);
    github.set("odile-m", { [TODAY]: 3 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(10));
    await cycleAt(at(21));
    expect(summaries().map((alert) => alert.payload.aps.alert.body)).toEqual([
      "#2 today with 2 · Your longest streak yet: 8 days",
    ]);
  });

  it("sends nothing when nothing was held", async () => {
    // You've contributed (no reminder), and odile-m is 6 ahead (too far for a close call).
    github.set("me", calendar(40, 3));
    github.set("odile-m", { [TODAY]: 9 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(19), { streakReminder: true, closeCalls: true });
    for (const hour of [20, 21, 22, 23]) expect(await cycleAt(at(hour))).toHaveLength(0);
  });

  it("sends nothing when everything held has been answered", async () => {
    github.set("me", calendar(40));
    github.set("odile-m", { [TODAY]: 3 });
    github.set("bob", { [TODAY]: 1 });
    await registerAt(at(19, 50), { streakReminder: true });
    expect(await cycleAt(at(20))).toHaveLength(0);

    // You contributed before 9 PM: the reminder has nothing left to say, so there's no summary.
    github.set("me", calendar(40, 1));
    expect(await cycleAt(at(21))).toHaveLength(0);
  });

  describe("timing", () => {
    it("goes out when quiet hours start, if that's before 9 PM, and not again at 9", async () => {
      github.set("me", calendar(12));
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(19), { streakReminder: true, quietHours: { start: "20:30", end: "07:00" } });

      expect(await cycleAt(at(19, 30))).toHaveLength(0); // the reminder, an hour before, is held
      expect(await cycleAt(at(20, 25))).toHaveLength(0);
      const sent = await cycleAt(at(20, 30));
      expect(sent).toHaveLength(1);
      // Quiet hours start with it: it still makes its sound.
      expect(sent[0]!.payload.aps.sound).toBe("default");
      expect(sent[0]!.payload.aps["interruption-level"]).toBeUndefined();
      expect(await cycleAt(at(21))).toHaveLength(1);
    });

    it("stays at 9 PM when quiet hours start later, or in the morning", async () => {
      github.set("me", calendar(12));
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(19), { streakReminder: true, quietHours: { start: "06:00", end: "11:00" } });
      expect(await cycleAt(at(20))).toHaveLength(0);
      expect(await cycleAt(at(20, 55))).toHaveLength(0);
      expect(await cycleAt(at(21))).toHaveLength(1);
    });

    it("a run late into quiet hours sends it without a sound", async () => {
      github.set("me", calendar(12));
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(19, 50), { streakReminder: true });
      expect(await cycleAt(at(20))).toHaveLength(0);
      // No cycle ran from 9 PM until well after quiet hours started at 10.
      const sent = await cycleAt(at(22, 30));
      expect(sent).toHaveLength(1);
      expect(sent[0]!.payload.aps.sound).toBeUndefined();
      expect(sent[0]!.payload.aps["interruption-level"]).toBe("passive");
    });
  });

  describe("what's held after tonight's summary", () => {
    it("drops a close call found after 9 PM: tomorrow it's a new day", async () => {
      github.set("me", { [TODAY]: 31 });
      github.set("odile-m", { [TODAY]: 10 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(20), { closeCalls: true, records: false });
      expect(await cycleAt(at(21))).toHaveLength(0);

      github.set("odile-m", { [TODAY]: 33 });
      expect(await cycleAt(at(21, 30))).toHaveLength(0);
      expect(await cycleAt(at(21, 0, 1))).toHaveLength(0);
    });

    it("sends a record set during quiet hours in the next evening's summary, saying when", async () => {
      const history = { "2026-10-20": 33, "2026-10-21": 30 };
      github.set("me", { ...history, [TODAY]: 41 });
      github.set("odile-m", { [TODAY]: 10, "2026-11-06": 3 });
      github.set("bob", { [TODAY]: 1 });
      // Registered at 11 PM, inside quiet hours: the record waits for them to end.
      await registerAt(at(23));
      expect(await cycleAt(at(23, 5))).toHaveLength(0);
      expect(await cycleAt(at(8, 5, 1))).toHaveLength(0); // quiet hours over: held for the summary

      github.set("me", { ...history, [TODAY]: 41, "2026-11-06": 0 });
      expect(await cycleAt(at(21, 0, 1))).toHaveLength(1);
      expect(summaries()[0]!.payload.aps.alert.body).toBe("#2 today with 0 · New best day: 41 yesterday");
    });
  });

  describe("changing your choices", () => {
    it("what's held for tonight still goes out after switching to Right away", async () => {
      github.set("me", calendar(40));
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(19, 50), { streakReminder: true });
      expect(await cycleAt(at(20))).toHaveLength(0);

      await registerAt(at(20, 10), { streakReminder: true, delivery: "immediate" });
      expect(await cycleAt(at(20, 15))).toHaveLength(0);
      expect(await cycleAt(at(21))).toHaveLength(1);
      expect(summaries()).toHaveLength(1);
    });

    it("turning a kind off drops what it had held", async () => {
      github.set("me", calendar(40));
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(19, 50), { streakReminder: true });
      expect(await cycleAt(at(20))).toHaveLength(0);

      await registerAt(at(20, 10), { streakReminder: false });
      expect(await cycleAt(at(21))).toHaveLength(0);
    });
  });

  describe("unaffected", () => {
    it("Right away sends the streak reminder at 8 PM and no summary", async () => {
      github.set("me", calendar(40));
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(19, 50), { streakReminder: true, delivery: "immediate" });

      const sent = await cycleAt(at(20));
      expect(sent.map((alert) => alert.payload.kind)).toEqual(["streakReminder"]);
      await cycleAt(at(21));
      await cycleAt(at(21, 30));
      expect(summaries()).toHaveLength(0);
    });

    it("passes still arrive right away in summary delivery", async () => {
      github.set("me", { [TODAY]: 5 });
      github.set("odile-m", { [TODAY]: 3 });
      github.set("bob", { [TODAY]: 1 });
      await registerAt(at(14), { passes: "everyone" });
      expect(await cycleAt(at(14, 5))).toHaveLength(0); // the baseline

      github.set("odile-m", { [TODAY]: 7 });
      const sent = await cycleAt(at(14, 10));
      expect(sent.map((alert) => alert.payload.kind)).toEqual(["pass"]);
    });

    it("results still arrive in the morning in summary delivery", async () => {
      github.set("me", { [TODAY]: 5, "2026-11-06": 0 });
      github.set("odile-m", { [TODAY]: 3, "2026-11-06": 0 });
      github.set("bob", { [TODAY]: 1, "2026-11-06": 0 });
      await registerAt(at(14), { results: true });
      expect(await cycleAt(at(14, 5))).toHaveLength(0);

      const sent = await cycleAt(at(8, 0, 1));
      expect(sent.map((alert) => alert.payload.kind)).toEqual(["result"]);
    });
  });
});
