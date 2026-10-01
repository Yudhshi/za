// ブラウザで画面を確かめるための見本(Tauri の中では読まない)。?prompt=askStand などで坐站の小窓を切り替える

const q = new URLSearchParams(location.search);
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
  { pose: "shoulder-blades", name: "夹肩胛骨", text: "保持 5 秒 × 10 次", meta: "5 秒 · 10 次" },
  { pose: "shoulder-rolls", name: "转肩", text: "向后转 10 次", meta: "10 次" },
  { pose: "chin-tuck", name: "收下巴", text: "保持 5 秒 × 10 次", meta: "5 秒 · 10 次" },
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
    breathToday: 4,
    ritualStreak: 5,
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
    const prompt = q.get("prompt") || "standing";
    return {
      prompt,
      posture: prompt === "askStand" ? "sitting" : "standing",
      dueAt: now + 12.5 * 60 * 1000,
      stretch: { name: "肩颈三步（约 2 分钟）", steps: steps.map((s) => s.text) },
      steps,
      step: Number(q.get("step") || 1),
      heading: "转肩",
      frieze: true,
      breathStartedAt: q.get("breath") ? now - 3000 : null,
      breathToday: 3,
      nextStretch: "斜角肌拉伸 · 2 分钟",
      caution: "※ 拉伸感可以，发麻或刺痛传到手上就停",
    };
  },
  posture_action: () => handlers.posture_state(),
  ritual_plan: ({ short }) => ({
    videos: [
      { title: "跟练 1", page: "https://www.bilibili.com/video/BV1JW4y1k7F7/", embed: null },
      { title: "跟练 2", page: "https://www.bilibili.com/video/BV1UL411F7Hk/", embed: null },
      { title: "跟练 3", page: "https://www.youtube.com/watch?v=SGPBSqxKGAc", embed: null },
      { title: "跟练 4", page: "https://www.youtube.com/watch?v=aHlNoTpXf_8", embed: null },
    ],
    steps: [
      { heading: "斜角肌拉伸", name: "斜角肌拉伸 · 2 分钟", text: "右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 20 秒", pose: "neck-side", meta: "20 秒", duration: 20, stepNumber: 0, stepCount: 4, stretchNumber: 0 },
      { heading: "斜角肌拉伸", name: "斜角肌拉伸 · 2 分钟", text: "微微抬头停 15 秒，再微微低头停 15 秒", pose: "neck-side", meta: "15 秒", duration: 30, stepNumber: 1, stepCount: 4, stretchNumber: 0 },
      { heading: "横臂拉肩后侧", name: "横臂拉肩后侧 · 1 分钟", text: "左手扣住右肘往左肩方向拉，肩膀不要耸，停 30 秒", pose: "stretch", meta: "30 秒", duration: 30, stepNumber: 1, stepCount: 3, stretchNumber: 1 },
    ],
    stretchNames: short ? ["斜角肌拉伸", "横臂拉肩后侧"] : ["斜角肌拉伸", "横臂拉肩后侧", "网球放松", "肩袖力量", "仰躺腹式呼吸"],
    hasStrength: !short,
    short,
    voice: false,
    streak: 5,
    caution: "※ 拉伸感可以，发麻或刺痛传到手上就停",
  }),
  ritual_done: () => 6,
  settings_get: () => ({
    syncRoot: "C:\\Users\\yudh\\OneDrive\\Yudh",
    device: "DESKTOP-9F2",
    autostart: true,
    postureEnabled: true,
    sitMinutes: 40,
    standMinutes: 15,
    stretches: "斜角肌拉伸（约 2 分钟）\n…",
    breathHabit: true,
    ritualVideos: "跟练 1 https://www.bilibili.com/video/BV1JW4y1k7F7/",
    ritualStretches: "…",
    ritualStrength: "…",
    ritualFloor: "…",
    ritualStrengthOn: true,
    ritualVoice: true,
    defaults: {},
  }),
  settings_save: () => null,
  pick_folder: () => "D:\\OneDrive\\Yudh",
  open_surface: () => null,
};

export async function call(cmd, args) {
  void revealed;
  const handler = handlers[cmd];
  if (!handler) throw new Error(`mock: ${cmd}`);
  return structuredClone(handler(args));
}
