//! 設定と記録(アプリの設定フォルダの settings.json 1 つ)。英語の進捗は同期フォルダの jsonl が正本なので、ここには置かない

use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};
use yudh_core::posture::{self, PostureSettings};
use yudh_core::standing::StandLog;
use yudh_core::{quiet, ritual};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    /// 同期フォルダ(OneDrive などの中。Mac と同じフォルダ)
    pub sync_root: Option<String>,
    /// 出来事に付ける端末名(ファイル名にもなる)
    pub device: String,
    /// ログインしたら自動で起動する(坐站の提醒が毎日届くように)
    pub autostart: bool,
    /// 打游戏时让 Yudh 完全安静的程序(1 行 1 つ。exe 名)
    pub quiet_apps: String,
    /// 初回の説明(坐 30 站 30、到点小窗会叫你)を読んだ
    pub welcomed: bool,
    /// 自分で動かした面板の左下(論理 px。帯と全体で下の辺を揃えるため左下を覚える)。次からその位置に出す。
    /// 前の版の panelPos(左上)は読まない
    pub panel_anchor: Option<[f64; 2]>,
    /// 自分で動かした坐站の小窓の左上(論理 px)
    pub posture_pos: Option<[f64; 2]>,
    pub posture: PostureSettings,
    /// 日ごとの立った時間と姿勢を変えた回数(「今天站了 1 小时 30 分，换了 3 次姿势」)
    pub stand_log: StandLog,
    /// 次に出す拉伸の番号(钟が立たせるたびに進める。「我还坐着」で戻す)
    pub stretch_index: usize,
    /// 立つたびに、拉伸の前に腹式呼吸を 3 回
    pub breath_habit: bool,
    pub breath_log: BTreeMap<String, u32>,
    pub ritual_videos: String,
    pub ritual_stretches: String,
    pub ritual_strength: String,
    pub ritual_floor: String,
    pub ritual_strength_on: bool,
    pub ritual_log: BTreeMap<String, u32>,
    pub ritual_strength_log: BTreeMap<String, u32>,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            sync_root: None,
            device: std::env::var("COMPUTERNAME").unwrap_or_else(|_| "Windows PC".into()),
            autostart: true,
            quiet_apps: quiet::DEFAULT_QUIET_APPS.into(),
            welcomed: false,
            panel_anchor: None,
            posture_pos: None,
            posture: PostureSettings::default(),
            stand_log: StandLog::new(),
            stretch_index: 0,
            breath_habit: true,
            breath_log: BTreeMap::new(),
            ritual_videos: ritual::DEFAULT_VIDEOS.into(),
            ritual_stretches: ritual::DEFAULT_STRETCHES.into(),
            ritual_strength: ritual::DEFAULT_STRENGTH.into(),
            ritual_floor: ritual::DEFAULT_FLOOR.into(),
            ritual_strength_on: true,
            ritual_log: BTreeMap::new(),
            ritual_strength_log: BTreeMap::new(),
        }
    }
}

impl Settings {
    /// 読めなければ既定(壊れたファイルで起動できなくならないように)。
    /// 坐站の分数は計画で固定(前の版で保存した 40 / 15 は使わない)
    pub fn load(path: &Path) -> Settings {
        let mut settings: Settings = std::fs::read(path)
            .ok()
            .and_then(|data| serde_json::from_slice(&data).ok())
            .unwrap_or_default();
        settings.posture.sit_minutes = posture::PLAN_SIT_MINUTES;
        settings.posture.stand_minutes = posture::PLAN_STAND_MINUTES;
        settings
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        let text = serde_json::to_string_pretty(self).map_err(io::Error::other)?;
        yudh_core::sync::write_atomic(path, &text).map(|_| ())
    }
}

/// 画面から変える分だけ(記録は画面から上書きさせない)
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SettingsPatch {
    pub sync_root: Option<Option<String>>,
    pub device: Option<String>,
    pub autostart: Option<bool>,
    pub quiet_apps: Option<String>,
    pub welcomed: Option<bool>,
    pub posture_enabled: Option<bool>,
    pub stretches: Option<String>,
    pub breath_habit: Option<bool>,
    pub ritual_videos: Option<String>,
    pub ritual_stretches: Option<String>,
    pub ritual_strength: Option<String>,
    pub ritual_floor: Option<String>,
    pub ritual_strength_on: Option<bool>,
}

impl Settings {
    /// 当てる。同期フォルダか端末名が変わったら true(英語を読み直す)
    pub fn apply(&mut self, patch: SettingsPatch) -> bool {
        let mut resync = false;
        if let Some(root) = patch.sync_root {
            let root = root.filter(|r| !r.trim().is_empty());
            resync |= root != self.sync_root;
            self.sync_root = root;
        }
        if let Some(device) = patch.device.filter(|d| !d.trim().is_empty()) {
            resync |= device != self.device;
            self.device = device;
        }
        if let Some(v) = patch.autostart {
            self.autostart = v;
        }
        if let Some(v) = patch.quiet_apps {
            self.quiet_apps = v;
        }
        if let Some(v) = patch.welcomed {
            self.welcomed = v;
        }
        if let Some(v) = patch.posture_enabled {
            self.posture.enabled = v;
        }
        if let Some(v) = patch.stretches {
            self.posture.stretches = v;
        }
        if let Some(v) = patch.breath_habit {
            self.breath_habit = v;
        }
        if let Some(v) = patch.ritual_videos {
            self.ritual_videos = v;
        }
        if let Some(v) = patch.ritual_stretches {
            self.ritual_stretches = v;
        }
        if let Some(v) = patch.ritual_strength {
            self.ritual_strength = v;
        }
        if let Some(v) = patch.ritual_floor {
            self.ritual_floor = v;
        }
        if let Some(v) = patch.ritual_strength_on {
            self.ritual_strength_on = v;
        }
        resync
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_or_broken_files_give_defaults_and_patches_keep_logs() {
        let dir = std::env::temp_dir().join(format!("yudh-settings-{}", std::process::id()));
        let path = dir.join("settings.json");
        assert!(Settings::load(&path).breath_habit);
        assert!(
            !Settings::load(&path).welcomed,
            "the first run shows the plan"
        );
        let mut s = Settings::default();
        s.breath_log.insert("2026-10-01".into(), 3);
        s.save(&path).unwrap();
        std::fs::write(dir.join("broken.json"), "{not json").unwrap();
        assert_eq!(Settings::load(&dir.join("broken.json")).stretch_index, 0);
        let mut loaded = Settings::load(&path);
        assert_eq!(loaded.breath_log["2026-10-01"], 3);
        assert_eq!(
            (loaded.posture.sit_minutes, loaded.posture.stand_minutes),
            (30, 30),
            "the sit / stand plan is fixed"
        );
        let resync = loaded.apply(SettingsPatch {
            sync_root: Some(Some("D:\\OneDrive\\Yudh".into())),
            ..Default::default()
        });
        assert!(resync, "a new folder reloads English");
        assert_eq!(loaded.breath_log["2026-10-01"], 3, "logs are untouched");
        assert!(!loaded.apply(SettingsPatch {
            sync_root: Some(Some("D:\\OneDrive\\Yudh".into())),
            ..Default::default()
        }));
        assert!(loaded.apply(SettingsPatch {
            sync_root: Some(Some("  ".into())),
            ..Default::default()
        }));
        assert_eq!(loaded.sync_root, None, "blank clears the folder");
        assert!(!loaded.apply(SettingsPatch {
            welcomed: Some(true),
            ..Default::default()
        }));
        assert!(loaded.welcomed);
        std::fs::remove_dir_all(&dir).ok();
    }
}
