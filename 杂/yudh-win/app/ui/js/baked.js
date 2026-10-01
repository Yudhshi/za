// 焼いた素材(Mac と同じ material/ と manifest.json)を置く道具。
// slice = 九宫格(border-image。bleed の分だけ外へ広げ、insets は焼いた絵の端から)、sprite = 1 枚絵、
// tile = 敷き詰め、stencil = 図集の模板字。素材が無いときは何も描かず false を返す(呼ぶ側が文字と色で代える)

let manifest = { assets: {}, glyphs: {} };
const atlas = {};

export async function loadMaterial() {
  try {
    manifest = await (await fetch("material/manifest.json")).json();
  } catch {
    manifest = { assets: {}, glyphs: {} };
  }
  // 模板字の図集は大きさを先に知っておく(background-size に要る)
  await Promise.all(
    Object.entries(manifest.glyphs || {}).map(
      ([set, info]) =>
        new Promise((resolve) => {
          const img = new Image();
          img.onload = () => {
            atlas[set] = { w: img.naturalWidth / 2, h: img.naturalHeight / 2 };
            resolve();
          };
          img.onerror = () => resolve();
          img.src = `material/${info.file}`;
        }),
    ),
  );
  return manifest;
}

export function asset(id) {
  return manifest.assets?.[id];
}

export function has(id) {
  return Boolean(asset(id));
}

/** ids のうち、目録にある最初の素材 */
export function first(...ids) {
  return ids.find((id) => has(id));
}

function edges(v) {
  return { top: v?.[0] || 0, left: v?.[1] || 0, bottom: v?.[2] || 0, right: v?.[3] || 0 };
}

/** 九宫格を el の後ろ(over なら前)に敷く */
export function slice(el, id, { tile = false, over = false } = {}) {
  el.querySelector(`:scope > .paint${over ? ".over" : ":not(.over)"}`)?.remove();
  const a = asset(id);
  if (!a) return false;
  el.classList.add("baked");
  const b = edges(a.bleed);
  const i = edges(a.insets);
  const p = document.createElement("i");
  p.className = over ? "paint over" : "paint";
  p.setAttribute("aria-hidden", "true");
  Object.assign(p.style, {
    top: `${-b.top}px`,
    left: `${-b.left}px`,
    right: `${-b.right}px`,
    bottom: `${-b.bottom}px`,
    borderWidth: `${i.top}px ${i.right}px ${i.bottom}px ${i.left}px`,
    borderImageSource: `url("material/${a.file}")`,
    borderImageSlice: `${i.top * 2} ${i.right * 2} ${i.bottom * 2} ${i.left * 2} fill`,
    borderImageRepeat: tile ? "round" : "stretch",
  });
  el.prepend(p);
  return true;
}

/** 1 枚絵(大きさは pt。bleed は外へはみ出す) */
export function sprite(id, { scale = 1, height } = {}) {
  const a = asset(id);
  if (!a) return null;
  const s = height ? height / (a.size[1] - edges(a.bleed).top - edges(a.bleed).bottom) : scale;
  const b = edges(a.bleed);
  const img = document.createElement("img");
  img.className = "sprite";
  img.alt = "";
  img.src = `material/${a.file}`;
  Object.assign(img.style, {
    width: `${a.size[0] * s}px`,
    height: `${a.size[1] * s}px`,
    margin: `${-b.top * s}px ${-b.right * s}px ${-b.bottom * s}px ${-b.left * s}px`,
  });
  return img;
}

/** 敷き詰めの材質(混凝土) */
export function tile(el, id) {
  const a = asset(id);
  if (!a) return false;
  el.style.backgroundImage = `url("material/${a.file}")`;
  el.style.backgroundSize = `${a.size[0]}px ${a.size[1]}px`;
  el.style.backgroundRepeat = "repeat";
  return true;
}

/** 図集の模板字(字身の箱 = 大文字の高さ、幅 = 最後の字の墨の右端)。1 字でも無ければ null */
export function stencil(text, set) {
  const info = manifest.glyphs?.[set];
  const size = atlas[set];
  if (!info || !size || !text) return null;
  const capTop = info.capTop ?? 0;
  const capHeight = info.capHeight ?? info.pt;
  const box = document.createElement("span");
  box.className = "stencil";
  box.setAttribute("aria-label", text);
  let pen = 0;
  let right = 0;
  for (const ch of text) {
    const g = info.glyphs[ch];
    if (!g) return null;
    const [x, y, w, h] = g.rect;
    const span = document.createElement("span");
    Object.assign(span.style, {
      left: `${pen + g.bearing}px`,
      top: `${-capTop}px`,
      width: `${w / 2}px`,
      height: `${h / 2}px`,
      backgroundImage: `url("material/${info.file}")`,
      backgroundSize: `${size.w}px ${size.h}px`,
      backgroundPosition: `${-x / 2}px ${-y / 2}px`,
    });
    box.append(span);
    right = pen + (g.inkRight ?? g.advance);
    pen += g.advance;
  }
  box.style.width = `${right}px`;
  box.style.height = `${capHeight}px`;
  return box;
}

/** 小さな DOM の道具 */
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "style") Object.assign(el.style, v);
    else if (k.startsWith("on")) el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === "text") el.textContent = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

/** 喷漆 / 枠 / 文字だけのボタン(焼いた块を敷く) */
export function button(label, { kind = "teal", onClick, width, disabled, onKraft = false, title } = {}) {
  const cls = kind === "frame" ? `frame${onKraft ? " on-kraft" : ""}` : kind === "bare" ? `bare${onKraft ? " on-kraft" : ""}` : "spray";
  const el = h("button", { class: cls, onclick: onClick, disabled, title }, label);
  if (width) el.style.width = `${width}px`;
  if (kind === "teal") slice(el, "button-teal-night") || (el.style.background = "var(--teal)");
  if (kind === "orange") slice(el, "button-orange-night") || (el.style.background = "var(--orange)");
  if (kind === "frame") slice(el, onKraft ? first("frame-white-kraft", "frame-white-night") : "frame-white-night");
  return el;
}
