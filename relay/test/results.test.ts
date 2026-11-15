import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import type { AlertRequest } from "../src/apns";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub, HOUR, MINUTE } from "./support/fakes";

/**
 * Daily and weekly result notifications (#131): the cron cycle stepped every 5 minutes through a
 * day and a Monday, with a fake GitHub, a fake APNs that records alerts and a fake clock.
 */

const SECRET = "k".repeat(40);
const ALERT = "ab".repeat(32);
const BUNDLE = "com.example.app";
const ID = "inst-0131";

/** Unix seconds for a local time in New York, which is UTC−5 all of November 2026 after the 1st. */
const ny = (day: number, hour: number, minute = 0) => Date.UTC(2026, 10, day, hour + 5, minute) / 1000;

let apns: FakeApns;
let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  apns = new FakeApns();
  github = new FakeGitHub();
  clock = new Clock(ny(12, 6));
  relay = createRelay({ db: env.DB, apns, github: github.fetch, githubName: github.name, now: clock.now, bundleId: BUNDLE, log: () => {} });
});

async function register(
  notifications: Record<string, unknown> = {},
  overrides: Partial<{ competitors: string[]; timeZone: string }> = {},
) {
  const res = await relay.fetch(
    new Request(`https://relay.test/v1/installations/${ID}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: JSON.stringify({
        pushToStartToken: null,
        login: "me",
        competitors: ["me", "alice", "bob"],
        window: "daily",
        timeZone: "America/New_York",
        apnsEnvironment: "production",
        liveRank: false,
        alertToken: ALERT,
        // Passes off, so only results are sent.
        notifications: { passes: "off", ...notifications },
        ...overrides,
      }),
    }),
  );
  expect(res.ok).toBe(true);
}

/** Runs the cycle every 5 minutes from the clock's time through `until` (inclusive). */
async function runThrough(until: number) {
  while (clock.seconds <= until) {
    await relay.runCycle();
    clock.advance(5 * MINUTE);
  }
}

function results(): AlertRequest[] {
  return apns.alerts.filter((alert) => alert.payload.kind === "result");
}

describe("the daily result", () => {
  beforeEach(() => {
    github.set("me", { "2026-11-11": 41, "2026-11-12": 2 });
    github.set("alice", { "2026-11-11": 33, "2026-11-12": 9 });
    github.set("bob", { "2026-11-11": 12 });
  });

  it("is sent once, when quiet hours end at 8 AM, with yesterday's Today standings", async () => {
    await register();
    await runThrough(ny(12, 7, 55));
    expect(results()).toHaveLength(0);

    await runThrough(ny(12, 8, 0));
    expect(results()).toHaveLength(1);
    const push = results()[0]!;
    expect(push.token).toBe(ALERT);
    expect(push.payload).toEqual({
      aps: {
        alert: { title: "You won yesterday", body: "41 contributions, 8 ahead of alice." },
        sound: "default",
        "thread-id": "results",
      },
      kind: "result",
    });

    await runThrough(ny(13, 7, 55));
    expect(results()).toHaveLength(1);
  }, 60_000);

  it("names the winner when you didn't win", async () => {
    github.set("alice", { "2026-11-11": 50 });
    await register();
    await runThrough(ny(12, 8, 0));
    expect(results().map((alert) => alert.payload.aps.alert)).toEqual([
      { title: "You finished #2 yesterday", body: "alice won with 50. You had 41." },
    ]);
  });

  it("says level when you tie for first, which counts for you", async () => {
    github.set("alice", { "2026-11-11": 41 });
    await register();
    await runThrough(ny(12, 8, 0));
    expect(results().map((alert) => alert.payload.aps.alert)).toEqual([
      { title: "You won yesterday", body: "41 contributions, level with alice." },
    ]);
  });

  it("says contribution for one", async () => {
    github.set("me", { "2026-11-11": 1 });
    github.set("alice", { "2026-11-11": 0 });
    github.set("bob", { "2026-11-11": 0 });
    await register();
    await runThrough(ny(12, 8, 0));
    expect(results()[0]!.payload.aps.alert.body).toBe("1 contribution, 1 ahead of alice.");
  });

  it("is held through quiet hours, and sent when they end", async () => {
    await register({ quietHours: { start: "22:00", end: "09:30" } });
    await runThrough(ny(12, 9, 25));
    expect(results()).toHaveLength(0);
    await runThrough(ny(12, 9, 30));
    expect(results()).toHaveLength(1);
  });

  it("goes out when quiet hours end, even before 8 AM", async () => {
    await register({ quietHours: { start: "23:00", end: "06:30" } });
    await runThrough(ny(12, 6, 25));
    expect(results()).toHaveLength(0);
    await runThrough(ny(12, 6, 30));
    expect(results()).toHaveLength(1);
  });

  it("goes out at 8 AM with quiet hours off", async () => {
    await register({ quietHours: null });
    await runThrough(ny(12, 7, 55));
    expect(results()).toHaveLength(0);
    await runThrough(ny(12, 8, 0));
    expect(results()).toHaveLength(1);
  });

  it("follows the installation's own time zone", async () => {
    // 08:00 on Nov 12 in Tokyo is 23:00 on Nov 11 UTC.
    clock.seconds = Date.UTC(2026, 10, 11, 21, 0) / 1000;
    github.set("me", { "2026-11-11": 41 });
    github.set("alice", { "2026-11-11": 33 });
    await register({}, { timeZone: "Asia/Tokyo" });
    await runThrough(Date.UTC(2026, 10, 11, 22, 55) / 1000);
    expect(results()).toHaveLength(0);
    await runThrough(Date.UTC(2026, 10, 11, 23, 0) / 1000);
    expect(results().map((alert) => alert.payload.aps.alert.title)).toEqual(["You won yesterday"]);
  });

  it("isn't sent twice when a time zone change moves the local date back", async () => {
    // 08:00 on Nov 13 in Auckland (UTC+13) is 09:00 on Nov 12 in Honolulu (UTC−10).
    clock.seconds = Date.UTC(2026, 10, 12, 18, 30) / 1000;
    github.set("me", { "2026-11-11": 41, "2026-11-12": 30 });
    github.set("alice", { "2026-11-11": 33, "2026-11-12": 20 });
    await register({}, { timeZone: "Pacific/Auckland" });
    await runThrough(Date.UTC(2026, 10, 12, 19, 0) / 1000);
    expect(results()).toHaveLength(1);

    await register({}, { timeZone: "Pacific/Honolulu" });
    await runThrough(Date.UTC(2026, 10, 12, 20, 0) / 1000);
    expect(results()).toHaveLength(1);
  });

  it("is skipped with no visible rivals", async () => {
    await register({}, { competitors: ["me"] });
    await runThrough(ny(12, 9, 0));
    expect(results()).toHaveLength(0);
  });

  it("is skipped when nobody on the board contributed yesterday", async () => {
    github.set("me", { "2026-11-11": 0, "2026-11-12": 4 });
    github.set("alice", { "2026-11-11": 0 });
    github.set("bob", { "2026-11-12": 3 });
    await register();
    await runThrough(ny(12, 9, 0));
    expect(results()).toHaveLength(0);
  });

  it("waits for your own count, then sends once", async () => {
    github.fail("me");
    await register();
    await runThrough(ny(12, 8, 30));
    expect(results()).toHaveLength(0);
    github.set("me", { "2026-11-11": 41 });
    await runThrough(ny(12, 9, 0));
    expect(results()).toHaveLength(1);
  });

  it("isn't sent the moment you turn results on after 8 AM, but the next morning", async () => {
    clock.seconds = ny(12, 15);
    await register();
    await runThrough(ny(12, 16));
    clock.seconds = ny(13, 7); // overnight, nothing changes
    await runThrough(ny(13, 7, 55));
    expect(results()).toHaveLength(0);
    github.set("me", { "2026-11-12": 20 });
    github.set("alice", { "2026-11-12": 25 });
    await runThrough(ny(13, 8, 0));
    expect(results().map((alert) => alert.payload.aps.alert)).toEqual([
      { title: "You finished #2 yesterday", body: "alice won with 25. You had 20." },
    ]);
  });

  it("isn't sent with results off", async () => {
    await register({ results: false });
    await runThrough(ny(12, 9, 0));
    expect(results()).toHaveLength(0);
  });

  it("turned off and on again the same afternoon, waits for the next morning", async () => {
    await register();
    await runThrough(ny(12, 8, 0));
    expect(results()).toHaveLength(1);
    await register({ results: false });
    await runThrough(ny(12, 14, 0));
    await register();
    await runThrough(ny(12, 16));
    clock.seconds = ny(13, 7);
    await runThrough(ny(13, 7, 55));
    expect(results()).toHaveLength(1);
  });

  it("runs beside passes, each keeping its own state", async () => {
    await register({ passes: "everyone" });
    await runThrough(ny(12, 8, 0));
    github.set("alice", { "2026-11-11": 33, "2026-11-12": 1 }); // you pass alice today
    await runThrough(ny(12, 8, 5));
    expect(apns.alerts.map((alert) => alert.payload.kind)).toEqual(["result", "pass"]);
    const row = await env.DB.prepare("SELECT notification_state FROM installations WHERE id = ?").bind(ID)
      .first<{ notification_state: string }>();
    const state = JSON.parse(row!.notification_state) as Record<string, unknown>;
    expect(state.results).toEqual({ date: "2026-11-12" });
    expect(state.passes).toBeDefined();
  });
});

describe("last week's final, on Mondays", () => {
  // Monday, November 9, 2026: last week is Nov 2–8.
  beforeEach(() => {
    clock.seconds = ny(9, 6);
    github.set("me", { "2026-11-02": 100, "2026-11-06": 86, "2026-11-08": 0, "2026-11-09": 1 });
    github.set("alice", { "2026-11-01": 500, "2026-11-03": 179, "2026-11-08": 2, "2026-11-09": 40 });
    github.set("bob", { "2026-11-08": 7 });
  });

  it("is sent beside the daily result, at the same time, once", async () => {
    await register();
    await runThrough(ny(9, 7, 55));
    expect(results()).toHaveLength(0);
    await runThrough(ny(9, 8, 0));
    expect(results().map((alert) => [alert.collapseId, alert.payload.aps.alert])).toEqual([
      ["result.daily", { title: "You finished #3 yesterday", body: "bob won with 7. You had 0." }],
      ["result.weekly", { title: "Last week's final: #1", body: "186 contributions, 5 ahead of alice." }],
    ]);
    expect(results()[1]!.payload).toMatchObject({ kind: "result", aps: { "thread-id": "results" } });

    // Tuesday brings a daily result only.
    await runThrough(ny(9, 9, 0));
    clock.seconds = ny(10, 7);
    await runThrough(ny(10, 9, 0));
    expect(results().map((alert) => alert.collapseId)).toEqual(["result.daily", "result.weekly", "result.daily"]);
  });

  it("names the winner when you didn't win the week", async () => {
    github.set("bob", { "2026-11-04": 200 });
    await register();
    await runThrough(ny(9, 8, 0));
    expect(results().find((alert) => alert.collapseId === "result.weekly")!.payload.aps.alert).toEqual({
      title: "Last week's final: #2",
      body: "bob won with 200. You had 186.",
    });
  });

  it("is sent even when nobody contributed on Sunday", async () => {
    github.set("alice", { "2026-11-03": 181 });
    github.set("bob", { "2026-11-02": 3 });
    await register();
    await runThrough(ny(9, 8, 0));
    expect(results().map((alert) => alert.collapseId)).toEqual(["result.weekly"]);
  });

  it("is skipped when nobody contributed all week", async () => {
    github.set("me", { "2026-11-09": 1 });
    github.set("alice", { "2026-11-01": 500 });
    github.set("bob", { "2026-11-09": 7 });
    await register();
    await runThrough(ny(9, 8, 30));
    expect(results()).toHaveLength(0);
  });

  it("counts Monday to Sunday in your time zone", async () => {
    // 11 PM Sunday in New York is already Monday in UTC: it still counts for last week.
    github.set("me", { "2026-11-08": 3 });
    github.set("alice", { "2026-11-08": 2, "2026-11-09": 50 });
    github.set("bob", {});
    await register();
    await runThrough(ny(9, 8, 0));
    expect(results().find((alert) => alert.collapseId === "result.weekly")!.payload.aps.alert).toEqual({
      title: "Last week's final: #1",
      body: "3 contributions, 1 ahead of alice.",
    });
  });
});

