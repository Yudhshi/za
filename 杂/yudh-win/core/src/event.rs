//! 同期の出来事 1 行(JSON)。Swift の `SyncEvent` と同じ書式:キーはアルファベット順、空の項目は書かない、
//! `at` は ISO 8601・UTC・ミリ秒付き(読むときはミリ秒なしも受ける)。壊れた行・知らない op は読み飛ばす

use chrono::{DateTime, SecondsFormat, Utc};
use serde_json::{Map, Value};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Op {
    /// 同期を始める前からあったカードの状態(Mac の移行時に 1 回だけ)
    Snapshot,
    /// 同期を始める前の答えた記録(Mac の移行時に 1 回だけ)
    Log,
    Rate,
    Known,
    Add,
    Restore,
    Undo,
}

impl Op {
    pub fn as_str(self) -> &'static str {
        match self {
            Op::Snapshot => "snapshot",
            Op::Log => "log",
            Op::Rate => "rate",
            Op::Known => "known",
            Op::Add => "add",
            Op::Restore => "restore",
            Op::Undo => "undo",
        }
    }

    pub fn parse(text: &str) -> Option<Op> {
        [
            Op::Snapshot,
            Op::Log,
            Op::Rate,
            Op::Known,
            Op::Add,
            Op::Restore,
            Op::Undo,
        ]
        .into_iter()
        .find(|op| op.as_str() == text)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct SyncEvent {
    pub id: String,
    pub device: String,
    pub at: DateTime<Utc>,
    pub op: Op,
    pub card: Option<String>,
    pub kind: Option<String>,
    pub rating: Option<String>,
    /// undo が取り消す出来事の id
    pub target: Option<String>,
    // snapshot の中身
    pub interval: Option<i64>,
    pub ease: Option<f64>,
    pub reps: Option<i64>,
    pub lapses: Option<i64>,
    pub due: Option<String>,
    pub known: Option<bool>,
    pub first_seen: Option<String>,
    // log の中身
    pub day: Option<String>,
    pub result: Option<String>,
}

/// 新しい出来事の id(UUID 小写)
pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string().to_lowercase()
}

/// "2026-10-01T01:00:05.000Z"
pub fn format_time(at: DateTime<Utc>) -> String {
    at.to_rfc3339_opts(SecondsFormat::Millis, true)
}

pub fn parse_time(text: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(text)
        .ok()
        .map(|t| t.with_timezone(&Utc))
}

impl SyncEvent {
    /// 中身が空の出来事(id は新しく振る)
    pub fn new(device: &str, at: DateTime<Utc>, op: Op) -> SyncEvent {
        SyncEvent {
            id: new_id(),
            device: device.to_string(),
            at,
            op,
            card: None,
            kind: None,
            rating: None,
            target: None,
            interval: None,
            ease: None,
            reps: None,
            lapses: None,
            due: None,
            known: None,
            first_seen: None,
            day: None,
            result: None,
        }
    }

    /// 1 行の JSON(キーはアルファベット順。serde_json の Map は既定で BTreeMap なので並びは固定)
    pub fn json_line(&self) -> String {
        let mut o = Map::new();
        o.insert("id".into(), Value::from(self.id.clone()));
        o.insert("device".into(), Value::from(self.device.clone()));
        o.insert("at".into(), Value::from(format_time(self.at)));
        o.insert("op".into(), Value::from(self.op.as_str()));
        let mut text = |key: &str, value: &Option<String>| {
            if let Some(v) = value {
                o.insert(key.into(), Value::from(v.clone()));
            }
        };
        text("card", &self.card);
        text("kind", &self.kind);
        text("rating", &self.rating);
        text("target", &self.target);
        text("due", &self.due);
        text("firstSeen", &self.first_seen);
        text("day", &self.day);
        text("result", &self.result);
        for (key, value) in [
            ("interval", self.interval),
            ("reps", self.reps),
            ("lapses", self.lapses),
        ] {
            if let Some(v) = value {
                o.insert(key.into(), Value::from(v));
            }
        }
        if let Some(v) = self.ease {
            o.insert("ease".into(), Value::from(v));
        }
        if let Some(v) = self.known {
            o.insert("known".into(), Value::from(v));
        }
        Value::Object(o).to_string()
    }

    /// 1 行を読む。壊れた行・知らない op は None(読み飛ばす)
    pub fn parse(line: &str) -> Option<SyncEvent> {
        let value: Value = serde_json::from_str(line).ok()?;
        let o = value.as_object()?;
        let id = o.get("id")?.as_str()?;
        if id.is_empty() {
            return None;
        }
        let device = o.get("device")?.as_str()?;
        let at = parse_time(o.get("at")?.as_str()?)?;
        let op = Op::parse(o.get("op")?.as_str()?)?;
        let text = |key: &str| o.get(key).and_then(Value::as_str).map(str::to_string);
        // 整数は 8 でも 8.0 でも読む(Swift 側と同じ)
        let int = |key: &str| {
            o.get(key)
                .and_then(|v| v.as_i64().or_else(|| v.as_f64().map(|f| f as i64)))
        };
        Some(SyncEvent {
            id: id.to_string(),
            device: device.to_string(),
            at,
            op,
            card: text("card"),
            kind: text("kind"),
            rating: text("rating"),
            target: text("target"),
            interval: int("interval"),
            ease: o.get("ease").and_then(Value::as_f64),
            reps: int("reps"),
            lapses: int("lapses"),
            due: text("due"),
            known: o.get("known").and_then(Value::as_bool),
            first_seen: text("firstSeen"),
            day: text("day"),
            result: text("result"),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;

    #[test]
    fn lines_round_trip_with_sorted_keys() {
        let mut e = SyncEvent::new("Mac Book", tokyo(2026, 10, 1, 10, 0, 5), Op::Rate);
        e.id = "abc".into();
        e.card = Some("vocab:x".into());
        e.kind = Some("vocab".into());
        e.rating = Some("good".into());
        let line = e.json_line();
        assert_eq!(
            line,
            r#"{"at":"2026-10-01T01:00:05.000Z","card":"vocab:x","device":"Mac Book","id":"abc","kind":"vocab","op":"rate","rating":"good"}"#
        );
        assert_eq!(SyncEvent::parse(&line), Some(e));

        let mut s = SyncEvent::new("history", tokyo(2026, 9, 1, 0, 0, 0), Op::Snapshot);
        s.id = "s1".into();
        s.card = Some("vocab:y".into());
        s.kind = Some("vocab".into());
        s.interval = Some(8);
        s.ease = Some(2.36);
        s.reps = Some(3);
        s.lapses = Some(1);
        s.due = Some("2026-09-09".into());
        s.known = Some(false);
        s.first_seen = Some("2026-08-20".into());
        assert_eq!(SyncEvent::parse(&s.json_line()), Some(s));
    }

    #[test]
    fn mac_lines_are_read_and_garbage_is_skipped() {
        // Mac(JSONSerialization)が書いた行:ミリ秒なし・ease が整数・スラッシュ入りの id
        let line = r#"{"at":"2026-10-01T01:00:00Z","card":"para:listening:have to","device":"MacBook","ease":2,"id":"x/1","interval":3.0,"kind":"para","op":"snapshot"}"#;
        let e = SyncEvent::parse(line).expect("parses");
        assert_eq!(e.ease, Some(2.0));
        assert_eq!(e.interval, Some(3));
        assert_eq!(e.card.as_deref(), Some("para:listening:have to"));
        assert!(SyncEvent::parse("not json").is_none());
        assert!(SyncEvent::parse(
            r#"{"id":"x","device":"a","at":"2026-10-01T01:00:00Z","op":"dance"}"#
        )
        .is_none());
        assert!(SyncEvent::parse(
            r#"{"id":"","device":"a","at":"2026-10-01T01:00:00Z","op":"rate"}"#
        )
        .is_none());
        // スラッシュはエスケープしない、日本語・中国語はそのまま
        let mut u = SyncEvent::new("デスクトップ", tokyo(2026, 10, 1, 9, 0, 0), Op::Add);
        u.card = Some("dict:a/b".into());
        assert!(u.json_line().contains("dict:a/b"));
        assert!(u.json_line().contains("デスクトップ"));
        let id = new_id();
        assert_eq!(id.len(), 36);
        assert_eq!(id, id.to_lowercase(), "ids are lowercase");
        assert_ne!(id, new_id(), "ids are unique");
    }
}
