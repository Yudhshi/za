// 拉伸という「もの」の見た目を 1 か所に:小窓(compact)・日课の舞台(stage)・設定の拉伸库(preview)で同じ牛皮纸の卡。
// 中身(姿勢の絵・題・黒牌・文・残り秒)の部品と、設定でテキストから構造を読む小さな道具
import { slice, sprite, stencil, h, first, has } from "./baked.js";

/** 牛皮纸を敷く(無ければ色) */
export function kraft(el) {
  if (!slice(el, "kraft-sheet-night")) el.classList.add("fallback");
  return el;
}

export function pose(name, height = 132) {
  return sprite(`pose-${name}`, { height }) ?? h("div", { style: { width: `${height}px`, height: `${height}px` } });
}

/** 小さい姿勢の絵(一覧の行・日课の次の手順) */
export function poseSmall(name, height = 44) {
  return sprite(`pose-${name}-s`, { height }) ?? sprite(`pose-${name}`, { height }) ?? h("div", { style: { width: `${height}px`, height: `${height}px` } });
}

export function dots(count, index) {
  return h(
    "div",
    { class: "dots row" },
    Array.from({ length: count }, (_, i) => {
      const s = i < index ? "done" : i === index ? "current" : "future";
      return sprite(`dot-${s}-kraft`, { height: i === index ? 16 : 10 });
    }),
  );
}

export function chip(text) {
  const el = h("span", { class: "chip" }, text);
  slice(el, first("chip-black-kraft", "chip-black-card")) || (el.style.background = "var(--black)");
  return el;
}

/** 模板の数字。役割ごとに 1 つの大きさ:count-black = 手順の残り秒(字高 40)、timer-black = 呼吸(28)、mid-black = 日课の舞台(58) */
export function figure(text, set, cls = "", fallbackPx = 34) {
  const el = stencil(text, set) ?? h("span", { class: "t-time", style: { fontSize: `${fallbackPx}px` } }, text);
  if (cls) el.classList.add(cls);
  return el;
}

/** 本体:姿勢の絵 + 題(遠くから読める大きさ)+ 黒牌 + 文 */
export function stretchBody({ pose: poseName, heading, meta, text, note, far = true, poseHeight = 132 }) {
  return h(
    "div",
    { class: "body row" },
    pose(poseName, poseHeight),
    h("div", { class: "col" }, h("div", { class: `heading${far ? " far" : ""}` }, heading), meta ? chip(meta) : null, text ? h("div", { class: "text" }, text) : null, note ? h("div", { class: "muted" }, note) : null),
  );
}

/** 残り秒の行:模板の大字 + 単位 + 右に「第 N/M 步」 */
export function countRow({ seconds, unit, note, set = "count-black", fallbackPx = 40 }) {
  return h(
    "div",
    { class: "count row" },
    figure(String(Math.max(0, seconds)), set, "tick-count", fallbackPx),
    h("span", { class: "unit" }, unit),
    h("span", { class: "grow" }),
    note ? h("span", { class: "step-of" }, note) : null,
  );
}

/** 「坐 | 站」の札:姿勢という「もの」。いまの側が黒、押すと返る(帯・トレイ・小窓・今天で同じ) */
export function postureChip(posture, onFlip, { onKraft = false, disabled = false } = {}) {
  const el = h("button", {
    class: `posture-chip row${onKraft ? " on-kraft" : ""}`,
    title: disabled ? "休息中，不用换" : "点一下换姿势：刚被叫的话等于「说错了」",
    "data-no-drag": "",
    disabled,
  });
  for (const [key, label] of [
    ["sitting", "坐"],
    ["standing", "站"],
  ]) {
    const half = h("span", { class: `half${posture === key ? " on" : ""}` }, label);
    if (posture === key) slice(half, first(onKraft ? "chip-black-kraft" : "chip-black-card", "chip-black-card")) || (half.style.background = "var(--black)");
    el.append(half);
  }
  el.addEventListener("click", (e) => {
    e.stopPropagation();
    if (!disabled) onFlip?.();
  });
  return el;
}

// MARK: 設定の拉伸库:テキスト ⇄ 構造(Rust の stretches() / duration() / illustration() と同じ規則)

/** 空行区切りの塊 → [{ name, steps }] */
export function parseStretches(text) {
  const out = [];
  let block = [];
  for (const raw of `${text ?? ""}\n`.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) {
      if (block.length) out.push({ name: block[0], steps: block.slice(1) });
      block = [];
    } else block.push(line);
  }
  return out;
}

export function renderStretches(list) {
  return list
    .filter((s) => s.name.trim())
    .map((s) => [s.name.trim(), ...s.steps.map((l) => l.trim()).filter(Boolean)].join("\n"))
    .join("\n\n");
}

const half = (s) => s.replace(/[！-～]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0)).replace(/　/g, " ");

function numbersBefore(text, unit) {
  const re = new RegExp(`(\\d+)\\s*${unit}`, "g");
  return [...half(text).matchAll(re)].map((m) => Number(m[1]));
}

/** 1 歩の秒数(秒 × 回数 + 回の間 2 秒 / 秒 / 回 × 4 秒 / 分。無ければ 10 秒の構え) */
export function stepSeconds(line) {
  const t = half(line);
  const secs = numbersBefore(t, "秒").reduce((a, b) => a + b, 0);
  const after = t.match(/[×xX]\s*(\d+)/);
  const reps = after ? Number(after[1]) : numbersBefore(t, "[次回]")[0];
  const minutes = numbersBefore(t, "分")[0];
  if (reps > 0 && secs > 0) return secs * reps + (reps - 1) * 2;
  if (secs > 0) return secs;
  if (reps > 0) return reps * 4;
  if (minutes > 0) return minutes * 60;
  return 10;
}

export function metaText(line) {
  const t = half(line);
  const secs = numbersBefore(t, "秒")[0];
  const after = t.match(/[×xX]\s*(\d+)/);
  const reps = after ? Number(after[1]) : numbersBefore(t, "[次回]")[0];
  const minutes = numbersBefore(t, "分")[0];
  if (secs && reps) return `${secs} 秒 · ${reps} 次`;
  if (secs) return `${secs} 秒`;
  if (reps) return `${reps} 次`;
  if (minutes) return `${minutes} 分钟`;
  return null;
}

const POSES = [
  [["走", "歩", "walk"], "walk"],
  [["呼吸", "息", "breath"], "belly-breathing"],
  [["肩胛", "肩甲", "blade"], "shoulder-blades"],
  [["转肩", "肩回", "转动肩", "roll"], "shoulder-rolls"],
  [["下巴", "顎", "あご", "chin"], "chin-tuck"],
  [["颈", "首", "脖", "neck"], "neck-side"],
  [["胸", "chest"], "chest-doorway"],
];

/** 拉伸の絵(名前と手順のキーワードから) */
export function illustration(stretch) {
  const text = [stretch.name, ...stretch.steps].join("").toLowerCase();
  for (const [keys, name] of POSES) if (keys.some((k) => text.includes(k))) return name;
  return "stretch";
}

/** 「夹肩胛骨（约 1 分钟）」→ 夹肩胛骨 */
export function title(name) {
  return (name ?? "").split(/[（(]/)[0].trim() || name;
}

export function totalSeconds(stretch) {
  return stretch.steps.reduce((a, l) => a + Math.max(10, stepSeconds(l)), 0);
}

export function mmss(seconds) {
  const s = Math.max(0, Math.round(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export { has };
