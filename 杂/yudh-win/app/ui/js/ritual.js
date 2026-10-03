// 泡澡のあとの日课:跟练の動画(公式の埋め込み)→ 立ってやる拉伸 →(隔天)肩袖の力 → 床の拉伸 → 仰向けの腹式呼吸。
// 動画は長さが分かっていれば放し終わる時刻に自動で次へ(YouTube は播放器の「終わった」の知らせでも)。
// 拉伸は 1 歩ずつ:読んで構える 4〜9 秒のあと数え、終われば鳴らして次へ
import { loadMaterial, slice, sprite, stencil, tile, h, button, first } from "./baked.js";
import { call, openUrl, closeWindow } from "./api.js";
import { loadIcons, icon, clock, chime, clear } from "./common.js";

const $ = (id) => document.getElementById(id);

const s = {
  plan: null,
  items: [],
  index: 0,
  preparing: false,
  endsAt: null,
  pausedLeft: null,
  finished: false,
  /// 今日の分を記録したか(done 画面から戻ってまた終えても二重に数えない)
  recorded: false,
  streak: 0,
  token: 0,
  timer: null,
  lead: null,
  /// 動画が放し終わる予定の時刻(長さが分かっているとき)
  videoEndsAt: null,
};

/** 読み込みと広告の分の余白(秒)。長さどおりに切ると最後が欠ける */
const VIDEO_SLACK = 8;

function build(plan) {
  s.plan = plan;
  s.items = [
    ...plan.videos.map((v, number) => ({ type: "video", number, ...v })),
    ...plan.steps.map((step) => ({ type: "stretch", ...step })),
  ];
}

const videoCount = () => s.plan.videos.length;

function cancel() {
  clearTimeout(s.timer);
  clearTimeout(s.lead);
  s.timer = s.lead = null;
}

function enter(i) {
  // 映している最中の動画をもう一度選んだ(一覧の同じ行・最初の動画で ←):動画は続いているので数え直さない
  const same = Math.max(0, i) === s.index && !s.finished && s.items[s.index]?.type === "video";
  if (same && s.videoEndsAt) return render();
  cancel();
  s.token += 1;
  s.endsAt = s.pausedLeft = s.videoEndsAt = null;
  s.preparing = false;
  if (i >= s.items.length) return finish();
  s.index = Math.max(0, i);
  s.finished = false;
  const item = s.items[s.index];
  if (item.type === "stretch") prepare(item);
  else if (item.seconds) runVideo(item.seconds + VIDEO_SLACK);
  render();
}

/** 長さの分かっている動画:放し終わる頃に自動で次へ */
function runVideo(seconds) {
  s.videoEndsAt = Date.now() + seconds * 1000;
  const mine = s.token;
  s.timer = setTimeout(() => {
    if (s.token !== mine) return;
    chime();
    enter(s.index + 1);
  }, seconds * 1000);
}

/** YouTube の播放器からの知らせ(enablejsapi):終わったら次へ。いま映している播放器からの知らせだけ受ける
 *  (終わった知らせは 2 通り来るし、前の動画の播放器からも遅れて来る:二度進めない) */
function onPlayerMessage(e) {
  const item = s.items[s.index];
  if (item?.type !== "video" || !item.embed?.includes("youtube")) return;
  const frame = $("stage").querySelector("iframe");
  if (!frame || e.source !== frame.contentWindow) return;
  let data = e.data;
  if (typeof data === "string") {
    try {
      data = JSON.parse(data);
    } catch {
      return;
    }
  }
  const ended = (data?.event === "onStateChange" && data.info === 0) || (data?.event === "infoDelivery" && data.info?.playerState === 0);
  if (ended) {
    chime();
    enter(s.index + 1);
  }
}

/** 読んで構える時間(語音播报は無い):文の長さに合わせて 4〜9 秒。そのあと自動で計時 */
function prepare(step) {
  s.preparing = true;
  const mine = s.token;
  const text = step.stepNumber === 0 ? `${step.heading}。${step.text}` : step.text;
  startAfter(Math.min(9000, Math.max(4000, text.length * 160)), mine, step.duration);
}

function startAfter(ms, mine, seconds) {
  clearTimeout(s.lead);
  s.lead = setTimeout(() => {
    if (s.token !== mine || !s.preparing) return;
    s.preparing = false;
    run(seconds);
    render();
  }, ms);
}

function run(seconds) {
  s.endsAt = Date.now() + seconds * 1000;
  const mine = s.token;
  s.timer = setTimeout(() => {
    if (s.token !== mine) return;
    chime();
    enter(s.index + 1);
  }, seconds * 1000);
}

function togglePause() {
  const item = s.items[s.index];
  if (s.preparing && item?.type === "stretch") {
    clearTimeout(s.lead);
    s.preparing = false;
    run(item.duration);
  } else if (s.pausedLeft != null) {
    const left = s.pausedLeft;
    s.pausedLeft = null;
    run(left);
  } else if (s.endsAt) {
    clearTimeout(s.timer);
    s.pausedLeft = Math.max(0, (s.endsAt - Date.now()) / 1000);
    s.endsAt = null;
  }
  render();
}

async function finish() {
  if (s.finished) return;
  s.finished = true;
  s.index = s.items.length;
  if (!s.recorded) {
    s.recorded = true;
    s.streak = await call("ritual_done", { strength: s.plan.hasStrength });
  }
  render();
}

async function setShort(short) {
  const inStretches = s.index >= videoCount();
  build(await call("ritual_plan", { short }));
  if (inStretches || s.finished) enter(videoCount());
  else render();
}

// MARK: 画面

function pose(name, height = 132) {
  return sprite(`pose-${name}`, { height }) ?? h("div", { style: { width: `${height}px`, height: `${height}px` } });
}

function dots(count, index) {
  return h(
    "div",
    { class: "dots row" },
    Array.from({ length: count }, (_, i) => sprite(`dot-${i < index ? "done" : i === index ? "current" : "future"}-kraft`, { height: i === index ? 16 : 10 })),
  );
}

/** いまの手順の残り(ミリ秒) */
function stepLeft(step) {
  return s.preparing ? step.duration * 1000 : s.pausedLeft != null ? s.pausedLeft * 1000 : s.endsAt ? s.endsAt - Date.now() : 0;
}

function timerText(time) {
  return stencil(time, "timer-black") ?? h("span", { class: "t-time", style: { fontSize: "34px" } }, time);
}

function stretchCard(step) {
  const time = clock(stepLeft(step));
  const chip = step.meta ? h("span", { class: "chip" }, step.meta) : null;
  if (chip) slice(chip, first("chip-black-kraft", "chip-black-card")) || (chip.style.background = "var(--black)");
  const card = h(
    "div",
    { class: "sheet" },
    h("div", { class: "head row" }, h("span", { class: "label" }, step.heading), h("span", { class: "grow" }), dots(step.stepCount, step.stepNumber)),
    h(
      "div",
      { class: "body row" },
      pose(step.pose),
      h(
        "div",
        { class: "col" },
        s.preparing ? h("span", { class: "prep" }, "准备") : null,
        h("span", { class: "time" }, timerText(time)),
        chip,
      ),
    ),
    h("div", { class: "text" }, step.text),
    h("div", { class: "muted" }, s.plan.caution),
  );
  if (!slice(card, "kraft-sheet-night")) card.classList.add("fallback");
  return card;
}

function upcoming() {
  const next = s.items[s.index + 1];
  if (!next || next.type !== "stretch") return h("div", { class: "upcoming" });
  return h(
    "div",
    { class: "upcoming" },
    h("span", { class: "t-section" }, "下一步"),
    h("span", { class: "t-card-title" }, next.stepNumber === 0 ? next.name : next.heading),
    h("span", { class: "t-body", style: { color: "var(--text-2)" } }, next.text),
  );
}

function videoStage(item) {
  if (!item.embed) {
    return h(
      "div",
      { class: "done" },
      h("span", { class: "t-card-title" }, "这个视频只能在浏览器里看"),
      h("span", { class: "t-caption" }, item.page),
    );
  }
  const youtube = item.embed.includes("youtube");
  // YouTube には自分の origin を伝えて、播放器の知らせ(終わった)を受け取る
  const src = youtube && /^https?:/.test(location.origin) ? `${item.embed}&origin=${encodeURIComponent(location.origin)}` : item.embed;
  const frame = h("iframe", {
    src,
    allow: "autoplay; encrypted-media; fullscreen; picture-in-picture",
    allowfullscreen: true,
    referrerpolicy: "strict-origin-when-cross-origin",
  });
  if (youtube) {
    frame.addEventListener("load", () => {
      try {
        frame.contentWindow.postMessage(JSON.stringify({ event: "listening", id: 1, channel: "widget" }), "*");
      } catch {
        /* 知らせが来なければ長さで進む */
      }
    });
  }
  return h("div", { class: "video" }, frame);
}

/** 動画の下の一言:自動で進むか、押して進むか */
function videoNote(item) {
  if (s.videoEndsAt) return h("span", { class: "t-caption video-left" }, `${clock(s.videoEndsAt - Date.now())} 后自动下一个`);
  if (item.embed?.includes("youtube")) return h("span", { class: "t-caption" }, "放完自动下一个");
  return h("span", { class: "t-caption" }, "没写时长：看完点「跟练完了，下一个」。设置里在链接后面写上时长（如 4:35）就会自动跳");
}

function doneStage() {
  return h(
    "div",
    { class: "done" },
    h("span", { class: "t-title" }, "今天的日课做完了"),
    h(
      "div",
      { class: "row", style: { gap: "10px", alignItems: "baseline" } },
      h("span", { class: "t-button" }, "连续"),
      stencil(String(s.streak), "mid-teal") ?? h("span", { class: "t-title", style: { color: "var(--teal)" } }, s.streak),
      h("span", { class: "t-button" }, "天"),
    ),
    h("span", { class: "t-body", style: { color: "var(--text-2)" } }, "睡前躺着再做几次腹式呼吸，慢慢让它变成平时的呼吸方式。"),
  );
}

let shownVideo = null;

function render() {
  const item = s.items[s.index];
  // 動画は同じ 1 本のあいだ作り直さない(再生が止まらないように)
  if (item?.type === "video") {
    if (shownVideo !== item.embed + item.number) {
      shownVideo = item.embed + item.number;
      clear($("stage"), videoStage(item));
    }
  } else {
    shownVideo = null;
    clear($("stage"), item ? [stretchCard(item), upcoming()] : doneStage());
  }
  $("subtitle").textContent = item
    ? item.type === "video"
      ? item.title === `跟练 ${item.number + 1}`
        ? `跟练 ${item.number + 1} / ${videoCount()}`
        : `跟练 ${item.number + 1} / ${videoCount()} · ${item.title}`
      : `拉伸 ${item.stretchNumber + 1} / ${s.plan.stretchNames.length} · ${item.name}`
    : "做完了";
  renderControls(item);
  renderList();
}

function renderControls(item) {
  const bare = (label, onclick, disabled) => h("button", { class: "bare", onclick, disabled, style: { fontSize: "14px" } }, label);
  let row;
  if (!item) {
    row = [bare("‹ 回到上一步", () => enter(s.items.length - 1)), h("span", { class: "grow" }), button("关闭", { kind: "teal", width: 150, onClick: () => closeWindow() })];
  } else if (item.type === "video") {
    row = [
      bare("‹ 上一个", () => enter(s.index - 1), s.index === 0),
      bare("在浏览器里打开", () => openUrl(item.page)),
      videoNote(item),
      h("span", { class: "grow" }),
      button("跟练完了，下一个", { kind: "teal", onClick: () => enter(s.index + 1) }),
    ];
  } else {
    row = [
      bare("‹ 上一步", () => enter(s.index - 1)),
      h("span", { class: "grow" }),
      button(s.preparing ? "开始" : s.pausedLeft != null ? "继续" : "暂停", { kind: "frame", width: 110, onClick: togglePause, title: s.preparing ? "不用等，马上开始计时" : "暂停 / 继续" }),
      button("下一步", { kind: "teal", width: 150, onClick: () => enter(s.index + 1) }),
    ];
  }
  clear($("controls"), row);
}

function renderList() {
  const p = s.plan;
  const rows = [];
  const state = (first, last) => (s.index > last ? "done" : s.index >= first ? "current" : "later");
  const row = (title, st, to) =>
    h("button", { class: `item is-${st}`, onclick: () => enter(to) }, icon(st === "done" ? "check" : "play", 12), h("span", {}, title));
  if (p.videos.length) {
    rows.push(h("span", { class: "t-section" }, "跟练"));
    p.videos.forEach((v, i) => rows.push(row(v.title, state(i, i), i)));
  }
  if (p.stretchNames.length) {
    rows.push(h("span", { class: "t-section", style: { marginTop: "12px" } }, p.short ? "拉伸（简版）" : p.hasStrength ? "拉伸 · 今天加肩袖力量" : "拉伸"));
    p.stretchNames.forEach((name, n) => {
      const firstItem = s.items.findIndex((it) => it.type === "stretch" && it.stretchNumber === n);
      const nextFirst = s.items.findIndex((it) => it.type === "stretch" && it.stretchNumber === n + 1);
      const last = (nextFirst < 0 ? s.items.length : nextFirst) - 1;
      if (firstItem >= 0) rows.push(row(name, state(firstItem, last), firstItem));
    });
  }
  rows.push(h("span", { class: "grow" }));
  rows.push(h("button", { class: "bare", style: { textAlign: "left" }, onclick: () => setShort(!p.short) }, p.short ? "改回全部拉伸" : "今天累了，只做简版（约 5 分钟）"));
  rows.push(h("span", { class: "t-caption" }, `连续 ${s.finished ? s.streak : p.streak} 天`));
  clear($("list"), rows);
}

function bindKeys() {
  document.addEventListener("keydown", (e) => {
    if (e.key === " " || e.key === "ArrowRight") {
      e.preventDefault();
      enter(s.index + 1);
    } else if (e.key === "ArrowLeft") {
      enter(s.index - 1);
    }
  });
}

async function init() {
  await Promise.all([loadMaterial(), loadIcons()]);
  tile(document.body, "concrete-night");
  build(await call("ritual_plan", { short: false }));
  s.streak = s.plan.streak;
  bindKeys();
  window.addEventListener("message", onPlayerMessage);
  enter(0);
  // 残り秒の数字だけ差し替える(画面を作り直すと、押している途中のボタンが消えて押せない)
  setInterval(() => {
    const item = s.items[s.index];
    if (item?.type === "video") {
      const left = $("controls").querySelector(".video-left");
      if (left && s.videoEndsAt) left.textContent = `${clock(s.videoEndsAt - Date.now())} 后自动下一个`;
      return;
    }
    if (item?.type !== "stretch") return;
    const holder = $("stage").querySelector(".time");
    if (holder) clear(holder, timerText(clock(stepLeft(item))));
  }, 250);
}

init();
