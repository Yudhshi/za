// ブラウザで画面を確かめるための見本(Tauri の中では読まない)。
// posture.html?prompt=standing|sit、&phase=announce|breath|stretch|done、&step=N、&manual=1(トレイから開いた)、&preview=1(试做)
// index.html?welcome=0(初回の説明)、?configured=0、?pinned=1(常駐の帯)、?resting=1(夜)、?off=1(坐站提醒を切った)、?tomorrow=none、?new=1
// ritual.html?embed=1(Rust と同じ埋め込みの地址。外のサイトを読む)

const q = new URLSearchParams(location.search);
/** 小窓の見本が受けた操作(手順を進めた数・閉じた・呼吸を終えた) */
const mockPosture = { stepDelta: 0, closed: false, breathDone: false };
const now = Date.now();
let answered = 7;
let revealed = 0;

const vocab = {
  id: "vocab:b1-0807",
  word: "storey",
  phonetic: "/ˈstɔːri/",
  pos: "n.",
  meaning: "楼层",
  example: "The office is on the third storey of the building.",
  level: "B1",
  isNew: true,
  known: false,
};

const stats = () => ({
  today: "2026-10-02",
  todayCount: answered,
  goal: 20,
  results: ["good", "again", "easy", "good", "hard", "good", "known"].slice(0, answered),
  board: Array.from({ length: 20 }, (_, i) =>
    i < answered ? ["good", "forgot", "easy", "good", "fuzzy", "good", "easy"][i % 7] : i === answered ? "current" : "empty",
  ),
  streak: 12,
  remaining: { vocab: 13, para: 10, spell: 15 },
});

const steps = [
  { pose: "neck-side", name: "第 1 步", text: "右手按住右侧锁骨下方固定第一根肋骨，头向左倒拉伸右侧颈部，右肩放松下沉，停 20 秒", meta: "20 秒", section: "斜角肌拉伸", titled: false },
  { pose: "neck-side", name: "第 2 步", text: "再微微抬头看斜上方，停 20 秒", meta: "20 秒", section: "斜角肌拉伸", titled: false },
  { pose: "neck-side", name: "第 3 步", text: "换左边：左手按住左侧锁骨下方，头向右倒拉伸左侧颈部，左肩放松下沉，停 20 秒", meta: "20 秒", section: "斜角肌拉伸", titled: false },
  { pose: "neck-side", name: "第 4 步", text: "再微微抬头看斜上方，停 20 秒", meta: "20 秒", section: "斜角肌拉伸", titled: false },
  { pose: "shoulder-blades", name: "夹肩胛骨", text: "保持 5 秒 × 10 次", meta: "5 秒 · 10 次", section: "肩颈三步", titled: true },
  { pose: "shoulder-rolls", name: "转肩", text: "向后转 10 次", meta: "10 次", section: "肩颈三步", titled: true },
  { pose: "chin-tuck", name: "收下巴", text: "保持 5 秒 × 10 次", meta: "5 秒 · 10 次", section: "肩颈三步", titled: true },
];

const handlers = {
  panel_state: () => ({
    configured: q.get("configured") !== "0",
    syncRoot: "C:\\Users\\yudh\\OneDrive\\Yudh",
    hasLibrary: true,
    stats: stats(),
    tomorrow:
      q.get("tomorrow") === "none"
        ? { state: "notSynced" }
        : {
            state: "meetings",
            meetings: [
              { id: "e1", title: "デザインレビュー", start: "2026-10-03T00:30:00Z", end: "2026-10-03T01:00:00Z", allDay: false, join: "https://meet.google.com/abc" },
              { id: "e2", title: "朝会", start: "2026-10-03T01:00:00Z", end: "2026-10-03T01:15:00Z", allDay: false, join: null },
              { id: "e3", title: "1on1 with 田中", start: "2026-10-03T05:00:00Z", end: "2026-10-03T05:30:00Z", allDay: false, join: "https://meet.google.com/xyz" },
            ],
          },
    posture: "sitting",
    minutesInPosture: 23,
    prompt: null,
    since: now - 23 * 60 * 1000,
    dueAt: now + 7 * 60 * 1000,
    announced: true,
    resting: q.get("resting") === "1",
    restReason: q.get("resting") === "1" ? "night" : null,
    quietTo: 8,
    marks: (() => {
      const t = new Date();
      t.setHours(9, 0, 0, 0);
      const b = t.getTime();
      const m = (min, kind) => ({ at: b + min * 60000, kind });
      return [m(0, "sit"), m(30, "stand"), m(60, "sit"), m(75, "away"), m(95, "sit"), m(120, "stand"), m(150, "sit"), m(180, "game"), m(250, "sit"), m(280, "stand"), m(310, "sit")];
    })(),
    today: "今天站了 1 小时 30 分，换了 3 次姿势",
    todayShort: "站了 1 小时 30 分 · 换了 3 次",
    breathToday: 4,
    ritualStreak: 5,
    ritualToday: false,
    welcomed: q.get("welcome") !== "0",
    pinned: q.get("pinned") === "1",
    enabled: q.get("off") !== "1",
  }),
  english_card: ({ kind }) =>
    kind === "spell"
      ? {
          kind: "spell",
          id: "spell:accommodation",
          isNew: q.get("new") === "1",
          vocab: null,
          question: null,
          spell: { w: "accommodation", ipa: "əˌkɒməˈdeɪʃn", zh: "住宿", set: "住宿租房" },
          history: ["forgot", "fuzzy", "current"],
        }
      : kind === "para"
      ? {
          kind: "para",
          id: "para:listening:reserve",
          isNew: false,
          vocab: null,
          question: { entry: { w: "reserve", pos: "v.", zh: "预订", syn: ["book"], skill: "listening" }, choices: ["alter", "book", "identify", "be similar to"], answerIndex: 1 },
          history: ["good", "forgot", "current"],
        }
      : { kind: "vocab", id: vocab.id, isNew: true, vocab, question: null, history: ["fuzzy", "good", "current"] },
  english_rate: () => {
    answered += 1;
    revealed = 0;
    return stats();
  },
  english_known: () => {
    answered += 1;
    return stats();
  },
  english_spell: ({ input }) => {
    answered += 1;
    const typed = (input ?? "").trim().toLowerCase();
    const answer = "accommodation";
    const result = typed === answer ? "correct" : typed === "acommodation" ? "almost" : "wrong";
    const marks =
      typed === "acommodation"
        ? { typed, typedMarks: Array(12).fill(false), answer, answerMarks: answer.split("").map((_, i) => i === 2) }
        : { typed, typedMarks: Array.from(typed, (c, i) => c !== answer[i]), answer, answerMarks: Array.from(answer, (c, i) => typed !== answer && (typed[i] ?? "") !== c) };
    return { result, marks, stats: stats() };
  },
  english_undo: () => "vocab",
  english_more: () => null,
  posture_state: () => {
    const prompt = mockPosture.closed ? null : q.get("prompt") || "standing";
    const phase = q.get("phase") || "stretch";
    const preview = q.get("preview") === "1";
    // announce:いま言ったところ。breath:一言のあと呼吸 3 秒目。stretch / done:呼吸は済んだ
    const since = phase === "announce" ? now - 1000 : phase === "breath" ? now - 7000 - 3000 : now - 5 * 60 * 1000;
    const count = preview ? 3 : steps.length;
    const step = Math.max(0, Math.min(count, (phase === "done" ? steps.length : Number(q.get("step") || 5)) + mockPosture.stepDelta));
    const current = steps[Math.min(step, steps.length - 1)];
    return {
      prompt,
      posture: prompt === "sit" ? "sitting" : "standing",
      since,
      dueAt: since + 30 * 60 * 1000,
      announced: !preview && q.get("manual") !== "1",
      stretch: { name: "肩颈三步（约 2 分钟）", steps: steps.slice(4).map((s) => s.text) },
      fixedName: preview ? "" : "斜角肌拉伸",
      steps: preview ? steps.slice(4) : steps,
      durations: preview ? [52, 40, 52] : [20, 20, 20, 20, 52, 40, 52],
      step: preview ? Math.min(step, 3) : step,
      heading: current.titled ? current.name : current.section,
      frieze: false,
      preview,
      breathStartedAt: !mockPosture.breathDone && (phase === "announce" || phase === "breath") ? since : null,
      breathToday: 3,
      nextStretch: "斜角肌拉伸 · 2 分钟",
      today: "今天站了 1 小时 30 分，换了 3 次姿势",
      lastStandMinutes: 30,
      marks: handlers.panel_state().marks,
      quietTo: 8,
      caution: "※ 拉伸感可以，发麻或刺痛传到手上就停",
    };
  },
  // 操作を見本の状態に当てる(当てないと自動送りが同じ歩で回り続ける)
  posture_action: ({ action }) => {
    if (action === "next") mockPosture.stepDelta += 1;
    else if (action === "prev") mockPosture.stepDelta -= 1;
    else if (action === "close" || action === "flip") mockPosture.closed = true;
    else if (action === "breathDone" || action === "breathSkip") mockPosture.breathDone = true;
    return handlers.posture_state();
  },
  ritual_plan: ({ short }) => ({
    videos: [
      // ?embed=1 で Rust と同じ埋め込み地址(外のサイトを読む)。既定はブラウザで開く舞台(素材だけで見られる)
      { title: "跟练 1", page: "https://www.bilibili.com/video/BV1JW4y1k7F7/", embed: q.get("embed") ? "https://player.bilibili.com/player.html?bvid=BV1JW4y1k7F7&page=1&autoplay=1&danmaku=0&high_quality=1" : null, seconds: 244 },
      { title: "跟练 2", page: "https://www.bilibili.com/video/BV1UL411F7Hk/", embed: q.get("embed") ? "https://player.bilibili.com/player.html?bvid=BV1UL411F7Hk&page=1&autoplay=1&danmaku=0&high_quality=1" : null, seconds: null },
      { title: "跟练 3", page: "https://www.youtube.com/watch?v=SGPBSqxKGAc", embed: q.get("embed") ? "https://www.youtube-nocookie.com/embed/SGPBSqxKGAc?autoplay=1&rel=0&playsinline=1&enablejsapi=1" : null, seconds: null },
      { title: "跟练 4", page: "https://www.youtube.com/watch?v=aHlNoTpXf_8", embed: q.get("embed") ? "https://www.youtube-nocookie.com/embed/aHlNoTpXf_8?autoplay=1&rel=0&playsinline=1&enablejsapi=1" : null, seconds: null },
    ],
    steps: [
      { heading: "斜角肌拉伸", name: "斜角肌拉伸 · 2 分钟", text: "右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 20 秒", pose: "neck-side", meta: "20 秒", duration: 20, stepNumber: 0, stepCount: 4, stretchNumber: 0 },
      { heading: "斜角肌拉伸", name: "斜角肌拉伸 · 2 分钟", text: "微微抬头停 15 秒，再微微低头停 15 秒", pose: "neck-side", meta: "15 秒", duration: 30, stepNumber: 1, stepCount: 4, stretchNumber: 0 },
      { heading: "横臂拉肩后侧", name: "横臂拉肩后侧 · 1 分钟", text: "左手扣住右肘往左肩方向拉，肩膀不要耸，停 30 秒", pose: "stretch", meta: "30 秒", duration: 30, stepNumber: 1, stepCount: 3, stretchNumber: 1 },
    ],
    stretchNames: short ? ["斜角肌拉伸", "横臂拉肩后侧"] : ["斜角肌拉伸", "横臂拉肩后侧", "网球放松", "肩袖力量", "仰躺腹式呼吸"],
    hasStrength: !short,
    short,
    streak: 5,
    caution: "※ 拉伸感可以，发麻或刺痛传到手上就停",
  }),
  ritual_done: () => 6,
  settings_get: () => ({
    syncRoot: "C:\\Users\\yudh\\OneDrive\\Yudh",
    device: "DESKTOP-9F2",
    autostart: true,
    quietApps: "Aion2.exe\nAion2-Win64-Shipping.exe",
    welcomed: true,
    pinned: false,
    postureEnabled: true,
    sitMinutes: 30,
    standMinutes: 30,
    quietFrom: 23,
    quietTo: 8,
    fixed: "斜角肌拉伸（约 1 分半）\n右手按住右侧锁骨下方固定第一根肋骨，头向左倒拉伸右侧颈部，右肩放松下沉，停 20 秒\n再微微抬头看斜上方，停 20 秒\n换左边：左手按住左侧锁骨下方，头向右倒拉伸左侧颈部，左肩放松下沉，停 20 秒\n再微微抬头看斜上方，停 20 秒",
    stretches: "W 字收肩（约 1 分钟）\n手肘贴着身体弯成 90°，手心朝前\n前臂向外打开，同时把肩胛骨往后、往中间收，不要耸肩\n停 5 秒后放松。做 12 次\n\n肩颈三步（约 2 分钟）\n夹肩胛骨：保持 5 秒 × 10 次\n转肩：向后转 10 次\n收下巴：保持 5 秒 × 10 次\n\n走一走（1〜2 分钟）\n离开座位去接杯水，手臂自然摆动地走 1 分钟\n看窗外等远处 20 秒",
    breathHabit: true,
    ritualVideos: "跟练 1 https://www.bilibili.com/video/BV1JW4y1k7F7/ 4:04\n跟练 2 https://www.bilibili.com/video/BV1UL411F7Hk/\n跟练 3 https://www.youtube.com/watch?v=SGPBSqxKGAc\n跟练 4 https://www.youtube.com/watch?v=aHlNoTpXf_8",
    ritualStretches: "斜角肌拉伸（约 2 分钟）\n右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 20 秒\n微微抬头停 15 秒，再微微低头停 15 秒\n\n横臂拉肩后侧（约 1 分钟）\n右臂伸直横过身体前方，和肩同高\n左手扣住右肘往左肩方向拉，肩膀不要耸，停 30 秒\n换另一侧，停 30 秒",
    ritualStrength: "肩袖力量（隔天做，约 6 分钟）\n坐在地上，右手肘贴腰弯 90°，左手握住右手腕；右手往外推、左手顶住不让动，用 5 成力，停 10 秒 × 5 次\n换左手往外推，停 10 秒 × 5 次",
    ritualFloor: "仰躺腹式呼吸（约 3 分钟）\n仰躺，膝盖弯曲，一只手放肚子上，一只手放胸口\n用鼻子吸气 4 秒只让肚子鼓起来，用嘴呼气 6 秒，做 12 次",
    ritualStrengthOn: true,
    defaults: { quietApps: "Aion2.exe\nAion2-Win64-Shipping.exe", fixed: "斜角肌拉伸（约 1 分半）\n停 20 秒", stretches: "W 字收肩（约 1 分钟）\n停 5 秒后放松。做 12 次", ritualStretches: "斜角肌拉伸（约 2 分钟）\n停 20 秒", ritualStrength: "肩袖力量\n停 10 秒 × 5 次", ritualFloor: "仰躺腹式呼吸\n做 12 次" },
  }),
  settings_save: ({ patch }) => {
    window.__saved = patch;
    return null;
  },
  pick_folder: () => "D:\\OneDrive\\Yudh",
  open_surface: () => null,
  posture_preview: () => null,
  posture_summary: () => {
    const p = handlers.panel_state();
    return { posture: p.posture, minutesInPosture: p.minutesInPosture, prompt: p.prompt, since: p.since, dueAt: p.dueAt, announced: p.announced, resting: p.resting, restReason: p.restReason, quietTo: p.quietTo, enabled: p.enabled, pinned: p.pinned, marks: p.marks, today: p.today, todayShort: p.todayShort };
  },
};

export async function call(cmd, args) {
  void revealed;
  const handler = handlers[cmd];
  if (!handler) throw new Error(`mock: ${cmd}`);
  return structuredClone(handler(args));
}
