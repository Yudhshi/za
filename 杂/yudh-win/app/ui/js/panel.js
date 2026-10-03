// 面板:最初は細い帯(姿勢の札・今日の一行・泡完澡了)。「打开」で全体:今天 / 英語(単語・考点词・听写)/ 明天的会 / 设置。
// 「今天」が家:姿勢という「もの」(坐 | 站 の札)、一日の胶带(時間軸)、呼吸・英語・日课・明天の一行ずつ。
// 初回は計画の説明を先に見せる(同期フォルダは英語と会議にだけ要る)
import { loadMaterial, slice, sprite, tile, h, button, first, asset, has } from "./baked.js";
import { call, closeWindow, openUrl, enableDragging, listen } from "./api.js";
import { loadIcons, icon, weekdays, weekdaysZh, hhmm, speak, stopSpeaking, clear, voiceFor, voicesReady, withNums } from "./common.js";
import { postureChip, poseSmall, parseStretches, renderStretches, stepSeconds, metaText, illustration, title, totalSeconds, mmss } from "./stretchcard.js";
import { dayTape } from "./daytape.js";

const $ = (id) => document.getElementById(id);

const state = {
  tab: safeGet("tab") || "today",
  mode: "vocab",
  panel: null,
  card: null,
  revealed: false,
  picked: null,
  /** 听写:採点の結果({ result, marks })と、一度でも再生したか(したら次の語は自動で読む) */
  graded: null,
  listened: false,
  undoable: false,
  settings: null,
  /** 帯から全体に広げたか */
  expanded: false,
  /** 拉伸库で開いている行("key:index") */
  libraryOpen: null,
};

function safeGet(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function safeSet(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* 覚えられなくても動く */
  }
}

// MARK: 墙と表头

function paintWall() {
  const panel = $("panel");
  const wall = panel.querySelector(".wall");
  tile(wall, "concrete-night");
  const edge = h("div", { class: "edge" });
  wall.append(edge);
  slice(edge, "concrete-edge-night", { tile: true });
}

/** 全体のときだけ面板の枠(帯のときは帯の黒い帯だけ) */
function paintFrame(on) {
  const panel = $("panel");
  if (on) slice(panel, "panel-frame-night");
  else panel.querySelector(":scope > .paint:not(.over)")?.remove();
}

function renderWeekday() {
  const day = weekdays[new Date().getDay()];
  const holder = $("weekday");
  const art = sprite(`day-${day}-white-night`);
  clear(holder, art ?? h("span", { class: "fallback" }, day.toUpperCase()));
}

const TABS = [
  ["today", "今天"],
  ["english", "英语"],
  ["tomorrow", "明天"],
  ["settings", "设置"],
];

function renderTabs() {
  // 初回の説明のあいだは札を出さない(押しても説明のままなので)
  if (state.panel && !state.panel.welcomed) return clear($("tabs"));
  const remaining = state.panel?.stats ? Object.values(state.panel.stats.remaining).reduce((a, b) => a + b, 0) : null;
  clear(
    $("tabs"),
    TABS.map(([key, title]) => {
      const on = state.tab === key;
      const badge = key === "english" ? remaining : null;
      const el = h("button", { class: `tab${on ? " on" : ""}`, onclick: () => switchTab(key) }, title, badge != null && badge > 0 ? h("span", { class: "badge" }, badge) : null);
      if (on) {
        const wide = title.length + (badge ? String(badge).length + 1 : 0) >= 5;
        slice(el, wide ? first("tab-chip-wide-night", "tab-chip-night") : "tab-chip-night") || (el.style.background = "var(--white)");
      }
      return el;
    }),
  );
}

function switchTab(key) {
  state.tab = key;
  safeSet("tab", key);
  renderTabs();
  renderView();
}

// MARK: 姿勢という「もの」:帯・今天・小窓・トレイで同じ札と同じ一行

async function flip() {
  await call("posture_action", { action: "flip" });
  await refreshAfterFlip();
}

/** 姿勢と今日の数字だけ読み直す(軽い命令:英語・会議・習慣のファイルは読まない。見ている卡や書きかけの設定は作り直さない) */
async function refreshQuiet() {
  if (!state.panel) return;
  Object.assign(state.panel, await call("posture_summary"));
  renderStrip();
  if (state.expanded && state.tab === "today" && state.panel.welcomed) {
    const view = $("view");
    const scroll = view.scrollTop;
    clear(view, todayView());
    view.scrollTop = scroll;
  }
}

/** 札を返した:姿勢が変わり、日课も変わりうるので今日の分は全部読み直す */
async function refreshAfterFlip() {
  state.panel = await call("panel_state");
  renderStrip();
  if (state.expanded && state.tab === "today" && state.panel.welcomed) clear($("view"), todayView());
}

/** 「已坐 23 分钟」(夜は「休息中」) */
function postureWord() {
  const p = state.panel;
  if (p.resting) return "休息中";
  return `${p.posture === "sitting" ? "已坐" : "已站"} ${Math.max(0, p.minutesInPosture)} 分钟`;
}

/** 次の切り替え:「12:30 坐下」。休み中は理由と朝の時刻 */
function nextSwitch() {
  const p = state.panel;
  if (p.resting) {
    const morning = `早上 ${p.quietTo ?? 8} 点重新开始`;
    return p.restReason === "ritual" ? `日课做完了，今天不叫了 · ${morning}` : `夜里不叫 · ${morning}`;
  }
  const at = new Date(p.dueAt);
  return `${hhmm(at)} ${p.posture === "sitting" ? "站起来" : "坐下"}`;
}

function ritualButton() {
  return h(
    "button",
    { class: "bare row", style: { gap: "6px" }, onclick: () => call("open_surface", { which: "ritual" }), title: "跟练视频 → 肩颈拉伸 → 躺着做腹式呼吸" },
    icon("play", 13),
    "泡完澡了",
  );
}

function renderStrip() {
  const p = state.panel;
  const strip = $("strip");
  // 帯に入るのは姿勢という「もの」とその一行だけ(泡完澡了は「今天」とトレイに)
  clear(
    strip,
    postureChip(p.posture, flip, { disabled: p.resting }),
    h("span", { class: "status" }, h("b", {}, withNums(postureWord())), " · ", withNums(p.todayShort)),
    h("span", { class: "grow" }),
    h("button", { class: "bare open", onclick: expand }, "打开 ›"),
  );
  slice(strip, "strip-black-night") || strip.classList.add("fallback");
}

// MARK: 今天(家)

function todayRow(label, ...children) {
  return h("div", { class: "today-row row" }, h("span", { class: "t-section label" }, label), ...children);
}

function breathDots(n) {
  const el = h("span", { class: "breath-dots row" });
  for (let i = 0; i < Math.min(n, 12); i++) el.append(sprite("cell-teal-night", { height: 14 }) ?? h("i", { class: "dot" }));
  return el;
}

function todayView() {
  const p = state.panel;
  const s = p.stats;
  const t = p.tomorrow;
  const meeting = t.state === "meetings" ? t.meetings[0] : null;
  const meetingText = meeting ? `${hhmm(new Date(meeting.start))} ${meeting.title}${t.meetings.length > 1 ? ` · 共 ${t.meetings.length} 个` : ""}` : t.state === "empty" ? "明天没有会" : t.state === "notSynced" ? "Mac 还没同步明天的日程" : "还没有会议数据";
  return h(
    "div",
    { class: "today" },
    h(
      "div",
      { class: "posture-line row" },
      postureChip(p.posture, flip, { disabled: p.resting }),
      h("span", { class: "big" }, withNums(postureWord())),
      h("span", { class: "grow" }),
      h("span", { class: "next t-caption" }, withNums(nextSwitch())),
    ),
    dayTape(p),
    h("div", { class: "t-caption total" }, withNums(p.today)),
    todayRow("腹式呼吸", breathDots(p.breathToday), h("span", { class: "value" }, withNums(`${p.breathToday} 次`)), h("span", { class: "grow" }), h("span", { class: "t-caption" }, "每次站起来 3 次，日课最后 12 次")),
    todayRow(
      "英语",
      s ? h("span", { class: "value" }, withNums(`今天 ${s.todayCount}/${s.goal} · 连续 ${s.streak} 天`)) : h("span", { class: "t-caption" }, p.configured ? "词表还没同步过来" : "先在设置里选同步文件夹"),
      h("span", { class: "grow" }),
      s ? h("button", { class: "bare", onclick: () => switchTab("english") }, "去背单词 ›") : null,
    ),
    todayRow(
      "日课",
      h("span", { class: "value" }, withNums(p.ritualToday ? `今天做过了 · 连续 ${p.ritualStreak} 天` : `连续 ${p.ritualStreak} 天`)),
      h("span", { class: "grow" }),
      ritualButton(),
    ),
    todayRow("明天", h("span", { class: "value" }, withNums(meetingText)), h("span", { class: "grow" }), meeting?.join ? h("button", { class: "bare", onclick: () => openUrl(meeting.join) }, "会议链接") : null),
  );
}

// MARK: 帯 ⇄ 全体

/** 帯から全体へ(窓は Rust が下の辺を揃えて上へ伸ばす)。帯の黒い帯は消え、面板の枠が上へ広がる */
async function expand() {
  if (state.expanded) return;
  state.expanded = true;
  const panel = $("panel");
  panel.classList.add("expanding");
  panel.classList.remove("strip-mode");
  paintFrame(true);
  setTimeout(() => panel.classList.remove("expanding"), 260);
  await call("open_surface", { which: "panel-full" });
  renderTabs();
  await renderView();
  armFade();
}

/** 全体から帯へ(Rust が窓を縮めたあと、または Esc) */
function collapse() {
  if (!state.expanded) return;
  state.expanded = false;
  const panel = $("panel");
  panel.classList.add("strip-mode");
  paintFrame(false);
  stopSpeaking();
  renderStrip();
  armFade();
}

/** 常駐の帯:10 秒触らなければ薄くなり、触れば戻る */
let fadeTimer = null;
function armFade() {
  clearTimeout(fadeTimer);
  document.body.style.opacity = "";
  if (!state.panel?.pinned || state.expanded) return;
  fadeTimer = setTimeout(() => {
    if (!state.expanded) document.body.style.opacity = "0.4";
  }, 10000);
}

// MARK: 本体

async function refresh() {
  state.panel = await call("panel_state");
  renderStrip();
  armFade();
  if (!state.expanded) return;
  renderTabs();
  await renderView();
}

async function renderView() {
  const view = $("view");
  if (!state.panel.welcomed) return clear(view, welcomeView());
  if (state.tab === "today") return clear(view, todayView());
  if (state.tab === "tomorrow") return clear(view, tomorrowView());
  if (state.tab === "settings") return clear(view, await settingsView());
  clear(view, await englishView());
  focusSpell();
}

/** 听写は入力欄に焦点を置く(開いてすぐ打てる・Enter で続けられるように) */
function focusSpell() {
  if (state.card?.kind === "spell" && !state.graded) $("spell-input")?.focus();
}

/** 初回:計画を先に(同期フォルダは英語と会議にだけ要るので、あとで)。曜日の creature と胶带の見本つき */
function welcomeView() {
  const day = weekdays[new Date().getDay()].slice(0, 3);
  const creature = sprite(`creature-${day}-grey-m`, { height: 120 }) ?? sprite(`creature-${day}-grey`, { height: 120 });
  const sample = { marks: [], since: Date.now() - 23 * 60000, posture: "sitting", dueAt: Date.now() + 7 * 60000, resting: false };
  const t = new Date();
  t.setHours(9, 0, 0, 0);
  const base = t.getTime();
  sample.marks = [
    { at: base, kind: "sit" },
    { at: base + 30 * 60000, kind: "stand" },
    { at: base + 60 * 60000, kind: "sit" },
    { at: base + 75 * 60000, kind: "away" },
    { at: base + 90 * 60000, kind: "sit" },
    { at: base + 120 * 60000, kind: "stand" },
  ];
  return h(
    "div",
    { class: "welcome" },
    h("div", { class: "row", style: { gap: "16px", alignItems: "flex-start" } }, h("div", { class: "big grow" }, "从现在开始：坐 30 分钟，站 30 分钟"), creature),
    h(
      "div",
      { class: "body" },
      "到点屏幕上方的小窗会说",
      h("em", {}, "「站起来」"),
      "，接着 3 次腹式呼吸、斜角肌拉伸、再轮 1 个肩颈动作，每一步到时间自动往下走，做完自己关。30 分钟后它说",
      h("em", {}, "「坐下」"),
      "。你什么都不用点；它说错了，就把「坐 | 站」的牌子翻过来。",
    ),
    h("div", { class: "aside" }, "这条胶带是你的一天：黑是坐，青是站，灰是离开，橙色刻痕是现在。"),
    dayTape(sample),
    h("div", { class: "aside" }, "有声音：换姿势、换动作、做完各不一样。夜里 23 点到早上 8 点不叫；全屏游戏时不弹；AION2 运行时完全安静。英语和明天的会议要和 Mac 共用一个同步文件夹，以后在「设置」里选。"),
    button("知道了", {
      kind: "teal",
      width: 160,
      onClick: async () => {
        await call("settings_save", { patch: { welcomed: true } });
        state.tab = "today";
        await refresh();
      },
    }),
  );
}

function emptyState(title, note, action) {
  return h("div", { class: "empty-state" }, h("div", { class: "title" }, title), note && h("div", { class: "note" }, note), action);
}

// MARK: 英語

async function englishView() {
  const p = state.panel;
  if (!p.configured) {
    return emptyState(
      "先选同步文件夹",
      "选和 Mac 同一个同步文件夹（OneDrive 等）。单词进度两边共用。",
      button("去设置", { kind: "frame", onClick: () => switchTab("settings") }),
    );
  }
  if (!p.hasLibrary) {
    return emptyState(
      "词表还没同步过来",
      "在 Mac 的设置里打开「把词表复制一份给 Windows」，同步盘传过来之后再打开这里。",
    );
  }
  state.card = await call("english_card", { kind: state.mode });
  state.revealed = false;
  state.picked = null;
  state.graded = null;
  return h("div", {}, modesRow(), state.card ? stage() : doneView());
}

function modesRow() {
  const s = state.panel.stats;
  const modes = [
    ["vocab", "单词"],
    ["para", "考点词"],
    ["spell", "听写"],
  ];
  return h(
    "div",
    { class: "modes row" },
    modes.map(([key, title]) => {
      const on = state.mode === key;
      const el = h(
        "button",
        {
          class: `tab${on ? " on" : ""}`,
          onclick: () => {
            state.mode = key;
            stopSpeaking();
            renderView();
          },
        },
        title,
        s?.remaining?.[key] ? h("span", { class: "badge" }, s.remaining[key]) : null,
      );
      if (on) slice(el, "tab-chip-night") || (el.style.background = "var(--white)");
      return el;
    }),
    h("span", { class: "summary t-caption" }, `今天 ${s.todayCount}/${s.goal} · 连续 ${s.streak} 天`),
  );
}

function tag(text, style) {
  const latin = /^[\x00-\x7f]+$/.test(text);
  const el = h("span", { class: `tag ${style}${latin ? " t-tag-latin" : ""}` }, text);
  const long = text.length > 4;
  const id =
    style === "black"
      ? first("tag-black-card", "band-black-night")
      : style === "orange"
        ? "tag-orange-card"
        : long
          ? first("frame-black-long-night", "frame-black-night")
          : "frame-black-night";
  if (!slice(el, id)) el.style.background = style === "orange" ? "var(--orange)" : style === "black" ? "var(--black)" : "transparent";
  const a = asset(id);
  if (a) el.style.minWidth = `${(a.size[0] - a.bleed[1] - a.bleed[3]) * 0.8}px`;
  return el;
}

function history(marks) {
  return h("div", { class: "history row" }, marks.map((m) => sprite(`rate-14-${m}`)));
}

function card(...children) {
  const el = h("div", { class: `card${state.card?.kind === "para" ? " short" : ""}` }, ...children);
  if (!slice(el, "card-white-night")) el.classList.add("fallback");
  return el;
}

function example(text, word) {
  const el = h("div", { class: "example" });
  const lower = text.toLowerCase();
  const target = word.toLowerCase();
  let i = 0;
  for (;;) {
    const at = lower.indexOf(target, i);
    if (at < 0) break;
    el.append(text.slice(i, at), h("mark", {}, text.slice(at, at + word.length)));
    i = at + word.length;
  }
  el.append(text.slice(i));
  return el;
}

function vocabCard() {
  const c = state.card;
  const v = c.vocab;
  const size = v.word.length > 12 ? 36 : v.word.length > 9 ? 44 : 56;
  const meaning = state.revealed
    ? h(
        "div",
        { class: "meaning" },
        h("div", { class: "label" }, "释义"),
        h("div", { class: `text${v.meaning.length > 10 ? " long" : ""}` }, v.meaning),
        v.example ? example(v.example, v.word) : null,
      )
    : h(
        "div",
        { class: "meaning" },
        h("div", { class: "label" }, "释义"),
        h("div", { class: "redaction" }, sprite("redact-black-1-night"), sprite("redact-black-2-night")),
      );
  return card(
    h("div", { class: "tags row" }, tag(v.level, "black"), c.isNew ? tag("NEW", "orange") : null, v.pos ? tag(v.pos, "frame") : null),
    h("div", { class: "word", style: { fontSize: `${size}px` } }, v.word),
    h(
      "div",
      { class: "phonetic row" },
      v.phonetic ? h("span", {}, v.phonetic) : null,
      h("button", { class: "ink-button", title: "听发音", onclick: () => speak(v.word) }, icon("speaker", 16)),
    ),
    history(c.history),
    sprite("card-rule") ? h("div", { class: "rule" }, sprite("card-rule")) : null,
    meaning,
  );
}

function paraCard() {
  const c = state.card;
  const q = c.question;
  return card(
    h("div", { class: "tags row" }, tag("考点词", "black"), tag(q.entry.skill === "reading" ? "阅读" : "听力", "frame")),
    h("div", { class: "word", style: { fontSize: q.entry.w.length > 10 ? "40px" : "52px" } }, q.entry.w),
    h("div", { class: "phonetic row" }, [q.entry.pos, q.entry.zh].filter(Boolean).join(" ")),
    history(c.history),
    h("div", { class: "note", style: { color: "var(--card-text-2)" } }, "真题里它会被换成哪个？按 1–4 选"),
  );
}

// MARK: 听写(Mac と同じ:英式の読み上げを聞いて綴る。正确 / 差一个字母 = 模糊 / 错 = 今天再来)

/** 読む(慢速は 0.7 倍。Mac の 0.34 / 0.5 と同じくらい) */
function playSpell(slow = false) {
  const w = state.card?.spell;
  if (!w) return;
  state.listened = true;
  speak(w.w, { lang: "en-GB", rate: slow ? 0.7 : 1 });
  focusSpell();
}

/** 字の格(20 × 32、Archivo 26)の列。印の字は焼いた橙 / 青の遮块(素材がなければ下線)。長い語は 0.6 倍まで縮めて折り返す */
function letterRow(text, marks, paint) {
  const letters = Array.from(text);
  const room = 244;
  const scale = Math.max(0.6, Math.min(1, room / (Math.max(letters.length, 1) * 20)));
  return h(
    "div",
    { class: "letters" },
    letters.map((ch, i) => {
      const cell = h("span", { class: "letter", style: { width: `${20 * scale}px`, height: `${32 * scale}px`, fontSize: `${26 * scale}px` } }, ch);
      if (marks[i] && !slice(cell, `letter-${paint}-card`)) cell.classList.add(`under-${paint}`);
      return cell;
    }),
  );
}

/** 再生ボタンの下の一言:英式の声が無ければ、美式で読んでいることを正直に言う(一覧が取れないときは既定の言い方) */
function accentNote() {
  const known = "speechSynthesis" in window && speechSynthesis.getVoices().length > 0;
  if (!known || voiceFor(["en-GB"])) return "英式发音 · 建议戴耳机";
  return "美式发音（没装英式语音）";
}

const spellTitles = {
  correct: "正确",
  almost: "差一点（错了 1 个字母）",
  wrong: "正确答案 · 今天再来一次",
};

function spellCard() {
  const c = state.card;
  const w = c.spell;
  const g = state.graded;
  const disc = h("span", { class: "play-disc" }, sprite("button-play-orange-night") ?? h("span", { class: "disc" }), icon("play", 20));
  // spellcheck は文字列で切る(h() は false の属性を書かない。赤い波線が出ると答えが分かってしまう)
  const input = h("input", {
    id: "spell-input",
    type: "text",
    lang: "en",
    autocomplete: "off",
    autocapitalize: "off",
    spellcheck: "false",
    placeholder: "输入听到的单词，按回车",
    onkeydown: (e) => {
      // 中文・日本語の入力法で変換を確定する Enter は採点にしない
      if (e.key === "Enter" && !e.isComposing && e.keyCode !== 229) {
        e.preventDefault();
        submitSpell();
      }
    },
  });
  const box = h("div", { class: `spell-box${g ? " graded" : ""}` }, g ? (g.marks.typed ? letterRow(g.marks.typed, g.marks.typedMarks, "orange") : h("span", { class: "dash" }, "—")) : input);
  slice(box, "input-frame-night") || box.classList.add("fallback");
  const answer = g
    ? h(
        "div",
        { class: "spell-answer" },
        h("div", { class: "label" }, spellTitles[g.result]),
        h("div", { class: "answer-row" }, letterRow(g.marks.answer, g.marks.answerMarks, "teal")),
        w.ipa || w.zh ? h("div", { class: "gloss" }, [w.ipa ? `/${w.ipa}/` : null, w.zh].filter(Boolean).join(" · ")) : null,
      )
    : null;
  return card(
    h("div", { class: "tags row", title: `王陆语料 · ${w.set}` }, tag("听写", "black"), tag(w.set, "frame"), c.isNew ? tag("NEW", "orange") : null),
    h(
      "button",
      { class: "play row", title: "播放（Ctrl+R）", onclick: () => playSpell() },
      disc,
      h("span", { class: "play-text" }, h("span", { class: "play-title" }, "播放", h("span", { class: "keycap" }, "Ctrl+R")), h("span", { class: "play-note" }, accentNote())),
    ),
    history(c.history),
    h("div", { class: "spell-label" }, "你的拼写"),
    box,
    answer,
  );
}

function spellActions() {
  const g = state.graded;
  return h(
    "div",
    { class: "actions row" },
    button("慢速", { kind: "frame", width: 96, onClick: () => playSpell(true) }),
    g ? null : button("不知道", { kind: "frame", width: 110, onClick: () => submitSpell(true) }),
    h("span", { class: "grow" }),
    h("span", { class: "keycap on-wall" }, "Enter"),
    g ? button("下一个", { kind: "teal", width: 150, onClick: submitSpell }) : button("检查", { kind: "teal", width: 150, onClick: submitSpell }),
  );
}

/** Enter:未採点なら採点、採点済みなら次へ。giveUp は「不知道」(答えを見せて、今日もう一度) */
let spellBusy = false;

async function submitSpell(giveUp = false) {
  const c = state.card;
  if (!c?.spell || spellBusy) return;
  spellBusy = true;
  try {
    await gradeOrNext(c, giveUp);
  } finally {
    spellBusy = false;
  }
}

async function gradeOrNext(c, giveUp) {
  if (state.graded) {
    await nextCard();
    if (state.listened && state.card?.spell) speak(state.card.spell.w, { lang: "en-GB" });
    return;
  }
  const typed = $("spell-input")?.value ?? "";
  if (!giveUp && !typed.trim()) return;
  const graded = await call("english_spell", { id: c.id, input: giveUp ? null : typed });
  state.panel.stats = graded.stats;
  state.graded = { result: graded.result, marks: graded.marks };
  state.undoable = true;
  renderTabs();
  rerenderStage();
}

function column() {
  const s = state.panel.stats;
  return h(
    "div",
    { class: "column" },
    h("div", { class: "board" }, s.board.map((m) => sprite(`rate-30-${m}`) ?? h("span", { class: "cell" }))),
    h("div", { class: "count" }, s.todayCount, h("small", {}, `/${s.goal}`)),
    h("div", { class: "t-caption row", style: { gap: "6px" } }, icon("flame", 14), `连续 ${s.streak} 天`),
  );
}

const ratings = [
  ["again", "忘了", "1", "forgot"],
  ["hard", "模糊", "2", "fuzzy"],
  ["good", "记住了", "3 ␣", "good"],
  ["easy", "太简单", "4", "easy"],
];

function vocabActions() {
  if (!state.revealed) {
    return h(
      "div",
      { class: "actions row" },
      h("button", { class: "bare", onclick: markKnown, title: "以后不再出现" }, "已经会了"),
      h("span", { class: "grow" }),
      button("显示释义  ␣", { kind: "orange", width: 200, onClick: reveal }),
    );
  }
  return h(
    "div",
    { class: "actions row", title: "按 1–4 评分；Space = 记住了" },
    ratings.map(([rating, label, key, mark]) => {
      const swatch = h("span", { class: "swatch" }, sprite(`rate-14-${mark}-dark`));
      slice(swatch, "swatch-black-card");
      const el = h("button", { class: "rate", onclick: () => rate(rating) }, swatch, h("span", { class: "key" }, key), label);
      slice(el, "block-slate-rate-night") || (el.style.background = "#45494d");
      return el;
    }),
  );
}

function paraOptions() {
  const q = state.card.question;
  const answered = state.picked != null;
  return h(
    "div",
    {},
    h(
      "div",
      { class: "options" },
      q.choices.map((choice, i) => {
        const right = answered && i === q.answerIndex;
        const wrong = answered && i === state.picked && !right;
        const el = h(
          "button",
          { class: `option${right ? " right" : ""}`, onclick: () => choose(i), disabled: answered && !right && !wrong },
          h("span", { class: "key" }, i + 1),
          choice,
        );
        slice(el, right ? "block-teal-option-night" : wrong ? "block-slate-option-night" : "block-grey-option-night");
        return el;
      }),
    ),
    answered
      ? h("div", { class: "actions row" }, h("span", { class: "grow" }), button("下一个", { kind: "teal", width: 150, onClick: nextCard }))
      : null,
  );
}

function stage() {
  const kind = state.card.kind;
  return h(
    "div",
    {},
    h("div", { class: "stage" }, kind === "vocab" ? vocabCard() : kind === "spell" ? spellCard() : paraCard(), column()),
    kind === "vocab" ? vocabActions() : kind === "spell" ? spellActions() : paraOptions(),
    state.undoable ? h("button", { class: "bare", style: { marginTop: "10px" }, onclick: undo }, "撤销刚才的回答（Ctrl+Z）") : null,
  );
}

function doneView() {
  return h(
    "div",
    { class: "stage" },
    h(
      "div",
      { class: "empty-state", style: { padding: "24px 4px", width: "308px" } },
      h("div", { class: "title" }, { vocab: "今天的单词做完了", para: "今天的考点词做完了", spell: "今天的语料做完了" }[state.mode]),
      h("div", { class: "note" }, "复习的都做完了，新的也到了今天的数量。还想做的话再来 10 个。"),
      button("再来 10 个", {
        kind: "frame",
        onClick: async () => {
          await call("english_more", { kind: state.mode });
          renderView();
        },
      }),
    ),
    column(),
  );
}

function rerenderStage() {
  const view = $("view");
  const scroll = view.scrollTop;
  clear(view, h("div", {}, modesRow(), state.card ? stage() : doneView()));
  view.scrollTop = scroll;
  focusSpell();
}

function reveal() {
  state.revealed = true;
  rerenderStage();
}

// 同じ卡を二度評価しない(キーの長押し・二度押し)
let answering = false;

async function rate(rating) {
  if (answering) return;
  answering = true;
  try {
    const c = state.card;
    state.panel.stats = await call("english_rate", { id: c.id, kind: c.kind, rating });
    state.undoable = true;
    await nextCard();
  } finally {
    answering = false;
  }
}

async function markKnown() {
  if (answering) return;
  answering = true;
  try {
    state.panel.stats = await call("english_known", { id: state.card.id });
    state.undoable = true;
    await nextCard();
  } finally {
    answering = false;
  }
}

async function choose(i) {
  if (state.picked != null) return;
  const c = state.card;
  state.picked = i;
  const rating = i === c.question.answerIndex ? "good" : "again";
  state.panel.stats = await call("english_rate", { id: c.id, kind: c.kind, rating });
  state.undoable = true;
  rerenderStage();
}

async function nextCard() {
  state.card = await call("english_card", { kind: state.mode });
  state.revealed = false;
  state.picked = null;
  state.graded = null;
  renderTabs();
  rerenderStage();
}

async function undo() {
  const kind = await call("english_undo");
  state.undoable = false;
  if (kind) state.mode = kind;
  await refresh();
}

// MARK: 明天

function tomorrowView() {
  const t = state.panel.tomorrow;
  const date = new Date(Date.now() + 24 * 3600 * 1000);
  const head = h(
    "div",
    { class: "row", style: { gap: "12px", marginBottom: "12px" } },
    h("span", { class: "t-card-title" }, "明天"),
    h("span", { class: "t-caption" }, `${date.getMonth() + 1}/${date.getDate()} ${weekdaysZh[date.getDay()]}`),
  );
  if (t.state === "meetings") {
    return h(
      "div",
      {},
      head,
      t.meetings.map((m) => {
        const start = new Date(m.start);
        const end = new Date(m.end);
        return h(
          "div",
          { class: "meeting row" },
          h("span", { class: "time t-time" }, `${hhmm(start)}–${hhmm(end)}`),
          h("span", { class: "title grow" }, m.title),
          m.join ? h("button", { class: "bare", onclick: () => openUrl(m.join) }, "会议链接") : null,
        );
      }),
      h("div", { class: "note" }, "从 Mac 的日历同步过来（Mac 读日历时写 agenda.json）。Windows 不读日历。"),
    );
  }
  const notes = {
    empty: ["明天没有会议", null],
    notSynced: ["Mac 还没同步明天的日程", "Mac 读一次日历（打开面板或每分钟）之后，同步盘会把它带过来。"],
    noFile: state.panel.configured
      ? ["还没有会议数据", "在 Mac 的设置里打开「把今天和明天的会议写给 Windows」。"]
      : ["先选同步文件夹", "和 Mac 选同一个文件夹，明天的会议会从那里读。"],
  };
  const [title, note] = notes[t.state] ?? notes.noFile;
  return h("div", {}, head, emptyState(title, note));
}

// MARK: 设置

const LIBRARY = [
  ["fixed", "每次站起来先做", "斜角肌。狙いの筋肉は毎回"],
  ["stretches", "站起来时轮流（每次一个）", ""],
  ["ritualStretches", "日课 · 站着", ""],
  ["ritualStrength", "日课 · 肩袖力量（隔天）", ""],
  ["ritualFloor", "日课 · 地上", ""],
];

async function settingsView() {
  const s = (state.settings = await call("settings_get"));
  const save = async (patch) => {
    await call("settings_save", { patch });
    Object.assign(state.settings, patch);
  };
  // 打っている途中も少し待って保存する(面板はフォーカスを失うと閉じるので、blur を待っていては間に合わない)
  const text = (key, { area = false, rows } = {}) => {
    const el = h(area ? "textarea" : "input", area ? { rows } : { type: "text" });
    el.value = s[key] ?? "";
    let pending = null;
    const flush = () => {
      clearTimeout(pending);
      pending = null;
      if (state.settings[key] !== el.value) save({ [key]: el.value });
    };
    el.addEventListener("input", () => {
      clearTimeout(pending);
      pending = setTimeout(flush, 400);
    });
    el.addEventListener("change", flush);
    return el;
  };
  const check = (key, label, after) => {
    const el = h("input", { type: "checkbox" });
    el.checked = Boolean(s[key]);
    el.addEventListener("change", async () => {
      await save({ [key]: el.checked });
      after?.(el.checked);
    });
    return h("label", { class: "check" }, el, label);
  };
  const hour = (key) => {
    const el = h("input", { type: "number", min: 0, max: 23, class: "hour" });
    el.value = s[key];
    el.addEventListener("change", () => {
      const v = Math.max(0, Math.min(23, Number(el.value) || 0));
      el.value = v;
      save({ [key]: v });
    });
    return el;
  };
  const root = h("input", { type: "text", readonly: true });
  root.value = s.syncRoot ?? "";
  const note = (t) => h("div", { class: "hint", style: { color: "var(--text-2)", fontSize: "12px", lineHeight: 1.5 } }, t);
  return h(
    "div",
    { class: "form" },
    h("h3", {}, "坐站计划（固定）"),
    h(
      "div",
      { class: "plan" },
      h("div", { class: "plan-line" }, withNums(`坐 ${s.sitMinutes} 分钟 → 站 ${s.standMinutes} 分钟，一直循环`)),
      h("div", { class: "row plan-row" }, "夜里 ", hour("quietFrom"), " 点到 ", hour("quietTo"), " 点不叫；日课做完当天也不叫"),
      note("它不问你，默认你照做了。说错了就把「坐 | 站」翻过来：刚被叫的 90 秒内等于「我还坐着 / 我还站着」（10 分钟 / 5 分钟后再叫），之后等于现在就换。离开座位 3 分钟以上，切换等你回来再说；坐着离开则重新计时。全屏游戏时不弹，连续玩 60 分钟以上，关掉游戏马上让你站起来；读图、切出去不到 5 分钟不算关掉。"),
      check("pinned", "常驻细条（不点也一直在；10 秒没碰会变淡，碰一下就回来）", (on) => on && armFade()),
      check("postureEnabled", "坐站提醒（关掉就完全不提醒）"),
    ),
    h("h3", {}, "拉伸库"),
    note("每个拉伸一行一步，每步写上秒数或次数就能自动计时（「停 20 秒」「做 12 次」「停 5 秒 × 10 次」）。「试做」会在小窗里走一遍。"),
    ...LIBRARY.map(([key, label]) => libraryGroup(key, label, save)),
    h("h3", {}, "泡完澡后的日课"),
    note("托盘「泡完澡了」：跟练视频 → 站着拉伸 → 隔天加肩袖力量 → 地上拉伸和 12 次腹式呼吸。写了时长的视频放完自动跳下一个（YouTube 的还能收到播放器放完的消息），没写的看完点「跟练完了，下一个」。泡完热水澡先喝点水，从地上站起来慢一点。夜里疼醒、抬手没力气、手发麻，或不舒服超过 6 周，请去看医生或理疗师。"),
    h("div", { class: "field" }, "跟练视频（每行：名字 + 链接，链接后面可以写时长，如 4:04 或 4 分 35 秒）", text("ritualVideos", { area: true, rows: 5 })),
    check("ritualStrengthOn", "隔天加肩袖力量"),
    h("h3", {}, "同步（和 Mac 共用）"),
    h(
      "div",
      { class: "field" },
      "同步文件夹",
      h(
        "div",
        { class: "row", style: { gap: "8px" } },
        h("div", { class: "grow" }, root),
        h(
          "button",
          {
            class: "bare",
            onclick: async () => {
              const picked = await call("pick_folder");
              if (picked) {
                root.value = picked;
                await save({ syncRoot: picked });
                await refresh();
              }
            },
          },
          "选择…",
        ),
      ),
      h("div", { class: "hint" }, "选 Mac 设置里的同一个文件夹（OneDrive 等）。单词进度、明天的会议、词表都从这里来。"),
    ),
    h("div", { class: "field" }, "这台电脑的名字", text("device"), h("div", { class: "hint" }, "进度文件按名字分开写，两台设备不要同名。")),
    h(
      "details",
      {},
      h("summary", {}, "高级（一般不用动）"),
      h(
        "div",
        { class: "form", style: { marginTop: "14px" } },
        check("autostart", "开机后自动启动（只待在托盘里，几乎不占资源）"),
        h("div", { class: "field" }, "打游戏时让 Yudh 完全安静的程序（每行一个）", text("quietApps", { area: true, rows: 3 })),
        note(
          "这些程序运行时，Yudh 关掉自己所有的窗口、不再弹出任何东西，也不再读键鼠空闲和全屏状态，只留托盘图标；游戏关掉后自动恢复（连续玩了 60 分钟以上，关掉游戏就马上让你站起来）。只看进程列表里的名字（和任务管理器的「详细信息」一样），不会打开或读取游戏进程。默认是 AION2。",
        ),
        ...voiceSection(),
      ),
    ),
  );
}

/** 拉伸库の 1 群:一覧(姿勢の絵・名前・長さ・歩数)→ 行を開くと手順を直せる。テキストは構造から作り直して保存する */
function libraryGroup(key, label, save) {
  const s = state.settings;
  const list = parseStretches(s[key]);
  let pending = null;
  // 手元の値はすぐ更新(作り直す一覧は state.settings から読むので、保存の 400 ms を待つと古い一覧が出る)。保存だけ少し待つ
  const commit = (rerender = true) => {
    const textValue = renderStretches(list);
    state.settings[key] = textValue;
    clearTimeout(pending);
    pending = setTimeout(() => call("settings_save", { patch: { [key]: textValue } }), 400);
    if (rerender) rerenderGroup();
  };
  const holder = h("div", { class: "library-group" });
  const rerenderGroup = () => holder.replaceWith(libraryGroup(key, label, save));
  const row = (st, i) => {
    const id = `${key}:${i}`;
    const open = state.libraryOpen === id;
    const summary = h(
      "div",
      { class: "lib-row row" },
      h("span", { class: "lib-pose" }, poseSmall(illustration(st), 40)),
      h("span", { class: "lib-name grow" }, title(st.name), h("span", { class: "lib-meta" }, withNums(` ${mmss(totalSeconds(st))} · ${st.steps.length} 步`))),
      h("button", { class: "bare", title: "在小窗里走一遍", onclick: () => call("posture_preview", { text: renderStretches([st]) }) }, "试做"),
      h(
        "button",
        {
          class: "bare",
          onclick: () => {
            state.libraryOpen = open ? null : id;
            rerenderGroup();
          },
        },
        open ? "收起" : "编辑",
      ),
    );
    if (!open) return summary;
    const stepInput = (line, j) => {
      const input = h("input", { type: "text", value: line });
      const meta = h("span", { class: "lib-meta" }, metaText(line) ?? "10 秒");
      input.addEventListener("input", () => {
        st.steps[j] = input.value;
        meta.textContent = metaText(input.value) ?? "10 秒";
        commit(false);
      });
      return h(
        "div",
        { class: "lib-step row" },
        h("span", { class: "t-count" }, String(j + 1)),
        input,
        meta,
        h("button", { class: "bare", title: "删除这一步", onclick: () => (st.steps.splice(j, 1), commit()) }, "×"),
      );
    };
    const name = h("input", { type: "text", value: st.name });
    name.addEventListener("input", () => {
      st.name = name.value;
      commit(false);
    });
    const editor = h(
      "div",
      { class: "lib-editor" },
      h("div", { class: "lib-step row" }, h("span", { class: "t-count" }, "名"), name, h("span", { class: "lib-meta" }, "（约 N 分钟）")),
      st.steps.map(stepInput),
      h(
        "div",
        { class: "row", style: { gap: "12px", marginTop: "6px" } },
        h("button", { class: "bare", onclick: () => (st.steps.push("停 20 秒"), commit()) }, "+ 加一步"),
        h("span", { class: "grow" }),
        i > 0 ? h("button", { class: "bare", onclick: () => (list.splice(i - 1, 2, list[i], list[i - 1]), (state.libraryOpen = `${key}:${i - 1}`), commit()) }, "上移") : null,
        i < list.length - 1 ? h("button", { class: "bare", onclick: () => (list.splice(i, 2, list[i + 1], list[i]), (state.libraryOpen = `${key}:${i + 1}`), commit()) }, "下移") : null,
        h("button", { class: "bare", onclick: () => (list.splice(i, 1), (state.libraryOpen = null), commit()) }, "删除这个拉伸"),
      ),
    );
    return h("div", { class: "lib-item open" }, summary, editor);
  };
  clear(
    holder,
    h("div", { class: "lib-head row" }, h("span", { class: "t-section" }, label), h("span", { class: "grow" }), h("span", { class: "t-caption" }, withNums(`${list.length} 个 · 共 ${mmss(list.reduce((a, st) => a + totalSeconds(st), 0))}`))),
    list.map(row),
    h(
      "div",
      { class: "row", style: { gap: "14px", marginTop: "4px" } },
      h("button", { class: "bare", onclick: () => (list.push({ name: "新的拉伸（约 1 分钟）", steps: ["停 20 秒", "换另一侧，停 20 秒"] }), (state.libraryOpen = `${key}:${list.length - 1}`), commit()) }, "+ 新建拉伸"),
      s.defaults?.[key]
        ? h(
            "button",
            {
              class: "bare",
              onclick: async () => {
                await save({ [key]: s.defaults[key] });
                state.libraryOpen = null;
                rerenderGroup();
              },
            },
            "恢复默认",
          )
        : null,
    ),
  );
  return holder;
}

/** 听写で読む英語の声(英式が無ければ入れ方を書く)。日课の語音播报はやめた */
function voiceSection() {
  if (!("speechSynthesis" in window) || !speechSynthesis.getVoices().length) return [];
  const gb = voiceFor(["en-GB"]);
  const style = { color: "var(--text-2)", fontSize: "12px", lineHeight: 1.5 };
  const how = "Windows 设置 → 时间和语言 → 语音 → 管理语音 → 添加语音";
  return [
    h("div", { class: "hint", style }, gb ? `听写的语音：${gb.name}` : `听写的语音：没装英式英语，现在用美式代替。${how} →「English (United Kingdom)」`),
  ];
}

// MARK: 键盘

function bindKeys() {
  document.addEventListener("keydown", (e) => {
    // 押しっぱなしの繰り返しは受けない(Space の長押しで何枚も評価しない)
    if (e.repeat) return;
    // Ctrl+R / F5 で画面を読み直さない(WebView2 の既定の動き)。听写では Ctrl+R が「播放」
    if (e.key === "F5" || (e.ctrlKey && e.key.toLowerCase() === "r")) {
      e.preventDefault();
      if (e.key !== "F5" && state.tab === "english" && state.card?.kind === "spell") playSpell();
      return;
    }
    const typing = e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement;
    // 設定の入力中は Esc で閉じない(書きかけを失わない)。听写の入力欄からは閉じてよい。
    // 常駐の帯なら、広げた面板は帯に戻すだけ
    if (e.key === "Escape" && (!typing || e.target.id === "spell-input")) {
      // 常駐の帯:広げていれば帯に戻すだけ、帯なら何もしない(ゲームから戻って押す Esc で消えないように)
      if (state.panel?.pinned) {
        if (state.expanded) {
          call("open_surface", { which: "panel-strip" });
          collapse();
        }
      } else closeWindow();
      return;
    }
    if (typing) return;
    if (!state.expanded || state.tab !== "english" || !state.card) return;
    if (e.ctrlKey && e.key.toLowerCase() === "z") {
      if (state.undoable) undo();
      return;
    }
    if (state.card.kind === "vocab") {
      if (e.key === " ") {
        e.preventDefault();
        if (state.revealed) rate("good");
        else reveal();
      } else if (state.revealed && ["1", "2", "3", "4"].includes(e.key)) {
        rate(ratings[Number(e.key) - 1][0]);
      }
    } else if (state.card.kind === "spell") {
      if (e.key === "Enter" && state.graded) {
        e.preventDefault();
        submitSpell();
      }
    } else if (state.card.kind === "para") {
      if (["1", "2", "3", "4"].includes(e.key)) choose(Number(e.key) - 1);
      else if ((e.key === " " || e.key === "Enter") && state.picked != null) {
        e.preventDefault();
        nextCard();
      }
    }
  });
  document.addEventListener("mousemove", armFade);
  document.addEventListener("mouseenter", armFade);
}

async function init() {
  await Promise.all([loadMaterial(), loadIcons(), voicesReady()]);
  paintWall();
  renderWeekday();
  enableDragging();
  await refresh();
  // 初回は説明を読んでもらう:帯でなく全体を開く
  if (!state.panel.welcomed) await expand();
  bindKeys();
  // 30 秒ごとの钟の知らせ:帯と「今天」の数字を更新。Rust が帯に縮めたら中身も帯に
  listen("panel-tick", refreshQuiet);
  listen("panel-collapsed", collapse);
  // トレイの「打开面板」/アイコン(常駐の帯のとき):帯を広げる
  listen("panel-expand", expand);
}

init();
