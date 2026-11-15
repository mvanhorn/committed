import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { addDays } from "../src/ranking";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub } from "./support/fakes";

/**
 * The streak reminder (#133), through the relay's cron cycle: "Your 40-day streak" / "Nothing yet
 * today. It keeps going if you contribute by midnight." at 8 PM, or an hour before quiet hours
 * when that's earlier, while your streak is at least 2 days and today has 0. At most once a day,
 * never during quiet hours.
 */

const SECRET = "k".repeat(40);
const ALERT = "ef".repeat(32);
const BUNDLE = "com.example.app";
const ID = "inst-streak";
const TODAY = "2026-11-05";

/** Local time on Nov 5 in New York (UTC−5 that day) as Unix seconds. */
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
  github.set("alice", { [TODAY]: 3 });
});

/** A calendar with `streak` days in a row of contributions ending yesterday, and `today` today. */
function calendar(streak: number, today = 0, day = TODAY): Record<string, number> {
  const days: Record<string, number> = { [day]: today, [addDays(day, -streak - 1)]: 0 };
  for (let back = 1; back <= streak; back += 1) days[addDays(day, -back)] = 2;
  return days;
}

async function registerAt(seconds: number, notifications: Record<string, unknown> = {}) {
  clock.seconds = seconds;
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
        notifications: { streakReminder: true, ...notifications },
      }),
    }),
  );
  expect(res.ok).toBe(true);
}

/** Runs one cycle at `seconds` and returns the streak reminders sent so far. */
async function cycleAt(seconds: number) {
  clock.seconds = seconds;
  await relay.runCycle();
  return apns.alerts.filter((alert) => alert.payload.kind === "streakReminder");
}

describe("streak reminder", () => {
  it("reminds you at 8 PM, in the design voice, opening your own view", async () => {
    github.set("me", calendar(40));
    await registerAt(at(19, 50));

    expect(await cycleAt(at(19, 55))).toHaveLength(0);
    const sent = await cycleAt(at(20, 0));
    expect(sent).toHaveLength(1);
    const push = sent[0]!;
    expect(push.token).toBe(ALERT);
    expect(push.environment).toBe("production");
    expect(push.collapseId).toBe("streak");
    expect(push.payload).toEqual({
      aps: {
        alert: {
          title: "Your 40-day streak",
          body: "Nothing yet today. It keeps going if you contribute by midnight.",
        },
        sound: "default",
        "thread-id": "streak",
      },
      kind: "streakReminder",
      login: "me",
    });
  });

  describe("timing", () => {
    it("with quiet hours off, sends from 8 PM until midnight", async () => {
      github.set("me", calendar(5));
      await registerAt(at(19, 0), { quietHours: null });
      expect(await cycleAt(at(19, 55))).toHaveLength(0);
      // The relay missed 8 PM (say a late registration): later in the evening still reminds you.
      expect(await cycleAt(at(23, 30))).toHaveLength(1);
    });

    it("with the default quiet hours (10 PM), stays at 8 PM", async () => {
      github.set("me", calendar(5));
      await registerAt(at(19, 0));
      expect(await cycleAt(at(19, 55))).toHaveLength(0);
      expect(await cycleAt(at(20, 5))).toHaveLength(1);
    });

    it("moves to an hour before quiet hours when that's earlier", async () => {
      github.set("me", calendar(5));
      await registerAt(at(18, 0), { quietHours: { start: "20:30", end: "07:00" } });
      expect(await cycleAt(at(19, 25))).toHaveLength(0);
      expect(await cycleAt(at(19, 30))).toHaveLength(1);
    });

    it("never sends during quiet hours", async () => {
      github.set("me", calendar(5));
      // Quiet from 9 PM: due at 8 PM, but the relay's first look after that is at 9:05 PM.
      await registerAt(at(21, 0), { quietHours: { start: "21:00", end: "07:00" } });
      expect(await cycleAt(at(21, 5))).toHaveLength(0);
      expect(await cycleAt(at(23, 55))).toHaveLength(0);
      // Nor after midnight, inside the same quiet hours.
      github.set("me", calendar(5, 0, "2026-11-06"));
      expect(await cycleAt(at(2, 0, 1))).toHaveLength(0);
    });

    it("keeps 8 PM when quiet hours start in the morning, and skips it if that's quiet", async () => {
      github.set("me", calendar(5));
      await registerAt(at(7, 0), { quietHours: { start: "09:00", end: "17:00" } });
      expect(await cycleAt(at(8, 0))).toHaveLength(0);
      expect(await cycleAt(at(20, 0))).toHaveLength(1);

      apns.clear();
      await registerAt(at(7, 0, 1), { quietHours: { start: "09:00", end: "21:00" } });
      github.set("me", calendar(6, 0, "2026-11-06"));
      expect(await cycleAt(at(20, 0, 1))).toHaveLength(0);
    });
  });

  it("isn't sent once you've contributed today", async () => {
    github.set("me", calendar(40, 1));
    await registerAt(at(19, 50));
    expect(await cycleAt(at(20, 0))).toHaveLength(0);
  });

  it("isn't sent for a streak under 2 days", async () => {
    github.set("me", calendar(1));
    await registerAt(at(19, 50));
    expect(await cycleAt(at(20, 0))).toHaveLength(0);

    github.set("me", calendar(0));
    expect(await cycleAt(at(20, 30))).toHaveLength(0);

    github.set("me", calendar(2));
    expect(await cycleAt(at(20, 45))).toHaveLength(1);
    expect(apns.alerts.at(-1)!.payload.aps.alert.title).toBe("Your 2-day streak");
  });

  it("is sent at most once a day", async () => {
    github.set("me", calendar(7));
    await registerAt(at(19, 50));
    expect(await cycleAt(at(20, 0))).toHaveLength(1);
    expect(await cycleAt(at(20, 5))).toHaveLength(1);
    expect(await cycleAt(at(21, 30))).toHaveLength(1);

    // You contributed late on Nov 5; on Nov 6 the 8-day streak is reminded again.
    github.set("me", { ...calendar(7), [TODAY]: 3, "2026-11-06": 0 });
    expect(await cycleAt(at(19, 55, 1))).toHaveLength(1);
    const sent = await cycleAt(at(20, 0, 1));
    expect(sent).toHaveLength(2);
    expect(sent[1]!.payload.aps.alert.title).toBe("Your 8-day streak");
  });

  it("is off by default", async () => {
    github.set("me", calendar(5));
    await registerAt(at(19, 50), { streakReminder: false });
    expect(await cycleAt(at(20, 0))).toHaveLength(0);
  });

  it("is sent with Passes off", async () => {
    github.set("me", calendar(5));
    await registerAt(at(19, 50), { passes: "off" });
    expect(await cycleAt(at(20, 0))).toHaveLength(1);
  });

  it("isn't sent while your count is stale: an old \"nothing yet\" may be wrong", async () => {
    github.set("me", calendar(5));
    await registerAt(at(19, 0));
    await cycleAt(at(19, 0)); // your count, fetched at 7 PM
    github.fail("me");
    expect(await cycleAt(at(20, 0))).toHaveLength(0);
  });

  it("keeps the state other kinds own", async () => {
    github.set("me", calendar(5));
    await registerAt(at(19, 50));
    await cycleAt(at(20, 0));
    const row = await env.DB.prepare("SELECT notification_state FROM installations WHERE id = ?")
      .bind(ID)
      .first<{ notification_state: string }>();
    const state = JSON.parse(row!.notification_state) as Record<string, unknown>;
    expect(state.streak).toEqual({ date: TODAY });
    expect(state.passes).toBeDefined();
  });
});
