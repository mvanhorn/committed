import { readFile } from "node:fs/promises";
import { join } from "node:path";

/** Inter Tight for `next/og` images, read from `app/fonts` (traced into server bundles by next.config.ts). */
export async function ogFonts() {
  const [regular, extraBold] = await Promise.all([
    readFile(join(process.cwd(), "app/fonts/InterTight-Regular.ttf")),
    readFile(join(process.cwd(), "app/fonts/InterTight-ExtraBold.ttf")),
  ]);
  return [
    { name: "Inter Tight", data: regular, weight: 400 as const, style: "normal" as const },
    { name: "Inter Tight", data: extraBold, weight: 800 as const, style: "normal" as const },
  ];
}
