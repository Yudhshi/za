//! 出来事を再生して作る、英語の状態(カードと答えた記録)。Swift の `EnglishStore.replay` / `apply` と同じ規則。
//! 1. id で重複を除く 2. undo の target を除き、undo 自身も再生しない 3. 残りを (at, id) の昇順で頭から当てる

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::day::{self, Zone};
use crate::event::{Op, SyncEvent};
use crate::srs::{Rating, SrsState};

/// カードの種類(カード id の頭にも付く:vocab:b1-0807 / dict:abundant / para:listening:reserve / spell:insurance)
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Vocab,
    Para,
    Spell,
}

impl Kind {
    pub const ALL: [Kind; 3] = [Kind::Vocab, Kind::Para, Kind::Spell];

    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Vocab => "vocab",
            Kind::Para => "para",
            Kind::Spell => "spell",
        }
    }

    pub fn parse(text: &str) -> Option<Kind> {
        Kind::ALL.into_iter().find(|k| k.as_str() == text)
    }
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Card {
    pub id: String,
    pub kind: Kind,
    pub state: SrsState,
    /// 次の復習日("yyyy-MM-dd")
    pub due: String,
    /// 「知ってる」で出題から外した
    pub known: bool,
    /// 初めて出た日(今日の新規枠に使う)。一度決まったら変えない
    pub first_seen: String,
    /// 最後に変わった時刻(期限の来たカードの並び:due → これ)
    pub updated_at: DateTime<Utc>,
}

/// 答えた記録 1 行
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct LogEntry {
    pub day: String,
    pub kind: Kind,
    /// again / hard / good / easy / known
    pub result: String,
    pub at: DateTime<Utc>,
}

#[derive(Clone, Debug, Default)]
pub struct EnglishState {
    pub cards: HashMap<String, Card>,
    /// 書いた順(Swift の english_log の行番号の順)
    pub log: Vec<LogEntry>,
    /// 取り消されていない rate の評分(カードごと、古い順)。卡の复习记录
    pub ratings: HashMap<String, Vec<Rating>>,
}

/// 再生の順番に並べた、効いている出来事(取り消し済みと undo を除く)
pub fn effective(events: &[SyncEvent]) -> Vec<&SyncEvent> {
    let mut seen = HashSet::new();
    let unique: Vec<&SyncEvent> = events
        .iter()
        .filter(|e| seen.insert(e.id.as_str()))
        .collect();
    let undone: HashSet<&str> = unique
        .iter()
        .filter(|e| e.op == Op::Undo)
        .filter_map(|e| e.target.as_deref())
        .collect();
    let mut ordered: Vec<&SyncEvent> = unique
        .into_iter()
        .filter(|e| e.op != Op::Undo && !undone.contains(e.id.as_str()))
        .collect();
    ordered.sort_by(|a, b| (a.at, a.id.as_str()).cmp(&(b.at, b.id.as_str())));
    ordered
}

pub fn replay(events: &[SyncEvent], zone: Zone) -> EnglishState {
    let mut state = EnglishState::default();
    for e in effective(events) {
        state.apply(e, zone);
    }
    state
}

impl EnglishState {
    /// 保存(Swift の INSERT … ON CONFLICT と同じく、あるカードの kind と firstSeen は変えない)
    fn save(&mut self, mut card: Card) {
        if let Some(old) = self.cards.get(&card.id) {
            card.kind = old.kind;
            card.first_seen = old.first_seen.clone();
        }
        self.cards.insert(card.id.clone(), card);
    }

    fn write_log(&mut self, kind: Kind, result: &str, day: String, at: DateTime<Utc>) {
        self.log.push(LogEntry {
            day,
            kind,
            result: result.to_string(),
            at,
        });
    }

    fn fresh(id: &str, kind: Kind, day: &str, known: bool, at: DateTime<Utc>) -> Card {
        Card {
            id: id.to_string(),
            kind,
            state: SrsState::default(),
            due: day.to_string(),
            known,
            first_seen: day.to_string(),
            updated_at: at,
        }
    }

    /// 1 つの出来事を当てる(時刻は出来事のもの)
    pub fn apply(&mut self, e: &SyncEvent, zone: Zone) {
        let day = zone.key(e.at);
        let kind = e.kind.as_deref().and_then(Kind::parse);
        match e.op {
            Op::Snapshot => {
                let (Some(id), Some(kind)) = (e.card.as_deref(), kind) else {
                    return;
                };
                self.save(Card {
                    id: id.to_string(),
                    kind,
                    state: SrsState {
                        interval: e.interval.unwrap_or(0),
                        ease: e.ease.unwrap_or(2.5),
                        reps: e.reps.unwrap_or(0),
                        lapses: e.lapses.unwrap_or(0),
                    },
                    due: e.due.clone().unwrap_or_else(|| day.clone()),
                    known: e.known.unwrap_or(false),
                    first_seen: e.first_seen.clone().unwrap_or_else(|| day.clone()),
                    updated_at: e.at,
                });
            }
            Op::Log => {
                let (Some(kind), Some(result)) = (kind, e.result.as_deref()) else {
                    return;
                };
                let log_day = e.day.clone().unwrap_or(day);
                self.write_log(kind, result, log_day, e.at);
            }
            Op::Rate => {
                let (Some(id), Some(kind), Some(rating)) = (
                    e.card.as_deref(),
                    kind,
                    e.rating.as_deref().and_then(Rating::parse),
                ) else {
                    return;
                };
                let mut card = self
                    .cards
                    .get(id)
                    .cloned()
                    .unwrap_or_else(|| Self::fresh(id, kind, &day, false, e.at));
                card.state = card.state.applying(rating);
                card.due = zone.key_after(e.at, card.state.interval);
                card.updated_at = e.at;
                self.save(card);
                self.write_log(kind, rating.as_str(), day, e.at);
                self.ratings.entry(id.to_string()).or_default().push(rating);
            }
            Op::Known => {
                let (Some(id), Some(kind)) = (e.card.as_deref(), kind) else {
                    return;
                };
                let mut card = self
                    .cards
                    .get(id)
                    .cloned()
                    .unwrap_or_else(|| Self::fresh(id, kind, &day, true, e.at));
                card.known = true;
                card.updated_at = e.at;
                self.save(card);
                self.write_log(kind, "known", day, e.at);
            }
            Op::Add => {
                let (Some(id), Some(kind)) = (e.card.as_deref(), kind) else {
                    return;
                };
                if !self.cards.contains_key(id) {
                    self.save(Self::fresh(id, kind, &day, false, e.at));
                }
            }
            Op::Restore => {
                let Some(mut card) = e.card.as_deref().and_then(|id| self.cards.get(id)).cloned()
                else {
                    return;
                };
                card.known = false;
                card.due = day;
                card.updated_at = e.at;
                self.save(card);
            }
            Op::Undo => {}
        }
    }

    // MARK: 読む

    pub fn card(&self, id: &str) -> Option<&Card> {
        self.cards.get(id)
    }

    /// 期限の来たカード(古い順。「知ってる」は除く)
    pub fn due_ids(&self, kind: Kind, today: &str) -> Vec<String> {
        let mut due: Vec<&Card> = self
            .cards
            .values()
            .filter(|c| c.kind == kind && !c.known && c.due.as_str() <= today)
            .collect();
        due.sort_by(|a, b| {
            (a.due.as_str(), a.updated_at, a.id.as_str()).cmp(&(
                b.due.as_str(),
                b.updated_at,
                b.id.as_str(),
            ))
        });
        due.into_iter().map(|c| c.id.clone()).collect()
    }

    /// 一度でも出た(または「知ってる」にした)カード
    pub fn seen_ids(&self, kind: Kind) -> HashSet<String> {
        self.cards
            .values()
            .filter(|c| c.kind == kind)
            .map(|c| c.id.clone())
            .collect()
    }

    /// その日に初めて出したカードの数(新規枠)。辞書から足した語は数えない
    pub fn new_count(&self, kind: Kind, day: &str) -> usize {
        self.cards
            .values()
            .filter(|c| c.kind == kind && c.first_seen == day && !c.id.starts_with("dict:"))
            .count()
    }

    /// その日に答えた数(「知ってる」も 1 問)
    pub fn answered_count(&self, day: &str) -> usize {
        self.log.iter().filter(|l| l.day == day).count()
    }

    /// その日に答えた結果(答えた順)。本轮の盤面
    pub fn results(&self, day: &str) -> Vec<String> {
        let mut rows: Vec<(usize, &LogEntry)> = self
            .log
            .iter()
            .enumerate()
            .filter(|(_, l)| l.day == day)
            .collect();
        rows.sort_by_key(|a| (a.1.at, a.0));
        rows.into_iter().map(|(_, l)| l.result.clone()).collect()
    }

    /// そのカードの評分の履歴(古い順。取り消した分は除く)
    pub fn ratings(&self, id: &str) -> Vec<Rating> {
        self.ratings.get(id).cloned().unwrap_or_default()
    }

    /// その種類のカード全部(一覧用。復習日の近い順、同じ日は id 順)
    pub fn cards_of(&self, kind: Kind) -> Vec<&Card> {
        let mut cards: Vec<&Card> = self.cards.values().filter(|c| c.kind == kind).collect();
        cards.sort_by(|a, b| (a.due.as_str(), a.id.as_str()).cmp(&(b.due.as_str(), b.id.as_str())));
        cards
    }

    /// 連続日数(今日まだなら昨日までで数える)
    pub fn streak(&self, today: &str) -> usize {
        let days: HashSet<&str> = self.log.iter().map(|l| l.day.as_str()).collect();
        let Some(mut date) = day::parse_key(today) else {
            return 0;
        };
        if !days.contains(day::key(date).as_str()) {
            date = day::add_days(date, -1);
        }
        let mut count = 0;
        while days.contains(day::key(date).as_str()) {
            count += 1;
            date = day::add_days(date, -1);
        }
        count
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;

    fn ev(op: Op, id: &str, at: DateTime<Utc>, card: &str, kind: &str) -> SyncEvent {
        let mut e = SyncEvent::new("A", at, op);
        e.id = id.to_string();
        e.card = Some(card.to_string());
        e.kind = Some(kind.to_string());
        e
    }

    fn rate(id: &str, at: DateTime<Utc>, card: &str, kind: &str, rating: Rating) -> SyncEvent {
        let mut e = ev(Op::Rate, id, at, card, kind);
        e.rating = Some(rating.as_str().into());
        e
    }

    #[test]
    fn schedules_due_list_known_quota_counts_streak() {
        // Swift: store: schedules, due list, known, quota, counts, streak
        let z = Zone::tokyo();
        let day1 = tokyo(2026, 10, 1, 10, 0, 0);
        let events = vec![
            rate("1", day1, "vocab:b1-1", "vocab", Rating::Good),
            rate("2", day1, "vocab:b1-2", "vocab", Rating::Again),
            ev(Op::Known, "3", day1, "vocab:b1-3", "vocab"),
            ev(Op::Add, "4", day1, "dict:abundant", "vocab"),
            ev(Op::Add, "5", day1, "dict:abundant", "vocab"),
            rate(
                "6",
                tokyo(2026, 10, 2, 9, 0, 0),
                "spell:town",
                "spell",
                Rating::Good,
            ),
        ];
        let s = replay(&events, z);
        assert_eq!(s.card("vocab:b1-1").unwrap().due, "2026-10-02");
        // dict:abundant は追加した日が期限。同じ期限・同じ時刻なら id 順
        assert_eq!(
            s.due_ids(Kind::Vocab, "2026-10-01"),
            vec!["dict:abundant", "vocab:b1-2"]
        );
        assert_eq!(s.due_ids(Kind::Vocab, "2026-10-02").len(), 3);
        assert!(!s
            .due_ids(Kind::Vocab, "2026-12-31")
            .contains(&"vocab:b1-3".to_string()));
        assert_eq!(s.seen_ids(Kind::Vocab).len(), 4);
        assert_eq!(
            s.new_count(Kind::Vocab, "2026-10-01"),
            3,
            "dictionary adds don't use the quota"
        );
        assert_eq!(s.new_count(Kind::Spell, "2026-10-01"), 0);
        assert_eq!(s.answered_count("2026-10-01"), 3);
        assert_eq!(s.results("2026-10-01"), vec!["good", "again", "known"]);
        assert_eq!(s.streak("2026-10-02"), 2);
        assert_eq!(
            s.streak("2026-10-03"),
            2,
            "today not started yet: count up to yesterday"
        );
        assert_eq!(s.streak("2026-10-05"), 0);
    }

    #[test]
    fn undo_restore_and_ordering() {
        let z = Zone::tokyo();
        let now = tokyo(2026, 10, 1, 10, 0, 0);
        // 初めてのカードの答えを取り消すと、カードも記録も消える
        let mut events = vec![rate("r1", now, "vocab:a", "vocab", Rating::Good)];
        let mut undo = SyncEvent::new("A", now, Op::Undo);
        undo.card = Some("vocab:a".into());
        undo.target = Some("r1".into());
        events.push(undo);
        let s = replay(&events, z);
        assert!(s.card("vocab:a").is_none());
        assert_eq!(s.answered_count("2026-10-01"), 0);
        assert!(s.ratings("vocab:a").is_empty());

        // 2 回目の答えを取り消すと、1 回目のあとの状態に戻る
        events.push(rate("r2", now, "vocab:a", "vocab", Rating::Good));
        events.push(rate("r3", now, "vocab:a", "vocab", Rating::Again));
        let mut undo3 = SyncEvent::new("A", now, Op::Undo);
        undo3.target = Some("r3".into());
        events.push(undo3);
        let s = replay(&events, z);
        assert_eq!(s.card("vocab:a").unwrap().due, "2026-10-02");
        assert_eq!(s.card("vocab:a").unwrap().state.reps, 1);
        assert_eq!(s.answered_count("2026-10-01"), 1);
        assert_eq!(s.ratings("vocab:a"), vec![Rating::Good]);

        // 「知ってる」を戻すと今日の復習に並ぶ
        events.push(ev(Op::Known, "k", now, "vocab:b", "vocab"));
        let s = replay(&events, z);
        assert!(!s
            .due_ids(Kind::Vocab, "2026-10-01")
            .contains(&"vocab:b".to_string()));
        events.push(ev(Op::Restore, "x", now, "vocab:b", "vocab"));
        let s = replay(&events, z);
        assert!(s
            .due_ids(Kind::Vocab, "2026-10-01")
            .contains(&"vocab:b".to_string()));
        let ids: Vec<&str> = s
            .cards_of(Kind::Vocab)
            .iter()
            .map(|c| c.id.as_str())
            .collect();
        assert_eq!(ids, vec!["vocab:b", "vocab:a"], "ordered by due");
        assert!(s.cards_of(Kind::Spell).is_empty());
    }

    #[test]
    fn snapshot_and_log_from_the_mac_history() {
        let z = Zone::tokyo();
        let mut snap = ev(
            Op::Snapshot,
            "s",
            tokyo(2026, 9, 1, 0, 0, 0),
            "vocab:y",
            "vocab",
        );
        snap.interval = Some(8);
        snap.ease = Some(2.36);
        snap.reps = Some(3);
        snap.lapses = Some(1);
        snap.due = Some("2026-09-09".into());
        snap.first_seen = Some("2026-08-20".into());
        let mut log = SyncEvent::new("history", tokyo(2026, 8, 31, 23, 0, 0), Op::Log);
        log.id = "l".into();
        log.kind = Some("vocab".into());
        log.day = Some("2026-08-31".into());
        log.result = Some("good".into());
        // 新しい rate はスナップショットの続きから
        let r = rate(
            "r",
            tokyo(2026, 9, 9, 8, 0, 0),
            "vocab:y",
            "vocab",
            Rating::Good,
        );
        let s = replay(&[r, snap, log], z);
        let card = s.card("vocab:y").unwrap();
        assert_eq!(card.state.interval, 19, "8 × 2.36 rounded");
        assert_eq!(card.first_seen, "2026-08-20", "firstSeen is kept");
        assert_eq!(card.due, "2026-09-28");
        assert_eq!(s.answered_count("2026-08-31"), 1);
        assert_eq!(s.results("2026-09-09"), vec!["good"]);
    }

    #[test]
    fn duplicates_and_same_time_order_by_id() {
        let z = Zone::tokyo();
        let t = tokyo(2026, 10, 1, 10, 0, 0);
        let a = rate("b", t, "vocab:x", "vocab", Rating::Again);
        let b = rate("a", t, "vocab:x", "vocab", Rating::Good);
        // 同時刻は id 順:a(good)→ b(again)。同じ id の重複は 1 回だけ
        let s = replay(&[a.clone(), b.clone(), a], z);
        assert_eq!(s.ratings("vocab:x"), vec![Rating::Good, Rating::Again]);
        assert_eq!(s.card("vocab:x").unwrap().state.lapses, 1);
        assert_eq!(s.answered_count("2026-10-01"), 2);
    }
}
