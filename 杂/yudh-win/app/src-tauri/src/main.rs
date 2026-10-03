//! Yudh for Windows:常駐はトレイだけ(30 秒ごとに坐站の钟を進め、同期フォルダは開いたときに読む)。
//! 面板・坐站の小窓・日课の窓は、出すときに作り、閉じたら捨てる(ゲームの邪魔をしない・メモリを返す)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod platform;
mod settings;
mod surfaces;

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

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
    /// 名単のゲーム(AION2 など)が動いている:Yudh は窓を一切作らず、OS への問い合わせも止める
    pub quiet: Option<String>,
}

pub struct AppState {
    pub inner: Mutex<Inner>,
    pub settings_path: PathBuf,
    /// 面板がフォーカスを失って閉じた時刻:トレイのアイコンを押して閉じたときに、ボタンを離した知らせでまた開かないように
    pub blur_closed: Mutex<Option<Instant>>,
    /// いまトレイのメニューに出している状態(立っているか、ゲーム中か)。変わったときだけ作り直す
    pub tray_state: Mutex<Option<(bool, Option<String>)>>,
}

impl AppState {
    pub fn save(&self, inner: &Inner) {
        let _ = inner.settings.save(&self.settings_path);
    }
}

fn main() {
    tauri::Builder::default()
        // 2 回目に起動されたら、新しく立ち上げずに面板を開く(トレイが 2 つにならないように)
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            surfaces::open_panel(app);
        }))
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let dir = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| std::env::temp_dir().join("Yudh"));
            let settings_path = dir.join("settings.json");
            let settings = Settings::load(&settings_path);
            let posture = PostureClock::new(Utc::now(), settings.stretch_index);
            let inner = Inner {
                settings,
                english: None,
                undo: None,
                posture,
                breath_started: None,
                rng: Rng::from_time(),
                picking: false,
                quiet: None,
            };
            // 手元の記録を同期フォルダへ(Mac から日课や呼吸の続きが見えるように)
            commands::publish_habits(&inner);
            app.manage(AppState {
                inner: Mutex::new(inner),
                settings_path,
                blur_closed: Mutex::new(None),
                tray_state: Mutex::new(None),
            });
            apply_autostart(app.handle());
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
            commands::english_spell,
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
            commands::open_url,
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

/// 設定どおりにログイン時の自動起動を入れる / 外す(既定は入れる)
pub fn apply_autostart(app: &AppHandle) {
    use tauri_plugin_autostart::ManagerExt;
    let wanted = app
        .state::<AppState>()
        .inner
        .lock()
        .map(|inner| inner.settings.autostart)
        .unwrap_or(true);
    let launcher = app.autolaunch();
    let enabled = launcher.is_enabled().unwrap_or(false);
    if wanted && !enabled {
        let _ = launcher.enable();
    } else if !wanted && enabled {
        let _ = launcher.disable();
    }
}

/// トレイのメニュー。钟は自分で切り替えるので、ここにあるのは先回りだけ:座っていれば「现在站起来」、
/// 立っていれば「看拉伸」と「坐下了」。ゲーム中はどれも押せない
pub fn tray_menu(
    app: &AppHandle,
    standing: bool,
    game: Option<&str>,
) -> tauri::Result<tauri::menu::Menu<tauri::Wry>> {
    let on = game.is_none();
    let panel_label = match game {
        Some(name) => format!("游戏中，已暂停（{name}）"),
        None => "打开面板".to_string(),
    };
    let menu = Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "panel", panel_label, on, None::<&str>)?,
            &MenuItem::with_id(app, "ritual", "泡完澡了", on, None::<&str>)?,
            &MenuItem::with_id(
                app,
                "posture",
                if standing {
                    "看拉伸"
                } else {
                    "现在站起来"
                },
                on,
                None::<&str>,
            )?,
        ],
    )?;
    if standing {
        menu.append(&MenuItem::with_id(app, "sat", "坐下了", on, None::<&str>)?)?;
    }
    menu.append(&PredefinedMenuItem::separator(app)?)?;
    menu.append(&MenuItem::with_id(
        app,
        "quit",
        "退出 Yudh",
        true,
        None::<&str>,
    )?)?;
    Ok(menu)
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let menu = tray_menu(app, false, None)?;
    if let Ok(mut state) = app.state::<AppState>().tray_state.lock() {
        *state = Some((false, None));
    }
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
            "sat" => {
                commands::apply_posture(app, "sat");
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
    // 通知領域の大きさ(96 DPI で 16px、150% で 24px)の段を .ico から取る。既定の窓のアイコンは 32px の段で、
    // それをシステムが縮めると、小さい段のために簡略化した絵(星なし・実線の枠)が使われない
    if let Some(icon) = tray_icon().or_else(|| app.default_window_icon().cloned()) {
        tray = tray.icon(icon);
    }
    tray.build(app)?;
    Ok(())
}

#[cfg(windows)]
fn tray_icon() -> Option<tauri::image::Image<'static>> {
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSMICON, SM_CYSMICON};
    // SAFETY: 引数は定数。失敗すると 0 が返る
    let metric = |index| match unsafe { GetSystemMetrics(index) } {
        n if n > 0 => n as u32,
        _ => 16,
    };
    // 32512 = Tauri がアプリのアイコン(.ico)を埋め込む資源の番号
    tauri::image::Image::from_icon_resource(32512u16, metric(SM_CXSMICON), metric(SM_CYSMICON)).ok()
}

#[cfg(not(windows))]
fn tray_icon() -> Option<tauri::image::Image<'static>> {
    None
}

/// 30 秒ごと:坐站の判定(全画面のゲーム中は出さない・長く遊んだら抜けたときに尋ねる)。
/// 名単のゲーム(AION2 など)が動いているあいだは「完全に安静」:開いている窓を閉じ、窓を作らず、
/// 無操作・全画面も問い合わせない(ゲーム中として計時だけ続け、抜けたら長いゲームの規則で尋ねる)
fn ticker(app: AppHandle) {
    let mut last_tick = Utc::now();
    loop {
        let list = app
            .state::<AppState>()
            .inner
            .lock()
            .map(|inner| inner.settings.quiet_apps.clone())
            .unwrap_or_default();
        let game = yudh_core::quiet::running_quiet_app(&platform::running_process_names(), &list);
        let (changed, entered, left) = {
            let state = app.state::<AppState>();
            let mut inner = state.inner.lock().expect("state");
            let entered = game.is_some() && inner.quiet.is_none();
            let left = game.is_none() && inner.quiet.is_some();
            inner.quiet = game.clone();
            let settings = inner.settings.posture.clone();
            // スリープから覚めた(2 分以上 tick が止まっていた):眠っていた時間を座っていた時間に数えない
            let now = Utc::now();
            let woke = now - last_tick > chrono::Duration::minutes(2);
            let last_seen = last_tick;
            last_tick = now;
            if woke {
                inner.posture.wake(now, last_seen);
                inner.breath_started = None;
            }
            let changed = if game.is_some() {
                inner.posture.check(now, &settings, 0, true)
            } else {
                let busy = platform::fullscreen_busy();
                let idle = platform::idle_seconds();
                inner.posture.check(now, &settings, idle, busy)
            };
            // 钟が切り替えた分を記録(今日の立った時間・回数、立ってすぐの呼吸)
            if commands::settle(&mut inner, now) {
                state.save(&inner);
            }
            if changed && inner.posture.prompt.is_none() {
                inner.breath_started = None;
            }
            (changed || woke, entered, left)
        };
        if entered || left {
            surfaces::quiet_changed(&app, game.as_deref());
        }
        if changed && game.is_none() {
            surfaces::sync_posture(&app);
        }
        std::thread::sleep(Duration::from_secs(30));
    }
}
