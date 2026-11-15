import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { createRelay } from "../src/relay";
import { Clock, FakeApns, FakeGitHub } from "./support/fakes";

// 2026-11-04 08:46 in New York, so the 30 days run 2026-10-06 … 2026-11-04.
const T0 = 1_793_800_000;

let github: FakeGitHub;
let limited: boolean;
let relay: ReturnType<typeof createRelay>;

function get(query: string, init: RequestInit = {}): Promise<Response> {
  return relay.fetch(new Request(`https://relay.test/v1/race?${query}`, init));
}

/** 30 zeros with the given day positions (0 = 2026-10-06, 29 = 2026-11-04) filled in. */
function days(filled: Record<number, number>): number[] {
  return Array.from({ length: 30 }, (_, i) => filled[i] ?? 0);
}

beforeEach(() => {
  github = new FakeGitHub();
  limited = false;
  relay = createRelay({
    db: env.DB,
    apns: new FakeApns(),
    github: github.fetch,
    githubName: github.name,
    now: new Clock(T0).now,
    bundleId: "com.example.app",
    boardLimiter: { limit: async () => ({ success: !limited }) },
  });
});

describe("GET /v1/race", () => {
  it("returns both 30-day calendars, totals and the latest change of lead, readable from any origin", async () => {
    // The day before the window doesn't count.
    github.set("me", { "2026-10-05": 100, "2026-10-06": 3, "2026-10-20": 4, "2026-11-04": 5 });
    github.set("alice", { "2026-10-10": 5, "2026-11-02": 6 });

    const res = await get("login=Me&rival=@alice&tz=America/New_York");
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("cache-control")).toBe("public, max-age=60");
    const body = (await res.json()) as Record<string, unknown>;
    expect(body).toEqual({
      login: "me",
      rival: "alice",
      dates: expect.any(Array),
      days: {
        me: days({ 0: 3, 14: 4, 29: 5 }),
        alice: days({ 4: 5, 27: 6 }),
      },
      totals: { me: 12, alice: 11 },
      // me led on day one; alice passed on 10-10, me on 10-20, alice on 11-02, me on 11-04.
      latestLeadChange: { date: "2026-11-04", login: "me", kind: "passed" },
      leadChanges: 4,
      updatedAt: T0,
    });
    const dates = body.dates as string[];
    expect(dates).toHaveLength(30);
    expect(dates[0]).toBe("2026-10-06");
    expect(dates[14]).toBe("2026-10-20");
    expect(dates[29]).toBe("2026-11-04");
  });

  // The app's race stories (PersonSummary.Story), told as the latest change of lead.
  it.each<{ story: string; me: Record<string, number>; alice: Record<string, number>; latest: unknown; changes: number }>([
    {
      story: "led from the first day: no change",
      me: { "2026-10-06": 2 },
      alice: { "2026-10-07": 1 },
      latest: null,
      changes: 0,
    },
    {
      story: "level at first, then pulled ahead",
      me: { "2026-10-06": 0 },
      alice: { "2026-10-12": 4 },
      latest: { date: "2026-10-12", login: "alice", kind: "pulledAhead" },
      changes: 0,
    },
    {
      story: "a level day keeps the lead: no pass",
      me: { "2026-10-06": 2, "2026-10-20": 2 },
      alice: { "2026-10-08": 2, "2026-10-21": 1 },
      latest: null,
      changes: 0,
    },
    {
      story: "caught: level now after a lead, from the first level day",
      me: { "2026-10-06": 3 },
      alice: { "2026-10-30": 1, "2026-11-01": 2 },
      latest: { date: "2026-11-01", login: "alice", kind: "caught" },
      changes: 0,
    },
    {
      story: "never apart",
      me: { "2026-10-06": 0 },
      alice: { "2026-10-06": 0 },
      latest: null,
      changes: 0,
    },
  ])("$story", async ({ me, alice, latest, changes }) => {
    github.set("me", me);
    github.set("alice", alice);
    const body = (await (await get("login=me&rival=alice&tz=America/New_York")).json()) as Record<string, unknown>;
    expect(body.latestLeadChange).toEqual(latest);
    expect(body.leadChanges).toBe(changes);
  });

  it("dates its days in the reader's time zone", async () => {
    // 13:46 UTC on 2026-11-04 is already 03:46 on 2026-11-05 in Kiritimati (UTC+14).
    github.set("me", { "2026-10-06": 50, "2026-11-04": 1, "2026-11-05": 9 });
    github.set("alice", { "2026-11-05": 0 });
    const body = (await (await get("login=me&rival=alice&tz=Pacific/Kiritimati")).json()) as {
      dates: string[];
      totals: Record<string, number>;
    };
    expect(body.dates[0]).toBe("2026-10-07");
    expect(body.dates[29]).toBe("2026-11-05");
    expect(body.totals).toEqual({ me: 10, alice: 0 });
  });

  it("rejects bad input without reading GitHub", async () => {
    const cases: [string, string][] = [
      ["rival=alice", "invalid_login"],
      ["login=me", "invalid_rival"],
      ["login=me&rival=al ice", "invalid_rival"],
      ["login=me&rival=ME", "invalid_rival"],
      ["login=me&rival=alice&tz=Mars/Base", "invalid_time_zone"],
    ];
    for (const [query, error] of cases) {
      const res = await get(query);
      expect(res.status, query).toBe(400);
      expect(res.headers.get("access-control-allow-origin")).toBe("*");
      expect(res.headers.get("cache-control")).toBeNull();
      expect(await res.json()).toEqual({ error });
    }
    expect(github.requests).toEqual([]);
  });

  it("says so, uncached, when either login can't be read", async () => {
    github.set("me", { "2026-11-04": 1 });
    const res = await get("login=me&rival=nobody-here");
    expect(res.status).toBe(404);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("cache-control")).toBeNull();
    expect(await res.json()).toEqual({ error: "unknown_login" });
  });

  it("rate-limits per IP", async () => {
    limited = true;
    const res = await get("login=me&rival=alice");
    expect(res.status).toBe(429);
    expect(await res.json()).toEqual({ error: "rate_limited" });
    expect(github.requests).toEqual([]);
  });

  it("is read-only", async () => {
    expect((await get("login=me&rival=alice", { method: "POST", body: "{}" })).status).toBe(405);
  });
});
