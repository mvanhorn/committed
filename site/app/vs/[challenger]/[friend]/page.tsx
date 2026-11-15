import type { Metadata } from "next";
import { ChallengeDownloads } from "@/components/ChallengeDownloads";
import { RaceCard } from "@/components/RaceCard";
import { SiteFooter, SiteHeader } from "@/components/SiteChrome";
import { SquareField } from "@/components/SquareField";
import { challengeView } from "@/lib/challenge";
import { loadRace } from "@/lib/challenge-race";

type Props = { params: Promise<{ challenger: string; friend: string }> };

const nowSeconds = () => Math.floor(Date.now() / 1000);

async function viewFor(params: Props["params"]) {
  const { challenger, friend } = await params;
  const segments = [decodeURIComponent(challenger), decodeURIComponent(friend)] as const;
  return { segments, view: challengeView(...segments, await loadRace(...segments), nowSeconds()) };
}

// Each pair renders on request: link-preview crawlers don't run JavaScript, so the title and
// image have to be in the HTML. It's a personal link, so it stays out of search and the sitemap.
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { segments, view } = await viewFor(params);
  const description = view.ok ? view.story : "A GitHub contributions race on Committed, for iPhone, Mac and Windows.";
  const path = `/vs/${segments.map(encodeURIComponent).join("/")}`;
  return {
    title: { absolute: view.title },
    description,
    robots: { index: false, follow: false },
    alternates: { canonical: path },
    openGraph: { type: "website", url: path, siteName: "Committed", title: view.title, description },
    twitter: { card: "summary_large_image", title: view.title, description },
  };
}

export default async function ChallengePage({ params }: Props) {
  const { view } = await viewFor(params);

  return (
    <div className="isolate flex min-h-svh flex-col overflow-x-hidden px-[clamp(20px,5vw,72px)]">
      <SiteHeader />

      <main className="mx-auto flex w-full max-w-[44rem] flex-col items-center gap-5 pt-8 pb-[clamp(40px,6vw,72px)] text-center sm:pt-14">
        <p className="font-mono text-[11px] font-medium tracking-[.06em] text-lime uppercase">{view.eyebrow}</p>
        <h1 className="max-w-[16ch] animate-rise text-[clamp(40px,8vw,76px)] leading-[0.96] font-[750] tracking-[-0.04em] [word-spacing:0.06em] text-balance">{view.headline}</h1>
        {view.ok ? <p className="max-w-[32rem] text-lg leading-relaxed text-soft">{view.subline}</p> : null}
      </main>

      {view.ok ? (
        <SquareField>
          <RaceCard racers={view.racers} leadLine={view.leadLine} markDay={view.markDay} days={view.racers[0].running.length} />
        </SquareField>
      ) : null}

      <section aria-label="Get Committed" className="mx-auto flex w-full max-w-[44rem] flex-col items-center gap-6 pb-[clamp(72px,9vw,128px)] text-center">
        <ChallengeDownloads />
        {view.ok ? (
          <p className="max-w-[30rem] text-[17px] leading-relaxed text-soft">
            {view.closing.before}
            <a href={view.followUrl} className="text-lime underline decoration-lime/40 underline-offset-4 hover:decoration-lime">
              {view.closing.link}
            </a>
            {view.closing.after}
          </p>
        ) : (
          <p className="max-w-[30rem] text-[17px] leading-relaxed text-soft">Committed is a free GitHub leaderboard for you and the people you follow. No account.</p>
        )}
      </section>

      <SiteFooter />
    </div>
  );
}
