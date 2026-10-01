//! Mac が同期フォルダに書く `agenda.json`(今日と明日の会議)を読む。Windows はカレンダーに触らない。
//! 書式は Mac の `AgendaExport.swift` / docs/sync-format.md。`days` に明日が無い = Mac がまだ更新していない
//! (空の配列 = 本当に会議が無い)とは区別する

use std::collections::HashMap;
use std::path::Path;

use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::Value;

use crate::day::{self, Zone};

pub const FILE_NAME: &str = "agenda.json";
pub const VERSION: i64 = 1;

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Entry {
    pub id: String,
    pub title: String,
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
    #[serde(rename = "allDay")]
    pub all_day: bool,
    pub join: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Agenda {
    pub device: String,
    pub generated_at: DateTime<Utc>,
    pub time_zone: String,
    pub days: HashMap<String, Vec<Entry>>,
}

/// 明日の会議の見え方
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(tag = "state", content = "meetings", rename_all = "camelCase")]
pub enum Tomorrow {
    /// agenda.json が無い・読めない(同期フォルダ未設定、Mac 側で書き出しが切ってある)
    NoFile,
    /// ファイルはあるが明日の分が無い(Mac がまだ更新していない)
    NotSynced,
    /// 明日は会議なし
    Empty,
    /// 全日の予定を除いた、始まる順の会議
    Meetings(Vec<Entry>),
}

fn time(value: Option<&Value>) -> Option<DateTime<Utc>> {
    crate::event::parse_time(value?.as_str()?)
}

pub fn parse(text: &str) -> Option<Agenda> {
    let value: Value = serde_json::from_str(text).ok()?;
    let o = value.as_object()?;
    if o.get("version")?.as_i64()? != VERSION {
        return None;
    }
    let generated_at = time(o.get("generatedAt"))?;
    let mut days = HashMap::new();
    for day in o.get("days")?.as_array()? {
        let Some(key) = day.get("day").and_then(Value::as_str) else {
            continue;
        };
        let entries = day
            .get("events")
            .and_then(Value::as_array)
            .map(|events| {
                events
                    .iter()
                    .filter_map(|e| {
                        Some(Entry {
                            id: e.get("id")?.as_str()?.to_string(),
                            title: e.get("title")?.as_str()?.to_string(),
                            start: time(e.get("start"))?,
                            end: time(e.get("end"))?,
                            all_day: e.get("allDay").and_then(Value::as_bool).unwrap_or(false),
                            join: e.get("join").and_then(Value::as_str).map(str::to_string),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        days.insert(key.to_string(), entries);
    }
    Some(Agenda {
        device: o
            .get("device")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        generated_at,
        time_zone: o
            .get("timeZone")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        days,
    })
}

pub fn load(sync_root: &Path) -> Option<Agenda> {
    parse(&std::fs::read_to_string(sync_root.join(FILE_NAME)).ok()?)
}

impl Agenda {
    /// 本機の日付 + 1 日の会議(全日の予定は除く)
    pub fn tomorrow(&self, now: DateTime<Utc>, zone: Zone) -> Tomorrow {
        let key = day::key(day::add_days(zone.date(now), 1));
        match self.days.get(&key) {
            None => Tomorrow::NotSynced,
            Some(entries) => {
                let mut meetings: Vec<Entry> =
                    entries.iter().filter(|e| !e.all_day).cloned().collect();
                meetings.sort_by_key(|e| e.start);
                if meetings.is_empty() {
                    Tomorrow::Empty
                } else {
                    Tomorrow::Meetings(meetings)
                }
            }
        }
    }
}

/// 同期フォルダの agenda.json から明日を読む
pub fn tomorrow(sync_root: &Path, now: DateTime<Utc>, zone: Zone) -> Tomorrow {
    load(sync_root).map_or(Tomorrow::NoFile, |a| a.tomorrow(now, zone))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;

    /// Mac(AgendaExport.render)が書く形そのまま(JSONSerialization の prettyPrinted)
    const MAC: &str = r#"{
  "days" : [
    {
      "day" : "2026-10-01",
      "events" : [

      ]
    },
    {
      "day" : "2026-10-02",
      "events" : [
        {
          "allDay" : true,
          "end" : "2026-10-02T15:00:00Z",
          "id" : "e0",
          "start" : "2026-10-01T15:00:00Z",
          "title" : "全社休み"
        },
        {
          "allDay" : false,
          "end" : "2026-10-02T01:15:00Z",
          "id" : "e2",
          "join" : "https://meet.google.com/abc-defg-hij",
          "start" : "2026-10-02T01:00:00Z",
          "title" : "朝会"
        },
        {
          "allDay" : false,
          "end" : "2026-10-02T01:00:00Z",
          "id" : "e1",
          "start" : "2026-10-02T00:30:00Z",
          "title" : "デザインレビュー"
        }
      ]
    }
  ],
  "device" : "MacBook",
  "generatedAt" : "2026-10-01T12:00:00Z",
  "timeZone" : "Asia/Tokyo",
  "version" : 1
}
"#;

    #[test]
    fn reads_the_mac_file_and_tells_tomorrow_apart() {
        let agenda = parse(MAC).expect("parses");
        assert_eq!(agenda.device, "MacBook");
        assert_eq!(agenda.time_zone, "Asia/Tokyo");
        assert_eq!(agenda.days["2026-10-01"], vec![]);
        let z = Zone::tokyo();
        // 10/1 の夜:明日 = 10/2。全日の予定を除き、始まる順
        match agenda.tomorrow(tokyo(2026, 10, 1, 21, 0, 0), z) {
            Tomorrow::Meetings(m) => {
                let ids: Vec<&str> = m.iter().map(|e| e.id.as_str()).collect();
                assert_eq!(ids, vec!["e1", "e2"]);
                assert_eq!(
                    m[1].join.as_deref(),
                    Some("https://meet.google.com/abc-defg-hij")
                );
            }
            other => panic!("expected meetings, got {other:?}"),
        }
        // 9/30:明日 = 10/1 は空 = 会議なし
        assert_eq!(
            agenda.tomorrow(tokyo(2026, 9, 30, 21, 0, 0), z),
            Tomorrow::Empty
        );
        // 10/2:明日 = 10/3 はファイルに無い = Mac がまだ
        assert_eq!(
            agenda.tomorrow(tokyo(2026, 10, 2, 8, 0, 0), z),
            Tomorrow::NotSynced
        );
        assert!(parse(r#"{"version":2,"generatedAt":"2026-10-01T12:00:00Z","days":[]}"#).is_none());
        assert!(parse("not json").is_none());
        let missing = std::env::temp_dir().join(format!("yudh-agenda-{}", crate::event::new_id()));
        assert_eq!(
            tomorrow(&missing, tokyo(2026, 10, 1, 21, 0, 0), z),
            Tomorrow::NoFile
        );
    }
}
