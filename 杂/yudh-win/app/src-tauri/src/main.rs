//! Yudh for Windows:常駐はトレイだけ(常駐の帯を選べばその帯も)。30 秒ごとに坐站の钟を進める。
//! 同期フォルダは開いたときに読む(日课を終えたかだけは 5 分に 1 回 habits を読む)。
//! 面板・坐站の小窓・日课の窓は、出すときに作り、閉じたら捨てる(ゲームの邪魔をしない・メモリを返す)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod platform;
mod settings;
mod surfaces;

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use chrono::{DateTime, Timelike, Utc};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, RunEvent};
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
    /// 名単のゲーム(AION2 など)が動いている:Yudh は一言の帯のほかは窓を作らず、OS への問い合わせも止める
    pub quiet: Option<String>,
    /// 設定の拉伸库の「试做」:この拉伸を小窓で流している(钟は触らない)
    pub preview: Option<Preview>,
    /// 今日の日课を終えたか(Mac の分も足して。日付・値・読んだ時刻)。钟を止める判定に使う
    pub ritual_today: Option<(String, bool, Instant)>,
}

/// トレイに出している状態:状態の一行・立っているか・ゲーム中(名前)・休み中か
pub type TrayState = (String, bool, Option<String>, bool);

/// トレイのメニューの項目(作るのは 1 度だけ。文字と押せるかどうかをその場で変える:
/// メニューを作り直すと、開いているメニューが消える)
pub struct TrayItems {
    pub status: MenuItem<tauri::Wry>,
    pub flip: MenuItem<tauri::Wry>,
    pub guide: MenuItem<tauri::Wry>,
    pub ritual: MenuItem<tauri::Wry>,
    pub panel: MenuItem<tauri::Wry>,
}

pub struct Preview {
    pub stretch: yudh_core::posture::Stretch,
    pub step: usize,
    pub started: DateTime<Utc>,
}

pub struct AppState {
    pub inner: Mutex<Inner>,
    pub settings_path: PathBuf,
    /// 面板がフォーカスを失って閉じた時刻:トレイのアイコンを押して閉じたときに、ボタンを離した知らせでまた開かないように
    pub blur_closed: Mutex<Option<Instant>>,
    /// いまトレイのメニューに出している状態(状態の一行・立っているか・ゲーム中か・休み中か)。変わったときだけ書き換える
    pub tray_state: Mutex<Option<TrayState>>,
    pub tray_items: Mutex<Option<TrayItems>>,
    /// 面板が帯から全体に広がっている
    pub panel_expanded: Mutex<bool>,
    /// こちらで面板を動かした時刻(帯を広げたとき):その移動はユーザーの位置として覚えない
    pub programmatic_move: Mutex<Option<Instant>>,
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
            surfaces::open_panel(app, true);
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
            let mut posture = PostureClock::new(Utc::now(), settings.stretch_index);
            // 胶带:前に動いていたときの最後の印(立ち・離席・ゲーム)を、起動した時刻の座りで閉じる
            posture.start(Utc::now());
            let inner = Inner {
                settings,
                english: None,
                undo: None,
                posture,
                breath_started: None,
                rng: Rng::from_time(),
                picking: false,
                quiet: None,
                preview: None,
                ritual_today: None,
            };
            // 手元の記録を同期フォルダへ(Mac から日课や呼吸の続きが見えるように)
            commands::publish_habits(&inner);
            app.manage(AppState {
                inner: Mutex::new(inner),
                settings_path,
                blur_closed: Mutex::new(None),
                tray_state: Mutex::new(None),
                tray_items: Mutex::new(None),
                panel_expanded: Mutex::new(false),
                programmatic_move: Mutex::new(None),
            });
            apply_autostart(app.handle());
            build_tray(app.handle())?;
            let handle = app.handle().clone();
            std::thread::spawn(move || ticker(handle));
            // 帯を常駐させる設定なら、起動した時点で出す
            let pinned = app
                .state::<AppState>()
                .inner
                .lock()
                .map(|inner| inner.settings.pinned)
                .unwrap_or(false);
            if pinned {
                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    surfaces::open_panel(&handle, false);
                });
            }
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
            commands::posture_summary,
            commands::posture_action,
            commands::posture_preview,
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

/// トレイのメニュー。1 行目は姿勢という「もの」そのもの(帯・小窓と同じ一行)、その下にそれへの操作:
/// 「站起来」/「坐下」(札を返す)と「看拉伸」(立っているときだけ押せる)。項目は作るのは 1 度だけで、
/// あとは `update_tray_items` が文字と押せるかどうかを書き換える
pub fn tray_menu(app: &AppHandle) -> tauri::Result<(tauri::menu::Menu<tauri::Wry>, TrayItems)> {
    let items = TrayItems {
        status: MenuItem::with_id(app, "status", "Yudh", false, None::<&str>)?,
        flip: MenuItem::with_id(app, "flip", "站起来", true, None::<&str>)?,
        guide: MenuItem::with_id(app, "posture", "看拉伸", false, None::<&str>)?,
        ritual: MenuItem::with_id(app, "ritual", "泡完澡了", true, None::<&str>)?,
        panel: MenuItem::with_id(app, "panel", "打开面板", true, None::<&str>)?,
    };
    let menu = Menu::with_items(
        app,
        &[
            &items.status,
            &items.flip,
            &items.guide,
            &PredefinedMenuItem::separator(app)?,
            &items.ritual,
            &items.panel,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "quit", "退出 Yudh", true, None::<&str>)?,
        ],
    )?;
    Ok((menu, items))
}

/// トレイの項目を今の状態に(一行・站起来 / 坐下・看拉伸・ゲーム中・休み中)。
/// 名単のゲーム中も钟は進むので、札(站起来 / 坐下)は返せる(窓は作らない)。窓を開く項目だけ止める
pub fn update_tray_items(
    items: &TrayItems,
    status: &str,
    standing: bool,
    game: Option<&str>,
    resting: bool,
) {
    let on = game.is_none();
    let status = match game {
        Some(_) => format!("游戏中 · {status}"),
        None => status.to_string(),
    };
    let _ = items.status.set_text(status);
    let _ = items
        .flip
        .set_text(if standing { "坐下" } else { "站起来" });
    let _ = items.flip.set_enabled(!resting);
    let _ = items.guide.set_enabled(on && standing && !resting);
    let _ = items.ritual.set_enabled(on);
    let _ = items.panel.set_enabled(on);
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let status = app
        .state::<AppState>()
        .inner
        .lock()
        .map(|inner| commands::status_line(&inner, Utc::now()))
        .unwrap_or_default();
    let (menu, items) = tray_menu(app)?;
    update_tray_items(&items, &status, false, None, false);
    if let Ok(mut state) = app.state::<AppState>().tray_state.lock() {
        *state = Some((status, false, None, false));
    }
    if let Ok(mut slot) = app.state::<AppState>().tray_items.lock() {
        *slot = Some(items);
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
            "flip" => {
                commands::apply_posture(app, "flip");
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

/// 30 秒ごと:坐站の钟を進める。全画面のゲーム中も钟は進み、切り替えは一言の細い帯で言う(手順の小窓は出さない)。
/// 名単のゲーム(AION2 など)が動いているあいだは開いている窓を閉じ、その帯のほかは窓を作らず、
/// 無操作・全画面も問い合わせない(ゲーム中として钟を進める)
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
            // 夜(設定の時間)と、今日の日课を終えたあとは钟を止める
            let hour = now.with_timezone(&chrono::Local).hour();
            // 今日の日课(Mac でやった分も)を終えていれば、今日はもう止める
            let ritual_done = commands::ritual_done_today(&mut inner);
            let resting = settings.is_quiet_hour(hour) || ritual_done;
            let changed = if game.is_some() {
                inner.posture.check(now, &settings, 0, true, resting)
            } else {
                let busy = platform::fullscreen_busy();
                let idle = platform::idle_seconds();
                inner.posture.check(now, &settings, idle, busy, resting)
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
        if changed {
            surfaces::sync_posture(&app);
        }
        // トレイの一行(已坐 N 分钟 …)は毎分変わる。帯が出ていればそちらも
        surfaces::refresh_tray_menu(&app);
        let _ = app.emit_to("panel", "panel-tick", ());
        std::thread::sleep(Duration::from_secs(30));
    }
}
