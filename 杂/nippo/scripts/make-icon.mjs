// Resources/AppIcon/ の SVG(scripts/make-icon-svg.py が作る「30/30」のアイコン)から PNG を書き出し、
// Mac の AppIcon.icns と Windows の ../yudh-win/app/src-tauri/icons/(png・icon.ico)をまとめて作り直す。
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
const winDir = join(root, "../yudh-win/app/src-tauri/icons");
// 途中の PNG は一時フォルダへ(引数で出力先を指定可)
const outDir = process.argv[2] ?? join(tmpdir(), "yudh-icon");
mkdirSync(outDir, { recursive: true });

const browser = await playwright.chromium.launch();
const page = await browser.newPage();
const cache = {};
async function render(name, size) {
  const key = `${name}@${size}`;
  if (cache[key]) return cache[key];
  const svg = readFileSync(join(dir, name), "utf8");
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(
    `<html><body style="margin:0;background:transparent">` +
      svg.replace('width="1024" height="1024"', `width="${size}" height="${size}"`) +
      `</body></html>`
  );
  cache[key] = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
  writeFileSync(join(outDir, `${name.replace(".svg", "")}_${size}.png`), cache[key]);
  return cache[key];
}

// ---- Mac: icns = "icns" + 全長 + (種別 4 文字 + 長さ + PNG) の並び。
// 16pt・32pt で表示される絵は簡略版(16px は軸なし)、それ以上は質感ありの AppIcon.svg
const macEntries = [
  ["icp4", 16, "AppIcon-tiny.svg"], ["icp5", 32, "AppIcon-small.svg"], ["icp6", 64, "AppIcon.svg"],
  ["ic11", 32, "AppIcon-small.svg"], ["ic12", 64, "AppIcon-small.svg"], ["ic07", 128, "AppIcon.svg"],
  ["ic13", 256, "AppIcon.svg"], ["ic08", 256, "AppIcon.svg"], ["ic14", 512, "AppIcon.svg"],
  ["ic09", 512, "AppIcon.svg"], ["ic10", 1024, "AppIcon.svg"],
];
const chunks = [];
for (const [type, size, name] of macEntries) {
  const png = await render(name, size);
  const header = Buffer.alloc(8);
  header.write(type, 0, "ascii");
  header.writeUInt32BE(png.length + 8, 4);
  chunks.push(header, png);
}
const body = Buffer.concat(chunks);
const head = Buffer.alloc(8);
head.write("icns", 0, "ascii");
head.writeUInt32BE(body.length + 8, 4);
writeFileSync(join(dir, "AppIcon.icns"), Buffer.concat([head, body]));
console.log("Wrote", join(dir, "AppIcon.icns"));

// ---- Windows: 16–24px(通知領域)= win-tiny、32–48px = win-small、それ以上 = win
const winSvg = (size) => (size <= 24 ? "win-tiny.svg" : size <= 48 ? "win-small.svg" : "win.svg");
for (const [file, size] of [["32x32.png", 32], ["128x128.png", 128], ["128x128@2x.png", 256], ["icon.png", 512]]) {
  writeFileSync(join(winDir, file), await render(winSvg(size), size));
}
// ico = 6 バイトの頭 + 16 バイトの目録 × 枚数 + PNG の並び(Vista 以降は PNG のまま入れてよい)
const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const pngs = [];
for (const size of icoSizes) pngs.push(await render(winSvg(size), size));
const icoHead = Buffer.alloc(6 + 16 * icoSizes.length);
icoHead.writeUInt16LE(0, 0);
icoHead.writeUInt16LE(1, 2);
icoHead.writeUInt16LE(icoSizes.length, 4);
let offset = icoHead.length;
icoSizes.forEach((size, i) => {
  const at = 6 + 16 * i;
  icoHead.writeUInt8(size % 256, at); // 256 は 0 と書く
  icoHead.writeUInt8(size % 256, at + 1);
  icoHead.writeUInt16LE(1, at + 4);
  icoHead.writeUInt16LE(32, at + 6);
  icoHead.writeUInt32LE(pngs[i].length, at + 8);
  icoHead.writeUInt32LE(offset, at + 12);
  offset += pngs[i].length;
});
writeFileSync(join(winDir, "icon.ico"), Buffer.concat([icoHead, ...pngs]));
console.log("Wrote", winDir, "(32x32 / 128x128 / 128x128@2x / icon.png, icon.ico)");
await browser.close();
