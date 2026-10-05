//! 聴写の採点(Swift の `SpellCheck`)。大文字小文字・前後と連続の空白・全角・曲がった引用符の違いは無視する

use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SpellResult {
    Correct,
    /// 1 文字違い(4 文字以上の語)。半分正解として「模糊」で記録する
    Almost,
    Wrong,
}

/// 全角の英数字・記号・空白を半角に(Swift の .fullwidthToHalfwidth の英数字の範囲)
fn halfwidth(c: char) -> char {
    match c {
        '\u{FF01}'..='\u{FF5E}' => char::from_u32(c as u32 - 0xFEE0).unwrap_or(c),
        '\u{3000}' => ' ',
        _ => c,
    }
}

pub fn normalize(text: &str) -> String {
    let half: String = text
        .chars()
        .map(halfwidth)
        .map(|c| if c == '’' || c == '‘' { '\'' } else { c })
        .collect();
    half.to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn check(input: &str, answer: &str) -> SpellResult {
    let a = normalize(input);
    let b = normalize(answer);
    if a == b {
        return SpellResult::Correct;
    }
    if b.chars().count() >= 4 && !a.is_empty() && levenshtein(&a, &b) <= 1 {
        return SpellResult::Almost;
    }
    SpellResult::Wrong
}

pub fn levenshtein(a: &str, b: &str) -> usize {
    let x: Vec<char> = a.chars().collect();
    let y: Vec<char> = b.chars().collect();
    if x.is_empty() {
        return y.len();
    }
    if y.is_empty() {
        return x.len();
    }
    let mut previous: Vec<usize> = (0..=y.len()).collect();
    for i in 1..=x.len() {
        let mut current = vec![0; y.len() + 1];
        current[0] = i;
        for j in 1..=y.len() {
            let cost = usize::from(x[i - 1] != y[j - 1]);
            current[j] = (previous[j] + 1)
                .min(current[j - 1] + 1)
                .min(previous[j - 1] + cost);
        }
        previous = current;
    }
    previous[y.len()]
}

/// 採点した綴りと正解の食い違い(Mac の `engSpellingMarks`)。入力は正規化した字、正解はそのままの字。
/// 編集距離の道筋をたどって、入力の余計・違う字(橙)と、正解の足りない・違う字(青)に印を付ける
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpellMarks {
    pub typed: String,
    pub typed_marks: Vec<bool>,
    pub answer: String,
    pub answer_marks: Vec<bool>,
}

pub fn marks(input: &str, answer: &str) -> SpellMarks {
    let typed = normalize(input);
    let x: Vec<char> = typed.chars().collect();
    let y: Vec<char> = answer.chars().collect();
    let same = |a: char, b: char| a.to_lowercase().eq(b.to_lowercase());
    let (n, m) = (x.len(), y.len());
    let mut cost = vec![vec![0usize; m + 1]; n + 1];
    for (i, row) in cost.iter_mut().enumerate() {
        row[0] = i;
    }
    for (j, c) in cost[0].iter_mut().enumerate() {
        *c = j;
    }
    for i in 1..=n {
        for j in 1..=m {
            let step = usize::from(!same(x[i - 1], y[j - 1]));
            cost[i][j] = (cost[i - 1][j] + 1)
                .min(cost[i][j - 1] + 1)
                .min(cost[i - 1][j - 1] + step);
        }
    }
    let mut typed_marks = vec![false; n];
    let mut answer_marks = vec![false; m];
    let (mut i, mut j) = (n, m);
    while i > 0 || j > 0 {
        if i > 0 && j > 0 {
            let alike = same(x[i - 1], y[j - 1]);
            if cost[i][j] == cost[i - 1][j - 1] + usize::from(!alike) {
                if !alike {
                    typed_marks[i - 1] = true;
                    answer_marks[j - 1] = true;
                }
                i -= 1;
                j -= 1;
                continue;
            }
        }
        if i > 0 && cost[i][j] == cost[i - 1][j] + 1 {
            typed_marks[i - 1] = true;
            i -= 1;
        } else if j > 0 {
            answer_marks[j - 1] = true;
            j -= 1;
        } else {
            i -= 1;
        }
    }
    SpellMarks {
        typed,
        typed_marks,
        answer: answer.to_string(),
        answer_marks,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(flags: &[bool]) -> Vec<usize> {
        flags
            .iter()
            .enumerate()
            .filter(|(_, f)| **f)
            .map(|(i, _)| i)
            .collect()
    }

    #[test]
    fn marks_point_at_the_wrong_letters() {
        let same = marks("Accommodation", "accommodation");
        assert_eq!(same.typed, "accommodation");
        assert!(at(&same.typed_marks).is_empty() && at(&same.answer_marks).is_empty());
        let missing = marks("acommodation", "accommodation");
        assert!(at(&missing.typed_marks).is_empty());
        assert_eq!(at(&missing.answer_marks).len(), 1, "one c is missing");
        let extra = marks("townn", "town");
        assert_eq!(
            at(&extra.typed_marks),
            vec![3],
            "either n; same pick as the Mac"
        );
        assert!(at(&extra.answer_marks).is_empty());
        let swapped = marks("recieve", "receive");
        assert_eq!(at(&swapped.typed_marks), vec![3, 4]);
        assert_eq!(at(&swapped.answer_marks), vec![3, 4]);
        let blank = marks("", "bus");
        assert_eq!(blank.typed, "");
        assert_eq!(at(&blank.answer_marks), vec![0, 1, 2]);
    }

    #[test]
    fn exact_almost_wrong_ignoring_case_and_spacing() {
        assert_eq!(
            check("Accommodation", "accommodation"),
            SpellResult::Correct
        );
        assert_eq!(
            check("  a  couple of ", "a couple of"),
            SpellResult::Correct
        );
        assert_eq!(check("acommodation", "accommodation"), SpellResult::Almost);
        assert_eq!(
            check("recieve", "receive"),
            SpellResult::Wrong,
            "transposition = 2 edits"
        );
        assert_eq!(
            check("tow", "town"),
            SpellResult::Almost,
            "4 letters: one off is almost"
        );
        assert_eq!(
            check("bas", "bus"),
            SpellResult::Wrong,
            "under 4 letters must be exact"
        );
        assert_eq!(check("", "town"), SpellResult::Wrong);
        assert_eq!(
            check("ｔｏｗｎ", "town"),
            SpellResult::Correct,
            "full-width"
        );
        assert_eq!(check("it’s", "it's"), SpellResult::Correct, "curly quote");
        assert_eq!(levenshtein("kitten", "sitting"), 3);
    }
}
