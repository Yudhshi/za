//! 同義替換の 4 択(Swift の `ParaphraseQuiz`)と、そのための小さな乱数。
//! 誤答は毎回作る(固定すると誤答ごと覚えてしまう)

use serde::Serialize;

use crate::library::ParaphraseEntry;

/// 決まった種から同じ並びを作る乱数(SplitMix64。Swift の SeededGenerator と同じ式)
#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
}

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng {
            state: seed.wrapping_add(0x9E37_79B9_7F4A_7C15),
        }
    }

    /// 時刻から種を作る(アプリ用)
    pub fn from_time() -> Rng {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0);
        Rng::new(nanos)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// 0..n(n > 0)
    pub fn below(&mut self, n: usize) -> usize {
        (self.next_u64() % n as u64) as usize
    }

    pub fn pick<'a, T>(&mut self, items: &'a [T]) -> Option<&'a T> {
        if items.is_empty() {
            None
        } else {
            Some(&items[self.below(items.len())])
        }
    }

    pub fn shuffle<T>(&mut self, items: &mut [T]) {
        for i in (1..items.len()).rev() {
            let j = self.below(i + 1);
            items.swap(i, j);
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Question {
    pub entry: ParaphraseEntry,
    pub choices: Vec<String>,
    pub answer_index: usize,
}

/// entry の言い換えを 1 つ正解に、他の考点词の言い換えから 3 つ誤答を選ぶ。誤答が 3 つ集まらなければ None
pub fn make(entry: &ParaphraseEntry, pool: &[ParaphraseEntry], rng: &mut Rng) -> Option<Question> {
    let answer = rng.pick(&entry.syn)?.clone();
    let mut used: Vec<String> = entry
        .syn
        .iter()
        .map(|s| s.to_lowercase())
        .chain(std::iter::once(entry.w.to_lowercase()))
        .collect();
    let mut others: Vec<&ParaphraseEntry> = pool.iter().filter(|o| o.w != entry.w).collect();
    rng.shuffle(&mut others);
    let mut distractors = Vec::new();
    for other in others {
        let Some(candidate) = rng.pick(&other.syn) else {
            continue;
        };
        if used.contains(&candidate.to_lowercase()) {
            continue;
        }
        used.push(candidate.to_lowercase());
        distractors.push(candidate.clone());
        if distractors.len() == 3 {
            break;
        }
    }
    if distractors.len() < 3 {
        return None;
    }
    let mut choices = distractors;
    choices.push(answer.clone());
    rng.shuffle(&mut choices);
    let answer_index = choices.iter().position(|c| *c == answer).unwrap_or(0);
    Some(Question {
        entry: entry.clone(),
        choices,
        answer_index,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(w: &str, syn: &[&str], skill: &str) -> ParaphraseEntry {
        ParaphraseEntry {
            w: w.into(),
            pos: None,
            zh: None,
            syn: syn.iter().map(|s| s.to_string()).collect(),
            skill: skill.into(),
        }
    }

    #[test]
    fn four_distinct_choices_one_correct_no_leaks() {
        let pool = vec![
            entry("reserve", &["book"], "listening"),
            entry("adjust", &["change", "alter"], "listening"),
            entry("recognize", &["identify", "realize"], "reading"),
            entry("resemble", &["be similar to"], "reading"),
            entry("have to", &["must"], "listening"),
        ];
        let mut rng = Rng::new(42);
        for _ in 0..50 {
            let q = make(&pool[1], &pool, &mut rng).expect("question");
            assert_eq!(q.choices.len(), 4);
            let mut unique = q.choices.clone();
            unique.sort();
            unique.dedup();
            assert_eq!(unique.len(), 4, "distinct");
            assert!(
                pool[1].syn.contains(&q.choices[q.answer_index]),
                "answer is a synonym"
            );
            let wrong: Vec<&String> = q
                .choices
                .iter()
                .enumerate()
                .filter(|(i, _)| *i != q.answer_index)
                .map(|(_, c)| c)
                .collect();
            assert!(
                !wrong.iter().any(|c| pool[1].syn.contains(c)),
                "no second correct answer"
            );
        }
        assert_eq!(
            make(&pool[0], &pool[..2], &mut rng),
            None,
            "not enough distractors"
        );
    }

    #[test]
    fn seeded_rng_matches_splitmix() {
        // Swift の SeededGenerator(seed: 0) と同じ最初の値
        let mut a = Rng::new(0);
        let mut b = Rng::new(0);
        assert_eq!(a.next_u64(), b.next_u64());
        assert_ne!(Rng::new(1).next_u64(), Rng::new(2).next_u64());
    }
}
