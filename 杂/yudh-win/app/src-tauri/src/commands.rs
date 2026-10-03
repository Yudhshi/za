//! 画面(HTML)から呼ぶ命令。返すものは JSON(camelCase)。鍵は短く持ち、窓を動かす前に放す

use std::collections::HashMap;
use std::path::Path;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};
use yudh_core::agenda::{self, Tomorrow};
use yudh_core::english::{Stats, VocabCard};
use yudh_core::habits::Habits;
use yudh_core::library::DictationWord;
use yudh_core::posture::{self, Posture, Prompt, Step, Stretch};
use yudh_core::quiz::Question;
use yudh_core::replay::Kind;
use yudh_core::ritual;
use yudh_core::round::RoundMark;
use yudh_core::spell::{self, SpellMarks, SpellResult};
use yudh_core::srs::Rating;
use yudh_core::standing;
use yudh_core::standing::DayMark;
use yudh_core::sync::SyncFolder;
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

fn folder(inner: &Inner) -> Option<SyncFolder> {
    let root = inner.settings.sync_root.as_deref()?;
    Some(SyncFolder::new(root, &inner.settings.device))
}

/// このパソコンでの習慣の記録(設定の中)
fn own_habits(inner: &Inner) -> Habits {
    let s = &inner.settings;
    Habits {
        ritual: s.ritual_log.clone(),
        ritual_strength: s.ritual_strength_log.clone(),
        breath: s.breath_log.clone(),
    }
}

/// Mac の分も足した記録(連続日数・隔天・今日の呼吸の回数はこれで数える)。同期フォルダが無ければ自分の分だけ
fn habits(inner: &Inner) -> Habits {
    let own = own_habits(inner);
    match folder(inner) {
        Some(f) => f.combined_habits(&own),
        None => own,
    }
}

/// 自分の記録を同期フォルダに書く(記録が増えたとき・起動時・設定を保存したとき。同じ中身なら書かない)
pub fn publish_habits(inner: &Inner) {
    if let Some(f) = folder(inner) {
        let _ = f.write_habits(&own_habits(inner));
    }
}

fn today_breaths(all: &Habits) -> u32 {
    all.breath.get(&today()).copied().unwrap_or(0)
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
    /// いまの姿勢を始めた時刻と、次に切り替える時刻(UNIX ミリ秒)
    since: i64,
    due_at: i64,
    /// いまの姿勢は钟が自分で切り替えた(札を返せば取り消し)
    announced: bool,
    /// 夜・日课のあと:钟を止めている
    resting: bool,
    /// 今日の胶带の印(時間軸)
    marks: Vec<DayMark>,
    /// 「今天站了 1 小时 30 分，换了 3 次姿势」(いま立っている分も入れて)と、帯に入る短い形「站了 1 小时 30 分 · 换了 3 次」
    today: String,
    today_short: String,
    breath_today: u32,
    ritual_streak: usize,
    ritual_today: bool,
    /// 初回の説明をまだ読んでいない:面板は先に計画を見せる
    welcomed: bool,
    /// 帯を常駐させる
    pinned: bool,
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
    let all = habits(&inner);
    PanelState {
        configured: root.is_some(),
        sync_root: root,
        has_library,
        stats,
        tomorrow,
        posture: inner.posture.posture,
        minutes_in_posture: (now - inner.posture.since).num_minutes(),
        prompt: inner.posture.prompt,
        since: inner.posture.since.timestamp_millis(),
        due_at: inner
            .posture
            .due_at(&inner.settings.posture)
            .timestamp_millis(),
        announced: inner.posture.announced,
        resting: inner.posture.resting,
        marks: day_stand(&inner, now).marks,
        today: standing::summary(day_stand(&inner, now)),
        today_short: standing::short_summary(day_stand(&inner, now)),
        breath_today: today_breaths(&all),
        ritual_streak: ritual::streak(&all.ritual, now, Zone::Local),
        ritual_today: all.ritual.get(&today()).is_some_and(|n| *n > 0),
        welcomed: inner.settings.welcomed,
        pinned: inner.settings.pinned,
    }
}

/// 帯・トレイ・小窓で同じ一行:「已坐 23 分钟 · 站了 1 小时 30 分 · 换了 3 次」(夜は「夜里不叫」)
pub fn status_line(inner: &Inner, now: chrono::DateTime<Utc>) -> String {
    if inner.posture.resting {
        return format!(
            "休息中 · {}",
            standing::short_summary(day_stand(inner, now))
        );
    }
    let minutes = (now - inner.posture.since).num_minutes().max(0);
    let posture = match inner.posture.posture {
        Posture::Sitting => "已坐",
        Posture::Standing => "已站",
    };
    format!(
        "{posture} {minutes} 分钟 · {}",
        standing::short_summary(day_stand(inner, now))
    )
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
    spell: Option<DictationWord>,
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
        spell: (kind == Kind::Spell)
            .then(|| e.spell_word(&id).cloned())
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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpellGraded {
    result: SpellResult,
    marks: SpellMarks,
    stats: Stats,
}

/// 聴写の採点(Mac と同じ:正确 = 记住了、差一个字母 = 模糊、错 = 忘了)。
/// input が None なら「不知道」:答えを見せて、今日もう一度
#[tauri::command]
pub fn english_spell(
    state: State<'_, AppState>,
    id: String,
    input: Option<String>,
) -> Result<SpellGraded, String> {
    let mut inner = state.inner.lock().expect("state");
    let now = Utc::now();
    let e = english(&mut inner).ok_or("no sync folder")?;
    let answer = e
        .spell_word(&id)
        .map(|w| w.w.clone())
        .ok_or("unknown word")?;
    let typed = input.unwrap_or_default();
    let result = if typed.trim().is_empty() {
        SpellResult::Wrong
    } else {
        spell::check(&typed, &answer)
    };
    let rating = match result {
        SpellResult::Correct => Rating::Good,
        SpellResult::Almost => Rating::Hard,
        SpellResult::Wrong => Rating::Again,
    };
    let point = e
        .rate(&id, Kind::Spell, rating, now)
        .map_err(|err| err.to_string())?;
    let stats = e.stats(now, true);
    inner.undo = Some((point, Kind::Spell));
    Ok(SpellGraded {
        result,
        marks: spell::marks(&typed, &answer),
        stats,
    })
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
    /// いまの姿勢を始めた時刻(UNIX ミリ秒。「站起来」「坐下」と言った時刻)
    since: i64,
    /// 切り替えの時刻(UNIX ミリ秒)
    due_at: i64,
    /// いまの姿勢は钟が自分で切り替えた(「我还坐着」「我还站着」で直せる)
    announced: bool,
    /// 順番の拉伸(名前は小窓の鍵と「然后：…」に)
    stretch: Stretch,
    /// 毎回の分の題(「斜角肌拉伸」。無ければ空)
    fixed_name: String,
    /// 通した手順(毎回の分 → 順番の分)
    steps: Vec<Step>,
    /// 各手順の秒数(秒・回数から。読めなければ 10 秒、どの手順も 10 秒より短くしない)。時間が来たら自動で次へ進む
    durations: Vec<u32>,
    step: usize,
    heading: String,
    frieze: bool,
    /// 設定の「试做」:钟は動かさず、この拉伸だけを流している
    preview: bool,
    /// 立ってすぐの腹式呼吸を始めた時刻(UNIX ミリ秒)
    breath_started_at: Option<i64>,
    breath_today: u32,
    next_stretch: String,
    /// 「今天站了 1 小时 30 分，换了 3 次姿势」
    today: String,
    /// 直前に終えた立ち作業の長さ(分。「坐下」の知らせの「站了 N 分钟」)
    last_stand_minutes: i64,
    caution: &'static str,
}

/// 今日の立った時間と回数(いま立っている分も足して)
fn day_stand(inner: &Inner, now: chrono::DateTime<Utc>) -> standing::DayStand {
    let clock = &inner.posture;
    let open = match clock.posture {
        Posture::Standing => (now - clock.since).num_seconds(),
        Posture::Sitting => 0,
    };
    standing::today(&inner.settings.stand_log, &today()).plus_open(open)
}

/// 钟の切り替わりを記録に落とす(日ごとの立った時間・回数、次の拉伸の番号、立ってすぐの腹式呼吸)。
/// 判定のあと・操作のあとに毎回呼ぶ。記録が増えたら true(設定を保存する)
pub fn settle(inner: &mut Inner, now: chrono::DateTime<Utc>) -> bool {
    let marks = inner.posture.take_marks();
    for m in &marks {
        standing::record_mark(&mut inner.settings.stand_log, &Zone::Local.key(m.at), m);
    }
    let transitions = inner.posture.take_transitions();
    if transitions.is_empty() {
        return !marks.is_empty();
    }
    for t in &transitions {
        standing::record(&mut inner.settings.stand_log, &Zone::Local.key(t.at), t);
        match t.to {
            // 立ったらまず腹式呼吸を 3 回(习惯にする。拉伸はそのあと)。「我还站着」で戻ったときはもう済んでいる
            Posture::Standing => {
                inner.breath_started = (inner.settings.breath_habit && !t.revert).then_some(now);
            }
            Posture::Sitting => inner.breath_started = None,
        }
    }
    inner.settings.stretch_index = inner.posture.stretch_index;
    true
}

/// 各手順の秒数(秒・回数から。読めなければ 10 秒、どの手順も 10 秒より短くしない)
fn durations(parts: &[Stretch]) -> Vec<u32> {
    parts
        .iter()
        .flat_map(|s| s.steps.iter())
        .map(|line| {
            ritual::duration(line)
                .unwrap_or(ritual::SETUP_SECONDS)
                .max(ritual::SETUP_SECONDS)
        })
        .collect()
}

fn posture_view(inner: &Inner) -> PostureView {
    let clock = &inner.posture;
    let now = Utc::now();
    // 設定の「试做」:钟は触らず、その拉伸だけを手順として見せる
    if let Some(p) = &inner.preview {
        let parts = vec![p.stretch.clone()];
        let steps = posture::routine_steps(&parts);
        let step = p.step.min(steps.len());
        return PostureView {
            prompt: Some(Prompt::Standing),
            posture: clock.posture,
            since: p.started.timestamp_millis(),
            due_at: (p.started + chrono::Duration::minutes(30)).timestamp_millis(),
            announced: false,
            heading: posture::routine_heading(&steps, step),
            frieze: posture::shows_frieze(&steps),
            durations: durations(&parts),
            stretch: p.stretch.clone(),
            fixed_name: String::new(),
            steps,
            step,
            preview: true,
            breath_started_at: None,
            breath_today: 0,
            next_stretch: String::new(),
            today: String::new(),
            last_stand_minutes: 0,
            caution: posture::CAUTION,
        };
    }
    let parts = clock.parts();
    let steps = posture::routine_steps(&parts);
    let step = clock.step.min(steps.len());
    PostureView {
        prompt: clock.prompt,
        posture: clock.posture,
        since: clock.since.timestamp_millis(),
        due_at: clock.due_at(&inner.settings.posture).timestamp_millis(),
        announced: clock.announced,
        heading: posture::routine_heading(&steps, step),
        frieze: posture::shows_frieze(&steps),
        durations: durations(&parts),
        stretch: clock.stretch.clone(),
        fixed_name: clock
            .fixed
            .first()
            .map(|s| posture::split(&s.name).0)
            .unwrap_or_default(),
        steps,
        step,
        preview: false,
        breath_started_at: inner.breath_started.map(|t| t.timestamp_millis()),
        breath_today: today_breaths(&habits(inner)),
        next_stretch: posture::display_name(&clock.next_stretch(&inner.settings.posture).name),
        today: standing::summary(day_stand(inner, now)),
        last_stand_minutes: (clock.last_stand_seconds + 30) / 60,
        caution: posture::CAUTION,
    }
}

#[tauri::command]
pub fn posture_state(state: State<'_, AppState>) -> PostureView {
    posture_view(&state.inner.lock().expect("state"))
}

/// 坐站の操作(トレイからも呼ぶ)。小窓の出し入れまでする。
/// 播报の钟なので操作は少ない:钟が間違えたときの「我还坐着」「我还站着」、トレイの「现在站起来」「坐下了」、手順の送り、閉じる
pub fn apply_posture(app: &AppHandle, action: &str) -> PostureView {
    let view = {
        let state = app.state::<AppState>();
        let mut inner = state.inner.lock().expect("state");
        let now = Utc::now();
        let settings = inner.settings.posture.clone();
        // 「试做」の最中:手順の送りと閉じるだけ。钟は触らない
        if let Some(p) = inner.preview.as_mut() {
            match action {
                "next" => p.step += 1,
                "prev" => p.step = p.step.saturating_sub(1),
                "close" => inner.preview = None,
                _ => {}
            }
            let view = posture_view(&inner);
            drop(inner);
            surfaces::sync_posture(app);
            return view;
        }
        match action {
            // トレイ:座っていればすぐ立ち作業に、立っていれば手順を開き直す
            "stood" | "open" => inner.posture.confirm_stood(now, &settings),
            "sat" => inner.posture.confirm_sat(now, &settings),
            // 「坐 | 站」の札:切り替えた直後なら取り消し、それより後なら今ここで切り替え
            "flip" => inner.posture.flip(now, &settings),
            "stillSitting" => {
                inner.posture.still_sitting(now, &settings);
            }
            "stillStanding" => {
                inner.posture.still_standing(now);
            }
            "close" => inner.posture.close_prompt(),
            "next" => inner.posture.move_step(1),
            "prev" => inner.posture.move_step(-1),
            "breathDone" => {
                if inner.breath_started.take().is_some() {
                    ritual::record(&mut inner.settings.breath_log, &today());
                    state.save(&inner);
                    publish_habits(&inner);
                }
            }
            "breathSkip" => inner.breath_started = None,
            _ => {}
        }
        if settle(&mut inner, now) {
            state.save(&inner);
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

/// 設定の拉伸库の「试做」:その拉伸(1 つ分のテキスト)を小窓で流す。钟は動かさない
#[tauri::command]
pub async fn posture_preview(app: AppHandle, text: String) -> Result<(), String> {
    let stretch = posture::stretches(&text)
        .into_iter()
        .next()
        .ok_or("empty stretch")?;
    {
        let state = app.state::<AppState>();
        let mut inner = state.inner.lock().expect("state");
        inner.preview = Some(crate::Preview {
            stretch,
            step: 0,
            started: Utc::now(),
        });
    }
    surfaces::sync_posture(&app);
    Ok(())
}

// MARK: 日课

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RitualVideo {
    title: String,
    page: String,
    embed: Option<String>,
    /// 長さ(秒)。あれば放し終わったら自動で次へ
    seconds: Option<u32>,
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
    streak: usize,
    caution: &'static str,
}

#[tauri::command]
pub fn ritual_plan(state: State<'_, AppState>, short: bool) -> RitualPlan {
    let inner = state.inner.lock().expect("state");
    let s = &inner.settings;
    let now = Utc::now();
    let all = habits(&inner);
    let has_strength = !short
        && s.ritual_strength_on
        && ritual::includes_strength(&all.ritual_strength, now, Zone::Local);
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
                seconds: v.seconds,
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
        streak: ritual::streak(&all.ritual, now, Zone::Local),
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
    publish_habits(&inner);
    ritual::streak(&habits(&inner).ritual, Utc::now(), Zone::Local)
}

// MARK: 設定

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsView {
    sync_root: Option<String>,
    device: String,
    autostart: bool,
    quiet_apps: String,
    welcomed: bool,
    pinned: bool,
    posture_enabled: bool,
    sit_minutes: i64,
    stand_minutes: i64,
    quiet_from: u32,
    quiet_to: u32,
    fixed: String,
    stretches: String,
    breath_habit: bool,
    ritual_videos: String,
    ritual_stretches: String,
    ritual_strength: String,
    ritual_floor: String,
    ritual_strength_on: bool,
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
        quiet_apps: s.quiet_apps.clone(),
        welcomed: s.welcomed,
        pinned: s.pinned,
        posture_enabled: s.posture.enabled,
        sit_minutes: s.posture.sit_minutes,
        stand_minutes: s.posture.stand_minutes,
        quiet_from: s.posture.quiet_from,
        quiet_to: s.posture.quiet_to,
        fixed: s.posture.fixed.clone(),
        stretches: s.posture.stretches.clone(),
        breath_habit: s.breath_habit,
        ritual_videos: s.ritual_videos.clone(),
        ritual_stretches: s.ritual_stretches.clone(),
        ritual_strength: s.ritual_strength.clone(),
        ritual_floor: s.ritual_floor.clone(),
        ritual_strength_on: s.ritual_strength_on,
        defaults: HashMap::from([
            ("fixed", posture::DEFAULT_FIXED),
            ("stretches", posture::DEFAULT_STRETCHES),
            ("ritualShort", ritual::SHORT_STRETCHES),
            ("ritualVideos", ritual::DEFAULT_VIDEOS),
            ("ritualStretches", ritual::DEFAULT_STRETCHES),
            ("ritualStrength", ritual::DEFAULT_STRENGTH),
            ("ritualFloor", ritual::DEFAULT_FLOOR),
            ("quietApps", yudh_core::quiet::DEFAULT_QUIET_APPS),
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
        let before = folder(&inner);
        if inner.settings.apply(patch) {
            inner.english = None;
            inner.undo = None;
            // 同じフォルダで名前だけ変えたら、古い名前の記録を消す(別の端末として二重に数えないように)
            if let (Some(old), Some(new)) = (before, folder(&inner)) {
                if old.root == new.root && old.habits_file() != new.habits_file() {
                    let _ = std::fs::remove_file(old.habits_file());
                }
            }
        }
        inner
            .settings
            .save(&state.settings_path)
            .map_err(|e| e.to_string())?;
        publish_habits(&inner);
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
    let picked = tauri::async_runtime::spawn_blocking(move || {
        // 面板を親にする:面板は最前面なので、親にしないとダイアログの下の端が面板に隠れる
        let mut builder = dialog.dialog().file();
        if let Some(panel) = dialog.get_webview_window("panel") {
            builder = builder.set_parent(&panel);
        }
        builder.blocking_pick_folder()
    })
    .await
    .ok()
    .flatten();
    if let Ok(mut inner) = app.state::<AppState>().inner.lock() {
        inner.picking = false;
    }
    picked.map(|path| path.to_string())
}

/// 既定のブラウザで開く(会議のリンク・動画のページ)。WebView2 の window.open は窓を作る手当てが無いと何も起きない。
/// http(s) だけ(ファイルやプログラムを開かせない)
#[tauri::command]
pub fn open_url(url: String) -> Result<(), String> {
    let trimmed = url.trim();
    if !(trimmed.starts_with("https://") || trimmed.starts_with("http://")) {
        return Err("only http(s) links are opened".into());
    }
    crate::platform::open_in_browser(trimmed);
    Ok(())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Fit {
    width: f64,
    height: f64,
}

/// 窓を開く("ritual" / "panel")・面板を細い帯から全体に広げる("panel-full")・大きさを合わせる(fit)。
/// 窓を作るので async(同期の命令の中で窓を作ると Windows では止まる)
#[tauri::command]
pub async fn open_surface(app: AppHandle, which: String, fit: Option<Fit>) {
    match (which.as_str(), fit) {
        ("ritual", _) => surfaces::open_ritual(&app),
        ("panel", _) => surfaces::toggle_panel(&app),
        ("panel-full", _) => surfaces::expand_panel(&app),
        ("panel-strip", _) => surfaces::collapse_panel(&app),
        (label, Some(size)) => surfaces::fit(&app, label, size.width, size.height),
        _ => {}
    }
}
