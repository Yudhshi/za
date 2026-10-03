// Mac 版の焼いた素材と字体を ui/ に写す(git には入れない。ビルドの前に毎回)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, "..");
const mac = path.resolve(app, "../../nippo/Resources");

function copyDir(from, to, filter = () => true, { clean = true } = {}) {
  if (clean) fs.rmSync(to, { recursive: true, force: true });
  fs.mkdirSync(to, { recursive: true });
  let count = 0;
  for (const name of fs.readdirSync(from)) {
    if (!filter(name)) continue;
    fs.copyFileSync(path.join(from, name), path.join(to, name));
    count += 1;
  }
  return count;
}

const material = copyDir(path.join(mac, "Material"), path.join(app, "ui/material"));
// 字体のフォルダは消さない:中文の見出しの切り出し(NotoSansCJKsc-Black-subset.woff2)はこちらの git に入っている
const fonts = copyDir(path.join(mac, "Fonts"), path.join(app, "ui/fonts"), (n) => n.endsWith(".ttf") || n.endsWith(".txt"), { clean: false });
// 模板アイコン(Mac と同じ 13 個)
fs.copyFileSync(path.resolve(mac, "../scripts/material/icons.svg"), path.join(app, "ui/material/icons.svg"));
console.log(`copied ${material} material files and ${fonts} font files from ${mac}`);
