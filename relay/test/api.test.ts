import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub } from "./support/fakes";

const ID = "8f0c1d5e-4b7a-4c39-9a51-2f6d8e0b7c11";
const SECRET = "s".repeat(43);
const PTS = "a1".repeat(40);
const ACTIVITY_TOKEN = "b2".repeat(40);

const registration = {
  pushToStartToken: PTS,
  login: "Me",
  competitors: ["me", "Alice", "bob"],
  window: "daily",
  timeZone: "America/New_York",
  apnsEnvironment: "sandbox",
};

let apns: FakeApns;
let clock: Clock;
let relay: ReturnType<typeof createRelay>;

function call(method: string, path: string, body?: unknown, secret: string | null = SECRET): Promise<Response> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (secret !== null) headers.authorization = `Bearer ${secret}`;
  return relay.fetch(
    new Request(`https://relay.test${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
}

async function row(id = ID) {
  return env.DB.prepare("SELECT * FROM installations WHERE id = ?").bind(id).first<Record<string, unknown>>();
}

beforeEach(() => {
  apns = new FakeApns();
  clock = new Clock(1_793_800_000);
  relay = createRelay({ db: env.DB, apns, github: new FakeGitHub().fetch, githubName: new FakeGitHub().name, now: clock.now, bundleId: "com.example.app" });
});

describe("PUT /v1/installations/{id}", () => {
  it("registers an installation and stores only a hash of the secret", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, registration);
    expect(res.status).toBe(201);
    const stored = await row();
    expect(stored).not.toBeNull();
    expect(stored!.secret_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(stored)).not.toContain(SECRET);
    expect(stored!.login).toBe("me");
    expect(JSON.parse(stored!.competitors_json as string)).toEqual(["me", "alice", "bob"]);
    expect(stored!.push_to_start_token).toBe(PTS);
    expect(stored!.window).toBe("daily");
    expect(stored!.time_zone).toBe("America/New_York");
    expect(stored!.apns_environment).toBe("sandbox");
  });

  it("updates with the same secret and rejects a different one", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    const update = await call("PUT", `/v1/installations/${ID}`, { ...registration, window: "weekly" });
    expect(update.status).toBe(200);
    expect((await row())!.window).toBe("weekly");

    const hijack = await call("PUT", `/v1/installations/${ID}`, { ...registration, login: "mallory" }, "x".repeat(43));
    expect(hijack.status).toBe(401);
    expect((await row())!.login).toBe("me");
  });

  it("requires a bearer secret", async () => {
    expect((await call("PUT", `/v1/installations/${ID}`, registration, null)).status).toBe(401);
    expect((await call("PUT", `/v1/installations/${ID}`, registration, "short")).status).toBe(401);
    expect(await row()).toBeNull();
  });

  it("puts self first when the board list omits it, and drops duplicates", async () => {
    await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["alice", "ALICE", "bob"] });
    expect(JSON.parse((await row())!.competitors_json as string)).toEqual(["me", "alice", "bob"]);
  });

  // You're first on your own board, so you win a tie with any rival, as the iPhone's rows do
  // ("N to pass" relies on it). The rivals keep the order the device sent.
  it("moves self to the front when the board list has it later", async () => {
    await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["alice", "bob", "me"] });
    expect(JSON.parse((await row())!.competitors_json as string)).toEqual(["me", "alice", "bob"]);
  });

  it("accepts at most 1,000 competitors", async () => {
    const logins = (n: number) => Array.from({ length: n }, (_, i) => `user-${i}`);
    const ok = await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["me", ...logins(999)] });
    expect(ok.status).toBe(201);
    const tooMany = await call("PUT", `/v1/installations/${ID}`, { ...registration, competitors: ["me", ...logins(1000)] });
    expect(tooMany.status).toBe(400);
  });

  it("never accepts a GitHub token: unknown fields are rejected", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, { ...registration, githubToken: "gho_secret" });
    expect(res.status).toBe(400);
    expect(await row()).toBeNull();
  });

  it("accepts every Window the app offers", async () => {
    for (const window of ["daily", "weekly", "monthly"]) {
      const res = await call("PUT", `/v1/installations/${ID}`, { ...registration, window });
      expect(res.status, window).toBeLessThan(300);
      expect((await row())!.window).toBe(window);
    }
  });

  it("answers invalid_window for a Window it doesn't know", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, { ...registration, window: "month" });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "invalid_window" });
  });

  it("rejects invalid fields", async () => {
    const bad = [
      { ...registration, login: "gho_abc123" },
      { ...registration, window: "yearly" },
      { ...registration, timeZone: "Mars/Olympus" },
      { ...registration, apnsEnvironment: "staging" },
      { ...registration, pushToStartToken: "not-hex" },
      { ...registration, competitors: "me" },
    ];
    for (const body of bad) {
      expect((await call("PUT", `/v1/installations/${ID}`, body)).status, JSON.stringify(body)).toBe(400);
    }
    expect((await call("PUT", "/v1/installations/bad id!", registration)).status).toBe(404);
  });

  it("rate-limits writes per installation", async () => {
    let status = 0;
    for (let i = 0; i < 40 && status !== 429; i++) {
      status = (await call("PUT", `/v1/installations/${ID}`, registration)).status;
    }
    expect(status).toBe(429);
    clock.advance(11 * 60);
    expect((await call("PUT", `/v1/installations/${ID}`, registration)).status).toBe(200);
  });
});

describe("PUT /v1/installations/{id}/activity", () => {
  it("records the activity id, push token, and start time", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    const res = await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "act-1", pushToken: ACTIVITY_TOKEN });
    expect(res.status).toBe(200);
    const stored = await row();
    expect(stored!.activity_id).toBe("act-1");
    expect(stored!.activity_push_token).toBe(ACTIVITY_TOKEN);
    expect(stored!.activity_started_at).toBe(clock.seconds);
  });

  it("needs a registered installation and its secret", async () => {
    expect((await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "a", pushToken: ACTIVITY_TOKEN })).status).toBe(404);
    await call("PUT", `/v1/installations/${ID}`, registration);
    const wrong = await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "a", pushToken: ACTIVITY_TOKEN }, "y".repeat(43));
    expect(wrong.status).toBe(401);
  });
});

describe("DELETE /v1/installations/{id}", () => {
  it("ends the activity with immediate dismissal and forgets the installation", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "act-1", pushToken: ACTIVITY_TOKEN });
    const res = await call("DELETE", `/v1/installations/${ID}`);
    expect(res.status).toBe(204);
    expect(await row()).toBeNull();
    expect(apns.events()).toEqual([`end:${ACTIVITY_TOKEN}`]);
    expect(apns.sent[0]!.payload.aps["dismissal-date"]).toBe(clock.seconds);
  });

  it("rejects the wrong secret", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    expect((await call("DELETE", `/v1/installations/${ID}`, undefined, "z".repeat(43))).status).toBe(401);
    expect(await row()).not.toBeNull();
  });
});

// Spec #124: relay notifications. The new keys are optional, so the live 1.0.x apps' bodies
// (exactly `registration` above) keep working.
describe("PUT /v1/installations/{id}: Live rank and relay notifications", () => {
  const ALERT = "e7".repeat(32);
  const defaults = {
    window: "daily",
    passes: "everyone",
    closeCalls: false,
    results: true,
    records: true,
    streakReminder: false,
    delivery: "summary",
    quietHours: { start: "22:00", end: "08:00" },
  };
  const withNotifications = {
    ...registration,
    liveRank: false,
    alertToken: ALERT,
    notifications: defaults,
    rivals: ["alice"],
  };

  it("treats a 1.0.x body as Live rank on with no notifications", async () => {
    expect((await call("PUT", `/v1/installations/${ID}`, registration)).status).toBe(201);
    const stored = await row();
    expect(stored!.live_rank).toBe(1);
    expect(stored!.alert_token).toBeNull();
    expect(stored!.notifications_json).toBeNull();
    expect(JSON.parse(stored!.rivals_json as string)).toEqual([]);
  });

  it("stores Live rank, the alert token, the preferences and pinned rivals", async () => {
    expect((await call("PUT", `/v1/installations/${ID}`, withNotifications)).status).toBe(201);
    const stored = await row();
    expect(stored!.live_rank).toBe(0);
    expect(stored!.alert_token).toBe(ALERT);
    expect(JSON.parse(stored!.notifications_json as string)).toEqual(defaults);
    expect(JSON.parse(stored!.rivals_json as string)).toEqual(["alice"]);
  });

  it("fills missing preferences with the defaults, and accepts quiet hours off", async () => {
    await call("PUT", `/v1/installations/${ID}`, { ...withNotifications, notifications: { passes: "rivals", quietHours: null } });
    expect(JSON.parse((await row())!.notifications_json as string)).toEqual({ ...defaults, passes: "rivals", quietHours: null });
  });

  it("accepts notifications before iOS has issued an alert token", async () => {
    expect((await call("PUT", `/v1/installations/${ID}`, { ...withNotifications, alertToken: null })).status).toBe(201);
    expect((await row())!.alert_token).toBeNull();
  });

  it("turning notifications off forgets the preferences and the alert token", async () => {
    await call("PUT", `/v1/installations/${ID}`, { ...withNotifications, liveRank: true });
    await call("PUT", `/v1/installations/${ID}`, { ...registration, liveRank: true, notifications: null, alertToken: null });
    const stored = await row();
    expect(stored!.notifications_json).toBeNull();
    expect(stored!.alert_token).toBeNull();
  });

  it("answers an error code for each bad field", async () => {
    const cases: [Record<string, unknown>, string][] = [
      [{ liveRank: "yes" }, "invalid_live_rank"],
      [{ alertToken: "not-hex" }, "invalid_alert_token"],
      [{ notifications: "on" }, "invalid_notifications"],
      [{ notifications: { ...defaults, sound: true } }, "unknown_field:notifications.sound"],
      [{ notifications: { window: "yearly" } }, "invalid_notifications_window"],
      [{ notifications: { passes: "some" } }, "invalid_notifications_passes"],
      [{ notifications: { closeCalls: 1 } }, "invalid_notifications_close_calls"],
      [{ notifications: { results: "true" } }, "invalid_notifications_results"],
      [{ notifications: { records: null } }, "invalid_notifications_records"],
      [{ notifications: { streakReminder: "no" } }, "invalid_notifications_streak_reminder"],
      [{ notifications: { delivery: "later" } }, "invalid_notifications_delivery"],
      [{ notifications: { quietHours: { start: "22:00" } } }, "invalid_quiet_hours"],
      [{ notifications: { quietHours: { start: "25:00", end: "08:00" } } }, "invalid_quiet_hours"],
      [{ notifications: { quietHours: { start: "22:00", end: "8:00" } } }, "invalid_quiet_hours"],
      [{ rivals: "alice" }, "invalid_rivals"],
      [{ rivals: ["alice", "bob", "carol", "dave"] }, "too_many_rivals"],
      [{ rivals: ["zed"] }, "unknown_rival"],
    ];
    for (const [fields, error] of cases) {
      const res = await call("PUT", `/v1/installations/${ID}`, { ...withNotifications, ...fields });
      expect(res.status, error).toBe(400);
      expect(await res.json(), error).toEqual({ error });
    }
    expect(await row()).toBeNull();
  });

  it("normalizes pinned rivals like the board, and allows at most three", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, {
      ...withNotifications,
      competitors: ["me", "alice", "bob", "carol"],
      rivals: ["@Alice", "BOB", "carol"],
    });
    expect(res.status).toBe(201);
    expect(JSON.parse((await row())!.rivals_json as string)).toEqual(["alice", "bob", "carol"]);
  });

  it("deletes the installation, ending Live rank, when both features are off", async () => {
    await call("PUT", `/v1/installations/${ID}`, registration);
    await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "act-1", pushToken: ACTIVITY_TOKEN });
    const res = await call("PUT", `/v1/installations/${ID}`, { ...registration, liveRank: false, notifications: null });
    expect(res.status).toBe(204);
    expect(await row()).toBeNull();
    expect(apns.events()).toEqual([`end:${ACTIVITY_TOKEN}`]);
  });

  it("never creates an installation with both features off", async () => {
    const res = await call("PUT", `/v1/installations/${ID}`, { ...registration, liveRank: false });
    expect(res.status).toBe(204);
    expect(await row()).toBeNull();
  });

  it("turning Live rank off ends its activity and forgets its tokens", async () => {
    await call("PUT", `/v1/installations/${ID}`, withNotifications);
    await call("PUT", `/v1/installations/${ID}`, { ...withNotifications, liveRank: true });
    await call("PUT", `/v1/installations/${ID}/activity`, { activityId: "act-1", pushToken: ACTIVITY_TOKEN });
    await call("PUT", `/v1/installations/${ID}`, withNotifications);
    const stored = await row();
    expect(stored!.live_rank).toBe(0);
    expect(stored!.activity_push_token).toBeNull();
    expect(stored!.push_to_start_token).toBeNull();
    expect(apns.events()).toEqual([`end:${ACTIVITY_TOKEN}`]);
  });
});

describe("migration 0004", () => {
  it("gives rows from before it Live rank on and no notifications", async () => {
    // Exactly the columns the 1.0.x Worker's INSERT names.
    await env.DB.prepare(
      `INSERT INTO installations (id, secret_hash, apns_environment, push_to_start_token, login,
         competitors_json, window, time_zone, rate_window_start, rate_count, created_at, updated_at)
       VALUES (?, 'h', 'sandbox', NULL, 'me', '["me"]', 'daily', 'UTC', 0, 0, 0, 0)`,
    ).bind(ID).run();
    const stored = await row();
    expect(stored!.live_rank).toBe(1);
    expect(stored!.notifications_json).toBeNull();
    expect(stored!.alert_token).toBeNull();
    expect(stored!.notification_state).toBeNull();
    expect(JSON.parse(stored!.rivals_json as string)).toEqual([]);
  });
});
