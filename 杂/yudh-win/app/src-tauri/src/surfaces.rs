//! 窓の出し入れ:面板(トレイの上、フォーカスを失ったら閉じる)・坐站の小窓(画面上部の中央、フォーカスを奪わない)・
//! 日课の窓(ふつうの窓)。どれも閉じたら捨てる

use tauri::{
    AppHandle, Emitter, LogicalPosition, LogicalSize, Manager, WebviewUrl, WebviewWindowBuilder,
    WindowEvent,
};

use crate::AppState;

/// 面板の大きさ(Mac と同じ 520 幅 + 焼いた枠のはみ出し)
const PANEL_SIZE: (f64, f64) = (560.0, 760.0);
/// 坐站の小窓(牛皮纸 360 + はみ出し。高さは中身に合わせて画面側が変える)
const POSTURE_SIZE: (f64, f64) = (400.0, 520.0);

/// 主画面の論理サイズ(取れなければ 1920×1080)
fn screen(app: &AppHandle) -> (f64, f64) {
    app.primary_monitor()
        .ok()
        .flatten()
        .map(|m| {
            let scale = m.scale_factor();
            let size = m.size();
            (
                f64::from(size.width) / scale,
                f64::from(size.height) / scale,
            )
        })
        .unwrap_or((1920.0, 1080.0))
}

pub fn toggle_panel(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("panel") {
        let _ = window.close();
        return;
    }
    let (w, h) = screen(app);
    // タスクバー(下 48)の上、右端に寄せる
    let x = (w - PANEL_SIZE.0 - 8.0).max(0.0);
    let y = (h - PANEL_SIZE.1 - 56.0).max(0.0);
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
            let (w, _) = screen(app);
            let _ =
                WebviewWindowBuilder::new(app, "posture", WebviewUrl::App("posture.html".into()))
                    .title("Yudh")
                    .inner_size(POSTURE_SIZE.0, POSTURE_SIZE.1)
                    .position(((w - POSTURE_SIZE.0) / 2.0).max(0.0), 16.0)
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

/// 画面側から大きさを合わせる(坐站の小窓の高さ)
pub fn fit(app: &AppHandle, label: &str, width: f64, height: f64) {
    if let Some(window) = app.get_webview_window(label) {
        let _ = window.set_size(LogicalSize::new(width, height));
        if label == "posture" {
            let (w, _) = screen(app);
            let _ = window.set_position(LogicalPosition::new(((w - width) / 2.0).max(0.0), 16.0));
        }
    }
}
