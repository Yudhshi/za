// 面板:英語(単語・考点词・听写)/ 明天的会 / 设置。底栏は坐站の状態と「泡完澡了」
import { loadMaterial, slice, sprite, tile, h, button, first, asset } from "./baked.js";
import { call, closeWindow, openUrl } from "./api.js";
import { loadIcons, icon, weekdays, weekdaysZh, hhmm, speak, stopSpeaking, clear, voiceFor, voicesReady } from "./common.js";

const $ = (id) => document.getElementById(id);

const state = {
  tab: safeGet("tab") || "english",
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
  slice(panel, "panel-frame-night");
}

function renderWeekday() {
  const day = weekdays[new Date().getDay()];
  const holder = $("weekday");
  const art = sprite(`day-${day}-white-night`);
  clear(holder, art ?? h("span", { class: "fallback" }, day.toUpperCase()));
}

function renderTabs() {
  const remaining = state.panel?.stats
    ? Object.values(state.panel.stats.remaining).reduce((a, b) => a + b, 0)
    : null;
  const tabs = [
    ["english", "英语", remaining],
    ["tomorrow", "明天", null],
    ["settings", "设置", null],
  ];
  clear(
    $("tabs"),
    tabs.map(([key, title, badge]) => {
      const on = state.tab === key;
      const el = h(
        "button",
        { class: `tab${on ? " on" : ""}`, onclick: () => switchTab(key) },
        title,
        badge != null && badge > 0 ? h("span", { class: "badge" }, badge) : null,
      );
      if (on) {
        const wide = title.length + (badge ? String(badge).length + 1 : 0) >= 5;
        slice(el, wide ? first("tab-chip-wide-night", "tab-chip-night") : "tab-chip-night") ||
          (el.style.background = "var(--white)");
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

function renderFooter() {
  const p = state.panel;
  const sitting = p.posture === "sitting";
  clear(
    $("footer"),
    h(
      "span",
      { class: "status" },
      icon(sitting ? "seat" : "stand", 15),
      `${sitting ? "已坐" : "已站"} ${Math.max(0, p.minutesInPosture)} 分钟`,
    ),
    h("button", { class: "bare", onclick: () => call("posture_action", { action: "open" }) }, sitting ? "站起来了吗？" : "看拉伸"),
    h("span", { class: "grow" }),
    h("span", { class: "status" }, `腹式呼吸今天 ${p.breathToday} 次`),
    h(
      "button",
      { class: "bare row", style: { gap: "6px" }, onclick: () => call("open_surface", { which: "ritual" }), title: "跟练视频 → 肩颈拉伸 → 躺着做腹式呼吸" },
      icon("play", 13),
      "泡完澡了",
    ),
  );
}

// MARK: 本体

async function refresh() {
  state.panel = await call("panel_state");
  renderTabs();
  renderFooter();
  await renderView();
}

async function renderView() {
  const view = $("view");
  if (state.tab === "tomorrow") return clear(view, tomorrowView());
  if (state.tab === "settings") return clear(view, await settingsView());
  clear(view, await englishView());
  focusSpell();
}

/** 听写は入力欄に焦点を置く(開いてすぐ打てる・Enter で続けられるように) */
function focusSpell() {
  if (state.card?.kind === "spell" && !state.graded) $("spell-input")?.focus();
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
      "选 Mac 同一个同步文件夹（OneDrive 等）。单词进度两边共用。",
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

async function rate(rating) {
  const c = state.card;
  state.panel.stats = await call("english_rate", { id: c.id, kind: c.kind, rating });
  state.undoable = true;
  await nextCard();
}

async function markKnown() {
  state.panel.stats = await call("english_known", { id: state.card.id });
  state.undoable = true;
  await nextCard();
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

async function settingsView() {
  const s = (state.settings = await call("settings_get"));
  const save = async (patch) => {
    await call("settings_save", { patch });
    Object.assign(state.settings, patch);
  };
  const text = (key, { area = false, rows } = {}) => {
    const el = h(area ? "textarea" : "input", area ? { rows } : { type: "text" });
    el.value = s[key] ?? "";
    el.addEventListener("change", () => save({ [key]: el.value }));
    return el;
  };
  const number = (key, min, max, step) => {
    const el = h("input", { type: "number", min, max, step });
    el.value = s[key];
    el.addEventListener("change", () => save({ [key]: Number(el.value) }));
    return el;
  };
  const check = (key, label) => {
    const el = h("input", { type: "checkbox" });
    el.checked = Boolean(s[key]);
    el.addEventListener("change", () => save({ [key]: el.checked }));
    return h("label", { class: "check" }, el, label);
  };
  const resettable = (key, title, rows) => {
    const area = text(key, { area: true, rows });
    return h(
      "details",
      {},
      h("summary", {}, title),
      h(
        "div",
        { class: "field", style: { marginTop: "8px" } },
        area,
        s.defaults?.[key]
          ? h(
              "button",
              {
                class: "bare",
                style: { alignSelf: "flex-start" },
                onclick: async () => {
                  area.value = s.defaults[key];
                  await save({ [key]: area.value });
                },
              },
              "恢复默认",
            )
          : null,
      ),
    );
  };
  const root = h("input", { type: "text", readonly: true });
  root.value = s.syncRoot ?? "";
  return h(
    "div",
    { class: "form" },
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
    check("autostart", "开机后自动启动（只待在托盘里，几乎不占资源）"),
    resettable("quietApps", "打游戏时让 Yudh 完全安静的程序（每行一个）", 3),
    h(
      "div",
      { class: "hint", style: { color: "var(--text-2)", fontSize: "12px", lineHeight: 1.5 } },
      "这些程序运行时，Yudh 关掉自己所有的窗口、不再弹出任何东西，也不再读键鼠空闲和全屏状态，只留托盘图标；游戏关掉后自动恢复（玩了 60 分钟以上会马上问一次要不要站起来）。只看进程列表里的名字（和任务管理器的「详细信息」一样），不会打开或读取游戏进程。默认是 AION2。",
    ),
    h("h3", {}, "坐站提醒"),
    check("postureEnabled", "提醒我切换坐姿和站姿"),
    h("div", { class: "row", style: { gap: "16px" } }, h("div", { class: "field" }, "坐几分钟", number("sitMinutes", 20, 90, 5)), h("div", { class: "field" }, "站几分钟", number("standMinutes", 5, 60, 5))),
    h("div", { class: "hint", style: { color: "var(--text-2)", fontSize: "12px", lineHeight: 1.5 } }, "全屏游戏时不弹；连续玩 60 分钟以上，退出全屏就马上问一次。坐着 3 分钟以上没操作就当作离开座位，重新计时。"),
    check("breathHabit", "站起来时先做 3 次腹式呼吸（吸 4 秒、呼 6 秒）"),
    resettable("stretches", "站起来时的拉伸（每次轮到一个）", 10),
    h("h3", {}, "泡完澡后的日课"),
    check("ritualStrengthOn", "隔天加肩袖力量（约 6 分钟，徒手 + 一瓶水）"),
    check("ritualVoice", "拉伸时语音播报每一步"),
    resettable("ritualVideos", "跟练视频（每行：名字 + 链接）", 5),
    resettable("ritualStretches", "站着做的拉伸", 10),
    resettable("ritualStrength", "肩袖力量（在地上做）", 6),
    resettable("ritualFloor", "最后在地上做的拉伸", 6),
    h("div", { class: "hint", style: { color: "var(--text-2)", fontSize: "12px", lineHeight: 1.5 } }, "泡完热水澡先喝点水，从地上站起来慢一点。夜里疼醒、抬手没力气、手发麻，或不舒服超过 6 周，请去看医生或理疗师。"),
    ...voiceSection(),
  );
}

/** このパソコンに入っている声(听写の英式・日课の中文)。無ければ入れ方を書く */
function voiceSection() {
  if (!("speechSynthesis" in window) || !speechSynthesis.getVoices().length) return [];
  const gb = voiceFor(["en-GB"]);
  const zh = voiceFor(["zh-CN", "zh-TW", "zh-HK"]);
  const style = { color: "var(--text-2)", fontSize: "12px", lineHeight: 1.5 };
  const how = "Windows 设置 → 时间和语言 → 语音 → 管理语音 → 添加语音";
  return [
    h("h3", {}, "语音"),
    h("div", { class: "hint", style }, gb ? `听写：${gb.name}` : `听写：没装英式英语语音，现在用美式代替。${how} →「English (United Kingdom)」`),
    h("div", { class: "hint", style }, zh ? `日课播报：${zh.name}` : `日课播报：没装中文语音，现在只计时不播报。${how} →「中文(简体，中国)」`),
  ];
}

// MARK: 键盘

function bindKeys() {
  document.addEventListener("keydown", (e) => {
    // Ctrl+R / F5 で画面を読み直さない(WebView2 の既定の動き)。听写では Ctrl+R が「播放」
    if (e.key === "F5" || (e.ctrlKey && e.key.toLowerCase() === "r")) {
      e.preventDefault();
      if (e.key !== "F5" && state.tab === "english" && state.card?.kind === "spell") playSpell();
      return;
    }
    const typing = e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement;
    // 設定の入力中は Esc で閉じない(書きかけを失わない)。听写の入力欄からは閉じてよい
    if (e.key === "Escape" && (!typing || e.target.id === "spell-input")) {
      closeWindow();
      return;
    }
    if (typing) return;
    if (state.tab !== "english" || !state.card) return;
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
}

async function init() {
  await Promise.all([loadMaterial(), loadIcons(), voicesReady()]);
  paintWall();
  renderWeekday();
  await refresh();
  bindKeys();
}

init();
