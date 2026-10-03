//! 一日に立った時間と姿勢を変えた回数(「今天站了 1 小时 30 分，换了 3 次姿势」)。
//! 钟の切り替わり(`posture::Transition`)を日ごとに足すだけ。設定ファイルに残す(60 日)。
//! 播报の钟なので「計画どおりにした」数字:本当に立ったかは聞かない

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::posture::{Mark, MarkKind, Transition};

/// 胶带(一日の時間軸)の印:この時刻からこの状態(UNIX ミリ秒)
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DayMark {
    pub at: i64,
    pub kind: MarkKind,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DayStand {
    pub stand_seconds: i64,
    pub switches: u32,
    /// 胶带の印(時刻順)
    pub marks: Vec<DayMark>,
}

/// 一日の印はこれより増やさない(30 秒ごとの判定が暴走しても設定ファイルが膨らまないように)
const MARKS_PER_DAY: usize = 400;

impl DayStand {
    /// いま立っている分(まだ切り替わっていない)を足したもの
    pub fn plus_open(mut self, open_seconds: i64) -> DayStand {
        self.stand_seconds += open_seconds.max(0);
        self
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
    log.get(day).cloned().unwrap_or_default()
}

/// 胶带の印を足す(同じ時刻・同じ種類が続けば 1 つに)。60 日より古いものは捨てる
pub fn record_mark(log: &mut StandLog, day: &str, mark: &Mark) {
    let entry = log.entry(day.to_string()).or_default();
    let at = mark.at.timestamp_millis();
    if let Some(last) = entry.marks.last_mut() {
        if last.kind == mark.kind && (at - last.at).abs() < 1000 {
            return;
        }
        if (at - last.at).abs() < 1000 {
            last.kind = mark.kind;
            return;
        }
    }
    if entry.marks.len() >= MARKS_PER_DAY {
        return;
    }
    entry.marks.push(DayMark {
        at,
        kind: mark.kind,
    });
    while log.len() > 60 {
        let oldest = log.keys().next().cloned();
        match oldest {
            Some(key) => log.remove(&key),
            None => break,
        };
    }
}

/// 「1 小时 30 分」「25 分钟」
pub fn minutes_text(minutes: i64) -> String {
    time_text(minutes)
}

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
                switches: 2,
                marks: vec![]
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
        let d = |stand_seconds: i64, switches: u32| DayStand {
            stand_seconds,
            switches,
            marks: vec![],
        };
        assert_eq!(summary(d(59, 0)), "今天还没站过");
        assert_eq!(
            summary(d(25 * 60 + 30, 1)),
            "今天站了 25 分钟，换了 1 次姿势"
        );
        assert_eq!(summary(d(3600, 2)), "今天站了 1 小时，换了 2 次姿势");
        assert_eq!(
            summary(d(3 * 3600 + 40 * 60, 7)),
            "今天站了 3 小时 40 分，换了 7 次姿势"
        );
        assert_eq!(
            summary(d(600, 1).plus_open(300)),
            "今天站了 15 分钟，换了 1 次姿势"
        );
        assert_eq!(short_summary(DayStand::default()), "还没站过");
        assert_eq!(
            short_summary(d(3 * 3600 + 40 * 60, 7)),
            "站了 3 小时 40 分 · 换了 7 次"
        );
    }

    #[test]
    fn marks_are_kept_in_order_and_merged_when_they_coincide() {
        let mut log = StandLog::new();
        let t = tokyo(2026, 10, 1, 10, 0, 0);
        let m = |kind, secs: i64| Mark {
            at: t + chrono::Duration::seconds(secs),
            kind,
        };
        record_mark(&mut log, "2026-10-01", &m(MarkKind::Sit, 0));
        record_mark(&mut log, "2026-10-01", &m(MarkKind::Stand, 1800));
        // 同じ時刻の印は後のものが勝つ(ゲームの終わりと切り替えが同じ tick)
        record_mark(&mut log, "2026-10-01", &m(MarkKind::Game, 3600));
        record_mark(&mut log, "2026-10-01", &m(MarkKind::Sit, 3600));
        record_mark(&mut log, "2026-10-01", &m(MarkKind::Sit, 3600));
        let day = today(&log, "2026-10-01");
        let kinds: Vec<MarkKind> = day.marks.iter().map(|x| x.kind).collect();
        assert_eq!(kinds, vec![MarkKind::Sit, MarkKind::Stand, MarkKind::Sit]);
        assert_eq!(
            day.marks[1].at,
            (t + chrono::Duration::seconds(1800)).timestamp_millis()
        );
        for i in 0..500 {
            record_mark(&mut log, "2026-10-01", &m(MarkKind::Away, 4000 + i * 2));
        }
        assert!(today(&log, "2026-10-01").marks.len() <= 400);
    }
}
