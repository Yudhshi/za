//! 窓の出し入れ:面板(タスクバーのそば、フォーカスを失ったら閉じる)・坐站の小窓(画面上部の中央、フォーカスを奪わない)・
//! 日课の窓(ふつうの窓)。どれも閉じたら捨てる。位置はマウスのある画面の、タスクバーを除いた範囲で決める。
//! 名単のゲームが動いているあいだは、どの窓も作らない(反作弊に「ゲームの上に被さる窓」と見られないように)

use std::time::{Duration, Instant};

use tauri::{
    AppHandle, Emitter, LogicalPosition, LogicalSize, Manager, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder, WindowEvent,
};

use crate::settings::Settings;
use crate::AppState;

/// 面板の大きさ(Mac と同じ 520 幅 + 焼いた枠のはみ出し)
const PANEL_SIZE: (f64, f64) = (560.0, 760.0);
/// 面板は最初は細い帯(坐站の状態・今日の数字・泡完澡了)。「打开」で PANEL_SIZE に広がる
const STRIP_SIZE: (f64, f64) = (560.0, 100.0);
/// WebView2 の起動引数:小窓の音(切り替え・手順・做完)を操作なしで鳴らせるように。
/// 既定の引数(Edge の UI を切る)はそのまま残す。全部の窓で同じにする(違う引数の窓は別のデータフォルダが要る)
#[cfg(windows)]
const BROWSER_ARGS: &str =
    "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --autoplay-policy=no-user-gesture-required";

/// 窓の作り方のうち、全部の窓で同じ分
fn builder<'a>(
    app: &'a AppHandle,
    label: &str,
    page: &str,
) -> WebviewWindowBuilder<'a, tauri::Wry, AppHandle> {
    let b = WebviewWindowBuilder::new(app, label, WebviewUrl::App(page.into())).title("Yudh");
    #[cfg(windows)]
    let b = b.additional_browser_args(BROWSER_ARGS);
    b
}
/// 坐站の小窓(牛皮纸 360 + はみ出し。高さは中身に合わせて画面側が変える)
const POSTURE_SIZE: (f64, f64) = (400.0, 520.0);

/// マウスのある画面の、タスクバーを除いた範囲(論理 px:x, y, 幅, 高さ)。
/// 取れなければ主画面、それも無ければ 1920×1040
fn area(app: &AppHandle) -> (f64, f64, f64, f64) {
    let monitor = app
        .cursor_position()
        .ok()
        .and_then(|p| app.monitor_from_point(p.x, p.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    monitor
        .map(|m| {
            let scale = m.scale_factor();
            let work = m.work_area();
            (
                f64::from(work.position.x) / scale,
                f64::from(work.position.y) / scale,
                f64::from(work.size.width) / scale,
                f64::from(work.size.height) / scale,
            )
        })
        .unwrap_or((0.0, 0.0, 1920.0, 1040.0))
}

/// 自分で動かした位置(論理 px)が、いまのどれかの画面に収まっていればそれを使う
/// (少なくとも左上の 80×40 が作業範囲の中:掴み直せる)。画面を外したら既定の位置
fn saved_position(app: &AppHandle, saved: Option<[f64; 2]>, width: f64) -> Option<(f64, f64)> {
    let [x, y] = saved?;
    let monitors = app.available_monitors().ok()?;
    monitors
        .iter()
        .any(|m| {
            let s = m.scale_factor();
            let w = m.work_area();
            let (ax, ay) = (f64::from(w.position.x) / s, f64::from(w.position.y) / s);
            let (aw, ah) = (f64::from(w.size.width) / s, f64::from(w.size.height) / s);
            x >= ax - width + 80.0 && x <= ax + aw - 80.0 && y >= ay && y <= ay + ah - 40.0
        })
        .then_some((x, y))
}

/// 動かした位置を覚え、閉じたら設定に書く。作った直後にこちらで置いた分と、帯を広げるときにこちらで動かした分は数えない。
/// 面板は左下(帯と全体で下の辺を揃える)、坐站の小窓は左上を覚える
fn remember_position(
    window: &WebviewWindow,
    app: &AppHandle,
    slot: fn(&mut Settings) -> &mut Option<[f64; 2]>,
    bottom: bool,
) {
    let created = Instant::now();
    let handle = app.clone();
    let this = window.clone();
    window.on_window_event(move |event| match event {
        // 最小化(Win+D など)で (-32000, -32000) に動かされた分は覚えない
        WindowEvent::Moved(pos)
            if created.elapsed() > Duration::from_millis(800)
                && !just_moved_by_us(&handle)
                && pos.x > -32000
                && pos.y > -32000 =>
        {
            let scale = this.scale_factor().unwrap_or(1.0);
            let logical = pos.to_logical::<f64>(scale);
            let height = if bottom {
                this.inner_size()
                    .map(|size| f64::from(size.height) / scale)
                    .unwrap_or(0.0)
            } else {
                0.0
            };
            if let Ok(mut inner) = handle.state::<AppState>().inner.lock() {
                *slot(&mut inner.settings) = Some([logical.x, logical.y + height]);
            }
        }
        WindowEvent::Destroyed => {
            let state = handle.state::<AppState>();
            let guard = state.inner.lock();
            if let Ok(inner) = guard {
                state.save(&inner);
            }
        }
        _ => {}
    });
}

/// こちらで動かした直後か(帯を広げたとき。ユーザーが動かした位置として覚えない)
fn just_moved_by_us(app: &AppHandle) -> bool {
    app.state::<AppState>()
        .programmatic_move
        .lock()
        .ok()
        .and_then(|t| *t)
        .is_some_and(|t| t.elapsed() < Duration::from_millis(1000))
}

/// 名単のゲームが動いているか(動いていれば窓を作らない)
fn quiet(app: &AppHandle) -> bool {
    app.state::<AppState>()
        .inner
        .lock()
        .map(|inner| inner.quiet.is_some())
        .unwrap_or(false)
}

/// ゲームが始まった / 終わった:始まったら開いている窓を全部閉じる。トレイの説明とメニューを変える
pub fn quiet_changed(app: &AppHandle, game: Option<&str>) {
    if game.is_some() {
        if let Ok(mut inner) = app.state::<AppState>().inner.lock() {
            inner.preview = None;
        }
        for label in ["panel", "posture", "ritual"] {
            if let Some(window) = app.get_webview_window(label) {
                let _ = window.close();
            }
        }
    }
    refresh_tray_menu(app);
    // ゲームが終わって、帯を常駐させる設定なら戻す
    if game.is_none() {
        let pinned = app
            .state::<AppState>()
            .inner
            .lock()
            .map(|inner| inner.settings.pinned)
            .unwrap_or(false);
        if pinned {
            open_panel(app, false);
        }
    }
}

/// トレイのメニュー(姿勢の一行・站起来 / 坐下・看拉伸・ゲーム中)と説明を今の状態に合わせる。
/// 変わったときだけ、作ってある項目の文字と押せるかどうかを書き換える(メニューは作り直さない)
pub fn refresh_tray_menu(app: &AppHandle) {
    let state = app.state::<AppState>();
    let wanted = match state.inner.lock() {
        Ok(inner) => {
            let now = chrono::Utc::now();
            let status = match (&inner.quiet, inner.posture.game_since) {
                // 安静モードの説明は許される範囲(窓は作らない):長く遊んでいればその長さも
                (Some(name), Some(start)) if now - start >= chrono::Duration::minutes(90) => {
                    format!(
                        "游戏中 · 已 {}（{name}）",
                        yudh_core::standing::minutes_text((now - start).num_minutes())
                    )
                }
                _ => crate::commands::status_line(&inner, now),
            };
            (
                status,
                inner.posture.posture == yudh_core::posture::Posture::Standing,
                inner.quiet.clone(),
                inner.posture.resting,
            )
        }
        Err(_) => return,
    };
    let stale = state
        .tray_state
        .lock()
        .map(|current| current.as_ref() != Some(&wanted))
        .unwrap_or(false);
    if !stale {
        return;
    }
    let Some(tray) = app.tray_by_id("yudh") else {
        return;
    };
    let tip = match &wanted.2 {
        Some(name) => format!("Yudh · 游戏中，已暂停（{name}）"),
        None => format!("Yudh · {}", wanted.0),
    };
    let _ = tray.set_tooltip(Some(tip));
    let items = state.tray_items.lock();
    if let Ok(items) = &items {
        if let Some(items) = items.as_ref() {
            crate::update_tray_items(items, &wanted.0, wanted.1, wanted.2.as_deref(), wanted.3);
        }
    }
    drop(items);
    let current = state.tray_state.lock();
    if let Ok(mut current) = current {
        *current = Some(wanted);
    }
}

/// トレイから:開いていれば閉じる、閉じていれば開く。
/// アイコンを押した瞬間(ボタンを離す前)に面板はフォーカスを失って閉じるので、閉じた直後のクリックでは開き直さない
pub fn toggle_panel(app: &AppHandle) {
    let state = app.state::<AppState>();
    let just_closed = state
        .blur_closed
        .lock()
        .ok()
        .and_then(|t| *t)
        .is_some_and(|t| t.elapsed() < Duration::from_millis(500));
    if let Some(window) = app.get_webview_window("panel") {
        let pinned = state
            .inner
            .lock()
            .map(|inner| inner.settings.pinned)
            .unwrap_or(false);
        if !pinned {
            let _ = window.close();
            return;
        }
        // 常駐の帯は閉じない:広げていれば帯に戻し、帯なら広げる(押した瞬間に帯に戻ったばかりなら、そのまま)
        let expanded = state.panel_expanded.lock().map(|e| *e).unwrap_or(false);
        if expanded {
            collapse_panel(app);
        } else if !just_closed {
            let _ = window.set_focus();
            let _ = app.emit_to("panel", "panel-expand", ());
        }
        return;
    }
    if just_closed {
        return;
    }
    open_panel(app, true);
}

/// 面板を開く(開いていれば前に出す)。まず細い帯で、タスクバーを除いた範囲の右下(タスクバーが横や上にあっても重ならない)。
/// 覚えている位置は左下の角(帯でも全体でも下の辺が同じ所に来る)
/// focus = false:自動で出すとき(起動時・ゲームのあとの常駐の帯)。ゲームのランチャーなどからフォーカスを取らない
pub fn open_panel(app: &AppHandle, focus: bool) {
    if quiet(app) {
        return;
    }
    if let Some(window) = app.get_webview_window("panel") {
        if focus {
            let _ = window.set_focus();
        }
        return;
    }
    let saved = app
        .state::<AppState>()
        .inner
        .lock()
        .ok()
        .and_then(|inner| inner.settings.panel_anchor)
        .map(|[x, bottom]| [x, bottom - STRIP_SIZE.1]);
    let (x, y) = saved_position(app, saved, STRIP_SIZE.0).unwrap_or_else(|| {
        let (ax, ay, aw, ah) = area(app);
        (
            (ax + aw - STRIP_SIZE.0 - 4.0).max(ax),
            (ay + ah - STRIP_SIZE.1 - 4.0).max(ay),
        )
    });
    let built = builder(app, "panel", "index.html")
        .inner_size(STRIP_SIZE.0, STRIP_SIZE.1)
        .position(x, y)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .resizable(false)
        .skip_taskbar(true)
        .always_on_top(true)
        .focused(focus)
        .build();
    let Ok(window) = built else {
        return;
    };
    if let Ok(mut expanded) = app.state::<AppState>().panel_expanded.lock() {
        *expanded = false;
    }
    remember_position(&window, app, |s| &mut s.panel_anchor, true);
    let handle = app.clone();
    window.on_window_event(move |event| match event {
        WindowEvent::Focused(false) => {
            let state = handle.state::<AppState>();
            let (picking, pinned) = state
                .inner
                .lock()
                .map(|inner| (inner.picking, inner.settings.pinned))
                .unwrap_or((false, false));
            if picking {
                return;
            }
            // 常駐の帯:広げていたら帯に戻すだけ。帯のままなら何もしない
            if pinned {
                let expanded = state.panel_expanded.lock().map(|e| *e).unwrap_or(false);
                if expanded {
                    if let Ok(mut t) = state.blur_closed.lock() {
                        *t = Some(Instant::now());
                    }
                    collapse_panel(&handle);
                }
                return;
            }
            if let Some(panel) = handle.get_webview_window("panel") {
                if let Ok(mut t) = state.blur_closed.lock() {
                    *t = Some(Instant::now());
                }
                let _ = panel.close();
            }
        }
        WindowEvent::Destroyed => {
            // 英語(辞書ごと)を捨ててメモリを返す
            if let Ok(mut inner) = handle.state::<AppState>().inner.lock() {
                inner.english = None;
                inner.undo = None;
            }
        }
        _ => {}
    });
}

/// 面板を帯から全体に広げる(下の辺はそのまま、上へ伸ばす。画面の上を越えるなら下げる)。
/// この移動は覚えない(覚えた左下は帯を置いた所のまま。画面の低いノートで下げた分を次の帯の位置にしない)
pub fn expand_panel(app: &AppHandle) {
    let Some(window) = app.get_webview_window("panel") else {
        return;
    };
    let scale = window.scale_factor().unwrap_or(1.0);
    let (Ok(pos), Ok(size)) = (window.outer_position(), window.inner_size()) else {
        return;
    };
    let pos = pos.to_logical::<f64>(scale);
    let bottom = pos.y + f64::from(size.height) / scale;
    let (_, ay, _, _) = area(app);
    let y = (bottom - PANEL_SIZE.1).max(ay);
    let state = app.state::<AppState>();
    if let Ok(mut t) = state.programmatic_move.lock() {
        *t = Some(Instant::now());
    }
    if let Ok(mut expanded) = state.panel_expanded.lock() {
        *expanded = true;
    }
    let _ = window.set_size(LogicalSize::new(PANEL_SIZE.0, PANEL_SIZE.1));
    let _ = window.set_position(LogicalPosition::new(pos.x, y));
}

/// 面板を全体から帯に戻す(下の辺はそのまま)。画面側には知らせる(帯の中身に描き直す)
pub fn collapse_panel(app: &AppHandle) {
    let Some(window) = app.get_webview_window("panel") else {
        return;
    };
    let scale = window.scale_factor().unwrap_or(1.0);
    let (Ok(pos), Ok(size)) = (window.outer_position(), window.inner_size()) else {
        return;
    };
    let pos = pos.to_logical::<f64>(scale);
    let bottom = pos.y + f64::from(size.height) / scale;
    let state = app.state::<AppState>();
    if let Ok(mut t) = state.programmatic_move.lock() {
        *t = Some(Instant::now());
    }
    if let Ok(mut expanded) = state.panel_expanded.lock() {
        *expanded = false;
    }
    let _ = window.set_position(LogicalPosition::new(pos.x, bottom - STRIP_SIZE.1));
    let _ = window.set_size(LogicalSize::new(STRIP_SIZE.0, STRIP_SIZE.1));
    let _ = app.emit_to("panel", "panel-collapsed", ());
}

/// 坐站の小窓を、いまの状態に合わせて出す / 閉じる / 中身を更新する
pub fn sync_posture(app: &AppHandle) {
    if quiet(app) {
        if let Ok(mut inner) = app.state::<AppState>().inner.lock() {
            inner.preview = None;
        }
        if let Some(window) = app.get_webview_window("posture") {
            let _ = window.close();
        }
        return;
    }
    let wanted = app
        .state::<AppState>()
        .inner
        .lock()
        .map(|inner| inner.posture.prompt.is_some() || inner.preview.is_some())
        .unwrap_or(false);
    refresh_tray_menu(app);
    let existing = app.get_webview_window("posture");
    match (wanted, existing) {
        (true, Some(_)) => {
            let _ = app.emit_to("posture", "posture-changed", ());
        }
        (true, None) => {
            // 自分で動かした位置。無ければマウスのある画面の上部中央
            let saved = app
                .state::<AppState>()
                .inner
                .lock()
                .ok()
                .and_then(|inner| inner.settings.posture_pos);
            let (x, y) = saved_position(app, saved, POSTURE_SIZE.0).unwrap_or_else(|| {
                let (ax, ay, aw, _) = area(app);
                (ax + ((aw - POSTURE_SIZE.0) / 2.0).max(0.0), ay + 12.0)
            });
            let built = builder(app, "posture", "posture.html")
                .inner_size(POSTURE_SIZE.0, POSTURE_SIZE.1)
                .position(x, y)
                .decorations(false)
                .transparent(true)
                .shadow(false)
                .resizable(false)
                .skip_taskbar(true)
                .always_on_top(true)
                .focused(false)
                .build();
            if let Ok(window) = built {
                remember_position(&window, app, |s| &mut s.posture_pos, false);
                // 小窓がどう閉じても(Alt+F4 など)试做は終わり。残ると次の切り替えで试做が出てしまう
                let handle = app.clone();
                window.on_window_event(move |event| {
                    if let WindowEvent::Destroyed = event {
                        if let Ok(mut inner) = handle.state::<AppState>().inner.lock() {
                            inner.preview = None;
                        }
                    }
                });
            }
        }
        (false, Some(window)) => {
            let _ = window.close();
        }
        (false, None) => {}
    }
}

/// 日课の窓(ふつうの窓。動画のプレーヤーごと、閉じたら捨てる)
pub fn open_ritual(app: &AppHandle) {
    if quiet(app) {
        return;
    }
    if let Some(window) = app.get_webview_window("ritual") {
        let _ = window.set_focus();
        return;
    }
    let _ = builder(app, "ritual", "ritual.html")
        .title("泡完澡后的日课")
        .inner_size(1040.0, 680.0)
        .min_inner_size(880.0, 580.0)
        .center()
        .focused(true)
        .build();
}

/// 画面側から大きさを合わせる(坐站の小窓の高さ。幅は決まっているので位置はそのまま:自分で動かした位置も保つ)
pub fn fit(app: &AppHandle, label: &str, width: f64, height: f64) {
    if let Some(window) = app.get_webview_window(label) {
        let _ = window.set_size(LogicalSize::new(width, height));
    }
}
