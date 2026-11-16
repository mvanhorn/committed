import { describe, expect, it } from "vitest";
import { closeCallCopy } from "../src/notifications/closeCalls";
import { passCopy } from "../src/notifications/passes";
import { recordCopy, recordLine } from "../src/notifications/records";
import { dailyCopy, weeklyCopy } from "../src/notifications/results";
import { streakReminderCopy } from "../src/notifications/streakReminder";

/**
 * Counts in the relay's notification copy (spec #124 review): every new kind writes them as the
 * app does, "1,204"; pass copy stays byte for byte the shipped `NotificationService.copy(for:)`,
 * which doesn't group digits. Expected strings are written out by hand.
 */
describe("notification copy: counts", () => {
  it("groups thousands in results", () => {
    const finish = { rank: 1, mine: 1204, other: { login: "alice", contributions: 0 } };
    expect(dailyCopy(finish).body).toBe("1,204 contributions, 1,204 ahead of alice.");
    expect(weeklyCopy({ rank: 2, mine: 1100, other: { login: "bob", contributions: 2050 } }).body).toBe(
      "bob won with 2,050. You had 1,100.",
    );
  });

  it("groups thousands in close calls", () => {
    expect(
      closeCallCopy({ rival: "odile-m", toPass: 12, myContributions: 1190, rivalContributions: 1202, window: "monthly" }),
    ).toEqual({ title: "Close call: 12 to pass odile-m", body: "You're at 1,190, they're at 1,202 · 30 days" });
  });

  it("groups thousands in records, in the notification and the summary line alike", () => {
    const record = {
      id: "bestWeek:2026-11-02",
      kind: "bestWeek" as const,
      day: "2026-11-05",
      value: 1500,
      oldBest: { value: 1200, first: "2026-10-05", last: "2026-10-11" },
    };
    expect(recordCopy(record, "2026-11-05")).toEqual({
      title: "New best week",
      body: "1,500 so far this week. Your old best was 1,200.",
    });
    expect(recordLine(record, "2026-11-05")).toBe("New best week: 1,500");
    expect(recordLine(record, "2026-11-09")).toBe("New best week: 1,500 last week");
  });

  it("groups thousands in the streak reminder", () => {
    expect(streakReminderCopy(1000).title).toBe("Your 1,000-day streak");
  });

  it("leaves pass copy as shipped, without grouping", () => {
    expect(passCopy({ rival: "alice", direction: "iPassedRival", myContributions: 1204, rivalContributions: 1199 })).toEqual({
      title: "🎉 You passed alice!",
      body: "You're ahead 1204–1199. Keep climbing!",
    });
  });
});
