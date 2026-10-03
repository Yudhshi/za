// 坐站の小窓:牛皮纸の台紙(360 幅)に皱纹纸胶带の持ち手。播报の钟:尋ねない。
// 「站起来」→ 腹式呼吸 3 回 → 拉伸の手順(時間が来たら自動で次へ)→ 做完 → 自分で閉じる。30 分後に「坐下」→ 15 秒で閉じる。
// ユーザーがするのは、钟が間違えたときの「我还坐着」「我还站着」だけ。
// 立っているときは離れて見るので、この手順の残り秒を模板の大字で、動作の名前を大きく出す。
// 画面は状態が変わったときだけ作り直す(4 分の 1 秒ごとに作り直すと、押している途中のボタンが消えて押せない)。秒の数字だけを差し替える
import { loadMaterial, slice, sprite, stencil, h, button, first } from "./baked.js";
import { call, listen, fitWindow, enableDragging } from "./api.js";
import { loadIcons, clock, clear, sound } from "./common.js";

const $ = (id) => document.getElementById(id);
let view = null;
let lastSize = "";
/** いま描いてある画面(状態の鍵)。違うときだけ render() */
let drawnKey = null;
let finishing = false;
/** 拉伸の手順は時間が来たら自動で次へ(押さなくていい)。手順が替わったら(自分で押しても)計り直す */
let stepKey = "";
let stepStart = 0;
/** 手順の自動送りと「下一步」が同時に走らないように */
let advancing = false;
/** 全部やり終えた画面 / 「坐下」を見せ始めた時刻(しばらくして自分で閉じる) */
let lingerSince = 0;
let closing = false;
/** 切り替えの音を鳴らした姿勢(since で区別。作り直しで二度鳴らさない) */
let soundedSwitch = 0;
/** 一度でも中身を描いたか(出場の動きは最初の中身で) */
let entered = false;
/** 注意書きは一日に一度だけ(見れば分かる。立っているときの小窓に 2 行は要らない) */
let showCaution = null;

/** 「站起来」の一言を見せる長さ。呼吸はこの後に始まる */
const ANNOUNCE_MS = 7000;
const DONE_LINGER_MS = 15000;
const SIT_LINGER_MS = 15000;
/** 切り替えの音と「我还坐着」は切り替えてからこのあいだだけ(一言 + 呼吸 + 最初の手順。あとで小窓を開き直しても鳴らさない・出さない) */
const FRESH_MS = 90000;
const BREATH = { inhale: 4, exhale: 6, breaths: 3 };

/** 「站起来」の一言の分(钟が自分で立たせたときだけ) */
function announceMs() {
  return view.announced ? ANNOUNCE_MS : 0;
}

/** 呼吸を始めてからの秒数(「站起来」の一言の分は引く。負なら、まだ一言の最中) */
function breathElapsed() {
  return (Date.now() - view.breathStartedAt - announceMs()) / 1000;
}

function breathState(elapsed) {
  const cycle = BREATH.inhale + BREATH.exhale;
  const total = cycle * BREATH.breaths;
  if (elapsed >= total) return { breath: BREATH.breaths, inhaling: false, remaining: 0, inPhase: 0, finished: true };
  const breath = Math.floor(elapsed / cycle);
  const t = elapsed - breath * cycle;
  return t < BREATH.inhale
    ? { breath, inhaling: true, remaining: Math.ceil(BREATH.inhale - t), inPhase: t, finished: false }
    : { breath, inhaling: false, remaining: Math.ceil(cycle - t), inPhase: t - BREATH.inhale, finished: false };
}

/** いまの手順の残り(ミリ秒)。全部終えていれば null */
function stepLeft() {
  const count = view.steps.length;
  const step = Math.min(view.step, count);
  if (step >= count) return null;
  const key = `${view.stretch?.name ?? ""}#${step}`;
  if (key !== stepKey) {
    stepKey = key;
    stepStart = Date.now();
    advancing = false;
  }
  const total = (view.durations?.[step] ?? 10) * 1000;
  return Math.max(0, total - (Date.now() - stepStart));
}

/** 「斜角肌拉伸（约 2 分钟）」→「斜角肌拉伸」 */
function title(name) {
  return (name ?? "").split(/[（(]/)[0].trim() || name;
}

function cautionDue() {
  if (showCaution !== null) return showCaution;
  try {
    const today = new Date().toDateString();
    showCaution = localStorage.getItem("cautionDay") !== today;
    localStorage.setItem("cautionDay", today);
  } catch {
    showCaution = true;
  }
  return showCaution;
}

// MARK: 部品

function pose(name, height = 132) {
  return sprite(`pose-${name}`, { height }) ?? h("div", { style: { width: `${height}px`, height: `${height}px` } });
}

function dots(count, index) {
  return h(
    "div",
    { class: "dots row" },
    Array.from({ length: count }, (_, i) => {
      const s = i < index ? "done" : i === index ? "current" : "future";
      return sprite(`dot-${s}-kraft`, { height: i === index ? 16 : 10 });
    }),
  );
}

/** 模板の大字(set = timer-black 28 / mid-black 58 の字高)。無ければ太字 */
function figure(text, set, cls = "", fallbackPx = 34) {
  const el = stencil(text, set) ?? h("span", { class: "t-time", style: { fontSize: `${fallbackPx}px` } }, text);
  if (cls) el.classList.add(cls);
  return el;
}

function chip(text) {
  const el = h("span", { class: "chip" }, text);
  slice(el, first("chip-black-kraft", "chip-black-card")) || (el.style.background = "var(--black)");
  return el;
}

function tape(text) {
  const el = $("tape");
  el.textContent = text;
  slice(el, "tape-handle-night") || (el.style.background = "#e6d9b0");
}

/** 立ち作業の残り(小さく。遠くから見て要るのは手順の秒のほう) */
function smallTimer() {
  return h("span", { class: "small-timer tick-timer" }, `还剩 ${clock(view.dueAt - Date.now())}`);
}

/** 切り替えたばかりか(钟が自分で、かつ 1 分半以内) */
function fresh() {
  return view.announced && Date.now() - view.since < FRESH_MS;
}

/** 钟が間違えたときの一言(钟が自分で立たせた / 座らせた直後だけ:一言・呼吸・最初の手順のあいだ) */
function correction() {
  if (!fresh()) return null;
  const standing = view.posture === "standing";
  return h("button", { class: "bare on-kraft", onclick: () => leave(standing ? "stillSitting" : "stillStanding") }, standing ? "我还坐着" : "我还站着");
}

async function act(action) {
  view = await call("posture_action", { action });
  render();
}

/** 揭がしてから閉じる(閉じる操作はみんなここを通る) */
function leave(action = "close") {
  if (closing) return;
  closing = true;
  $("wrap").classList.add("leaving");
  setTimeout(() => act(action).finally(() => (closing = false)), 170);
}

/** 次の手順へ(ボタンからも自動送りからも、同時には 1 回だけ)。最後の手順を終えたら「做完」の音 */
async function next() {
  if (advancing) return;
  advancing = true;
  try {
    const last = Math.min(view.step, view.steps.length) >= view.steps.length - 1;
    await act("next");
    if (last && view?.prompt === "standing" && phase() === "done") sound("done");
  } finally {
    advancing = false;
  }
}

// MARK: 画面

/** 「站起来」:呼吸はこの一言のあとに始まる */
function announce() {
  tape("STAND UP");
  return [
    h("div", { class: "head row" }, h("span", { class: "label" }, "到点了"), smallTimer(), h("span", { class: "grow" }), correction()),
    h(
      "div",
      { class: "body row" },
      pose("stand-up"),
      h(
        "div",
        { class: "col" },
        h("div", { class: "announce" }, "站起来"),
        h("div", { class: "text" }, "桌子升到手肘 90°，顺便喝口水"),
        h("div", { class: "muted" }, `${view.breathStartedAt ? "先 3 次腹式呼吸，然后：" : "然后："}${title(view.stretch?.name)}`),
      ),
    ),
  ];
}

function breath(s) {
  tape("BREATHE");
  const ring = h("div", { class: `breath-ring ${s.inhaling ? "inhale" : "exhale"}` }, h("div", { class: "ink", style: { animationDelay: `${-s.inPhase}s` } }));
  return [
    h("div", { class: "head row" }, h("span", { class: "label" }, "3 次腹式呼吸"), h("span", { class: "grow" }), correction(), dots(BREATH.breaths, s.breath)),
    h(
      "div",
      { class: "body row" },
      ring,
      h(
        "div",
        { class: "col" },
        h("div", { class: "row", style: { gap: "10px", alignItems: "baseline" } }, h("span", { class: "breath-word" }, s.inhaling ? "吸" : "呼"), figure(String(s.remaining), "timer-black", "tick-breath")),
        h("div", { class: "text" }, s.inhaling ? "用鼻子吸，只让肚子鼓起来" : "用嘴慢慢呼，肚子瘪下去"),
        h("div", { class: "muted" }, "一只手放在肚子上，胸口和肩膀不动"),
      ),
    ),
    h(
      "div",
      { class: "buttons row" },
      h("span", { class: "muted" }, `今天第 ${view.breathToday + 1} 次`),
      h("span", { class: "grow" }),
      h("button", { class: "bare on-kraft", onclick: () => act("breathSkip") }, "跳过"),
    ),
  ];
}

function stepOf(step, count) {
  return `第 ${step + 1}/${count} 步`;
}

/** 拉伸の手順(遠くから見る:残り秒が主役) */
function standing() {
  tape("STRETCH");
  const count = view.steps.length;
  const step = Math.min(view.step, count);
  const done = step >= count;
  const current = view.steps[step];
  const left = stepLeft();
  if (done) {
    return [
      h("div", { class: "head row" }, h("span", { class: "label" }, "做完了"), smallTimer(), h("span", { class: "grow" }), dots(count, step)),
      h(
        "div",
        { class: "body row" },
        pose("walk"),
        h("div", { class: "col" }, h("div", { class: "heading far" }, "站着把剩下的时间用完"), h("div", { class: "text" }, "到点我会说「坐下」。这个小窗一会儿自己关。")),
      ),
      h("div", { class: "buttons row" }, h("span", { class: "grow" }), button("关闭", { kind: "frame", onKraft: true, width: 135, onClick: () => leave("close") })),
    ];
  }
  return [
    h(
      "div",
      { class: "head row" },
      h("span", { class: "label" }, "站立中"),
      smallTimer(),
      h("span", { class: "grow" }),
      step > 0 ? h("button", { class: "bare on-kraft", onclick: () => act("prev") }, "‹ 上一步") : correction(),
      dots(count, step),
    ),
    h(
      "div",
      { class: "body row" },
      pose(current.pose),
      h("div", { class: "col" }, h("div", { class: "heading far" }, view.heading), current.meta ? chip(current.meta) : null, h("div", { class: "text" }, current.text)),
    ),
    h(
      "div",
      { class: "count row" },
      figure(String(Math.ceil((left ?? 0) / 1000)), "mid-black", "tick-count", 52),
      h("span", { class: "unit" }, step === count - 1 ? "秒后做完" : "秒后下一步"),
      h("span", { class: "grow" }),
      h("span", { class: "step-of" }, stepOf(step, count)),
    ),
    cautionDue() ? h("div", { class: "muted" }, view.caution) : null,
    h(
      "div",
      { class: "buttons row" },
      button(step === count - 1 ? "做完了" : "下一步", { kind: "teal", width: 169, onClick: next }),
      button("结束拉伸", { kind: "frame", onKraft: true, width: 135, onClick: () => leave("close") }),
    ),
  ];
}

/** 「坐下」:今日の数字を一行添える。15 秒で自分で閉じる */
function sit() {
  tape("SIT DOWN");
  return [
    h("div", { class: "head row" }, h("span", { class: "label" }, "到点了"), h("span", { class: "grow" }), correction()),
    h(
      "div",
      { class: "body row" },
      pose("sit-down"),
      h("div", { class: "col" }, h("div", { class: "announce" }, "坐下"), h("div", { class: "text" }, view.lastStandMinutes >= 1 ? `站了 ${view.lastStandMinutes} 分钟，坐下歇一歇` : "坐下歇一歇"), h("div", { class: "muted" }, view.today)),
    ),
    h("div", { class: "buttons row" }, h("span", { class: "muted" }, "30 分钟后再叫你"), h("span", { class: "grow" }), h("button", { class: "bare on-kraft", onclick: () => leave("close") }, "关闭")),
  ];
}

/** いまの段(立っている小窓の中):一言 → 呼吸 → 手順 → 做完 */
function phase() {
  if (view.announced && Date.now() - view.since < ANNOUNCE_MS) return "announce";
  if (view.breathStartedAt) return breathState(breathElapsed()).finished ? "breath-done" : "breath";
  return Math.min(view.step, view.steps.length) >= view.steps.length ? "done" : "stretch";
}

/** いまの画面の鍵:これが変わったときだけ作り直す(呼吸は吸う / 吐くの切り替わりごと、拉伸は手順ごと) */
function stateKey() {
  if (!view?.prompt) return "none";
  if (view.prompt === "sit") return `sit|${view.since}`;
  const p = phase();
  if (p === "announce") return `announce|${view.since}`;
  if (p === "breath") {
    const s = breathState(breathElapsed());
    return `breath|${s.breath}|${s.inhaling}`;
  }
  if (p === "breath-done") return "breath-done";
  return `stretch|${view.stretch?.name ?? ""}#${Math.min(view.step, view.steps.length)}`;
}

function render() {
  const sheet = $("sheet");
  const key = stateKey();
  // 画面が替わったら、しばらく見せてから閉じる数え直し(做完 → 坐下 と続いても「坐下」を 15 秒見せる)
  if (key !== drawnKey) lingerSince = 0;
  drawnKey = key;
  if (!view?.prompt) return clear(sheet);
  // 切り替えの音は切り替えた直後に一度(钟が自分で切り替えたときだけ。あとで小窓を開き直したときや、トレイから開いたときは鳴らさない)
  if (fresh() && soundedSwitch !== view.since) {
    soundedSwitch = view.since;
    sound("switch");
  }
  let content;
  if (view.prompt === "sit") {
    lingerSince ||= Date.now();
    content = sit();
  } else {
    const p = phase();
    if (p === "announce") content = announce();
    else if (p === "breath") content = breath(breathState(breathElapsed()));
    else if (p === "breath-done") {
      // 3 回終わった:記録して拉伸へ。終わるまで前の画面を残す(空にして窓を縮めない)
      if (!finishing) {
        finishing = true;
        act("breathDone").finally(() => (finishing = false));
      }
      return;
    } else content = standing();
  }
  clear(sheet, content);
  if (!slice(sheet, "kraft-sheet-night")) sheet.classList.add("fallback");
  // 出場の動き(胶带から紙が下へ広がる)は最初の中身と一緒に
  if (!entered) {
    entered = true;
    $("wrap").classList.add("entering");
  }
  // 中身の高さが変わったときだけ窓を合わせる(offset は出場の変形を含まない)
  requestAnimationFrame(() => {
    const wrap = $("wrap");
    const size = `${wrap.offsetWidth + 28}x${wrap.offsetHeight + 34}`;
    if (size === lastSize) return;
    lastSize = size;
    fitWindow("posture", wrap.offsetWidth + 28, wrap.offsetHeight + 34);
  });
}

/** 4 分の 1 秒ごと:画面の鍵が変わっていれば作り直し、同じなら秒の数字だけ差し替える */
function tick() {
  if (!view?.prompt) return;
  if (stateKey() !== drawnKey) {
    render();
    return;
  }
  const sheet = $("sheet");
  if (view.prompt === "sit") {
    if (!closing && Date.now() - lingerSince > SIT_LINGER_MS) leave("close");
    return;
  }
  sheet.querySelector(".tick-timer")?.replaceWith(smallTimer());
  const p = phase();
  if (p === "announce") return;
  if (p === "breath") {
    const s = breathState(breathElapsed());
    sheet.querySelector(".tick-breath")?.replaceWith(figure(String(s.remaining), "timer-black", "tick-breath"));
    return;
  }
  if (p === "done") {
    // 全部やり終えた:しばらく見せてから自分で閉じる(「关闭」を押さなくていい)
    lingerSince ||= Date.now();
    if (!closing && Date.now() - lingerSince > DONE_LINGER_MS) leave("close");
    return;
  }
  lingerSince = 0;
  const count = view.steps.length;
  const step = Math.min(view.step, count);
  const left = stepLeft();
  if (left === 0) {
    if (!advancing) {
      // 次の手順がある:「换步」の音。最後の手順なら next() が「做完」の音を鳴らす
      if (step < count - 1) sound("step");
      next();
    }
    return;
  }
  sheet.querySelector(".tick-count")?.replaceWith(figure(String(Math.ceil(left / 1000)), "mid-black", "tick-count", 52));
}

async function init() {
  await Promise.all([loadMaterial(), loadIcons()]);
  enableDragging();
  view = await call("posture_state");
  render();
  listen("posture-changed", async () => {
    view = await call("posture_state");
    render();
  });
  setInterval(tick, 250);
}

init();
