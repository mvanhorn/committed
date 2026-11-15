import { describe, expect, it } from "vitest";
import fixture from "../../fixtures/habit-conformance.json";
import { crossings, passCopy } from "../src/notifications/passes";

/**
 * The relay's pass detection held to the Swift `RankChangeDetector` (and the copy to
 * `NotificationService.copy(for:)`) by the shared cases in fixtures/habit-conformance.json.
 */
describe("pass conformance (fixtures/habit-conformance.json `passes`)", () => {
  it("has cases, including ones that fire nothing", () => {
    expect(fixture.passes.length).toBeGreaterThan(0);
    expect(fixture.passes.some((c) => c.expected.length === 0)).toBe(true);
  });

  for (const c of fixture.passes) {
    it(c.name, () => {
      const events = crossings(
        c.previous as Record<string, number> | null,
        c.current as Record<string, number>,
        c.self,
      );
      expect(events.map(({ rival, direction, rivalContributions, myContributions }) => ({
        rival,
        direction,
        rivalContributions,
        myContributions,
      }))).toEqual(c.expected.map(({ title: _t, body: _b, ...event }) => event));
      expect(events.map(passCopy)).toEqual(c.expected.map(({ title, body }) => ({ title, body })));
    });
  }
});
