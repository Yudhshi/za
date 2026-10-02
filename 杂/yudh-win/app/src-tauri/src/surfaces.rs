//! 窓の出し入れ:面板(タスクバーのそば、フォーカスを失ったら閉じる)・坐站の小窓(画面上部の中央、フォーカスを奪わない)・
//! 日课の窓(ふつうの窓)。どれも閉じたら捨てる。位置はマウスのある画面の、タスクバーを除いた範囲で決める。
//! 名単のゲームが動いているあいだは、どの窓も作らない(反作弊に「ゲームの上に被さる窓」と見られないように)

use tauri::{
    AppHandle, Emitter, LogicalSize, Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};

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
    let (ax, ay, aw, ah) = area(app);
    let x = (ax + aw - PANEL_SIZE.0 - 4.0).max(ax);
    let y = (ay + ah - PANEL_SIZE.1 - 4.0).max(ay);
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
            // マウスのある画面の上部中央
            let (ax, ay, aw, _) = area(app);
            let _ =
                WebviewWindowBuilder::new(app, "posture", WebviewUrl::App("posture.html".into()))
                    .title("Yudh")
                    .inner_size(POSTURE_SIZE.0, POSTURE_SIZE.1)
                    .position(ax + ((aw - POSTURE_SIZE.0) / 2.0).max(0.0), ay + 12.0)
                    .decorations(false)
                    .transparent(true)
                    .shadow(false)
                    .resizable(false)
                    .skip_taskbar(true)
                    .always_on_top(true)
                    .focused(false)
                    .build();
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
