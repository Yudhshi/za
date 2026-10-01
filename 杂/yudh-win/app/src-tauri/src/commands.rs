//! 画面(HTML)から呼ぶ命令。返すものは JSON(camelCase)。鍵は短く持ち、窓を動かす前に放す

use std::collections::HashMap;
use std::path::Path;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};
use yudh_core::agenda::{self, Tomorrow};
use yudh_core::english::{Stats, VocabCard};
use yudh_core::posture::{self, Posture, Prompt, Step, Stretch};
use yudh_core::quiz::Question;
use yudh_core::replay::Kind;
use yudh_core::ritual;
use yudh_core::round::RoundMark;
use yudh_core::srs::Rating;
use yudh_core::{English, Zone};

use crate::settings::SettingsPatch;
use crate::{surfaces, AppState, Inner};

fn today() -> String {
    Zone::Local.key(Utc::now())
}

/// 英語を開く(同期フォルダが無ければ None)
fn english(inner: &mut Inner) -> Option<&mut English> {
    if inner.english.is_none() {
        let root = inner.settings.sync_root.clone()?;
        inner.english = Some(English::open(
            Path::new(&root),
            &inner.settings.device,
            Zone::Local,
        ));
    }
    inner.english.as_mut()
}

fn kind(text: &str) -> Result<Kind, String> {
    Kind::parse(text).ok_or_else(|| format!("unknown kind {text}"))
}

// MARK: 面板

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelState {
    configured: bool,
    sync_root: Option<String>,
    has_library: bool,
    stats: Option<Stats>,
    tomorrow: Tomorrow,
    posture: Posture,
    minutes_in_posture: i64,
    prompt: Option<Prompt>,
    breath_today: u32,
    ritual_streak: usize,
}

#[tauri::command]
pub fn panel_state(state: State<'_, AppState>) -> PanelState {
    let mut inner = state.inner.lock().expect("state");
    let now = Utc::now();
    let root = inner.settings.sync_root.clone();
    let tomorrow = root.as_deref().map_or(Tomorrow::NoFile, |r| {
        agenda::tomorrow(Path::new(r), now, Zone::Local)
    });
    let (stats, has_library) = match english(&mut inner) {
        Some(e) => {
            let _ = e.reload();
            (Some(e.stats(now, true)), !e.library.is_empty())
        }
        None => (None, false),
    };
    PanelState {
        configured: root.is_some(),
        sync_root: root,
        has_library,
        stats,
        tomorrow,
        posture: inner.posture.posture,
        minutes_in_posture: (now - inner.posture.since).num_minutes(),
        prompt: inner.posture.prompt,
        breath_today: inner
            .settings
            .breath_log
            .get(&today())
            .copied()
            .unwrap_or(0),
        ritual_streak: ritual::streak(&inner.settings.ritual_log, now, Zone::Local),
    }
}

// MARK: 英語

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardView {
    kind: Kind,
    id: String,
    is_new: bool,
    vocab: Option<VocabCard>,
    question: Option<Question>,
    history: Vec<RoundMark>,
}

/// 次の 1 問(今日の分が終わっていれば None)
#[tauri::command]
pub fn english_card(state: State<'_, AppState>, kind: String) -> Result<Option<CardView>, String> {
    let kind = self::kind(&kind)?;
    let mut inner = state.inner.lock().expect("state");
    let mut rng = inner.rng.clone();
    let Some(e) = english(&mut inner) else {
        return Ok(None);
    };
    let Some((id, is_new)) = e.next(kind, Utc::now()) else {
        return Ok(None);
    };
    let view = CardView {
        kind,
        history: e.history(&id, false, 5),
        vocab: (kind == Kind::Vocab)
            .then(|| e.vocab_card(&id, is_new))
            .flatten(),
        question: (kind == Kind::Para)
            .then(|| e.para_question(&id, &mut rng))
            .flatten(),
        id,
        is_new,
    };
    inner.rng = rng;
    Ok(Some(view))
}

#[tauri::command]
pub fn english_rate(
    state: State<'_, AppState>,
    id: String,
    kind: String,
    rating: Rating,
) -> Result<Stats, String> {
    let kind = self::kind(&kind)?;
    let mut inner = state.inner.lock().expect("state");
    let now = Utc::now();
    let e = english(&mut inner).ok_or("no sync folder")?;
    let point = e
        .rate(&id, kind, rating, now)
        .map_err(|err| err.to_string())?;
    let stats = e.stats(now, true);
    inner.undo = Some((point, kind));
    Ok(stats)
}

/// 「已经会了」:もう出さない
#[tauri::command]
pub fn english_known(state: State<'_, AppState>, id: String) -> Result<Stats, String> {
    let mut inner = state.inner.lock().expect("state");
    let now = Utc::now();
    let e = english(&mut inner).ok_or("no sync folder")?;
    let point = e
        .known(&id, Kind::Vocab, now)
        .map_err(|err| err.to_string())?;
    let stats = e.stats(now, true);
    inner.undo = Some((point, Kind::Vocab));
    Ok(stats)
}

/// いま答えたことを取り消す。取り消したカードの種類を返す(その種類の 1 問目にまた出る)
#[tauri::command]
pub fn english_undo(state: State<'_, AppState>) -> Result<Option<Kind>, String> {
    let mut inner = state.inner.lock().expect("state");
    let Some((point, kind)) = inner.undo.take() else {
        return Ok(None);
    };
    let e = english(&mut inner).ok_or("no sync folder")?;
    e.undo(&point, Utc::now()).map_err(|err| err.to_string())?;
    Ok(Some(kind))
}

/// 今日の分のあと、新しいものをもう 10 問
#[tauri::command]
pub fn english_more(state: State<'_, AppState>, kind: String) -> Result<(), String> {
    let kind = self::kind(&kind)?;
    let mut inner = state.inner.lock().expect("state");
    let e = english(&mut inner).ok_or("no sync folder")?;
    e.add_more_new(kind, Utc::now());
    Ok(())
}

// MARK: 坐站

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PostureView {
    prompt: Option<Prompt>,
    posture: Posture,
    /// 切り替えの時刻(UNIX ミリ秒)
    due_at: i64,
    stretch: Stretch,
    steps: Vec<Step>,
    step: usize,
    heading: String,
    frieze: bool,
    /// 立ってすぐの腹式呼吸を始めた時刻(UNIX ミリ秒)
    breath_started_at: Option<i64>,
    breath_today: u32,
    next_stretch: String,
    caution: &'static str,
}

fn posture_view(inner: &Inner) -> PostureView {
    let clock = &inner.posture;
    let steps = posture::steps(&clock.stretch);
    let step = clock.step.min(steps.len());
    PostureView {
        prompt: clock.prompt,
        posture: clock.posture,
        due_at: clock.due_at(&inner.settings.posture).timestamp_millis(),
        heading: posture::heading(&clock.stretch, &steps, step),
        frieze: posture::shows_frieze(&steps),
        stretch: clock.stretch.clone(),
        steps,
        step,
        breath_started_at: inner.breath_started.map(|t| t.timestamp_millis()),
        breath_today: inner
            .settings
            .breath_log
            .get(&today())
            .copied()
            .unwrap_or(0),
        next_stretch: posture::display_name(&clock.next_stretch(&inner.settings.posture).name),
        caution: posture::CAUTION,
    }
}

#[tauri::command]
pub fn posture_state(state: State<'_, AppState>) -> PostureView {
    posture_view(&state.inner.lock().expect("state"))
}

/// 坐站の操作(トレイからも呼ぶ)。小窓の出し入れまでする
pub fn apply_posture(app: &AppHandle, action: &str) -> PostureView {
    let view = {
        let state = app.state::<AppState>();
        let mut inner = state.inner.lock().expect("state");
        let now = Utc::now();
        let settings = inner.settings.posture.clone();
        match action {
            "stood" => {
                inner.posture.confirm_stood(now, &settings);
                inner.settings.stretch_index = inner.posture.stretch_index;
                // 立ったらまず腹式呼吸を 3 回(习惯にする。拉伸はそのあと)
                inner.breath_started = inner.settings.breath_habit.then_some(now);
                state.save(&inner);
            }
            "sat" => {
                inner.posture.confirm_sat(now);
                inner.breath_started = None;
            }
            "snooze15" => {
                inner.posture.snooze(now, 15);
                inner.breath_started = None;
            }
            "snooze5" => {
                inner.posture.snooze(now, 5);
                inner.breath_started = None;
            }
            "close" => {
                inner.posture.close_prompt();
                inner.breath_started = None;
            }
            "open" => inner.posture.open_prompt(&settings),
            "next" => inner.posture.move_step(1),
            "prev" => inner.posture.move_step(-1),
            "breathDone" => {
                if inner.breath_started.take().is_some() {
                    ritual::record(&mut inner.settings.breath_log, &today());
                    state.save(&inner);
                }
            }
            "breathSkip" => inner.breath_started = None,
            _ => {}
        }
        posture_view(&inner)
    };
    surfaces::sync_posture(app);
    view
}

/// 窓を作ることがあるので async(同期の命令の中で窓を作ると Windows では止まる)
#[tauri::command]
pub async fn posture_action(app: AppHandle, action: String) -> PostureView {
    apply_posture(&app, &action)
}

// MARK: 日课

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RitualVideo {
    title: String,
    page: String,
    embed: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RitualStep {
    heading: String,
    name: String,
    text: String,
    pose: String,
    meta: Option<String>,
    duration: u32,
    step_number: usize,
    step_count: usize,
    stretch_number: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RitualPlan {
    videos: Vec<RitualVideo>,
    steps: Vec<RitualStep>,
    stretch_names: Vec<String>,
    has_strength: bool,
    short: bool,
    voice: bool,
    streak: usize,
    caution: &'static str,
}

#[tauri::command]
pub fn ritual_plan(state: State<'_, AppState>, short: bool) -> RitualPlan {
    let inner = state.inner.lock().expect("state");
    let s = &inner.settings;
    let now = Utc::now();
    let has_strength = !short
        && s.ritual_strength_on
        && ritual::includes_strength(&s.ritual_strength_log, now, Zone::Local);
    let stretches = ritual::plan(
        &s.ritual_stretches,
        has_strength.then_some(s.ritual_strength.as_str()),
        &s.ritual_floor,
        short,
    );
    let mut steps = Vec::new();
    for (number, stretch) in stretches.iter().enumerate() {
        let guide = posture::steps(stretch);
        for (i, step) in guide.iter().enumerate() {
            steps.push(RitualStep {
                heading: posture::heading(stretch, &guide, i),
                name: posture::display_name(&stretch.name),
                text: step.text.clone(),
                pose: step.pose.clone(),
                meta: step.meta.clone(),
                duration: ritual::duration(&stretch.steps[i]).unwrap_or(ritual::SETUP_SECONDS),
                step_number: i,
                step_count: guide.len(),
                stretch_number: number,
            });
        }
    }
    RitualPlan {
        videos: ritual::videos(&s.ritual_videos)
            .into_iter()
            .map(|v| RitualVideo {
                embed: v.embed(),
                title: v.title,
                page: v.page,
            })
            .collect(),
        steps,
        stretch_names: stretches
            .iter()
            .map(|s| posture::split(&s.name).0)
            .collect(),
        has_strength,
        short,
        voice: s.ritual_voice,
        streak: ritual::streak(&s.ritual_log, now, Zone::Local),
        caution: posture::CAUTION,
    }
}

/// 日课を終えた(最後の仰向けの腹式呼吸も 1 回に数える)。連続日数を返す
#[tauri::command]
pub fn ritual_done(state: State<'_, AppState>, strength: bool) -> usize {
    let mut inner = state.inner.lock().expect("state");
    let day = today();
    ritual::record(&mut inner.settings.ritual_log, &day);
    ritual::record(&mut inner.settings.breath_log, &day);
    if strength {
        ritual::record(&mut inner.settings.ritual_strength_log, &day);
    }
    state.save(&inner);
    ritual::streak(&inner.settings.ritual_log, Utc::now(), Zone::Local)
}

// MARK: 設定

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsView {
    sync_root: Option<String>,
    device: String,
    autostart: bool,
    posture_enabled: bool,
    sit_minutes: i64,
    stand_minutes: i64,
    stretches: String,
    breath_habit: bool,
    ritual_videos: String,
    ritual_stretches: String,
    ritual_strength: String,
    ritual_floor: String,
    ritual_strength_on: bool,
    ritual_voice: bool,
    defaults: HashMap<&'static str, &'static str>,
}

#[tauri::command]
pub fn settings_get(state: State<'_, AppState>) -> SettingsView {
    let inner = state.inner.lock().expect("state");
    let s = &inner.settings;
    SettingsView {
        sync_root: s.sync_root.clone(),
        device: s.device.clone(),
        autostart: s.autostart,
        posture_enabled: s.posture.enabled,
        sit_minutes: s.posture.sit_minutes,
        stand_minutes: s.posture.stand_minutes,
        stretches: s.posture.stretches.clone(),
        breath_habit: s.breath_habit,
        ritual_videos: s.ritual_videos.clone(),
        ritual_stretches: s.ritual_stretches.clone(),
        ritual_strength: s.ritual_strength.clone(),
        ritual_floor: s.ritual_floor.clone(),
        ritual_strength_on: s.ritual_strength_on,
        ritual_voice: s.ritual_voice,
        defaults: HashMap::from([
            ("stretches", posture::DEFAULT_STRETCHES),
            ("ritualVideos", ritual::DEFAULT_VIDEOS),
            ("ritualStretches", ritual::DEFAULT_STRETCHES),
            ("ritualStrength", ritual::DEFAULT_STRENGTH),
            ("ritualFloor", ritual::DEFAULT_FLOOR),
        ]),
    }
}

#[tauri::command]
pub fn settings_save(
    app: AppHandle,
    state: State<'_, AppState>,
    patch: SettingsPatch,
) -> Result<(), String> {
    let autostart = patch.autostart.is_some();
    {
        let mut inner = state.inner.lock().expect("state");
        if inner.settings.apply(patch) {
            inner.english = None;
            inner.undo = None;
        }
        inner
            .settings
            .save(&state.settings_path)
            .map_err(|e| e.to_string())?;
    }
    // 自動起動はレジストリを触るので、鍵を放してから
    if autostart {
        crate::apply_autostart(&app);
    }
    Ok(())
}

/// 同期フォルダを選ぶ(選んでいるあいだ面板を閉じない)
#[tauri::command]
pub async fn pick_folder(app: AppHandle) -> Option<String> {
    use tauri_plugin_dialog::DialogExt;
    if let Ok(mut inner) = app.state::<AppState>().inner.lock() {
        inner.picking = true;
    }
    let dialog = app.clone();
    let picked =
        tauri::async_runtime::spawn_blocking(move || dialog.dialog().file().blocking_pick_folder())
            .await
            .ok()
            .flatten();
    if let Ok(mut inner) = app.state::<AppState>().inner.lock() {
        inner.picking = false;
    }
    picked.map(|path| path.to_string())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Fit {
    width: f64,
    height: f64,
}

/// 窓を開く("ritual" / "panel")・大きさを合わせる("fit:posture")。
/// 窓を作るので async(同期の命令の中で窓を作ると Windows では止まる)
#[tauri::command]
pub async fn open_surface(app: AppHandle, which: String, fit: Option<Fit>) {
    match (which.as_str(), fit) {
        ("ritual", _) => surfaces::open_ritual(&app),
        ("panel", _) => surfaces::toggle_panel(&app),
        (label, Some(size)) => surfaces::fit(&app, label, size.width, size.height),
        _ => {}
    }
}
