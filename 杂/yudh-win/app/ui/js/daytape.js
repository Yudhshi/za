// 一日の胶带(時間軸)という「もの」:今天のページ・「坐下」の小窓・初回の説明で同じ見た目。
// 黒 = 座った、青 = 立った、斜線 = 離席 / ゲーム、薄い灰 = 休み、橙の刻み = いま、点線 = この姿勢の予定。
// 印(marks:{ at: UNIX ミリ秒, kind })は時計(Rust)が記録したもの。始まりは朝に戻る時刻(既定 8 時)、終わりは 24 時
import { slice, sprite, h } from "./baked.js";
import { hhmm } from "./common.js";

const TAPE_TO = 24;

function startHour(p) {
  const q = Number(p.quietTo);
  return Number.isFinite(q) && q >= 0 && q < 12 ? Math.min(8, q) : 8;
}

function tapeX(ms, width, from) {
  const d = new Date(ms);
  const hour = d.getHours() + d.getMinutes() / 60 + d.getSeconds() / 3600;
  return Math.max(0, Math.min(1, (hour - from) / (TAPE_TO - from))) * width;
}

/** 印 → 区間([from, to, kind])。今日より前の印は今日の 0 時から */
function tapeSegments(p) {
  const now = Date.now();
  const midnight = new Date(now);
  midnight.setHours(0, 0, 0, 0);
  const marks = [...(p.marks ?? [])].sort((a, b) => a.at - b.at);
  const segs = [];
  for (let i = 0; i < marks.length; i++) {
    const from = Math.max(marks[i].at, midnight.getTime());
    const to = Math.min(i + 1 < marks.length ? marks[i + 1].at : now, now);
    if (to > from) segs.push([from, to, marks[i].kind]);
  }
  if (!marks.length && p.since) segs.push([Math.max(p.since, midnight.getTime()), now, p.posture === "sitting" ? "sit" : "stand"]);
  const planned = p.resting || !p.dueAt ? null : [now, p.dueAt, p.posture === "sitting" ? "sit" : "stand"];
  return { segs, planned, now };
}

/** onKraft:牛皮纸の上(「坐下」の小窓)。焼いた黒と青は混凝土用なので、紙の上では色だけ */
export function dayTape(p, width = 472, { onKraft = false } = {}) {
  const from = startHour(p);
  const { segs, planned, now } = tapeSegments(p);
  const track = h("div", { class: `daytape${onKraft ? " on-kraft" : ""}`, style: { width: `${width}px` } });
  const seg = (a, b, kind, plan = false) => {
    const x = tapeX(a, width, from);
    const w = Math.max(plan ? 2 : 1.5, tapeX(b, width, from) - x);
    const el = h("span", { class: `seg ${kind}${plan ? " plan" : ""}`, style: { left: `${x}px`, width: `${w}px` }, title: `${hhmm(new Date(a))}–${hhmm(new Date(b))}` });
    if (!plan && !onKraft) {
      if (kind === "sit") slice(el, "band-black-night");
      if (kind === "stand") slice(el, "block-teal-night");
    }
    return el;
  };
  for (const [a, b, kind] of segs) track.append(seg(a, b, kind));
  if (planned && planned[1] > planned[0]) track.append(seg(planned[0], planned[1], planned[2], true));
  const notch = sprite("now-notch-night", { height: 20 }) ?? h("span", { class: "notch-fallback" });
  track.append(h("span", { class: "now", style: { left: `${tapeX(now, width, from)}px` } }, notch));
  const hours = h("div", { class: "hours row", style: { width: `${width}px` } });
  const marksAt = [from, ...[12, 16, 20].filter((x) => x > from + 1), 24];
  for (const hr of marksAt) hours.append(h("span", { style: { left: `${((hr - from) / (TAPE_TO - from)) * width}px` } }, String(hr)));
  return h("div", { class: `daytape-wrap${onKraft ? " on-kraft" : ""}` }, track, hours);
}
