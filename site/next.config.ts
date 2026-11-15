import type { NextConfig } from "next";

// Served by Vercel's Next.js builder. Every page is prerendered to static HTML at build time
// except the challenge page (/vs/<challenger>/<friend>), which renders on request so each pair's
// title and link-preview image are in the HTML that Messages and other crawlers read.
const nextConfig: NextConfig = {
  images: { unoptimized: true },
  trailingSlash: false,
  // The challenge image reads its fonts from disk at request time.
  outputFileTracingIncludes: { "/vs/**": ["./app/fonts/*.ttf"] },
};

export default nextConfig;
