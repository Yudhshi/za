//! Yudh for Windows:常駐はトレイだけ(30 秒ごとに坐站を計り、同期フォルダは開いたときに読む)。
//! 面板・坐站の小窓・日课の窓は、出すときに作り、閉じたら捨てる(ゲームの邪魔をしない・メモリを返す)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod platform;
mod settings;
mod surfaces;

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;

use chrono::{DateTime, Utc};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, RunEvent};
use yudh_core::posture::PostureClock;
use yudh_core::quiz::Rng;
use yudh_core::replay::Kind;
use yudh_core::{English, UndoPoint};

use settings::Settings;

/// アプリの状態(1 つの鍵で守る。鍵を持ったまま窓を作らない)
pub struct Inner {
    pub settings: Settings,
    /// 英語(面板を開いているあいだだけ持つ。閉じたら捨てる)
    pub english: Option<English>,
    /// いま答えた分の取り消し
    pub undo: Option<(UndoPoint, Kind)>,
    pub posture: PostureClock,
    /// 立ってすぐの腹式呼吸を始めた時刻
    pub breath_started: Option<DateTime<Utc>>,
    pub rng: Rng,
    /// フォルダを選ぶダイアログのあいだは、面板がフォーカスを失っても閉じない
    pub picking: bool,
}

pub struct AppState {
    pub inner: Mutex<Inner>,
    pub settings_path: PathBuf,
}

impl AppState {
    pub fn save(&self, inner: &Inner) {
        let _ = inner.settings.save(&self.settings_path);
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let dir = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| std::env::temp_dir().join("Yudh"));
            let settings_path = dir.join("settings.json");
            let settings = Settings::load(&settings_path);
            let posture = PostureClock::new(Utc::now(), settings.stretch_index);
            app.manage(AppState {
                inner: Mutex::new(Inner {
                    settings,
                    english: None,
                    undo: None,
                    posture,
                    breath_started: None,
                    rng: Rng::from_time(),
                    picking: false,
                }),
                settings_path,
            });
            build_tray(app.handle())?;
            let handle = app.handle().clone();
            std::thread::spawn(move || ticker(handle));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::panel_state,
            commands::english_card,
            commands::english_rate,
            commands::english_known,
            commands::english_undo,
            commands::english_more,
            commands::posture_state,
            commands::posture_action,
            commands::ritual_plan,
            commands::ritual_done,
            commands::settings_get,
            commands::settings_save,
            commands::pick_folder,
            commands::open_surface,
        ])
        .build(tauri::generate_context!())
        .expect("Yudh を起動できない")
        .run(|_app, event| {
            // 窓を全部閉じても常駐する(終わるのはトレイの「退出」だけ)
            if let RunEvent::ExitRequested {
                code: None, api, ..
            } = event
            {
                api.prevent_exit();
            }
        });
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let menu = Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "panel", "打开面板", true, None::<&str>)?,
            &MenuItem::with_id(app, "ritual", "泡完澡了（日课）", true, None::<&str>)?,
            &MenuItem::with_id(app, "posture", "站起来了吗？", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "quit", "退出 Yudh", true, None::<&str>)?,
        ],
    )?;
    let mut tray = TrayIconBuilder::with_id("yudh")
        .tooltip("Yudh")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "panel" => surfaces::toggle_panel(app),
            "ritual" => surfaces::open_ritual(app),
            "posture" => {
                commands::apply_posture(app, "open");
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                surfaces::toggle_panel(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.build(app)?;
    Ok(())
}

/// 30 秒ごと:坐站の判定(全画面のゲーム中は出さない・長く遊んだら抜けたときに尋ねる)
fn ticker(app: AppHandle) {
    loop {
        let changed = {
            let state = app.state::<AppState>();
            let mut inner = state.inner.lock().expect("state");
            let settings = inner.settings.posture.clone();
            let busy = platform::fullscreen_busy();
            let idle = platform::idle_seconds();
            let changed = inner.posture.check(Utc::now(), &settings, idle, busy);
            if changed && inner.posture.prompt.is_none() {
                inner.breath_started = None;
            }
            changed
        };
        if changed {
            surfaces::sync_posture(&app);
        }
        std::thread::sleep(Duration::from_secs(30));
    }
}
