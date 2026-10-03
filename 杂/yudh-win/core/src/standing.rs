//! 一日に立った時間と姿勢を変えた回数(「今天站了 1 小时 30 分，换了 3 次姿势」)。
//! 钟の切り替わり(`posture::Transition`)を日ごとに足すだけ。設定ファイルに残す(60 日)。
//! 播报の钟なので「計画どおりにした」数字:本当に立ったかは聞かない

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::posture::Transition;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DayStand {
    pub stand_seconds: i64,
    pub switches: u32,
}

impl DayStand {
    /// いま立っている分(まだ切り替わっていない)を足したもの
    pub fn plus_open(self, open_seconds: i64) -> DayStand {
        DayStand {
            stand_seconds: self.stand_seconds + open_seconds.max(0),
            switches: self.switches,
        }
    }
}

/// "yyyy-MM-dd" → その日の分
pub type StandLog = BTreeMap<String, DayStand>;

/// 切り替わりを足す(取り消しは負の数で来る。0 より下げない)。60 日より古いものは捨てる
pub fn record(log: &mut StandLog, day: &str, t: &Transition) {
    let entry = log.entry(day.to_string()).or_default();
    entry.stand_seconds = (entry.stand_seconds + t.stand_seconds).max(0);
    entry.switches = (i64::from(entry.switches) + i64::from(t.switches)).max(0) as u32;
    while log.len() > 60 {
        let oldest = log.keys().next().cloned();
        match oldest {
            Some(key) => log.remove(&key),
            None => break,
        };
    }
}

pub fn today(log: &StandLog, day: &str) -> DayStand {
    log.get(day).copied().unwrap_or_default()
}

/// 「1 小时 30 分」「25 分钟」
fn time_text(minutes: i64) -> String {
    match (minutes / 60, minutes % 60) {
        (0, m) => format!("{m} 分钟"),
        (h, 0) => format!("{h} 小时"),
        (h, m) => format!("{h} 小时 {m} 分"),
    }
}

/// 「今天站了 1 小时 30 分，换了 3 次姿势」。まだなら「今天还没站过」
pub fn summary(d: DayStand) -> String {
    let minutes = d.stand_seconds / 60;
    if minutes == 0 && d.switches == 0 {
        return "今天还没站过".to_string();
    }
    format!(
        "今天站了 {}，换了 {} 次姿势",
        time_text(minutes),
        d.switches
    )
}

/// 細い帯に入る短い形:「站了 1 小时 30 分 · 换了 3 次」。まだなら「还没站过」
pub fn short_summary(d: DayStand) -> String {
    let minutes = d.stand_seconds / 60;
    if minutes == 0 && d.switches == 0 {
        return "还没站过".to_string();
    }
    format!("站了 {} · 换了 {} 次", time_text(minutes), d.switches)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;
    use crate::posture::Posture;

    fn t(stand_seconds: i64, switches: i32) -> Transition {
        Transition {
            to: Posture::Sitting,
            at: tokyo(2026, 10, 1, 12, 0, 0),
            stand_seconds,
            switches,
            revert: switches < 0,
        }
    }

    #[test]
    fn transitions_add_up_per_day_and_never_go_negative() {
        let mut log = StandLog::new();
        record(&mut log, "2026-10-01", &t(0, 1));
        record(&mut log, "2026-10-01", &t(1800, 1));
        record(&mut log, "2026-10-01", &t(-1800, -1));
        record(&mut log, "2026-10-01", &t(2700, 1));
        assert_eq!(
            today(&log, "2026-10-01"),
            DayStand {
                stand_seconds: 2700,
                switches: 2
            }
        );
        record(&mut log, "2026-10-02", &t(-99, -5));
        assert_eq!(today(&log, "2026-10-02"), DayStand::default());
        assert_eq!(today(&log, "2026-09-30"), DayStand::default());
        for day in 1..=30 {
            record(&mut log, &format!("2026-11-{day:02}"), &t(60, 1));
        }
        for day in 1..=31 {
            record(&mut log, &format!("2026-12-{day:02}"), &t(60, 1));
        }
        for day in 1..=28 {
            record(&mut log, &format!("2027-01-{day:02}"), &t(60, 1));
        }
        assert_eq!(log.len(), 60, "old days are dropped");
        assert!(!log.contains_key("2026-10-01"));
        assert!(log.contains_key("2027-01-28"));
    }

    #[test]
    fn summary_reads_naturally() {
        assert_eq!(summary(DayStand::default()), "今天还没站过");
        assert_eq!(
            summary(DayStand {
                stand_seconds: 59,
                switches: 0
            }),
            "今天还没站过"
        );
        assert_eq!(
            summary(DayStand {
                stand_seconds: 25 * 60 + 30,
                switches: 1
            }),
            "今天站了 25 分钟，换了 1 次姿势"
        );
        assert_eq!(
            summary(DayStand {
                stand_seconds: 3600,
                switches: 2
            }),
            "今天站了 1 小时，换了 2 次姿势"
        );
        assert_eq!(
            summary(DayStand {
                stand_seconds: 3 * 3600 + 40 * 60,
                switches: 7
            }),
            "今天站了 3 小时 40 分，换了 7 次姿势"
        );
        assert_eq!(
            summary(
                DayStand {
                    stand_seconds: 600,
                    switches: 1
                }
                .plus_open(300)
            ),
            "今天站了 15 分钟，换了 1 次姿势"
        );
        assert_eq!(short_summary(DayStand::default()), "还没站过");
        assert_eq!(
            short_summary(DayStand {
                stand_seconds: 3 * 3600 + 40 * 60,
                switches: 7
            }),
            "站了 3 小时 40 分 · 换了 7 次"
        );
    }
}
