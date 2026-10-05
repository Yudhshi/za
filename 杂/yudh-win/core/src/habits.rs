//! 習慣の記録の共有。各端末は自分の `habits-<端末>.json` だけを書き、全員の分を足して数える
//! (日课の連続日数・隔天の力量・今日の腹式呼吸の回数が、Mac と Windows のどちらでやっても続くように)。
//! 中身は日ごとの回数("yyyy-MM-dd" → 回数)。書き方は英語の出来事と同じ(一時ファイルから置き換え、同じなら書かない)

use std::collections::BTreeMap;
use std::io;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::sync::{self, SyncFolder};

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Habits {
    /// 日课をやり終えた回数
    pub ritual: BTreeMap<String, u32>,
    /// 日课に肩袖の力量が入っていた回数(隔天の判定に使う)
    pub ritual_strength: BTreeMap<String, u32>,
    /// 腹式呼吸をやり終えた回数(立ったときの 3 回、日课の最後の 12 回を、それぞれ 1 回と数える)
    pub breath: BTreeMap<String, u32>,
}

impl Habits {
    /// 日ごとに足す
    pub fn merge(&mut self, other: &Habits) {
        fn add(into: &mut BTreeMap<String, u32>, from: &BTreeMap<String, u32>) {
            for (day, n) in from {
                *into.entry(day.clone()).or_insert(0) += n;
            }
        }
        add(&mut self.ritual, &other.ritual);
        add(&mut self.ritual_strength, &other.ritual_strength);
        add(&mut self.breath, &other.breath);
    }
}

pub fn file_name(device: &str) -> String {
    format!("habits-{}.json", sync::slug(device))
}

impl SyncFolder {
    pub fn habits_file(&self) -> PathBuf {
        self.root.join(file_name(&self.device))
    }

    /// 自分の記録を書く。同じ中身なら書かない(false)
    pub fn write_habits(&self, own: &Habits) -> io::Result<bool> {
        let mut text = serde_json::to_string_pretty(own).map_err(io::Error::other)?;
        text.push('\n');
        sync::write_atomic(&self.habits_file(), &text)
    }

    /// 自分の記録に、ほかの端末のファイルの分を足したもの(自分のファイルは読まない:手元のほうが新しい)。
    /// 読めないファイルは飛ばす
    pub fn combined_habits(&self, own: &Habits) -> Habits {
        let mine = file_name(&self.device);
        let mut total = own.clone();
        let Ok(entries) = std::fs::read_dir(&self.root) else {
            return total;
        };
        let mut files: Vec<PathBuf> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| {
                p.file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .is_some_and(|n| n.starts_with("habits-") && n.ends_with(".json") && n != mine)
            })
            .collect();
        files.sort();
        for file in files {
            let other = std::fs::read(&file)
                .ok()
                .and_then(|data| serde_json::from_slice::<Habits>(&data).ok());
            if let Some(other) = other {
                total.merge(&other);
            }
        }
        total
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;
    use crate::ritual;
    use crate::Zone;

    fn log(days: &[&str]) -> BTreeMap<String, u32> {
        days.iter().map(|d| (d.to_string(), 1)).collect()
    }

    #[test]
    fn devices_add_up_and_own_file_is_not_double_counted() {
        let dir = std::env::temp_dir().join(format!("yudh-habits-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mac = SyncFolder::new(&dir, "Yudh MacBook");
        let win = SyncFolder::new(&dir, "DESKTOP-9F2");

        // 9/29 と 10/1 は Mac、9/30 は Windows でやった
        let mac_own = Habits {
            ritual: log(&["2026-09-29", "2026-10-01"]),
            ritual_strength: log(&["2026-09-29"]),
            breath: log(&["2026-10-01"]),
        };
        assert!(mac.write_habits(&mac_own).unwrap());
        assert!(
            !mac.write_habits(&mac_own).unwrap(),
            "same content is not rewritten"
        );
        std::fs::write(dir.join("habits-broken.json"), "{oops").unwrap();

        let win_own = Habits {
            ritual: log(&["2026-09-30"]),
            breath: log(&["2026-10-01"]),
            ..Default::default()
        };
        // 自分のファイルが古くても、手元の記録だけを数える
        win.write_habits(&Habits::default()).unwrap();
        let all = win.combined_habits(&win_own);
        assert_eq!(all.breath["2026-10-01"], 2, "one breath on each device");
        let now = tokyo(2026, 10, 1, 22, 0, 0);
        assert_eq!(ritual::streak(&all.ritual, now, Zone::tokyo()), 3);
        assert_eq!(
            ritual::streak(&win_own.ritual, now, Zone::tokyo()),
            1,
            "alone it only sees 9/30"
        );

        // Mac で 9/30 に力量 → Windows の 10/1 は入れない(隔天)
        let mut mac_strength = mac_own.clone();
        mac_strength.ritual_strength = log(&["2026-09-30"]);
        mac.write_habits(&mac_strength).unwrap();
        let all = win.combined_habits(&win_own);
        assert!(!ritual::includes_strength(
            &all.ritual_strength,
            now,
            Zone::tokyo()
        ));

        // フォルダが無ければ自分の分だけ
        let missing = SyncFolder::new(dir.join("nope"), "DESKTOP-9F2");
        assert_eq!(missing.combined_habits(&win_own), win_own);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn file_format_is_camel_case_and_tolerates_missing_keys() {
        assert_eq!(file_name("Yudh MacBook"), "habits-Yudh-MacBook.json");
        let h: Habits = serde_json::from_str(r#"{"ritualStrength":{"2026-10-01":1}}"#).unwrap();
        assert_eq!(h.ritual_strength["2026-10-01"], 1);
        assert!(h.ritual.is_empty() && h.breath.is_empty());
    }
}
