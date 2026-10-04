// ゲーム中の一言の帯(320×76):钟がゲーム中に切り替えたときだけ、「站起来」/「坐下」と一行。
// フォーカスを取らない窓(押しても取らない)。切り替えの音を一度鳴らし、12 秒で(押せばすぐ)自分で閉じる。手順は出さない
import { loadMaterial, tile, h } from "./baked.js";
import { call, listen } from "./api.js";
import { loadSounds, sound, clear } from "./common.js";

const SHOW_MS = 12000;
let view = null;
/** いま見せている切り替え(since)。替わったら 12 秒を数え直し、音を鳴らす */
let shownSince = 0;
let timer = null;
let closing = false;

/** 切り替えの音は一度だけ(坐站の小窓と同じ印:作り直しても、両方の窓でも二度鳴らさない) */
function soundOnce(since, kind) {
  try {
    if (localStorage.getItem("soundedSince") === String(since)) return;
    localStorage.setItem("soundedSince", String(since));
  } catch {
    /* 覚えられなくても鳴らす */
  }
  sound(kind);
}

function leave() {
  if (closing) return;
  closing = true;
  document.body.classList.add("leaving");
  setTimeout(() => call("posture_action", { action: "close" }).catch(() => {}), 200);
}

function render() {
  const root = document.getElementById("note");
  if (view?.prompt !== "brief") return clear(root);
  const standing = view.posture === "standing";
  if (shownSince !== view.since) {
    shownSince = view.since;
    closing = false;
    document.body.classList.remove("leaving");
    clearTimeout(timer);
    timer = setTimeout(leave, SHOW_MS);
    soundOnce(view.since, standing ? "switch" : "sit");
  }
  const minutes = Math.round((view.dueAt - view.since) / 60000);
  const kind = standing ? "stand" : "sit";
  clear(
    root,
    h("div", { class: `edge ${kind}` }),
    h(
      "div",
      { class: "text" },
      h(
        "div",
        { class: "top" },
        h("span", { class: `word ${kind}` }, standing ? "站起来" : "坐下"),
        h("span", { class: "meta" }, standing ? `站 ${minutes} 分钟` : view.lastStandMinutes >= 1 ? `站了 ${view.lastStandMinutes} 分钟` : ""),
      ),
      h("div", { class: "line" }, standing ? "桌子升到手肘 90°，接着玩" : "桌子降下来，接着玩"),
    ),
  );
}

async function init() {
  await Promise.all([loadMaterial(), loadSounds()]);
  tile(document.body, "concrete-night");
  document.body.addEventListener("click", leave);
  view = await call("posture_state");
  render();
  listen("posture-changed", async () => {
    view = await call("posture_state");
    render();
  });
}

init();
