// 画面に共通の道具:模板アイコン、曜日、時刻、読み上げ、短い音
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

function bestVoice(langs) {
  const voices = speechSynthesis.getVoices();
  for (const lang of langs) {
    const found = voices.filter((v) => v.lang.replace("_", "-").toLowerCase() === lang.toLowerCase());
    // Windows の自然な声(Natural / Online)を先に
    found.sort((a, b) => /natural|online/i.test(b.name) - /natural|online/i.test(a.name));
    if (found[0]) return found[0];
  }
  return null;
}

/** 読み上げ。done は読み終えたときだけ(止めた・次を読んだときは呼ばない) */
export function speak(text, { lang = "en-GB", rate = 1, done } = {}) {
  if (!("speechSynthesis" in window)) return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  const langs = lang.startsWith("zh") ? ["zh-CN", "zh-TW", "zh-HK"] : [lang, "en-US", "en-AU"];
  const voice = bestVoice(langs);
  if (voice) u.voice = voice;
  u.lang = voice?.lang ?? lang;
  u.rate = rate;
  if (done) u.onend = done;
  speechSynthesis.speak(u);
}

export function stopSpeaking() {
  if ("speechSynthesis" in window) speechSynthesis.cancel();
}

/** 歩が終わったときの短い音 */
export function chime() {
  try {
    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.frequency.value = 1320;
    gain.gain.setValueAtTime(0.0001, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.35);
    osc.connect(gain).connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.4);
  } catch {
    /* 音が出なくても進む */
  }
}

export function clear(el, ...children) {
  el.replaceChildren(...children.flat().filter(Boolean));
  return el;
}

export { h };
