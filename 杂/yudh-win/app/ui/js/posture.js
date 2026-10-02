// 坐站の小窓:牛皮纸の台紙(360 幅)に皱纹纸胶带の持ち手。站起来了吗? → 腹式呼吸 3 回 → 拉伸の手順 → 坐下了吗?
// 画面は状態が変わったときだけ作り直す(4 分の 1 秒ごとに作り直すと、押している途中のボタンが消えて押せない)。
// 秒の数字だけを差し替える
import { loadMaterial, slice, sprite, stencil, h, button, first } from "./baked.js";
import { call, listen, fitWindow, enableDragging } from "./api.js";
import { loadIcons, clock, clear, chime } from "./common.js";

const $ = (id) => document.getElementById(id);
let view = null;
let lastSize = "";
/** いま描いてある画面(状態の鍵)。違うときだけ render() */
let drawnKey = null;
let finishing = false;
/** 拉伸の手順は時間が来たら自動で次へ(押さなくていい)。手順が替わったら(自分で押しても)計り直す */
let stepKey = "";
let stepStart = 0;
let advancing = false;
/** 全部やり終えた画面を見せ始めた時刻(しばらくして自分で閉じる) */
let doneSince = 0;
let closing = false;
/** 手順の自動送りと「下一步」が同時に走らないように */
const DONE_LINGER_MS = 15000;

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

const BREATH = { inhale: 4, exhale: 6, breaths: 3 };

function breathState(elapsed) {
  const total = (BREATH.inhale + BREATH.exhale) * BREATH.breaths;
  if (elapsed >= total) return { breath: BREATH.breaths, inhaling: false, remaining: 0, finished: true };
  const cycle = BREATH.inhale + BREATH.exhale;
  const breath = Math.floor(elapsed / cycle);
  const t = elapsed - breath * cycle;
  return t < BREATH.inhale
    ? { breath, inhaling: true, remaining: Math.ceil(BREATH.inhale - t), finished: false }
    : { breath, inhaling: false, remaining: Math.ceil(cycle - t), finished: false };
}

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

function timer(text, cls = "") {
  const el = stencil(text, "timer-black") ?? h("span", { class: "t-time", style: { fontSize: "34px" } }, text);
  if (cls) el.classList.add(cls);
  return el;
}

function chip(text) {
  const el = h("span", { class: "chip" }, text);
  slice(el, first("chip-black-kraft", "chip-black-card")) || (el.style.background = "var(--black)");
  return el;
}

async function act(action) {
  view = await call("posture_action", { action });
  render();
}

/** 次の手順へ(ボタンからも自動送りからも、同時には 1 回だけ) */
async function next() {
  if (advancing) return;
  advancing = true;
  try {
    await act("next");
  } finally {
    advancing = false;
  }
}

function tape(text) {
  const el = $("tape");
  el.textContent = text;
  slice(el, "tape-handle-night") || (el.style.background = "#e6d9b0");
}

function askStand() {
  tape("STAND UP");
  return [
    h(
      "div",
      { class: "row" },
      h("div", { class: "title" }, "站起来了吗？"),
      h("span", { class: "grow" }),
      // 自分で開いた問い(時間前)は、見るだけで閉じられる
      view.pinned ? h("button", { class: "bare on-kraft", onclick: () => act("close") }, "先不") : null,
    ),
    h(
      "div",
      { class: "body row" },
      pose("stand-up"),
      h(
        "div",
        { class: "col" },
        h("div", { class: "text" }, "把桌子升到手肘 90° 的高度，顺便喝杯水"),
        h("div", { class: "muted" }, `站起来先做 3 次腹式呼吸，然后：${view.nextStretch}`),
      ),
    ),
    h(
      "div",
      { class: "buttons row" },
      button("站起来了", { kind: "teal", width: 169, onClick: () => act("stood") }),
      button("15 分钟后", { kind: "frame", onKraft: true, width: 135, onClick: () => act("snooze15") }),
    ),
  ];
}

function breath(s) {
  tape("BREATHE");
  return [
    h("div", { class: "head row" }, h("span", { class: "label" }, "先做 3 次腹式呼吸"), h("span", { class: "grow" }), dots(BREATH.breaths, s.breath)),
    h(
      "div",
      { class: "body row" },
      pose("belly-breathing"),
      h(
        "div",
        { class: "col" },
        h("div", { class: "row", style: { gap: "10px", alignItems: "baseline" } }, h("span", { class: "breath-word" }, s.inhaling ? "吸" : "呼"), timer(String(s.remaining), "tick-breath")),
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

/** 「第 N/M 步 · N 秒后下一步」 */
function leftLine(step, count, left) {
  return `第 ${step + 1}/${count} 步 · ${Math.ceil((left ?? 0) / 1000)} 秒后${step === count - 1 ? "做完" : "下一步"}`;
}

function standing() {
  tape("STRETCH");
  const count = view.steps.length;
  const step = Math.min(view.step, count);
  const done = step >= count;
  const current = view.steps[step];
  const left = stepLeft();
  return [
    h(
      "div",
      { class: "head row" },
      h("span", { class: "label" }, "站立中"),
      timer(clock(view.dueAt - Date.now()), "tick-timer"),
      h("span", { class: "grow" }),
      step > 0 && !done ? h("button", { class: "bare on-kraft", onclick: () => act("prev") }, "‹ 上一步") : null,
      dots(count, step),
    ),
    h(
      "div",
      { class: "body row" },
      pose(done ? "walk" : current.pose),
      done
        ? h("div", { class: "col" }, h("div", { class: "heading" }, "做完了"), h("div", { class: "text" }, "站着把剩下的时间用完，到点了再提醒你坐下。这个小窗一会儿自己关。"))
        : h(
            "div",
            { class: "col" },
            h("div", { class: "muted tick-left" }, leftLine(step, count, left)),
            h("div", { class: "heading" }, view.heading),
            current.meta ? chip(current.meta) : null,
            h("div", { class: "text" }, current.text),
            h("div", { class: "muted" }, view.caution),
          ),
    ),
    h(
      "div",
      { class: "buttons row" },
      done
        ? [h("span", { class: "grow" }), button("关闭", { kind: "frame", onKraft: true, width: 135, onClick: () => act("close") })]
        : [
            button(step === count - 1 ? "做完了" : "下一步", { kind: "teal", width: 169, onClick: next }),
            button("结束拉伸", { kind: "frame", onKraft: true, width: 135, onClick: () => act("close") }),
          ],
    ),
  ];
}

function askSit() {
  tape("SIT DOWN");
  return [
    h("div", { class: "title" }, "坐下了吗？"),
    h("div", { class: "body row" }, pose("sit-down"), h("div", { class: "col" }, h("div", { class: "text" }, "站够了，坐下歇一歇"), h("div", { class: "muted" }, "坐着打字时手肘有支撑，键盘鼠标靠近身体"))),
    h(
      "div",
      { class: "buttons row" },
      button("坐下了", { kind: "teal", width: 169, onClick: () => act("sat") }),
      button("再站 5 分钟", { kind: "frame", onKraft: true, width: 135, onClick: () => act("snooze5") }),
    ),
  ];
}

/** いまの画面の鍵:これが変わったときだけ作り直す(呼吸は吸う / 吐くの切り替わりごと、拉伸は手順ごと) */
function stateKey() {
  if (!view?.prompt) return "none";
  if (view.prompt !== "standing") return `${view.prompt}|${view.pinned ? "pinned" : ""}`;
  if (view.breathStartedAt) {
    const s = breathState((Date.now() - view.breathStartedAt) / 1000);
    return s.finished ? "breath-done" : `breath|${s.breath}|${s.inhaling}`;
  }
  return `stretch|${view.stretch?.name ?? ""}#${Math.min(view.step, view.steps.length)}`;
}

function render() {
  const sheet = $("sheet");
  const key = stateKey();
  drawnKey = key;
  if (!view?.prompt) return clear(sheet);
  let content;
  if (view.prompt === "askStand") content = askStand();
  else if (view.prompt === "askSit") content = askSit();
  else if (view.breathStartedAt) {
    const s = breathState((Date.now() - view.breathStartedAt) / 1000);
    // 3 回終わった:記録して拉伸へ。終わるまで前の画面を残す(空にして窓を縮めない)
    if (s.finished) {
      if (!finishing) {
        finishing = true;
        act("breathDone").finally(() => (finishing = false));
      }
      return;
    }
    content = breath(s);
  } else content = standing();
  clear(sheet, content);
  if (!slice(sheet, "kraft-sheet-night")) sheet.classList.add("fallback");
  // 中身の高さが変わったときだけ窓を合わせる
  requestAnimationFrame(() => {
    const wrap = $("wrap").getBoundingClientRect();
    const size = `${Math.ceil(wrap.width + 28)}x${Math.ceil(wrap.height + 34)}`;
    if (size === lastSize) return;
    lastSize = size;
    fitWindow("posture", wrap.width + 28, wrap.height + 34);
  });
}

/** 4 分の 1 秒ごと:画面の鍵が変わっていれば作り直し、同じなら秒の数字だけ差し替える */
function tick() {
  if (view?.prompt !== "standing") return;
  if (stateKey() !== drawnKey) {
    render();
    return;
  }
  const sheet = $("sheet");
  if (view.breathStartedAt) {
    const s = breathState((Date.now() - view.breathStartedAt) / 1000);
    sheet.querySelector(".tick-breath")?.replaceWith(timer(String(s.remaining), "tick-breath"));
    return;
  }
  const count = view.steps.length;
  const step = Math.min(view.step, count);
  if (step >= count) {
    // 全部やり終えた:しばらく見せてから自分で閉じる(「关闭」を押さなくていい)
    doneSince ||= Date.now();
    if (!closing && Date.now() - doneSince > DONE_LINGER_MS) {
      closing = true;
      act("close").finally(() => (closing = false));
    }
    return;
  }
  doneSince = 0;
  const left = stepLeft();
  if (left === 0) {
    if (!advancing) {
      chime();
      next();
    }
    return;
  }
  sheet.querySelector(".tick-timer")?.replaceWith(timer(clock(view.dueAt - Date.now()), "tick-timer"));
  const line = sheet.querySelector(".tick-left");
  if (line) line.textContent = leftLine(step, count, left);
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
