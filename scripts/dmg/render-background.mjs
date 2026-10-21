// Renders scripts/dmg/background.html at 1x and 2x and combines them into scripts/dmg/background.tiff, the multi-resolution
// image Finder uses as the installer window background. Commit the tiff.
//
// usage: node scripts/dmg/render-background.mjs
// It needs `playwright-core` (npm i --no-save playwright-core in the repository root) and a Chromium: the one Playwright
// installed (npx playwright-core install chromium), or CHROMIUM_PATH pointing at any Chromium or Chrome binary.
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import { mkdirSync, readdirSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const require = createRequire(path.join(root, "package.json"));
let chromium;
for (const base of [root, path.join(root, "website"), process.cwd()]) {
  try {
    ({ chromium } = createRequire(path.join(base, "package.json"))("playwright-core"));
    break;
  } catch {
    // try the next place
  }
}
if (!chromium) {
  console.error("playwright-core not found. Run: npm i --no-save playwright-core");
  process.exit(1);
}

function installedChromium() {
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  const cache = path.join(homedir(), "Library/Caches/ms-playwright");
  if (!existsSync(cache)) return undefined;
  const dirs = readdirSync(cache).filter((d) => d.startsWith("chromium-")).sort().reverse();
  for (const d of dirs) {
    for (const rel of [
      "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
      "chrome-mac/Chromium.app/Contents/MacOS/Chromium",
    ]) {
      const candidate = path.join(cache, d, rel);
      if (existsSync(candidate)) return candidate;
    }
  }
  return undefined;
}

const out = path.join(root, "build/dmg");
mkdirSync(out, { recursive: true });
const executablePath = installedChromium();
const browser = await chromium.launch(executablePath ? { executablePath } : {});
for (const [scale, name] of [[1, "background.png"], [2, "background@2x.png"]]) {
  const page = await browser.newPage({ viewport: { width: 660, height: 420 }, deviceScaleFactor: scale });
  await page.goto(pathToFileURL(path.join(root, "scripts/dmg/background.html")).href);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(out, name), clip: { x: 0, y: 0, width: 660, height: 420 } });
  await page.close();
}
await browser.close();
execFileSync("sips", ["-s", "dpiWidth", "144", "-s", "dpiHeight", "144", path.join(out, "background@2x.png")], { stdio: "ignore" });
execFileSync("tiffutil", ["-cathidpicheck", path.join(out, "background.png"), path.join(out, "background@2x.png"),
  "-out", path.join(root, "scripts/dmg/background.tiff")]);
console.log("wrote scripts/dmg/background.tiff");
