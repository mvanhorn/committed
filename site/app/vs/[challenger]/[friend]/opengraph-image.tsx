import { ImageResponse } from "next/og";
import { challengeView, segment } from "@/lib/challenge";
import { loadRace } from "@/lib/challenge-race";
import { GLYPH_PATH } from "@/lib/glyph";
import { ogFonts } from "@/lib/og-fonts";

export const alt = "A Committed challenge: a 30-day GitHub contributions race";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const CELL = 50;
const COLS = Math.ceil(size.width / CELL);
const ROWS = Math.ceil(size.height / CELL);
const SQUARES = ["#14170f", "#1d2e0e", "#355c12", "#6aa81a", "#c8ff2e"];

/** The square field: a fixed, seeded contribution grid, brighter toward the right edge. */
const FIELD = (() => {
  let seed = 11;
  const next = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  return Array.from({ length: COLS * ROWS }, (_, i) => {
    const lean = (i % COLS) / COLS;
    const roll = next() * 0.75 + lean * 0.3;
    return roll > 0.93 ? 4 : roll > 0.8 ? 3 : roll > 0.62 ? 2 : roll > 0.4 ? 1 : 0;
  });
})();

/** The link preview: the score, the challenger's words to the friend, and the square field. */
export default async function ChallengeImage({ params }: { params: Promise<{ challenger: string; friend: string }> }) {
  const { challenger, friend } = await params;
  const segments = [segment(challenger), segment(friend)] as const;
  const view = challengeView(...segments, await loadRace(...segments), Math.floor(Date.now() / 1000));
  const words = view.ok ? view.story : view.title;

  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", position: "relative", background: "#050505", color: "#ffffff", fontFamily: "Inter Tight" }}>
        <svg width={size.width} height={size.height} viewBox={`0 0 ${size.width} ${size.height}`} style={{ position: "absolute", top: 0, left: 0 }}>
          {FIELD.map((level, i) => (
            <rect
              key={i}
              x={(i % COLS) * CELL + CELL * 0.12}
              y={Math.floor(i / COLS) * CELL + CELL * 0.12}
              width={CELL * 0.76}
              height={CELL * 0.76}
              rx={CELL * 0.14}
              fill={SQUARES[level]}
            />
          ))}
        </svg>
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            width: size.width,
            height: size.height,
            display: "flex",
            background: "linear-gradient(90deg, #050505 0%, rgba(5,5,5,.94) 52%, rgba(5,5,5,.55) 78%, rgba(5,5,5,.2) 100%)",
          }}
        />
        <div style={{ position: "relative", display: "flex", flexDirection: "column", justifyContent: "space-between", width: "100%", padding: "72px 88px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <svg width="52" height="52" viewBox="0 0 16 16">
              <path d={GLYPH_PATH} fill="#C8FF2E" />
            </svg>
            <span style={{ fontSize: 38, fontWeight: 800, letterSpacing: -1.2 }}>Committed</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", maxWidth: 860 }}>
            {view.ok ? (
              <span style={{ fontSize: 30, fontWeight: 800, letterSpacing: 3, color: "#C8FF2E" }}>{view.score}</span>
            ) : null}
            {/* One flex item per word, so a line breaks only between words. */}
            <div style={{ display: "flex", flexWrap: "wrap", marginTop: 22, fontSize: words.length > 40 ? 68 : 84, fontWeight: 800, letterSpacing: -3.5, lineHeight: 1.02 }}>
              {words.split(" ").map((word, i) => (
                // A word never wraps inside: Satori would otherwise break "odile-m" at its hyphen.
                <div key={i} style={{ display: "flex", flexShrink: 0, marginRight: "0.22em" }}>
                  {word.split(/(-)/).filter(Boolean).map((piece, j) => (
                    <span key={j}>{piece}</span>
                  ))}
                </div>
              ))}
            </div>
          </div>
          <span style={{ fontSize: 28, color: "#8E9288" }}>gitcommitted.app</span>
        </div>
      </div>
    ),
    { ...size, fonts: await ogFonts() },
  );
}
