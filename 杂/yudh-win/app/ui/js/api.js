// Rust の命令を呼ぶ。Tauri の外(ブラウザで画面だけ確かめるとき)は mock.js の見本を返す

const tauri = window.__TAURI__;

export const inTauri = Boolean(tauri?.core?.invoke);

let mock = null;

export async function call(cmd, args = {}) {
  if (inTauri) return tauri.core.invoke(cmd, args);
  mock ??= await import("./mock.js");
  return mock.call(cmd, args);
}

/** Rust から届く知らせ(坐站の小窓の更新など) */
export function listen(event, handler) {
  if (inTauri) return tauri.event.listen(event, handler);
  return Promise.resolve(() => {});
}

/** いまの窓を閉じる */
export function closeWindow() {
  if (inTauri) return tauri.window.getCurrentWindow().close();
  return Promise.resolve();
}

/** 中身に合わせて窓の大きさを変える(坐站の小窓) */
export function fitWindow(label, width, height) {
  return call("open_surface", { which: label, fit: { width: Math.ceil(width), height: Math.ceil(height) } });
}

export function openUrl(url) {
  window.open(url, "_blank");
}
