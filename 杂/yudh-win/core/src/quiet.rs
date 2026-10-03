//! 打游戏时让 Yudh 完全安静的程序(反作弊対策)。名单のプログラムが動いているあいだ、Yudh は窓を一切作らず、
//! 無操作・全画面の問い合わせもしない(トレイのアイコンだけ残る)。ゲームを閉じたら元に戻る。
//! ゲームの判定は動いているプロセスの名前だけ(タスクマネージャーと同じ一覧。ゲームのプロセスは開かない)

/// 既定:AION2(NCSOFT の反作弊は G Hub などの周辺ソフトまで止めたことがある)。
/// 起動する exe と、虚幻引擎の本体の exe の両方
pub const DEFAULT_QUIET_APPS: &str = "Aion2.exe
Aion2-Win64-Shipping.exe";

/// 名単の 1 行 1 つを、比べやすい形(小文字・.exe 付き)にする。空行と # で始まる行は飛ばす
pub fn names(text: &str) -> Vec<String> {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(|line| {
            let lower = line.to_lowercase();
            if lower.ends_with(".exe") {
                lower
            } else {
                format!("{lower}.exe")
            }
        })
        .collect()
}

/// 動いているプロセスのうち、名単にある最初のもの(大文字小文字は区別しない)。無ければ None
pub fn running_quiet_app(running: &[String], list: &str) -> Option<String> {
    let wanted = names(list);
    running
        .iter()
        .find(|name| wanted.contains(&name.to_lowercase()))
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_normalised_and_comments_skipped() {
        assert_eq!(
            names("  Aion2.exe \n\n# 注释\nSomeGame\nOTHER.EXE"),
            vec!["aion2.exe", "somegame.exe", "other.exe"]
        );
        assert!(names("").is_empty());
    }

    #[test]
    fn a_running_game_from_the_list_is_found_case_insensitively() {
        let running: Vec<String> = ["System", "explorer.exe", "AION2.EXE", "msedgewebview2.exe"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(
            running_quiet_app(&running, DEFAULT_QUIET_APPS).as_deref(),
            Some("AION2.EXE")
        );
        assert_eq!(
            running_quiet_app(&running, "aion2"),
            Some("AION2.EXE".into()),
            "the .exe may be left out"
        );
        let shipping = vec!["Aion2-Win64-Shipping.exe".to_string()];
        assert!(running_quiet_app(&shipping, DEFAULT_QUIET_APPS).is_some());
        assert_eq!(
            running_quiet_app(&running, "Aion.exe"),
            None,
            "a different game"
        );
        assert_eq!(
            running_quiet_app(&running, ""),
            None,
            "empty list: never quiet"
        );
        assert_eq!(
            running_quiet_app(&[], DEFAULT_QUIET_APPS),
            None,
            "game not running"
        );
    }
}
