import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub, HOUR, MINUTE } from "./support/fakes";

/**
 * Close calls (#132) through the cron cycle: a fake store (D1), a fake GitHub, a fake APNs that
 * records payloads and a fake clock, as in cycle.test.ts.
 */

const SECRET = "k".repeat(40);
const BUNDLE = "com.example.app";
const ALERT = "ab".repeat(32);
const ID = "inst-0132";

// New York is UTC−5 in November. 2026-11-05T15:00:00Z is 10:00 there, outside quiet hours.
const at = (hour: number, minute = 0, day = 5) => Date.UTC(2026, 10, day, hour + 5, minute) / 1000;

let apns: FakeApns;
let github: FakeGitHub;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

beforeEach(() => {
  apns = new FakeApns();
  github = new FakeGitHub();
  clock = new Clock(at(10));
  relay = createRelay({ db: env.DB, apns, github: github.fetch, githubName: github.name, now: clock.now, bundleId: BUNDLE, log: () => {} });
});

/**
 * Registers relay notifications with close calls on, Live rank off. Delivery is "immediate": in
 * summary delivery close calls wait for the evening summary (#135).
 */
async function registerCloseCalls(
  overrides: Partial<{ competitors: string[]; rivals: string[]; notifications: Record<string, unknown> }> = {},
) {
  const { notifications, ...rest } = overrides;
  const res = await relay.fetch(
    new Request(`https://relay.test/v1/installations/${ID}`, {
      method: "PUT",
      headers: { authorization: `Bearer ${SECRET}`, "content-type": "application/json" },
      body: JSON.stringify({
        pushToStartToken: null,
        login: "me",
        competitors: ["me", "odile-m", "bob"],
        window: "daily",
        timeZone: "America/New_York",
        apnsEnvironment: "production",
        liveRank: false,
        alertToken: ALERT,
        notifications: { window: "daily", passes: "off", closeCalls: true, delivery: "immediate", ...notifications },
        rivals: [],
        ...rest,
      }),
    }),
  );
  expect(res.ok).toBe(true);
}

const closeCalls = () => apns.alerts.filter((alert) => alert.payload.kind === "closeCall");

describe("relay notifications: close calls", () => {
  it("tells you how many you need to pass the person directly above you, in the spec's words", async () => {
    github.set("me", { "2026-11-05": 31 });
    github.set("odile-m", { "2026-11-05": 33 });
    github.set("bob", { "2026-11-05": 50 });
    await registerCloseCalls();
    await relay.runCycle();

    expect(closeCalls()).toHaveLength(1);
    const push = closeCalls()[0]!;
    expect(push.token).toBe(ALERT);
    expect(push.collapseId).toBe("closeCall.odile-m");
    expect(push.payload).toEqual({
      aps: {
        alert: { title: "Close call: 2 to pass odile-m", body: "You're at 31, they're at 33 · Today" },
        sound: "default",
        "thread-id": "closeCalls",
      },
      kind: "closeCall",
      login: "odile-m",
    });
  });

  describe("how close counts as close: 1 to max(3, ceil(5% of their count)) behind", () => {
    it.each([
      // [you, them, sent]: worked by hand.
      [9, 10, true], //    1 behind: the least
      [7, 10, true], //    3 behind, the floor of 3 at small counts
      [6, 10, false], //   4 behind
      [57, 60, true], //   5% of 60 is exactly 3
      [56, 60, false], //  4 behind 60
      [57, 61, true], //   5% of 61 is 3.05, rounded up to 4
      [56, 61, false], //  5 behind 61
      [95, 100, true], //  5% of 100 is 5
      [94, 100, false], // 6 behind 100
      [380, 400, true], // 5% of 400 is 20
      [379, 400, false], // 21 behind 400
    ])("you at %i, them at %i: %s", async (mine, theirs, sent) => {
      github.set("me", { "2026-11-05": mine });
      github.set("odile-m", { "2026-11-05": theirs });
      github.set("bob", { "2026-11-05": 1000 });
      await registerCloseCalls();
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.aps.alert.title)).toEqual(
        sent ? [`Close call: ${theirs - mine} to pass odile-m`] : [],
      );
    });

    it("never for someone you're tied with or ahead of", async () => {
      github.set("me", { "2026-11-05": 10 });
      github.set("odile-m", { "2026-11-05": 10 });
      github.set("bob", { "2026-11-05": 8 });
      await registerCloseCalls();
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });
  });

  describe("who", () => {
    it("with nobody pinned, only the person directly above you, not someone further up", async () => {
      github.set("me", { "2026-11-05": 10 });
      github.set("odile-m", { "2026-11-05": 30 }); // directly above, 20 behind: not close
      github.set("bob", { "2026-11-05": 31 }); // further up, only 1 more than odile-m
      await registerCloseCalls();
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);

      github.set("me", { "2026-11-05": 28 });
      clock.advance(5 * MINUTE);
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.login)).toEqual(["odile-m"]);
    });

    it("with rivals pinned, each pinned rival you're close behind, even with someone in between", async () => {
      github.set("me", { "2026-11-05": 20 });
      github.set("odile-m", { "2026-11-05": 23 }); // pinned, 3 ahead, bob in between
      github.set("bob", { "2026-11-05": 21 }); // not pinned, directly above you
      github.set("carol", { "2026-11-05": 22 }); // pinned, 2 ahead
      await registerCloseCalls({ competitors: ["me", "odile-m", "bob", "carol"], rivals: ["odile-m", "carol"] });
      await relay.runCycle();
      // In board order: odile-m (23) is above carol (22).
      expect(closeCalls().map((alert) => alert.payload.aps.alert.title)).toEqual([
        "Close call: 3 to pass odile-m",
        "Close call: 2 to pass carol",
      ]);
    });

    it("with rivals pinned but none close, nothing about the person above you", async () => {
      github.set("me", { "2026-11-05": 20 });
      github.set("odile-m", { "2026-11-05": 40 }); // pinned, far ahead
      github.set("bob", { "2026-11-05": 21 }); // not pinned, 1 ahead
      await registerCloseCalls({ rivals: ["odile-m"] });
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });

    it("never about a pinned rival behind you", async () => {
      github.set("me", { "2026-11-05": 20 });
      github.set("odile-m", { "2026-11-05": 19 });
      github.set("bob", { "2026-11-05": 50 });
      await registerCloseCalls({ rivals: ["odile-m"] });
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });

    it("leaves out people you've hidden", async () => {
      // bob is hidden: the app leaves him out of the board it registers.
      github.set("me", { "2026-11-05": 20 });
      github.set("odile-m", { "2026-11-05": 40 });
      github.set("bob", { "2026-11-05": 21 });
      await registerCloseCalls({ competitors: ["me", "odile-m"] });
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });

    it("says nothing while your own count can't be fetched", async () => {
      github.fail("me");
      github.set("odile-m", { "2026-11-05": 3 });
      await registerCloseCalls();
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });
  });

  describe("at most one per person per day", () => {
    it("doesn't repeat while you stay close, or come close again, the same day", async () => {
      github.set("me", { "2026-11-05": 31 });
      github.set("odile-m", { "2026-11-05": 33 });
      github.set("bob", { "2026-11-05": 50 });
      await registerCloseCalls();
      await relay.runCycle();
      clock.advance(5 * MINUTE);
      await relay.runCycle();
      // You pass odile-m, then she pulls 1 ahead again.
      github.set("me", { "2026-11-05": 34 });
      clock.advance(5 * MINUTE);
      await relay.runCycle();
      github.set("odile-m", { "2026-11-05": 35 });
      clock.advance(5 * MINUTE);
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.login)).toEqual(["odile-m"]);
    });

    it("one each for different people the same day", async () => {
      github.set("me", { "2026-11-05": 31 });
      github.set("odile-m", { "2026-11-05": 33 });
      github.set("bob", { "2026-11-05": 50 });
      await registerCloseCalls();
      await relay.runCycle();
      // You pass odile-m and close in on bob.
      github.set("me", { "2026-11-05": 48 });
      clock.advance(5 * MINUTE);
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.aps.alert.title)).toEqual([
        "Close call: 2 to pass odile-m",
        "Close call: 2 to pass bob",
      ]);
    });

    it("can come again the next local day", async () => {
      github.set("me", { "2026-11-05": 31, "2026-11-06": 31 });
      github.set("odile-m", { "2026-11-05": 33, "2026-11-06": 33 });
      github.set("bob", { "2026-11-05": 50, "2026-11-06": 50 });
      await registerCloseCalls({ notifications: { quietHours: null } });
      clock.seconds = at(23, 50);
      await relay.runCycle();
      clock.seconds = at(0, 5, 6); // 00:05 Nov 6 in New York
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(2);
    });
  });

  describe("quiet hours", () => {
    beforeEach(() => {
      github.set("me", { "2026-11-05": 31 });
      github.set("odile-m", { "2026-11-05": 33 });
      github.set("bob", { "2026-11-05": 50 });
    });

    it("sends nothing during quiet hours, then once they end if you're still close", async () => {
      clock.seconds = at(7, 30); // inside the default 22:00–08:00
      await registerCloseCalls();
      await relay.runCycle();
      clock.seconds = at(7, 55);
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);

      clock.seconds = at(8, 0);
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.aps.alert.title)).toEqual(["Close call: 2 to pass odile-m"]);
      expect(closeCalls()[0]!.payload.aps.sound).toBe("default");
    });

    it("stays silent from the start of quiet hours, past midnight", async () => {
      clock.seconds = at(22, 0);
      await registerCloseCalls();
      await relay.runCycle();
      clock.seconds = at(2, 0, 6);
      github.set("me", { "2026-11-05": 31, "2026-11-06": 1 });
      github.set("odile-m", { "2026-11-05": 33, "2026-11-06": 2 });
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });

    it("follows the chosen hours", async () => {
      clock.seconds = at(13, 0);
      await registerCloseCalls({ notifications: { quietHours: { start: "12:30", end: "14:00" } } });
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(0);
    });

    it("with quiet hours off, sends at night", async () => {
      clock.seconds = at(23, 30);
      await registerCloseCalls({ notifications: { quietHours: null } });
      await relay.runCycle();
      expect(closeCalls()).toHaveLength(1);
    });
  });

  describe("the Window", () => {
    it("judges 7 days and names it", async () => {
      github.set("me", { "2026-10-30": 20, "2026-11-05": 10 }); // 30 over 7 days
      github.set("odile-m", { "2026-11-05": 33 }); // 33: 3 ahead
      github.set("bob", { "2026-11-05": 50 });
      await registerCloseCalls({ notifications: { window: "weekly" } });
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.aps.alert)).toEqual([
        { title: "Close call: 3 to pass odile-m", body: "You're at 30, they're at 33 · 7 days" },
      ]);
    });

    it("judges 30 days and names it", async () => {
      github.set("me", { "2026-10-07": 100, "2026-11-05": 1 }); // 101 over 30 days
      github.set("odile-m", { "2026-10-06": 500, "2026-11-05": 104 }); // Oct 6 is outside: 104
      github.set("bob", { "2026-11-05": 500 });
      await registerCloseCalls({ notifications: { window: "monthly" } });
      await relay.runCycle();
      expect(closeCalls().map((alert) => alert.payload.aps.alert)).toEqual([
        { title: "Close call: 3 to pass odile-m", body: "You're at 101, they're at 104 · 30 days" },
      ]);
    });
  });

  describe("switches", () => {
    beforeEach(() => {
      github.set("me", { "2026-11-05": 31 });
      github.set("odile-m", { "2026-11-05": 33 });
      github.set("bob", { "2026-11-05": 50 });
    });

    it("sends nothing with close calls off", async () => {
      await registerCloseCalls({ notifications: { closeCalls: false, passes: "everyone" } });
      await relay.runCycle();
      expect(apns.alerts).toHaveLength(0);
    });

    it("works with passes off, and alongside passes", async () => {
      await registerCloseCalls({ notifications: { passes: "everyone" } });
      await relay.runCycle(); // passes take a baseline; the close call goes out
      github.set("odile-m", { "2026-11-05": 30 }); // you pass her
      clock.advance(5 * MINUTE);
      await relay.runCycle();
      expect(apns.alerts.map((alert) => alert.payload.kind)).toEqual(["closeCall", "pass"]);
    });

    it("never touches a Live Activity", async () => {
      await registerCloseCalls();
      await relay.runCycle();
      expect(apns.sent).toHaveLength(0);
      expect(closeCalls()).toHaveLength(1);
    });
  });

  it("stops after a dead alert token is cleared", async () => {
    github.set("me", { "2026-11-05": 20 });
    github.set("odile-m", { "2026-11-05": 22 });
    github.set("carol", { "2026-11-05": 21 });
    await registerCloseCalls({ competitors: ["me", "odile-m", "carol"], rivals: ["odile-m", "carol"] });
    apns.respond(ALERT, { status: 410, reason: "Unregistered" });
    await relay.runCycle();
    expect(closeCalls()).toHaveLength(1); // the failed one only
    clock.advance(HOUR);
    await relay.runCycle();
    expect(closeCalls()).toHaveLength(1);
  });
});
