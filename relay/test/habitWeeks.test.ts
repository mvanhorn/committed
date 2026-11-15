import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/habit-conformance.json";
import { fixedWeeks } from "../src/notifications/results";

/**
 * The relay's fixed weeks (last week's final) held to the Swift `FixedWeek` (CommitStandings/Store/
 * FixedWeek.swift) by the shared `weeks` cases in fixtures/habit-conformance.json: Monday through
 * Sunday in the installation's time zone, across DST changes and the date line.
 */
describe("week conformance (fixtures/habit-conformance.json `weeks`)", () => {
  it("has cases", () => {
    expect(fixture.weeks.length).toBeGreaterThan(0);
  });

  for (const c of fixture.weeks) {
    it(c.name, () => {
      expect(fixedWeeks(c.input.now, c.input.timeZone)).toEqual({
        thisWeek: c.expected.thisWeek,
        lastWeek: c.expected.lastWeek,
      });
    });
  }
});
