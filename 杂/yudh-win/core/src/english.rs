//! 英語の窓口(Tauri の命令がそのまま呼ぶ)。Mac の `EnglishCoordinator` の出題・記録・取り消し・数え方と同じ。
//! 自分の出来事はメモリと自分のファイルの両方に持ち、変わるたびにファイルを書き直す(ゲーム機は急に落ちることがある)。
//! ほかの端末の出来事は `reload` で読み直す(パネルを開いたときと 5 分ごと。常駐の監視はしない)

use std::collections::{HashMap, HashSet};
use std::io;
use std::path::Path;

use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::day::Zone;
use crate::event::{Op, SyncEvent};
use crate::library::{DictationWord, Library};
use crate::queue;
use crate::quiz::{self, Question, Rng};
use crate::replay::{self, EnglishState, Kind};
use crate::round::{self, RoundMark};
use crate::srs::Rating;
use crate::sync::SyncFolder;

/// 1 日の目標(問)
pub const DAILY_GOAL: usize = 20;

/// 1 日に新しく出す数(復習は別枠で全部出す)
pub fn new_limit(kind: Kind) -> usize {
    match kind {
        Kind::Vocab => 10,
        Kind::Para => 10,
        Kind::Spell => 15,
    }
}

/// 取り消しの控え:そのカードと、答える直前の自分の出来事の数
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct UndoPoint {
    pub card: String,
    pub own_len: usize,
}

/// 単語カードの表示内容(詞池の語か、辞書から足した語)
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct VocabCard {
    pub id: String,
    pub word: String,
    pub phonetic: Option<String>,
    pub pos: Option<String>,
    pub meaning: String,
    pub example: Option<String>,
    pub level: String,
    pub is_new: bool,
    pub known: bool,
}

/// 画面の上の数(今日の数・本轮の盤面・連続日数・種類ごとの残り)
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Stats {
    pub today: String,
    pub today_count: usize,
    pub goal: usize,
    pub results: Vec<String>,
    pub board: Vec<RoundMark>,
    pub streak: usize,
    pub remaining: HashMap<Kind, usize>,
}

pub struct English {
    pub folder: SyncFolder,
    pub zone: Zone,
    pub library: Library,
    /// 自分の出来事(起きた順。自分のファイルと同じ)
    own: Vec<SyncEvent>,
    /// ほかの端末の出来事
    others: Vec<SyncEvent>,
    state: EnglishState,
    pools: HashMap<Kind, Vec<String>>,
    vocab_index: HashMap<String, usize>,
    para_index: HashMap<String, usize>,
    spell_index: HashMap<String, usize>,
    /// いま答えたカード(「もう一回」がすぐ戻ってこないように)
    last_answered: HashMap<Kind, String>,
    /// 「再来 10 个」で今日だけ増やした新規枠
    extra_new: HashMap<Kind, usize>,
    extra_day: String,
}

impl English {
    /// 同期フォルダを開く:語表は `english-library/`、出来事は全員のファイル
    pub fn open(root: &Path, device: &str, zone: Zone) -> English {
        let folder = SyncFolder::new(root, device);
        let library = Library::load(&folder.library_dir());
        English::with_library(folder, zone, library)
    }

    pub fn with_library(folder: SyncFolder, zone: Zone, library: Library) -> English {
        let mut english = English {
            folder,
            zone,
            library: Library::default(),
            own: Vec::new(),
            others: Vec::new(),
            state: EnglishState::default(),
            pools: HashMap::new(),
            vocab_index: HashMap::new(),
            para_index: HashMap::new(),
            spell_index: HashMap::new(),
            last_answered: HashMap::new(),
            extra_new: HashMap::new(),
            extra_day: String::new(),
        };
        english.set_library(library);
        english.own = english.folder.own_events();
        english.reload();
        english
    }

    /// 語表を入れ替える(Mac が english-library を更新したとき)
    pub fn set_library(&mut self, library: Library) {
        let vocab: Vec<String> = library
            .vocab
            .iter()
            .map(|w| format!("vocab:{}", w.id))
            .collect();
        let para: Vec<String> = library
            .paraphrases
            .iter()
            .map(|p| format!("para:{}:{}", p.skill, p.w))
            .collect();
        let spell: Vec<String> = library
            .dictation
            .iter()
            .map(|d| format!("spell:{}", d.w.to_lowercase()))
            .collect();
        // 同じ id が 2 つあれば先のもの(Swift の uniquingKeysWith: first)
        fn index(ids: &[String]) -> HashMap<String, usize> {
            let mut map = HashMap::new();
            for (i, id) in ids.iter().enumerate() {
                map.entry(id.clone()).or_insert(i);
            }
            map
        }
        self.vocab_index = index(&vocab);
        self.para_index = index(&para);
        self.spell_index = index(&spell);
        self.pools = HashMap::from([
            (Kind::Vocab, vocab),
            (Kind::Para, para),
            (Kind::Spell, spell),
        ]);
        self.library = library;
    }

    /// ほかの端末のファイルを読み直して状態を作り直す。自分のファイルが欠けていれば書き直す。取り込んだ新しい数を返す
    pub fn reload(&mut self) -> usize {
        let own_ids: HashSet<&str> = self.own.iter().map(|e| e.id.as_str()).collect();
        let before: HashSet<String> = self.others.iter().map(|e| e.id.clone()).collect();
        let others: Vec<SyncEvent> = self
            .folder
            .all_events()
            .into_iter()
            .filter(|e| !own_ids.contains(e.id.as_str()))
            .collect();
        let fresh = others.iter().filter(|e| !before.contains(&e.id)).count();
        self.others = others;
        let _ = self.folder.write_own(&self.own);
        self.rebuild();
        fresh
    }

    /// 端末名を変える:新しい名前のファイルに自分の出来事を全部書く(古いファイルは残っても id で重複が消える)
    pub fn rename_device(&mut self, device: &str) -> io::Result<bool> {
        self.folder.device = device.to_string();
        self.folder.write_own(&self.own)
    }

    fn rebuild(&mut self) {
        let all: Vec<SyncEvent> = self.own.iter().chain(self.others.iter()).cloned().collect();
        self.state = replay::replay(&all, self.zone);
    }

    /// 自分の出来事を足して書き出す。書けなくてもメモリには残す(次に書くときにまとめて書く)
    fn push(&mut self, events: Vec<SyncEvent>) -> io::Result<()> {
        self.own.extend(events);
        self.rebuild();
        self.folder.write_own(&self.own).map(|_| ())
    }

    fn event(&self, at: DateTime<Utc>, op: Op, card: &str, kind: Option<Kind>) -> SyncEvent {
        let mut e = SyncEvent::new(&self.folder.device, at, op);
        e.card = Some(card.to_string());
        e.kind = kind.map(|k| k.as_str().to_string());
        e
    }

    pub fn state(&self) -> &EnglishState {
        &self.state
    }

    pub fn own_events(&self) -> &[SyncEvent] {
        &self.own
    }

    // MARK: 出題

    /// 取り込み直しで素材から消えたカードは出さない
    pub fn is_resolvable(&self, id: &str) -> bool {
        if self.vocab_index.contains_key(id)
            || self.para_index.contains_key(id)
            || self.spell_index.contains_key(id)
        {
            return true;
        }
        id.strip_prefix("dict:")
            .is_some_and(|word| self.library.lookup(word).is_some())
    }

    fn reset_extra_if_new_day(&mut self, today: &str) {
        if self.extra_day != today {
            self.extra_day = today.to_string();
            self.extra_new.clear();
        }
    }

    fn limit(&self, kind: Kind) -> usize {
        new_limit(kind) + self.extra_new.get(&kind).copied().unwrap_or(0)
    }

    /// 次のカードの id と、初めてかどうか
    pub fn next(&mut self, kind: Kind, now: DateTime<Utc>) -> Option<(String, bool)> {
        let today = self.zone.key(now);
        self.reset_extra_if_new_day(&today);
        let due: Vec<String> = self
            .state
            .due_ids(kind, &today)
            .into_iter()
            .filter(|id| self.is_resolvable(id))
            .collect();
        let seen = self.state.seen_ids(kind);
        let pool = self.pools.get(&kind).map(Vec::as_slice).unwrap_or(&[]);
        let id = queue::next(
            &due,
            pool,
            &seen,
            self.state.new_count(kind, &today),
            self.limit(kind),
            self.last_answered.get(&kind).map(String::as_str),
        )?;
        let is_new = !seen.contains(&id);
        Some((id, is_new))
    }

    /// 今日の分が終わったあと、新しいものをもう 10 問
    pub fn add_more_new(&mut self, kind: Kind, now: DateTime<Utc>) {
        let today = self.zone.key(now);
        self.reset_extra_if_new_day(&today);
        *self.extra_new.entry(kind).or_insert(0) += 10;
    }

    // MARK: 記録

    pub fn undo_point(&self, card: &str) -> UndoPoint {
        UndoPoint {
            card: card.to_string(),
            own_len: self.own.len(),
        }
    }

    /// 答えを記録する(初めてのカードなら作る)。取り消しの控えを返す
    pub fn rate(
        &mut self,
        id: &str,
        kind: Kind,
        rating: Rating,
        now: DateTime<Utc>,
    ) -> io::Result<UndoPoint> {
        let point = self.undo_point(id);
        let mut e = self.event(now, Op::Rate, id, Some(kind));
        e.rating = Some(rating.as_str().to_string());
        self.last_answered.insert(kind, id.to_string());
        self.push(vec![e])?;
        Ok(point)
    }

    /// 「知ってる」:もう出さない
    pub fn known(&mut self, id: &str, kind: Kind, now: DateTime<Utc>) -> io::Result<UndoPoint> {
        let point = self.undo_point(id);
        let e = self.event(now, Op::Known, id, Some(kind));
        self.last_answered.insert(kind, id.to_string());
        self.push(vec![e])?;
        Ok(point)
    }

    /// 辞書の語を単語カードに足す(あれば何もしないで false)
    pub fn add(&mut self, id: &str, kind: Kind, now: DateTime<Utc>) -> io::Result<bool> {
        if self.state.card(id).is_some() {
            return Ok(false);
        }
        let e = self.event(now, Op::Add, id, Some(kind));
        self.push(vec![e])?;
        Ok(true)
    }

    /// 「知ってる」にしたカードを出題に戻す(今日の復習に並ぶ)
    pub fn restore(&mut self, id: &str, now: DateTime<Utc>) -> io::Result<()> {
        let Some(kind) = self.state.card(id).map(|c| c.kind) else {
            return Ok(());
        };
        let e = self.event(now, Op::Restore, id, Some(kind));
        self.push(vec![e])
    }

    /// 元に戻す:そのカードについて、控えの後に自分が残した出来事を取り消す(Mac と同じ規則)
    pub fn undo(&mut self, point: &UndoPoint, now: DateTime<Utc>) -> io::Result<()> {
        let targets: Vec<String> = self
            .own
            .iter()
            .skip(point.own_len)
            .filter(|e| e.op != Op::Undo && e.card.as_deref() == Some(point.card.as_str()))
            .map(|e| e.id.clone())
            .collect();
        if targets.is_empty() {
            return Ok(());
        }
        let events: Vec<SyncEvent> = targets
            .into_iter()
            .map(|target| {
                let mut e = self.event(now, Op::Undo, &point.card, None);
                e.target = Some(target);
                e
            })
            .collect();
        self.last_answered.retain(|_, id| *id != point.card);
        self.push(events)
    }

    // MARK: 数

    pub fn stats(&self, now: DateTime<Utc>, pending: bool) -> Stats {
        let today = self.zone.key(now);
        let today_count = self.state.answered_count(&today);
        let results = self.state.results(&today);
        let mut remaining = HashMap::new();
        for kind in Kind::ALL {
            let due = self
                .state
                .due_ids(kind, &today)
                .into_iter()
                .filter(|id| self.is_resolvable(id))
                .count();
            let seen = self.state.seen_ids(kind);
            let unseen = self.pools.get(&kind).map_or(0, |pool| {
                pool.iter().filter(|id| !seen.contains(*id)).count()
            });
            let extra = if self.extra_day == today {
                self.extra_new.get(&kind).copied().unwrap_or(0)
            } else {
                0
            };
            remaining.insert(
                kind,
                queue::remaining(
                    due,
                    unseen,
                    self.state.new_count(kind, &today),
                    new_limit(kind) + extra,
                ),
            );
        }
        Stats {
            board: round::board(&results, today_count, DAILY_GOAL, pending),
            today,
            today_count,
            goal: DAILY_GOAL,
            results,
            streak: self.state.streak(&self.zone.key(now)),
            remaining,
        }
    }

    /// 卡の复习记录(最近の slots 回)
    pub fn history(&self, id: &str, answered: bool, slots: usize) -> Vec<RoundMark> {
        round::history(&self.state.ratings(id), answered, slots)
    }

    // MARK: 表示

    pub fn vocab_card(&self, id: &str, is_new: bool) -> Option<VocabCard> {
        let known = self.state.card(id).is_some_and(|c| c.known);
        if let Some(w) = self.vocab_index.get(id).map(|&i| &self.library.vocab[i]) {
            return Some(VocabCard {
                id: id.to_string(),
                word: w.w.clone(),
                phonetic: w.ph.clone(),
                pos: w.pos.clone(),
                meaning: w.zh.clone(),
                example: w.ex.clone(),
                level: w.lv.to_uppercase(),
                is_new,
                known,
            });
        }
        let hit = self.library.lookup(id.strip_prefix("dict:")?)?;
        Some(VocabCard {
            id: id.to_string(),
            word: hit.word,
            phonetic: Some(format!("/{}/", hit.ipa)),
            pos: None,
            meaning: hit.zh,
            example: None,
            level: "词典".into(),
            is_new: false,
            known,
        })
    }

    pub fn spell_word(&self, id: &str) -> Option<&DictationWord> {
        self.spell_index
            .get(id)
            .map(|&i| &self.library.dictation[i])
    }

    pub fn para_question(&self, id: &str, rng: &mut Rng) -> Option<Question> {
        let entry = self
            .para_index
            .get(id)
            .map(|&i| &self.library.paraphrases[i])?;
        quiz::make(entry, &self.library.paraphrases, rng)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;
    use crate::library::{ParaphraseEntry, VocabWord};

    fn temp_dir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("yudh-english-{}", crate::event::new_id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn library() -> Library {
        let mut lib = Library::default();
        for i in 1..=12 {
            lib.vocab.push(VocabWord {
                id: format!("b1-{i}"),
                w: format!("word{i}"),
                ph: None,
                pos: None,
                zh: format!("意思{i}"),
                ex: None,
                lv: "b1".into(),
            });
        }
        for (w, syn) in [
            ("reserve", "book"),
            ("adjust", "alter"),
            ("recognize", "identify"),
            ("resemble", "be similar to"),
        ] {
            lib.paraphrases.push(ParaphraseEntry {
                w: w.into(),
                pos: None,
                zh: None,
                syn: vec![syn.into()],
                skill: "listening".into(),
            });
        }
        lib.dictionary.insert(
            "abundant".into(),
            vec!["ә'bʌndәnt".into(), "a. 丰富的".into()],
        );
        lib
    }

    fn english(dir: &Path, device: &str) -> English {
        English::with_library(SyncFolder::new(dir, device), Zone::tokyo(), library())
    }

    #[test]
    fn new_cards_within_quota_then_due_reviews() {
        let dir = temp_dir();
        let mut e = english(&dir, "PC");
        let t = tokyo(2026, 10, 1, 21, 0, 0);
        let mut answered = Vec::new();
        while let Some((id, is_new)) = e.next(Kind::Vocab, t) {
            assert!(is_new);
            e.rate(&id, Kind::Vocab, Rating::Good, t).unwrap();
            answered.push(id);
        }
        assert_eq!(answered.len(), 10, "10 new words a day");
        assert_eq!(answered[0], "vocab:b1-1", "in library order");
        assert_eq!(e.stats(t, false).remaining[&Kind::Vocab], 0);
        e.add_more_new(Kind::Vocab, t);
        assert_eq!(
            e.stats(t, false).remaining[&Kind::Vocab],
            2,
            "only 2 unseen left"
        );
        // 次の日:昨日の 10 枚が復習に来る
        let t2 = tokyo(2026, 10, 2, 21, 0, 0);
        let stats = e.stats(t2, true);
        assert_eq!(stats.remaining[&Kind::Vocab], 12, "10 due + 2 new");
        assert_eq!(
            e.next(Kind::Vocab, t2).map(|n| n.1),
            Some(false),
            "reviews first"
        );
        assert_eq!(stats.streak, 1);
        assert_eq!(stats.board.first(), Some(&RoundMark::Current));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn mac_and_pc_converge_and_undo_follows_the_rules() {
        let dir = temp_dir();
        let t = tokyo(2026, 10, 1, 21, 0, 0);
        let mut mac = english(&dir, "MacBook");
        let mut pc = english(&dir, "DESKTOP-9F2");
        mac.rate("vocab:b1-1", Kind::Vocab, Rating::Good, t)
            .unwrap();
        mac.known("vocab:b1-2", Kind::Vocab, t + chrono::Duration::seconds(60))
            .unwrap();
        assert!(mac
            .add(
                "dict:abundant",
                Kind::Vocab,
                t + chrono::Duration::seconds(120)
            )
            .unwrap());
        assert!(
            !mac.add("dict:abundant", Kind::Vocab, t).unwrap(),
            "added once"
        );
        assert_eq!(pc.reload(), 3, "PC imports the Mac's three events");
        assert_eq!(pc.stats(t, false).today_count, 2);

        // PC で答えて、取り消す(1 回目は消え、カードも無くなる)
        let point = pc
            .rate("vocab:b1-3", Kind::Vocab, Rating::Again, t)
            .unwrap();
        assert_eq!(pc.state().card("vocab:b1-3").unwrap().state.lapses, 1);
        pc.undo(&point, t).unwrap();
        assert!(pc.state().card("vocab:b1-3").is_none());
        // 2 回目の取り消しは 1 回目のあとへ戻る
        pc.rate("vocab:b1-3", Kind::Vocab, Rating::Good, t).unwrap();
        let point = pc
            .rate(
                "vocab:b1-3",
                Kind::Vocab,
                Rating::Again,
                t + chrono::Duration::seconds(5),
            )
            .unwrap();
        pc.undo(&point, t).unwrap();
        assert_eq!(pc.state().card("vocab:b1-3").unwrap().state.reps, 1);
        assert_eq!(pc.history("vocab:b1-3", true, 5), vec![RoundMark::Good]);

        // Mac が読み直すと、同じ状態になる
        mac.reload();
        for id in ["vocab:b1-1", "vocab:b1-2", "vocab:b1-3", "dict:abundant"] {
            assert_eq!(mac.state().card(id), pc.state().card(id), "{id}");
        }
        assert_eq!(mac.stats(t, false), pc.stats(t, false));
        assert!(dir.join("english-events-DESKTOP-9F2.jsonl").exists());

        // 「知ってる」を戻すと今日の復習に並ぶ(Mac が「知ってる」にした後の時刻で)
        pc.restore("vocab:b1-2", t + chrono::Duration::minutes(10))
            .unwrap();
        assert!(pc
            .state()
            .due_ids(Kind::Vocab, "2026-10-01")
            .contains(&"vocab:b1-2".to_string()));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn views_and_renaming() {
        let dir = temp_dir();
        let mut e = english(&dir, "PC");
        let t = tokyo(2026, 10, 1, 21, 0, 0);
        let card = e.vocab_card("vocab:b1-1", true).unwrap();
        assert_eq!((card.word.as_str(), card.level.as_str()), ("word1", "B1"));
        let dict = e.vocab_card("dict:abundant", false).unwrap();
        assert_eq!(dict.phonetic.as_deref(), Some("/ә'bʌndәnt/"));
        assert_eq!(dict.level, "词典");
        assert!(e.vocab_card("vocab:nope", false).is_none());
        assert!(e.is_resolvable("dict:abundant") && !e.is_resolvable("dict:zzz"));
        let mut rng = Rng::new(7);
        let q = e.para_question("para:listening:reserve", &mut rng).unwrap();
        assert_eq!(q.choices[q.answer_index], "book");
        e.rate("vocab:b1-1", Kind::Vocab, Rating::Easy, t).unwrap();
        assert!(e.rename_device("Gaming PC").unwrap());
        assert!(dir.join("english-events-Gaming-PC.jsonl").exists());
        let reopened =
            English::with_library(SyncFolder::new(&dir, "Gaming PC"), Zone::tokyo(), library());
        assert_eq!(
            reopened.state().card("vocab:b1-1").unwrap().state.interval,
            4
        );
        std::fs::remove_dir_all(&dir).ok();
    }
}
