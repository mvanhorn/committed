import { describe, expect, it } from "vitest";
import { isQuietHours } from "../src/notifications/quietHours";

// New York is UTC−5 on 2026-11-05.
const newYork = (hour: number, minute = 0) => Date.UTC(2026, 10, 5, hour + 5, minute) / 1000;
const NIGHT = { start: "22:00", end: "08:00" };

describe("isQuietHours", () => {
  it("wraps past midnight: start inclusive, end exclusive", () => {
    const quiet = (hour: number, minute = 0) => isQuietHours(newYork(hour, minute), "America/New_York", NIGHT);
    expect(quiet(21, 59)).toBe(false);
    expect(quiet(22, 0)).toBe(true);
    expect(quiet(23, 59)).toBe(true);
    expect(quiet(0, 0)).toBe(true);
    expect(quiet(7, 59)).toBe(true);
    expect(quiet(8, 0)).toBe(false);
    expect(quiet(12, 0)).toBe(false);
  });

  it("covers hours inside one day", () => {
    const span = { start: "13:15", end: "14:45" };
    expect(isQuietHours(newYork(13, 14), "America/New_York", span)).toBe(false);
    expect(isQuietHours(newYork(13, 15), "America/New_York", span)).toBe(true);
    expect(isQuietHours(newYork(14, 44), "America/New_York", span)).toBe(true);
    expect(isQuietHours(newYork(14, 45), "America/New_York", span)).toBe(false);
  });

  it("is never quiet when off, or when start and end are the same", () => {
    expect(isQuietHours(newYork(23), "America/New_York", null)).toBe(false);
    expect(isQuietHours(newYork(23), "America/New_York", { start: "23:00", end: "23:00" })).toBe(false);
  });

  it("reads the installation's own clock", () => {
    // 15:00 UTC is 00:00 on Nov 6 in Tokyo and 10:00 in New York.
    const t = Date.UTC(2026, 10, 5, 15, 0) / 1000;
    expect(isQuietHours(t, "Asia/Tokyo", NIGHT)).toBe(true);
    expect(isQuietHours(t, "America/New_York", NIGHT)).toBe(false);
  });
});
