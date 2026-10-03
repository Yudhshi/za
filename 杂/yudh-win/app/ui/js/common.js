// 画面に共通の道具:模板アイコン、曜日、時刻、読み上げ、短い音(3 種類)
import { h } from "./baked.js";

let iconsLoaded = null;

/** Mac と同じ模板アイコン(material/icons.svg の symbol を一度だけ埋め込む) */
export function loadIcons() {
  iconsLoaded ??= fetch("material/icons.svg")
    .then((r) => r.text())
    .then((svg) => {
      const holder = document.createElement("div");
      holder.style.display = "none";
      holder.innerHTML = svg;
      document.body.prepend(holder);
    })
    .catch(() => {});
  return iconsLoaded;
}

export function icon(name, size = 16) {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("width", size);
  svg.setAttribute("height", size);
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("icon");
  const use = document.createElementNS(ns, "use");
  use.setAttribute("href", `#i-${name}`);
  svg.append(use);
  return svg;
}

export const weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
export const weekdaysZh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];

export function hhmm(date) {
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

/** 「12:30」(秒は切り上げ、分は 2 桁、過ぎたら 00:00) */
export function clock(ms) {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

const ZH = ["zh-CN", "zh-TW", "zh-HK"];

/** langs の順で、入っている声を探す(Windows の自然な声 Natural / Online を先に)。無ければ null */
export function voiceFor(langs) {
  if (!("speechSynthesis" in window)) return null;
  const voices = speechSynthesis.getVoices();
  for (const lang of langs) {
    const found = voices.filter((v) => v.lang.replace("_", "-").toLowerCase() === lang.toLowerCase());
    found.sort((a, b) => /natural|online/i.test(b.name) - /natural|online/i.test(a.name));
    if (found[0]) return found[0];
  }
  return null;
}

/** 声の一覧が読み込まれるのを待つ(WebView2 では開いた直後は空のことがある。最長 1.5 秒)。一覧が取れたら true */
export function voicesReady() {
  if (!("speechSynthesis" in window)) return Promise.resolve(false);
  if (speechSynthesis.getVoices().length) return Promise.resolve(true);
  return new Promise((resolve) => {
    const done = () => resolve(speechSynthesis.getVoices().length > 0);
    speechSynthesis.addEventListener("voiceschanged", done, { once: true });
    setTimeout(done, 1500);
  });
}

/** 読み上げ。done は読み終えたときだけ(止めた・次を読んだときは呼ばない)。
 *  中文の声が入っていなければ読まない(別の言語の声で中文を読むと聞き取れない)。読んだら true */
export function speak(text, { lang = "en-GB", rate = 1, done } = {}) {
  if (!("speechSynthesis" in window)) return false;
  speechSynthesis.cancel();
  const zh = lang.startsWith("zh");
  const voice = voiceFor(zh ? ZH : [lang, "en-US", "en-AU"]);
  if (zh && !voice) return false;
  const u = new SpeechSynthesisUtterance(text);
  if (voice) u.voice = voice;
  u.lang = voice?.lang ?? lang;
  u.rate = rate;
  if (done) u.onend = done;
  speechSynthesis.speak(u);
  return true;
}

export function stopSpeaking() {
  if ("speechSynthesis" in window) speechSynthesis.cancel();
}

/** 短い音。焼いた素材と同じ世界の 4 つ(sounds/*.wav:胶带を裂く + 喷漆 / 模板の板を置く / 喷漆を 2 回 / 罐を置く)。
 *  読めなければ正弦波で代える。switch = 「站起来」、sit = 「坐下」、step = 手順が替わった、done = 全部終わった */
const SOUND_FILES = { switch: "sounds/switch.wav", sit: "sounds/sit.wav", step: "sounds/step.wav", done: "sounds/done.wav" };
const TONES = {
  switch: [
    [660, 0, 0.18],
    [990, 0.2, 0.3],
  ],
  sit: [
    [660, 0, 0.18],
    [440, 0.2, 0.3],
  ],
  step: [[1320, 0, 0.35]],
  done: [
    [990, 0, 0.14],
    [660, 0.15, 0.32],
  ],
};
let audio = null;
const buffers = {};

function context() {
  audio ??= new AudioContext();
  if (audio.state === "suspended") audio.resume().catch(() => {});
  return audio;
}

/** 音を先に読んでおく(窓を開いた直後に鳴らすので) */
export function loadSounds() {
  return Promise.all(
    Object.entries(SOUND_FILES).map(async ([kind, file]) => {
      try {
        const data = await (await fetch(file)).arrayBuffer();
        buffers[kind] = await context().decodeAudioData(data);
      } catch {
        /* 正弦波で代える */
      }
    }),
  );
}

export function sound(kind = "step") {
  try {
    const ctx = context();
    const gain = ctx.createGain();
    gain.connect(ctx.destination);
    const buffer = buffers[kind];
    if (buffer) {
      gain.gain.value = 0.7;
      const src = ctx.createBufferSource();
      src.buffer = buffer;
      src.connect(gain);
      src.start();
      return;
    }
    for (const [freq, at, len] of TONES[kind] ?? TONES.step) {
      const osc = ctx.createOscillator();
      const g = ctx.createGain();
      osc.frequency.value = freq;
      const t = ctx.currentTime + at;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.18, t + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + len);
      osc.connect(g).connect(gain);
      osc.start(t);
      osc.stop(t + len + 0.05);
    }
  } catch {
    /* 音が出なくても進む */
  }
}

/** 歩が終わったときの短い音 */
export function chime() {
  sound("step");
}

/** 中文の行の数字を Archivo の等幅で(基線を少し下げて中文と揃える) */
export function withNums(text) {
  const frag = document.createDocumentFragment();
  for (const part of String(text).split(/(\d[\d:]*)/)) {
    if (!part) continue;
    frag.append(/^\d/.test(part) ? h("span", { class: "num" }, part) : document.createTextNode(part));
  }
  return frag;
}

export function clear(el, ...children) {
  el.replaceChildren(...children.flat().filter(Boolean));
  return el;
}

export { h };
