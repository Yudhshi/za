//! 窓の出し入れ:面板(タスクバーのそば、フォーカスを失ったら閉じる)・坐站の小窓(画面上部の中央、フォーカスを奪わない)・
//! 日课の窓(ふつうの窓)。どれも閉じたら捨てる。位置はマウスのある画面の、タスクバーを除いた範囲で決める。
//! 名単のゲームが動いているあいだは、どの窓も作らない(反作弊に「ゲームの上に被さる窓」と見られないように)

use std::time::{Duration, Instant};

use tauri::{
    AppHandle, Emitter, LogicalSize, Manager, WebviewUrl, WebviewWindow, WebviewWindowBuilder,
    WindowEvent,
};

use crate::settings::Settings;
use crate::AppState;

/// 面板の大きさ(Mac と同じ 520 幅 + 焼いた枠のはみ出し)
const PANEL_SIZE: (f64, f64) = (560.0, 760.0);
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

/// 動かした位置を覚え、閉じたら設定に書く。作った直後にこちらで置いた分は数えない
fn remember_position(
    window: &WebviewWindow,
    app: &AppHandle,
    slot: fn(&mut Settings) -> &mut Option<[f64; 2]>,
) {
    let created = Instant::now();
    let handle = app.clone();
    let this = window.clone();
    window.on_window_event(move |event| match event {
        WindowEvent::Moved(pos) if created.elapsed() > Duration::from_millis(800) => {
            let scale = this.scale_factor().unwrap_or(1.0);
            let logical = pos.to_logical::<f64>(scale);
            if let Ok(mut inner) = handle.state::<AppState>().inner.lock() {
                *slot(&mut inner.settings) = Some([logical.x, logical.y]);
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

/// 名単のゲームが動いているか(動いていれば窓を作らない)
fn quiet(app: &AppHandle) -> bool {
    app.state::<AppState>()
        .inner
        .lock()
        .map(|inner| inner.quiet.is_some())
        .unwrap_or(false)
}

/// ゲームが始まった / 終わった:始まったら開いている窓を全部閉じる。トレイの説明を変える
pub fn quiet_changed(app: &AppHandle, game: Option<&str>) {
    if game.is_some() {
        for label in ["panel", "posture", "ritual"] {
            if let Some(window) = app.get_webview_window(label) {
                let _ = window.close();
            }
        }
    }
    if let Some(tray) = app.tray_by_id("yudh") {
        let tip = match game {
            Some(name) => format!("Yudh · 游戏中，已暂停（{name}）"),
            None => "Yudh".to_string(),
        };
        let _ = tray.set_tooltip(Some(tip));
    }
}

/// トレイから:開いていれば閉じる、閉じていれば開く
pub fn toggle_panel(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("panel") {
        let _ = window.close();
        return;
    }
    open_panel(app);
}

/// 面板を開く(開いていれば前に出す)。タスクバーを除いた範囲の右下(タスクバーが横や上にあっても重ならない)
pub fn open_panel(app: &AppHandle) {
    if quiet(app) {
        return;
    }
    if let Some(window) = app.get_webview_window("panel") {
        let _ = window.set_focus();
        return;
    }
    let saved = app
        .state::<AppState>()
        .inner
        .lock()
        .ok()
        .and_then(|inner| inner.settings.panel_pos);
    let (x, y) = saved_position(app, saved, PANEL_SIZE.0).unwrap_or_else(|| {
        let (ax, ay, aw, ah) = area(app);
        (
            (ax + aw - PANEL_SIZE.0 - 4.0).max(ax),
            (ay + ah - PANEL_SIZE.1 - 4.0).max(ay),
        )
    });
    let built = WebviewWindowBuilder::new(app, "panel", WebviewUrl::App("index.html".into()))
        .title("Yudh")
        .inner_size(PANEL_SIZE.0, PANEL_SIZE.1)
        .position(x, y)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .resizable(false)
        .skip_taskbar(true)
        .always_on_top(true)
        .focused(true)
        .build();
    let Ok(window) = built else {
        return;
    };
    remember_position(&window, app, |s| &mut s.panel_pos);
    let handle = app.clone();
    window.on_window_event(move |event| match event {
        WindowEvent::Focused(false) => {
            let picking = handle
                .state::<AppState>()
                .inner
                .lock()
                .map(|inner| inner.picking)
                .unwrap_or(false);
            if !picking {
                if let Some(panel) = handle.get_webview_window("panel") {
                    let _ = panel.close();
                }
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

/// 坐站の小窓を、いまの状態に合わせて出す / 閉じる / 中身を更新する
pub fn sync_posture(app: &AppHandle) {
    if quiet(app) {
        if let Some(window) = app.get_webview_window("posture") {
            let _ = window.close();
        }
        return;
    }
    let wanted = app
        .state::<AppState>()
        .inner
        .lock()
        .map(|inner| inner.posture.prompt.is_some())
        .unwrap_or(false);
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
            let built =
                WebviewWindowBuilder::new(app, "posture", WebviewUrl::App("posture.html".into()))
                    .title("Yudh")
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
                remember_position(&window, app, |s| &mut s.posture_pos);
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
    let _ = WebviewWindowBuilder::new(app, "ritual", WebviewUrl::App("ritual.html".into()))
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
