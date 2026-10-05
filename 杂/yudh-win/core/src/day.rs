//! 日付("yyyy-MM-dd")。日付は本機の時区で数える(Mac と同じ。両方東京なら一致する)

use chrono::{DateTime, Days, FixedOffset, Local, NaiveDate, Utc};

/// 日付を数える時区。アプリは `Local`、テストは東京の固定オフセット
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Zone {
    Local,
    Fixed(FixedOffset),
}

impl Zone {
    /// 東京(+09:00)。テスト用
    pub fn tokyo() -> Zone {
        Zone::Fixed(FixedOffset::east_opt(9 * 3600).expect("valid offset"))
    }

    /// その時刻の、この時区での日付
    pub fn date(&self, at: DateTime<Utc>) -> NaiveDate {
        match self {
            Zone::Local => at.with_timezone(&Local).date_naive(),
            Zone::Fixed(offset) => at.with_timezone(offset).date_naive(),
        }
    }

    /// "yyyy-MM-dd"
    pub fn key(&self, at: DateTime<Utc>) -> String {
        key(self.date(at))
    }

    /// その時刻から n 日後の日付の "yyyy-MM-dd"(Swift の calendar.date(byAdding: .day) と同じく暦の上で足す)
    pub fn key_after(&self, at: DateTime<Utc>, days: i64) -> String {
        key(add_days(self.date(at), days))
    }
}

pub fn key(date: NaiveDate) -> String {
    date.format("%Y-%m-%d").to_string()
}

pub fn parse_key(text: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(text, "%Y-%m-%d").ok()
}

pub fn add_days(date: NaiveDate, days: i64) -> NaiveDate {
    if days >= 0 {
        date.checked_add_days(Days::new(days as u64))
            .unwrap_or(date)
    } else {
        date.checked_sub_days(Days::new(days.unsigned_abs()))
            .unwrap_or(date)
    }
}

#[cfg(test)]
pub(crate) mod testing {
    use chrono::{DateTime, TimeZone, Utc};

    /// 東京の壁時計の時刻 → UTC(テスト用。Swift の tokyoDate と同じ)
    pub fn tokyo(y: i32, mo: u32, d: u32, h: u32, mi: u32, s: u32) -> DateTime<Utc> {
        let offset = chrono::FixedOffset::east_opt(9 * 3600).unwrap();
        offset
            .with_ymd_and_hms(y, mo, d, h, mi, s)
            .single()
            .unwrap()
            .with_timezone(&Utc)
    }
}

#[cfg(test)]
mod tests {
    use super::testing::tokyo;
    use super::*;

    #[test]
    fn day_keys_follow_the_zone() {
        let z = Zone::tokyo();
        // 東京の 0:30 は UTC では前の日
        let at = tokyo(2026, 10, 1, 0, 30, 0);
        assert_eq!(z.key(at), "2026-10-01");
        assert_eq!(
            Zone::Fixed(FixedOffset::east_opt(0).unwrap()).key(at),
            "2026-09-30"
        );
        assert_eq!(z.key_after(at, 1), "2026-10-02");
        assert_eq!(z.key_after(at, 31), "2026-11-01");
        assert_eq!(z.key_after(at, -1), "2026-09-30");
        assert_eq!(
            parse_key("2026-10-01").map(key).as_deref(),
            Some("2026-10-01")
        );
        assert_eq!(parse_key("10/01"), None);
    }
}
