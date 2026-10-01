//! 英語の素材(語表)。Mac の `EnglishLibrary` と同じ JSON(vocab.json / paraphrase.json / dictation.json / dict.json)。
//! 教材由来の語表なので git には入れない。Windows では同期フォルダの `english-library/` から読む(Mac が置く)。
//! 無い・壊れたファイルは空のまま

use std::collections::HashMap;
use std::path::Path;

use serde::{Deserialize, Serialize};

/// 単語(分層詞池)。id は「b1-0807」など
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct VocabWord {
    pub id: String,
    pub w: String,
    pub ph: Option<String>,
    pub pos: Option<String>,
    pub zh: String,
    pub ex: Option<String>,
    pub lv: String,
}

/// 同義替換(考点词)。syn が真題での言い換え、skill は listening / reading
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct ParaphraseEntry {
    pub w: String,
    pub pos: Option<String>,
    pub zh: Option<String>,
    pub syn: Vec<String>,
    pub skill: String,
}

/// 聴写の語(语料库)。set は原書の小節名
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct DictationWord {
    pub w: String,
    pub ipa: Option<String>,
    pub zh: Option<String>,
    pub set: String,
}

/// 辞書を引いた結果
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct DictHit {
    pub word: String,
    pub ipa: String,
    pub zh: String,
}

#[derive(Clone, Debug, Default)]
pub struct Library {
    pub vocab: Vec<VocabWord>,
    pub paraphrases: Vec<ParaphraseEntry>,
    pub dictation: Vec<DictationWord>,
    /// { 小文字の語: [音標, 釈義] }
    pub dictionary: HashMap<String, Vec<String>>,
}

fn read<T: for<'de> Deserialize<'de>>(dir: &Path, name: &str) -> Option<T> {
    let data = std::fs::read(dir.join(name)).ok()?;
    serde_json::from_slice(&data).ok()
}

impl Library {
    pub fn load(dir: &Path) -> Library {
        Library {
            vocab: read(dir, "vocab.json").unwrap_or_default(),
            paraphrases: read(dir, "paraphrase.json").unwrap_or_default(),
            dictation: read(dir, "dictation.json").unwrap_or_default(),
            dictionary: read(dir, "dict.json").unwrap_or_default(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.vocab.is_empty()
            && self.paraphrases.is_empty()
            && self.dictation.is_empty()
            && self.dictionary.is_empty()
    }

    /// 辞書を引く。見つからなければ語形変化を外して引き直す(辞書にある最も長いもの:cares → care であって car ではない)
    pub fn lookup(&self, query: &str) -> Option<DictHit> {
        let word = query.trim().to_lowercase();
        if word.is_empty() {
            return None;
        }
        let hit = |w: &str| {
            self.dictionary
                .get(w)
                .filter(|e| e.len() >= 2)
                .map(|e| DictHit {
                    word: w.to_string(),
                    ipa: e[0].clone(),
                    zh: e[1].clone(),
                })
        };
        if let Some(found) = hit(&word) {
            return Some(found);
        }
        base_forms(&word)
            .into_iter()
            .filter(|f| self.dictionary.get(f).is_some_and(|e| e.len() >= 2))
            // Swift の max(by:) と同じく、同じ長さなら先のもの
            .fold(None::<String>, |best, f| match best {
                Some(b) if b.chars().count() >= f.chars().count() => Some(b),
                _ => Some(f),
            })
            .and_then(|best| hit(&best))
    }
}

/// 語形変化を外した候補(辞書に無い形も含む)
pub fn base_forms(word: &str) -> Vec<String> {
    let mut forms = Vec::new();
    let length = word.chars().count();
    let mut strip = |suffix: &str, add: &str| {
        if word.ends_with(suffix) && length > suffix.chars().count() + 1 {
            forms.push(format!("{}{}", &word[..word.len() - suffix.len()], add));
        }
    };
    strip("ies", "y");
    strip("ied", "y");
    strip("es", "");
    strip("s", "");
    strip("ing", "");
    strip("ing", "e");
    strip("ed", "");
    strip("ed", "e");
    strip("d", "");
    strip("er", "");
    strip("est", "");
    strip("ly", "");
    // running → run, stopped → stop(子音の重なり)
    for suffix in ["ing", "ed"] {
        if let Some(stem) = word.strip_suffix(suffix) {
            let chars: Vec<char> = stem.chars().collect();
            if chars.len() >= 3 && chars[chars.len() - 1] == chars[chars.len() - 2] {
                forms.push(chars[..chars.len() - 1].iter().collect());
            }
        }
    }
    forms
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lookup_strips_inflections() {
        let mut lib = Library::default();
        for (w, ipa, zh) in [
            ("study", "ˈstʌdi", "v. 学习"),
            ("run", "rʌn", "v. 跑"),
            ("abundant", "ә'bʌndәnt", "a. 丰富的"),
            ("care", "keә", "n. 照顾"),
            ("car", "kɑː", "n. 汽车"),
        ] {
            lib.dictionary.insert(w.into(), vec![ipa.into(), zh.into()]);
        }
        assert_eq!(
            lib.lookup(" Abundant ").map(|h| h.zh).as_deref(),
            Some("a. 丰富的")
        );
        assert_eq!(
            lib.lookup("studies").map(|h| h.word).as_deref(),
            Some("study")
        );
        assert_eq!(
            lib.lookup("running").map(|h| h.word).as_deref(),
            Some("run")
        );
        assert_eq!(lib.lookup("cares").map(|h| h.word).as_deref(), Some("care"));
        assert_eq!(lib.lookup("zzz"), None);
        assert_eq!(lib.lookup(""), None);
    }

    #[test]
    fn loads_json_and_tolerates_missing_files() {
        let dir = std::env::temp_dir().join(format!("yudh-library-{}", crate::event::new_id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("vocab.json"),
            r#"[{"id":"b1-1","w":"storey","ph":"/ˈstɔːri/","pos":"n.","zh":"层","lv":"b1"}]"#,
        )
        .unwrap();
        std::fs::write(
            dir.join("paraphrase.json"),
            r#"[{"w":"reserve","syn":["book"],"skill":"listening"}]"#,
        )
        .unwrap();
        std::fs::write(dir.join("dictation.json"), "not json").unwrap();
        let lib = Library::load(&dir);
        assert_eq!(lib.vocab[0].w, "storey");
        assert_eq!(lib.vocab[0].ex, None);
        assert_eq!(lib.paraphrases[0].syn, vec!["book"]);
        assert!(
            lib.dictation.is_empty() && lib.dictionary.is_empty(),
            "broken / missing are empty"
        );
        assert!(Library::load(&dir.join("nope")).is_empty(), "missing dir");
        std::fs::remove_dir_all(&dir).ok();
    }
}
