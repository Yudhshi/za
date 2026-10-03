//! 英語の「地盘」:答えた結果を格の漆の満ち具合で見せる(Swift の `EnglishRound`)

use serde::Serialize;

use crate::srs::Rating;

/// 满 + 星 / 满 / まばら / 灰 + ✕ / 空 / いまの 1 問
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RoundMark {
    Easy,
    Good,
    Fuzzy,
    Forgot,
    Empty,
    Current,
}

/// 記録の結果 → 漆(「知ってる」は太简单と同じ满 + 星。知らない値は满)
pub fn mark_result(result: &str) -> RoundMark {
    if result == "known" {
        return RoundMark::Easy;
    }
    Rating::parse(result).map(mark).unwrap_or(RoundMark::Good)
}

pub fn mark(rating: Rating) -> RoundMark {
    match rating {
        Rating::Again => RoundMark::Forgot,
        Rating::Hard => RoundMark::Fuzzy,
        Rating::Good => RoundMark::Good,
        Rating::Easy => RoundMark::Easy,
    }
}

/// 本轮の盤面:今日答えた順に goal マス + いまの 1 問 + 空き。結果が足りない(同期より前の記録)ところは满
pub fn board(results: &[String], answered: usize, goal: usize, pending: bool) -> Vec<RoundMark> {
    (0..goal)
        .map(|index| {
            if index < answered {
                results
                    .get(index)
                    .map(|r| mark_result(r))
                    .unwrap_or(RoundMark::Good)
            } else if index == answered && pending {
                RoundMark::Current
            } else {
                RoundMark::Empty
            }
        })
        .collect()
}

/// 卡の复习记录:最近の slots 回(答える前なら最後の 1 マスは「いまの 1 問」)
pub fn history(ratings: &[Rating], answered: bool, slots: usize) -> Vec<RoundMark> {
    if slots == 0 {
        return Vec::new();
    }
    let keep = if answered { slots } else { slots - 1 };
    let start = ratings.len().saturating_sub(keep);
    let mut marks: Vec<RoundMark> = ratings[start..].iter().map(|r| mark(*r)).collect();
    if !answered {
        marks.push(RoundMark::Current);
    }
    marks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn board_paints_answers_then_current_then_empty() {
        let results: Vec<String> = ["good", "again", "known", "hard"]
            .map(String::from)
            .to_vec();
        assert_eq!(
            board(&results, 4, 6, true),
            vec![
                RoundMark::Good,
                RoundMark::Forgot,
                RoundMark::Easy,
                RoundMark::Fuzzy,
                RoundMark::Current,
                RoundMark::Empty
            ]
        );
        assert_eq!(
            board(&[], 2, 3, false),
            vec![RoundMark::Good, RoundMark::Good, RoundMark::Empty],
            "answers without a result read as good"
        );
    }

    #[test]
    fn history_keeps_the_last_slots() {
        let ratings = [Rating::Again, Rating::Good, Rating::Easy];
        assert_eq!(
            history(&ratings, false, 3),
            vec![RoundMark::Good, RoundMark::Easy, RoundMark::Current]
        );
        assert_eq!(
            history(&ratings, true, 2),
            vec![RoundMark::Good, RoundMark::Easy]
        );
        assert!(history(&[], false, 0).is_empty());
    }
}
