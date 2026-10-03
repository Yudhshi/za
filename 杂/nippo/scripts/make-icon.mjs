// Resources/AppIcon/AppIcon.svg(scripts/make-icon-svg.py が作る v12 のアイコン)から PNG を書き出し、AppIcon.icns にまとめる。
// 使い方: node scripts/make-icon.mjs [PNG の出力先]   (要: playwright。iconutil は使わない=macOS 以外でも動く)
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require("playwright");
} catch {
  const globalRoot = execSync("npm root -g").toString().trim();
  playwright = require(join(globalRoot, "playwright"));
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, "Resources/AppIcon");
const svg = readFileSync(join(dir, "AppIcon.svg"), "utf8");
// 途中の PNG は一時フォルダへ(引数で出力先を指定可)
const outDir = process.argv[2] ?? join(tmpdir(), "yudh-icon");
mkdirSync(outDir, { recursive: true });

const sizes = [16, 32, 64, 128, 256, 512, 1024];
const browser = await playwright.chromium.launch();
const page = await browser.newPage();
const png = {};
for (const size of sizes) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(
    `<html><body style="margin:0;background:transparent">` +
      svg.replace('width="1024" height="1024"', `width="${size}" height="${size}"`) +
      `</body></html>`
  );
  png[size] = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
  writeFileSync(join(outDir, `icon_${size}.png`), png[size]);
}
await browser.close();

// icns = "icns" + 全長 + (種別 4 文字 + 長さ + PNG) の並び
const entries = [
  ["icp4", 16], ["icp5", 32], ["icp6", 64],
  ["ic11", 32], ["ic12", 64], ["ic07", 128], ["ic13", 256],
  ["ic08", 256], ["ic14", 512], ["ic09", 512], ["ic10", 1024],
];
const chunks = entries.map(([type, size]) => {
  const header = Buffer.alloc(8);
  header.write(type, 0, "ascii");
  header.writeUInt32BE(png[size].length + 8, 4);
  return Buffer.concat([header, png[size]]);
});
const body = Buffer.concat(chunks);
const head = Buffer.alloc(8);
head.write("icns", 0, "ascii");
head.writeUInt32BE(body.length + 8, 4);
writeFileSync(join(dir, "AppIcon.icns"), Buffer.concat([head, body]));
console.log("Wrote", join(dir, "AppIcon.icns"));
