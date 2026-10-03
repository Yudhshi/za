// 泡澡のあとの日课:跟练の動画(公式の埋め込み)→ 立ってやる拉伸 →(隔天)肩袖の力 → 床の拉伸 → 仰向けの腹式呼吸。
// 動画は長さが分かっていれば放し終わる時刻に自動で次へ(YouTube は播放器の「終わった」の知らせでも)。
// 長さが分からない動画は覚える:YouTube は播放器が知らせる長さ、bilibili は「跟练完了，下一个」を押すまでの時間(撤销できる)。
// 覚えた長さは設定の動画の行(链接の後ろ)に書くので、次からは自動で次へ進む。
// 拉伸は 1 歩ずつ:読んで構える 4〜9 秒のあと数え、終われば鳴らして次へ
import { loadMaterial, slice, sprite, stencil, tile, h, button } from "./baked.js";
import { call, openUrl, closeWindow } from "./api.js";
import { loadIcons, loadSounds, icon, clock, chime, clear } from "./common.js";
import { kraft, dots, poseSmall, stretchBody, figure, title } from "./stretchcard.js";

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
  /// いまの動画を映し始めた時刻(長さを覚えるため)
  videoStartedAt: null,
  /// いま覚えた長さ(次の画面に「记住了 · 撤销」を出す):{ title, seconds, before }
  learned: null,
};

/** 押すまでの時間で覚えるのは、この範囲だけ(途中で飛ばしたものを覚えない) */
const LEARN_MIN = 60;
const LEARN_MAX = 40 * 60;

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
  const current = s.items[s.index];
  const same = Math.max(0, i) === s.index && !s.finished && current?.type === "video";
  // 長さが分かっていてもいなくても、映している動画は続いている:計時も、覚えるための開始時刻も触らない
  if (same) return render();
  // 長さの分からない動画から次へ進んだ:見ていた時間を長さとして覚える(撤销できる)
  s.learned = null;
  if (!s.finished && current?.type === "video" && !current.seconds && i === s.index + 1 && s.videoStartedAt) {
    const watched = Math.round((Date.now() - s.videoStartedAt) / 1000) - VIDEO_SLACK;
    if (watched >= LEARN_MIN && watched <= LEARN_MAX) learnLength(current, watched, true);
  }
  cancel();
  s.token += 1;
  s.endsAt = s.pausedLeft = s.videoEndsAt = null;
  s.preparing = false;
  if (i >= s.items.length) return finish();
  s.index = Math.max(0, i);
  s.finished = false;
  const item = s.items[s.index];
  s.videoStartedAt = item.type === "video" ? Date.now() : null;
  if (item.type === "stretch") prepare(item);
  else if (item.seconds) runVideo(item.seconds + VIDEO_SLACK);
  render();
}

/** 動画の id(設定の行を探すため):bilibili の BV…、YouTube の v= / youtu.be / shorts */
function videoId(page) {
  return page.match(/\/video\/(BV[0-9A-Za-z]+)/)?.[1] ?? page.match(/[?&]v=([\w-]{6,})/)?.[1] ?? page.match(/youtu\.be\/([\w-]{6,})/)?.[1] ?? page.match(/\/(?:shorts|embed|live)\/([\w-]{6,})/)?.[1] ?? null;
}

function mmss(seconds) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

/** 覚えた長さを、設定の動画の行の链接の後ろに書く(もう長さがあれば触らない)。showNote なら次の画面に「记住了 · 撤销」 */
async function learnLength(item, seconds, showNote) {
  const id = videoId(item.page);
  if (!id) return;
  item.seconds = seconds;
  const plan = s.plan.videos[item.number];
  if (plan) plan.seconds = seconds;
  try {
    const settings = await call("settings_get");
    const before = settings.ritualVideos ?? "";
    let changed = false;
    const lines = before.split(/\r?\n/).map((line) => {
      if (changed || !line.includes(id)) return line;
      const start = line.indexOf("http");
      if (start < 0) return line;
      const url = line.slice(start).split(/\s+/)[0];
      const rest = line.slice(start + url.length);
      if (/\d/.test(rest)) return line;
      changed = true;
      return `${line.slice(0, start + url.length)} ${mmss(seconds)}${rest}`;
    });
    if (!changed) return;
    await call("settings_save", { patch: { ritualVideos: lines.join("\n") } });
    if (showNote) {
      s.learned = { title: item.title, seconds, before, item };
      renderControls(s.items[s.index]);
    }
  } catch {
    /* 覚えられなくても進む */
  }
}

/** 「记住了」を取り消す(途中で飛ばしたのに覚えてしまった) */
async function undoLearned() {
  const l = s.learned;
  if (!l) return;
  s.learned = null;
  l.item.seconds = null;
  const plan = s.plan.videos[l.item.number];
  if (plan) plan.seconds = null;
  await call("settings_save", { patch: { ritualVideos: l.before } });
  renderControls(s.items[s.index]);
  renderList();
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
  // 播放器が長さを知らせてきた:長さの分からない動画なら覚える(正確なので撤销は出さない)
  const duration = data?.event === "infoDelivery" ? Number(data.info?.duration) : NaN;
  if (!item.seconds && Number.isFinite(duration) && duration >= 30 && duration <= LEARN_MAX) {
    learnLength(item, Math.round(duration), false);
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

/** いまの手順の残り(ミリ秒) */
function stepLeft(step) {
  return s.preparing ? step.duration * 1000 : s.pausedLeft != null ? s.pausedLeft * 1000 : s.endsAt ? s.endsAt - Date.now() : 0;
}

/** 舞台の残り時間:模板の mid-black(字高 58。小窓の count-black とは役割が違う) */
function timerText(time) {
  return figure(time, "mid-black", "", 48);
}

/** 拉伸の卡:小窓と同じ牛皮纸・同じ部品(舞台の大きさ) */
function stretchCard(step) {
  const time = clock(stepLeft(step));
  const card = h(
    "div",
    { class: "sheet" },
    h("div", { class: "head row" }, h("span", { class: "label" }, `第 ${step.stepNumber + 1}/${step.stepCount} 步`), h("span", { class: "grow" }), dots(step.stepCount, step.stepNumber)),
    stretchBody({ pose: step.pose, heading: step.heading, meta: step.meta, text: step.text }),
    h("div", { class: "row time-row" }, s.preparing ? h("span", { class: "prep" }, "准备") : null, h("span", { class: "time" }, timerText(time))),
    h("div", { class: "muted" }, s.plan.caution),
  );
  return kraft(card);
}

function upcoming() {
  const next = s.items[s.index + 1];
  if (!next || next.type !== "stretch") return h("div", { class: "upcoming" });
  return h(
    "div",
    { class: "upcoming" },
    h("span", { class: "t-section" }, "下一步"),
    h("div", { class: "row", style: { gap: "10px" } }, poseSmall(next.pose, 44), h("span", { class: "t-card-title" }, next.stepNumber === 0 ? next.name : next.heading)),
    h("span", { class: "t-body", style: { color: "var(--text-2)" } }, next.text),
  );
}

/** ブラウザでしか見られない動画の舞台:牛皮纸に、次の拉伸の小さな絵と黒牌のリンク(空の混凝土を見せない) */
function browserOnlyStage(item) {
  const next = s.items.find((it, i) => i > s.index && it.type === "stretch");
  const card = h(
    "div",
    { class: "sheet" },
    h("div", { class: "head row" }, h("span", { class: "label" }, item.title), h("span", { class: "grow" })),
    h("div", { class: "body row" }, next ? poseSmall(next.pose, 96) : null, h("div", { class: "col" }, h("div", { class: "heading far" }, "这个视频只能在浏览器里看"), h("div", { class: "text" }, "开好了就按这边的「跟练完了，下一个」。"), next ? h("div", { class: "muted" }, `视频后面：${title(next.name)}`) : null)),
    h("div", { class: "row", style: { marginTop: "14px", gap: "12px" } }, button("在浏览器里打开", { kind: "teal", width: 180, onClick: () => openUrl(item.page) })),
    h("div", { class: "muted", style: { userSelect: "text" } }, item.page),
  );
  return kraft(card);
}

function videoStage(item) {
  if (!item.embed) return browserOnlyStage(item);
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
  // 覚えられるのは bilibili / YouTube の链接だけ(行を探す id が要る)
  if (videoId(item.page)) return h("span", { class: "t-caption" }, "第一次：看完点「跟练完了，下一个」，记住时长后下次自动跳");
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
  // さっきの動画の長さを覚えた:一言と撤销(途中で飛ばしたなら取り消す)
  const learnedNote = s.learned
    ? h("span", { class: "t-caption row", style: { gap: "8px" } }, `记住了：${s.learned.title} ${mmss(s.learned.seconds)}，下次自动跳`, bare("撤销", undoLearned))
    : null;
  let row;
  if (!item) {
    row = [bare("‹ 回到上一步", () => enter(s.items.length - 1)), h("span", { class: "grow" }), button("关闭", { kind: "teal", width: 150, onClick: () => closeWindow() })];
  } else if (item.type === "video") {
    row = [
      bare("‹ 上一个", () => enter(s.index - 1), s.index === 0),
      bare("在浏览器里打开", () => openUrl(item.page)),
      learnedNote ?? videoNote(item),
      h("span", { class: "grow" }),
      button("跟练完了，下一个", { kind: "teal", onClick: () => enter(s.index + 1) }),
    ];
  } else {
    row = [
      bare("‹ 上一步", () => enter(s.index - 1)),
      learnedNote,
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
  const row = (label, st, to, note) => {
    const el = h("button", { class: `item is-${st}`, onclick: () => enter(to) }, icon(st === "done" ? "check" : "play", 12), h("span", { class: "grow" }, label), note ? h("span", { class: "item-note" }, note) : null);
    if (st === "current") slice(el, "tab-chip-night") || (el.style.background = "var(--white)");
    return el;
  };
  if (p.videos.length) {
    rows.push(h("span", { class: "t-section" }, "跟练"));
    p.videos.forEach((v, i) => rows.push(row(v.title, state(i, i), i, v.embed ? (v.seconds ? clock(v.seconds * 1000) : "") : "浏览器")));
  }
  if (p.stretchNames.length) {
    rows.push(h("span", { class: "t-section", style: { marginTop: "12px" } }, p.short ? "拉伸（简版）" : p.hasStrength ? "拉伸 · 今天加肩袖力量" : "拉伸"));
    p.stretchNames.forEach((name, n) => {
      const firstItem = s.items.findIndex((it) => it.type === "stretch" && it.stretchNumber === n);
      const nextFirst = s.items.findIndex((it) => it.type === "stretch" && it.stretchNumber > n);
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
  await Promise.all([loadMaterial(), loadIcons(), loadSounds()]);
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
