//! 間隔反復(SM-2)。Swift の `SRSState.applying` と同じ式(docs/sync-format.md「SM-2 评分」)

use serde::{Deserialize, Serialize};

/// 評分(忘了 / 模糊 / 记住了 / 太简单)
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Rating {
    Again,
    Hard,
    Good,
    Easy,
}

impl Rating {
    pub const ALL: [Rating; 4] = [Rating::Again, Rating::Hard, Rating::Good, Rating::Easy];

    pub fn as_str(self) -> &'static str {
        match self {
            Rating::Again => "again",
            Rating::Hard => "hard",
            Rating::Good => "good",
            Rating::Easy => "easy",
        }
    }

    pub fn parse(text: &str) -> Option<Rating> {
        Rating::ALL.into_iter().find(|r| r.as_str() == text)
    }
}

/// カード 1 枚の復習状態
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SrsState {
    /// 次の復習までの日数(0 = 今日もう一度)
    pub interval: i64,
    pub ease: f64,
    pub reps: i64,
    pub lapses: i64,
}

impl Default for SrsState {
    fn default() -> Self {
        SrsState {
            interval: 0,
            ease: 2.5,
            reps: 0,
            lapses: 0,
        }
    }
}

/// Swift の `.rounded()`(0.5 は 0 から遠い方へ)。Rust の f64::round と同じ
fn round(value: f64) -> i64 {
    value.round() as i64
}

impl SrsState {
    pub fn applying(self, rating: Rating) -> SrsState {
        let mut s = self;
        match rating {
            Rating::Again => {
                s.interval = 0;
                s.ease = (self.ease - 0.2).max(1.3);
                s.reps = 0;
                s.lapses += 1;
            }
            Rating::Hard => {
                // 「模糊」でも間隔は必ず伸びる(1 → 1 に固まらない)
                s.interval = (self.interval + 1).max(round(self.interval.max(1) as f64 * 1.2));
                s.ease = (self.ease - 0.15).max(1.3);
                s.reps += 1;
            }
            Rating::Good => {
                s.interval = match self.reps {
                    0 => 1,
                    // 「太简单」の後に縮まない
                    1 => round(self.interval as f64 * self.ease).max(3),
                    _ => round(self.interval as f64 * self.ease).max(1),
                };
                s.reps += 1;
            }
            Rating::Easy => {
                s.interval = if self.reps == 0 {
                    4
                } else {
                    round(self.interval as f64 * self.ease * 1.3).max(1)
                };
                s.ease = self.ease + 0.15;
                s.reps += 1;
            }
        }
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sm2_matches_the_mac_schedule() {
        let mut s = SrsState::default();
        s = s.applying(Rating::Good);
        assert_eq!(s.interval, 1);
        s = s.applying(Rating::Good);
        assert_eq!(s.interval, 3);
        s = s.applying(Rating::Good);
        assert_eq!(s.interval, 8, "3 × 2.5 rounded");
        let hard = s.applying(Rating::Hard);
        assert_eq!(hard.interval, 10, "8 × 1.2 rounded");
        assert!((hard.ease - 2.35).abs() < 1e-9, "hard lowers ease");
        let again = s.applying(Rating::Again);
        assert_eq!((again.interval, again.reps, again.lapses), (0, 0, 1));
        assert_eq!(SrsState::default().applying(Rating::Easy).interval, 4);
        assert_eq!(
            SrsState::default().applying(Rating::Hard).interval,
            1,
            "new card hard → tomorrow"
        );
        let floor = SrsState {
            ease: 1.35,
            ..SrsState::default()
        }
        .applying(Rating::Again);
        assert!((floor.ease - 1.3).abs() < 1e-9, "ease never below 1.3");
    }

    #[test]
    fn easy_after_easy_does_not_shrink() {
        let s = SrsState::default().applying(Rating::Easy);
        assert_eq!((s.interval, s.reps), (4, 1));
        // reps 1 の good は 3 日より短くしない
        let g = SrsState {
            interval: 1,
            ease: 1.3,
            reps: 1,
            lapses: 0,
        }
        .applying(Rating::Good);
        assert_eq!(g.interval, 3);
        assert_eq!(Rating::parse("hard"), Some(Rating::Hard));
        assert_eq!(Rating::parse("known"), None);
    }
}
