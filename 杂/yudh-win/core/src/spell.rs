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

#[cfg(test)]
mod tests {
    use super::*;

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
