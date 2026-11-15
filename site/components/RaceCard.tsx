import type { Racer } from "@/lib/challenge";

const W = 320;
const H = 128;
const PAD = 6;

/** Running totals as one polyline, scaled to the larger total. */
function points(running: readonly number[], max: number): string {
  const last = Math.max(running.length - 1, 1);
  return running
    .map((value, i) => {
      const x = PAD + (i / last) * (W - PAD * 2);
      const y = H - PAD - (max === 0 ? 0 : (value / max) * (H - PAD * 2));
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
}

/**
 * The challenge's race card: both 30-day totals (you in lime), both running totals drawn over the
 * 30 days with the latest change of lead marked, and who passed whom.
 */
export function RaceCard({ racers, leadLine, markDay, days }: { racers: readonly Racer[]; leadLine: string; markDay: number | null; days: number }) {
  const max = Math.max(...racers.map((racer) => racer.running.at(-1) ?? 0));
  const markX = markDay === null ? null : PAD + (markDay / Math.max(days - 1, 1)) * (W - PAD * 2);
  const spoken = `${racers.map((racer) => `${racer.name} ${racer.total}`).join(", ")}, over ${days} days. ${leadLine}`;

  return (
    <figure data-field-desk aria-label={spoken} className="relative mx-auto w-full max-w-[34rem] rounded-[22px] border border-white/10 bg-ink/85 p-5 text-left shadow-[0_30px_80px_-30px_rgba(0,0,0,.9)] backdrop-blur-md sm:p-7">
      <p className="font-mono text-[11px] font-medium tracking-[.06em] text-muted uppercase">Last {days} days</p>
      <dl className="mt-4 grid grid-cols-2 gap-4">
        {racers.map((racer) => (
          <div key={racer.login} className="min-w-0">
            <dt className={`truncate text-[15px] font-semibold ${racer.you ? "text-lime" : "text-soft"}`}>{racer.name}</dt>
            <dd className={`mt-1 text-[clamp(36px,9vw,52px)] leading-none font-[750] tracking-[-0.045em] tabular-nums ${racer.you ? "text-lime" : "text-white"}`}>
              {racer.total}
            </dd>
          </div>
        ))}
      </dl>
      <svg aria-hidden viewBox={`0 0 ${W} ${H}`} className="mt-6 block h-auto w-full overflow-visible" preserveAspectRatio="none">
        <line x1={PAD} x2={W - PAD} y1={H - PAD} y2={H - PAD} stroke="rgb(255 255 255 / 0.1)" strokeWidth="1" vectorEffect="non-scaling-stroke" />
        {markX === null ? null : (
          <line x1={markX} x2={markX} y1={PAD} y2={H - PAD} stroke="rgb(255 255 255 / 0.28)" strokeWidth="1" strokeDasharray="3 4" vectorEffect="non-scaling-stroke" />
        )}
        {/* Theirs under yours, so a level stretch shows your lime line. */}
        {[...racers].reverse().map((racer) => (
          <polyline
            key={racer.login}
            points={points(racer.running, max)}
            fill="none"
            stroke={racer.you ? "var(--color-lime)" : "var(--color-muted)"}
            strokeWidth={racer.you ? 3 : 2.25}
            strokeLinejoin="round"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
        ))}
      </svg>
      <figcaption className="mt-5 border-t border-white/[.08] pt-4 text-[15px] leading-relaxed text-soft">{leadLine}</figcaption>
    </figure>
  );
}
