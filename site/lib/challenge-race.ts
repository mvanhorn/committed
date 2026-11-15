import { cache } from "react";
import { raceUrl, type Race } from "@/lib/challenge";
import { RELAY_URL } from "@/lib/kraken";

/** How long a pair's race is reused before the relay is asked again: the relay's own cache time. */
export const RACE_REVALIDATE_SECONDS = 60;

/**
 * The pair's race from the relay, or null when it can't be read (a malformed or unknown login, a
 * relay error, or a slow answer). One read per request, shared by the page and its metadata; Next's
 * data cache keeps it a minute so the image and later visits reuse it.
 */
export const loadRace = cache(async (challenger: string, friend: string): Promise<Race | null> => {
  const url = raceUrl(RELAY_URL, challenger, friend);
  if (!url) return null;
  try {
    const response = await fetch(url, {
      next: { revalidate: RACE_REVALIDATE_SECONDS },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return null;
    return (await response.json()) as Race;
  } catch {
    return null;
  }
});
