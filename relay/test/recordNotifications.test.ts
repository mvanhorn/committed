import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub, MINUTE } from "./support/fakes";

/**
 * Record notifications (#134) through the cron cycle: a fake GitHub, a fake APNs that records each
 * alert, and a fake clock stepped through the day. The rules themselves are held to the app's by
 * habitRecords.test.ts; these cover when the relay sends them, and what they say.
 */

const SECRET = "k".repeat(40);
const ALERT = "ab".repeat(32);
const BUNDLE = "com.example.app";
const ID = "inst-0134";

/** Local time in New York (UTC−5 in November after Nov 1) as Unix seconds. */
const ny = (day: number, hour: number, minute = 0) => Date.UTC(2026, 10, day, hour + 5, minute) / 1000;

let apns: FakeApns;
let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  apns = new FakeApns();
  github = new FakeGitHub();
  // Thursday, November 5, 2026, 10:00 in New York.
  clock = new Clock(ny(5, 10));
  relay = createRelay({ db: env.DB, apns, github: github.fetch, githubName: github.name, now: clock.now, bundleId: BUNDLE, log: () => {} });
  github.set("alice", { "2026-11-05": 1 });
});

async function register(notifications: Record<string, unknown> = {}) {
  const res = await relay.fetch(
    new Request(`https://relay.test/v1/installations/${ID}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: JSON.stringify({
        pushToStartToken: null,
        login: "me",
        competitors: ["me", "alice"],
        window: "daily",
        timeZone: "America/New_York",
        apnsEnvironment: "production",
        liveRank: false,
        alertToken: ALERT,
        // Passes and results (#131) off, so only records are sent.
        notifications: { passes: "off", results: false, ...notifications },
      }),
    }),
  );
  expect(res.ok).toBe(true);
}

async function runAt(seconds: number) {
  clock.seconds = seconds;
  await relay.runCycle();
}

const alerts = () => apns.alerts.map((alert) => alert.payload.aps.alert);

/** Days 1 … n of a month as one contribution each. */
function eachDay(month: string, from: number, to: number): Record<string, number> {
  const days: Record<string, number> = {};
  for (let day = from; day <= to; day += 1) days[`2026-${month}-${String(day).padStart(2, "0")}`] = 1;
  return days;
}

describe("relay notifications: records", () => {
  it("sends a new best day once, opening your own view", async () => {
    // An earlier week of 63 keeps this from also being a best week.
    github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
    await register();
    await relay.runCycle();

    expect(apns.alerts).toHaveLength(1);
    const push = apns.alerts[0]!;
    expect(push.token).toBe(ALERT);
    expect(push.payload).toEqual({
      aps: {
        alert: { title: "New best day", body: "41 today. Your old best was 33, on October 20." },
        sound: "default",
        "thread-id": "records",
      },
      kind: "record",
      login: "me",
    });

    // Still climbing later the same day: the record was already sent.
    github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 45 });
    await runAt(ny(5, 10, 5));
    await runAt(ny(5, 15));
    expect(apns.alerts).toHaveLength(1);
  });

  it("sends a new best week once, the day it passes the old best", async () => {
    github.set("me", { "2026-10-20": 50, "2026-11-02": 10, "2026-11-03": 10, "2026-11-04": 10, "2026-11-05": 25 });
    await register();
    await relay.runCycle();
    expect(alerts()).toEqual([{ title: "New best week", body: "55 so far this week. Your old best was 50." }]);

    // The next day adds to the week, but the record was broken yesterday.
    github.set("me", {
      "2026-10-20": 50, "2026-11-02": 10, "2026-11-03": 10, "2026-11-04": 10, "2026-11-05": 25, "2026-11-06": 5,
    });
    await runAt(ny(6, 10));
    expect(apns.alerts).toHaveLength(1);
  });

  it("sends your longest streak yet, past an old best of 7 days", async () => {
    github.set("me", { ...eachDay("10", 1, 7), ...eachDay("10", 29, 31), ...eachDay("11", 1, 5) });
    await register();
    await relay.runCycle();
    expect(alerts()).toEqual([{ title: "Your longest streak yet", body: "8 days, past your old best of 7." }]);
  });

  it("stays quiet under the minimums: an old best day under 5, an old streak under 7", async () => {
    github.set("me", { "2026-10-20": 4, "2026-10-21": 4, "2026-10-22": 4, "2026-11-05": 9 });
    await register();
    await relay.runCycle();
    github.set("me", { ...eachDay("10", 1, 6), ...eachDay("10", 30, 31), ...eachDay("11", 1, 5) });
    await runAt(ny(5, 10, 5));
    expect(apns.alerts).toHaveLength(0);
  });

  it("sends nothing with Records off", async () => {
    github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
    await register({ records: false });
    await relay.runCycle();
    expect(apns.alerts).toHaveLength(0);
  });

  it("works with Passes off, and sends no pass", async () => {
    github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
    await register({ passes: "off" });
    await relay.runCycle();
    github.set("alice", { "2026-11-05": 50 });
    await runAt(ny(5, 10, 5));
    expect(apns.alerts.map((alert) => alert.payload.kind)).toEqual(["record"]);
  });

  describe("quiet hours", () => {
    it("holds a record set in the early morning until quiet hours end, with the day's latest number", async () => {
      github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
      clock.seconds = ny(5, 6);
      await register(); // default quiet hours, 22:00–08:00
      await relay.runCycle();
      github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 44 });
      await runAt(ny(5, 7, 55));
      expect(apns.alerts).toHaveLength(0);

      await runAt(ny(5, 8));
      expect(alerts()).toEqual([{ title: "New best day", body: "44 today. Your old best was 33, on October 20." }]);
      await runAt(ny(5, 8, 5));
      expect(apns.alerts).toHaveLength(1);
    });

    it("holds a late-night record until the morning, and says it was yesterday", async () => {
      github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
      clock.seconds = ny(5, 23, 30);
      await register();
      await relay.runCycle();
      await runAt(ny(6, 7, 55));
      expect(apns.alerts).toHaveLength(0);

      await runAt(ny(6, 8));
      expect(alerts()).toEqual([{ title: "New best day", body: "41 yesterday. Your old best was 33, on October 20." }]);
    });

    it("says last week for a best week set late on Sunday", async () => {
      github.set("me", { "2026-10-20": 50, "2026-11-02": 30, "2026-11-08": 25 });
      clock.seconds = ny(8, 23, 30);
      await register();
      await relay.runCycle();
      expect(apns.alerts).toHaveLength(0);

      await runAt(ny(9, 8));
      expect(alerts()).toEqual([{ title: "New best week", body: "55 last week. Your old best was 50." }]);
    });

    it("sends right away with quiet hours off", async () => {
      github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
      clock.seconds = ny(5, 23, 30);
      await register({ quietHours: null });
      await relay.runCycle();
      expect(apns.alerts).toHaveLength(1);
    });

    it("drops a held record when Records is turned off before morning", async () => {
      github.set("me", { "2026-10-20": 33, "2026-10-21": 30, "2026-11-05": 41 });
      clock.seconds = ny(5, 23, 30);
      await register();
      await relay.runCycle();
      await register({ records: false });
      await runAt(ny(5, 23, 35));
      await register();
      await runAt(ny(6, 8));
      expect(apns.alerts).toHaveLength(0);
    });
  });
});
