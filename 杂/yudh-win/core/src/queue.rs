//! 出題の順番(Swift の `EnglishQueue`)

use std::collections::HashSet;

/// 次に出すカードの id:期限の来た復習(古い順)→ 今日の新規枠が残っていれば未学習を素材順に。
/// avoid(いま答えたもの)は、他に出すものが無いときだけ出す(「もう一回」がすぐ戻ってこないように)
pub fn next(
    due: &[String],
    pool: &[String],
    seen: &HashSet<String>,
    new_today: usize,
    new_limit: usize,
    avoid: Option<&str>,
) -> Option<String> {
    if let Some(id) = due.iter().find(|id| Some(id.as_str()) != avoid) {
        return Some(id.clone());
    }
    if new_today < new_limit {
        if let Some(id) = pool
            .iter()
            .find(|id| !seen.contains(*id) && Some(id.as_str()) != avoid)
        {
            return Some(id.clone());
        }
    }
    if let Some(avoid) = avoid {
        if due.iter().any(|id| id == avoid) {
            return Some(avoid.to_string());
        }
    }
    None
}

/// 今日あと何枚か(復習 + 残りの新規枠。未学習が尽きたらその分は数えない)
pub fn remaining(due: usize, unseen: usize, new_today: usize, new_limit: usize) -> usize {
    due + new_limit.saturating_sub(new_today).min(unseen)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn due_first_avoid_the_last_then_new_within_quota() {
        let pool = ids(&["a", "b", "c"]);
        let none = HashSet::new();
        assert_eq!(
            next(&ids(&["x", "y"]), &pool, &none, 0, 10, Some("x")).as_deref(),
            Some("y")
        );
        let seen: HashSet<String> = ["a".to_string()].into();
        assert_eq!(next(&[], &pool, &seen, 3, 10, None).as_deref(), Some("b"));
        assert_eq!(next(&[], &pool, &none, 10, 10, None), None, "quota used up");
        assert_eq!(
            next(&ids(&["x"]), &pool, &none, 10, 10, Some("x")).as_deref(),
            Some("x"),
            "only the failed card left"
        );
        assert_eq!(remaining(4, 2, 3, 10), 6);
        assert_eq!(remaining(0, 50, 12, 10), 0);
    }
}
