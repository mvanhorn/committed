import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/habit-conformance.json";
import { localDate } from "../src/parser";
import { deriveRecords, type BrokenRecord, type RecordBest } from "../src/notifications/records";

/**
 * The relay's records port held to the Swift `PersonalRecords` (#127) by the shared `records`
 * cases in fixtures/habit-conformance.json. The relay notifies only best day, best week and the
 * longest streak, so it ports and checks those three, and `set` (what's broken today). The board
 * tiles the iPhone alone shows (best 30 days, days at #1, first week at #1) stay Swift-only.
 */
describe("record conformance (fixtures/habit-conformance.json `records`)", () => {
  it("has cases, including ones that set nothing and ones under the minimum", () => {
    expect(fixture.records.length).toBeGreaterThan(0);
    expect(fixture.records.some((c) => c.expected.set.length === 0)).toBe(true);
    expect(fixture.records.some((c) => c.expected.set.some((s) => !s.meetsMinimum))).toBe(true);
  });

  for (const c of fixture.records) {
    it(c.name, () => {
      const today = localDate(c.input.now, c.input.timeZone);
      expect(today).toBe(c.input.asOf);
      const records = deriveRecords(c.input.you as unknown as Record<string, number>, today);

      const best = (record: RecordBest | null) =>
        record && { value: record.value, first: record.first, last: record.last, new: record.isNew };
      expect(best(records.bestDay)).toEqual(c.expected.bestDay);
      expect(best(records.bestWeek)).toEqual(c.expected.bestWeek);
      expect(best(records.longestStreak)).toEqual(c.expected.longestStreak);

      const set = (broken: BrokenRecord) => ({
        record: broken.kind,
        value: broken.value,
        oldBest: broken.oldBest,
        meetsMinimum: broken.meetsMinimum,
      });
      expect(records.set.map(set)).toEqual(c.expected.set);
    });
  }
});
