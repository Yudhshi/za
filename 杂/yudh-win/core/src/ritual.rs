//! 泡澡のあとの日课(Mac の `Ritual` / `BreathPacer` / `BreathLog` と同じ)。
//! 跟练の動画は落とさず、公式の埋め込みプレーヤーで順に流す。そのあと肩・首の拉伸、最後に仰向けの腹式呼吸。
//! 腹式呼吸は碎片時間(立つたび・会議の前・日课の最後)に 3 回ずつ挟んで習慣にする

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::day::{self, Zone};
use crate::posture::{stretches, StepMeta, Stretch};

pub const DEFAULT_VIDEOS: &str = "跟练 1 https://www.bilibili.com/video/BV1JW4y1k7F7/
跟练 2 https://www.bilibili.com/video/BV1UL411F7Hk/
跟练 3 https://www.youtube.com/watch?v=SGPBSqxKGAc
跟练 4 https://www.youtube.com/watch?v=aHlNoTpXf_8";

/// 跟练のあとの拉伸、立ってやる分(先に立ったまま全部やってから床へ)
pub const DEFAULT_STRETCHES: &str = "斜角肌拉伸（约 2 分钟）
右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 20 秒
微微抬头停 15 秒，再微微低头停 15 秒
换左边：左手按左侧锁骨下方，头向右倒，停 20 秒
微微抬头停 15 秒，再微微低头停 15 秒

颈后斜拉（约 1 分钟）
头向右转 45°，低头看右边腋下，右手轻按后脑，拉伸左侧颈后到肩上，停 30 秒
换另一侧，停 30 秒

横臂拉肩后侧（约 1 分钟）
右臂伸直横过身体前方，和肩同高（拉三角肌后束、小圆肌）
左手扣住右肘往左肩方向拉，肩膀不要耸，停 30 秒
换另一侧，停 30 秒

背后拉手腕（约 1 分钟）
双手背到身后，左手轻轻握住右手腕（拉冈上肌、三角肌中束）
把右手轻轻往左下方带，有拉伸感就停，肩膀上面或前面刺痛就放松，停 20 秒
换另一侧，停 20 秒

背后扣手抬臂（约 1 分钟）
双手在背后十指相扣，手臂伸直（拉三角肌前束）
挺胸，手臂慢慢往后上方抬，停 30 秒 × 2 次

网球放松（约 3 分钟）
背靠墙，网球放在右边腋窝后方（小圆肌），小幅上下滚动 45 秒。不要压到锁骨上方和喉咙两侧
把球移到右肩后上方的凹处（冈上肌），压住慢慢转动手臂 45 秒
换左边：腋窝后方 45 秒，肩后上方 45 秒";

/// 隔天に足す肩袖の力(床の上。手で押し合う等長と、水 1 本)
pub const DEFAULT_STRENGTH: &str = "肩袖力量（隔天做，约 6 分钟）
坐在地上，右手肘贴腰弯 90°，左手握住右手腕；右手往外推、左手顶住不让动，用 5 成力，停 10 秒 × 5 次
换左手往外推，停 10 秒 × 5 次
左侧躺，右手拿一瓶水，手肘贴腰弯 90°，前臂慢慢转向天花板再慢慢放下，做 15 次
换右侧躺，左手拿水，做 15 次
趴下，两手肘弯成 W 放在身体两侧，收紧肩胛把手肘和手抬离地面，停 3 秒，做 12 次";

/// 床の上の拉伸と、最後に仰向けの腹式呼吸
pub const DEFAULT_FLOOR: &str = "猫牛式和穿针式（约 2 分钟）
四点跪姿，吸气塌腰抬头，呼气拱背低头，慢慢做 8 次
右手从左手下方穿过去，右肩和右耳贴地，停 30 秒
换另一侧，停 30 秒

仰躺腹式呼吸（约 2 分钟）
仰躺，膝盖弯曲，一只手放肚子上，一只手放胸口
收下巴，后脑轻轻压向地面，停 5 秒 × 5 次
用鼻子吸气 4 秒只让肚子鼓起来，用嘴呼气 6 秒，做 8 次";

/// 累的晚上の简版(約 5 分)
pub const SHORT_STRETCHES: &str = "斜角肌拉伸（约 1 分钟）
右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 30 秒
换左边：左手按左侧锁骨下方，头向右倒，停 30 秒

横臂拉肩后侧（约 1 分钟）
右臂伸直横过身体前方，左手扣住右肘往左肩方向拉，停 30 秒
换另一侧，停 30 秒

网球放松（约 2 分钟）
背靠墙，网球放在右边腋窝后方，小幅上下滚动 60 秒。不要压到锁骨上方和喉咙两侧
换左边，腋窝后方 60 秒

仰躺腹式呼吸（约 1 分钟）
仰躺，膝盖弯曲，一只手放肚子上，一只手放胸口
用鼻子吸气 4 秒只让肚子鼓起来，用嘴呼气 6 秒，做 6 次";

/// 今日の日课に力量を入れるか:隔天(今日・昨日にやっていなければ入れる)
pub fn includes_strength(log: &BTreeMap<String, u32>, now: DateTime<Utc>, zone: Zone) -> bool {
    let today = zone.date(now);
    let done = |d: chrono::NaiveDate| log.get(&day::key(d)).is_some_and(|n| *n > 0);
    !done(today) && !done(day::add_days(today, -1))
}

/// 今日の拉伸の並び:立ってやる分 → (隔天)力量 → 床の上。简版なら简版だけ
pub fn plan(standing: &str, strength: Option<&str>, floor: &str, short: bool) -> Vec<Stretch> {
    if short {
        return stretches(SHORT_STRETCHES);
    }
    let mut all = stretches(standing);
    all.extend(stretches(strength.unwrap_or("")));
    all.extend(stretches(floor));
    all
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Site {
    Bilibili,
    Youtube,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Video {
    pub title: String,
    /// 元のページ(追跡用のクエリは落とす)
    pub page: String,
    pub site: Site,
    pub id: Option<String>,
}

impl Video {
    /// アプリの中で流す埋め込みプレーヤー(無ければブラウザで開く)
    pub fn embed(&self) -> Option<String> {
        let id = self.id.as_deref()?;
        match self.site {
            Site::Bilibili => Some(format!(
                "https://player.bilibili.com/player.html?bvid={id}&page=1&autoplay=1&danmaku=0&high_quality=1"
            )),
            Site::Youtube => Some(format!(
                "https://www.youtube-nocookie.com/embed/{id}?autoplay=1&rel=0&playsinline=1"
            )),
            Site::Other => None,
        }
    }
}

/// "https://host/path?query#frag" → (host, path の各段, query)
fn split_url(url: &str) -> Option<(String, Vec<String>, String)> {
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))?;
    let rest = rest.split('#').next().unwrap_or(rest);
    let (before_query, query) = rest.split_once('?').unwrap_or((rest, ""));
    let mut parts = before_query.split('/');
    let host = parts.next()?.to_lowercase();
    if host.is_empty() {
        return None;
    }
    let path = parts
        .filter(|p| !p.is_empty())
        .map(str::to_string)
        .collect();
    Some((host, path, query.to_string()))
}

fn video(url: &str, title: String) -> Option<Video> {
    let (host, path, query) = split_url(url)?;
    if host.ends_with("bilibili.com") {
        if let Some(i) = path.iter().position(|p| p == "video") {
            if let Some(bv) = path.get(i + 1).filter(|p| p.starts_with("BV")) {
                return Some(Video {
                    title,
                    page: format!("https://www.bilibili.com/video/{bv}/"),
                    site: Site::Bilibili,
                    id: Some(bv.clone()),
                });
            }
        }
    }
    let youtube = if host == "youtu.be" {
        path.first().cloned()
    } else if host.ends_with("youtube.com") {
        match path.first().map(String::as_str) {
            Some("shorts" | "embed" | "live") => path.get(1).cloned(),
            _ => query
                .split('&')
                .find_map(|kv| kv.strip_prefix("v=").map(str::to_string)),
        }
    } else {
        None
    };
    if let Some(id) = youtube.filter(|id| !id.is_empty()) {
        return Some(Video {
            title,
            page: format!("https://www.youtube.com/watch?v={id}"),
            site: Site::Youtube,
            id: Some(id),
        });
    }
    Some(Video {
        title,
        page: url.to_string(),
        site: Site::Other,
        id: None,
    })
}

/// 1 行 1 本:最初の http から URL、その前が名前(無ければ「视频 N」)
pub fn videos(text: &str) -> Vec<Video> {
    let mut result = Vec::new();
    for line in text.lines().map(str::trim) {
        let Some(start) = line.find("http") else {
            continue;
        };
        let url = line[start..].split_whitespace().next().unwrap_or("");
        let name = line[..start].trim();
        let title = if name.is_empty() {
            format!("视频 {}", result.len() + 1)
        } else {
            name.to_string()
        };
        if let Some(v) = video(url, title) {
            result.push(v);
        }
    }
    result
}

/// 数字の後(空白を飛ばして)に unit が来る数を全部
fn numbers_before(text: &str, unit: char) -> Vec<u32> {
    // 全角の数字(中文・日本語の入力法)も読む(StepMeta と Mac の Ritual.duration と同じ)
    let chars = crate::posture::halfwidth(text);
    let mut found = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_ascii_digit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_digit() {
                i += 1;
            }
            let mut j = i;
            while j < chars.len() && chars[j].is_whitespace() {
                j += 1;
            }
            if j < chars.len() && chars[j] == unit {
                if let Ok(n) = chars[start..i].iter().collect::<String>().parse() {
                    found.push(n);
                }
            }
        } else {
            i += 1;
        }
    }
    found
}

/// 1 歩の長さ(秒)。数えられなければ None(アプリでは 10 秒の構え)
pub fn duration(line: &str) -> Option<u32> {
    let meta = StepMeta::parse(line);
    let total: u32 = numbers_before(line, '秒').iter().sum();
    match (meta.reps, total) {
        (Some(reps), t) if reps > 0 && t > 0 => Some(t * reps + (reps - 1) * 2),
        (_, t) if t > 0 => Some(t),
        (Some(reps), _) if reps > 0 => Some(reps * 4),
        _ => meta.minutes.map(|m| m * 60),
    }
}

/// 構えの行(秒の無い行)の長さ
pub const SETUP_SECONDS: u32 = 10;

// MARK: 腹式呼吸

pub const INHALE: f64 = 4.0;
pub const EXHALE: f64 = 6.0;
pub const BREATHS: usize = 3;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct BreathState {
    pub breath: usize,
    pub inhaling: bool,
    pub remaining: u32,
    pub finished: bool,
}

pub fn breath_total() -> f64 {
    (INHALE + EXHALE) * BREATHS as f64
}

pub fn breath_state(elapsed: f64) -> BreathState {
    let t = elapsed.max(0.0);
    if t >= breath_total() {
        return BreathState {
            breath: BREATHS,
            inhaling: false,
            remaining: 0,
            finished: true,
        };
    }
    let cycle = INHALE + EXHALE;
    let breath = (t / cycle) as usize;
    let in_cycle = t - breath as f64 * cycle;
    if in_cycle < INHALE {
        BreathState {
            breath,
            inhaling: true,
            remaining: (INHALE - in_cycle).ceil() as u32,
            finished: false,
        }
    } else {
        BreathState {
            breath,
            inhaling: false,
            remaining: (cycle - in_cycle).ceil() as u32,
            finished: false,
        }
    }
}

/// 日ごとの回数("yyyy-MM-dd" → 回数)。60 日より古いものは捨てる
pub fn record(log: &mut BTreeMap<String, u32>, day: &str) {
    *log.entry(day.to_string()).or_insert(0) += 1;
    while log.len() > 60 {
        let oldest = log.keys().next().cloned();
        if let Some(key) = oldest {
            log.remove(&key);
        }
    }
}

/// 連続日数(今日まだなら昨日までで数える)
pub fn streak(log: &BTreeMap<String, u32>, now: DateTime<Utc>, zone: Zone) -> usize {
    let has = |d: chrono::NaiveDate| log.get(&day::key(d)).is_some_and(|n| *n > 0);
    let mut date = zone.date(now);
    if !has(date) {
        date = day::add_days(date, -1);
    }
    let mut count = 0;
    while has(date) {
        count += 1;
        date = day::add_days(date, -1);
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;
    use crate::posture::illustration;

    #[test]
    fn videos_sites_embeds_and_tracking_dropped() {
        let v = videos(DEFAULT_VIDEOS);
        let titles: Vec<&str> = v.iter().map(|x| x.title.as_str()).collect();
        assert_eq!(titles, vec!["跟练 1", "跟练 2", "跟练 3", "跟练 4"]);
        assert_eq!(v[0].embed().as_deref(), Some("https://player.bilibili.com/player.html?bvid=BV1JW4y1k7F7&page=1&autoplay=1&danmaku=0&high_quality=1"));
        assert_eq!(
            v[3].embed().as_deref(),
            Some(
                "https://www.youtube-nocookie.com/embed/aHlNoTpXf_8?autoplay=1&rel=0&playsinline=1"
            )
        );
        let pasted = videos("https://www.bilibili.com/video/BV1UL411F7Hk/?spm_id_from=333&vd_source=abc\n晨间 https://youtu.be/SGPBSqxKGAc?t=10\n短 https://www.youtube.com/shorts/abcDEF12345\n随便写的一行\n\n别处 https://example.com/v/1");
        let titles: Vec<&str> = pasted.iter().map(|x| x.title.as_str()).collect();
        assert_eq!(titles, vec!["视频 1", "晨间", "短", "别处"]);
        assert_eq!(
            pasted[0].page,
            "https://www.bilibili.com/video/BV1UL411F7Hk/"
        );
        assert_eq!(pasted[1].id.as_deref(), Some("SGPBSqxKGAc"));
        assert_eq!(pasted[2].id.as_deref(), Some("abcDEF12345"));
        assert_eq!(pasted[3].site, Site::Other);
        assert_eq!(pasted[3].embed(), None);
    }

    #[test]
    fn stretch_durations_match_the_mac() {
        assert_eq!(
            duration("右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 20 秒"),
            Some(20)
        );
        assert_eq!(duration("微微抬头停 15 秒，再微微低头停 15 秒"), Some(30));
        assert_eq!(
            duration("收下巴，后脑轻轻压向地面，停 5 秒 × 5 次"),
            Some(33)
        );
        assert_eq!(
            duration("挺胸，手臂慢慢往后上方抬，停 30 秒 × 2 次"),
            Some(62)
        );
        assert_eq!(
            duration("四点跪姿，吸气塌腰抬头，呼气拱背低头，慢慢做 8 次"),
            Some(32)
        );
        assert_eq!(duration("头向右转 45°，低头看右边腋下，停 30 秒"), Some(30));
        assert_eq!(
            duration(
                "趴下，两手肘弯成 W 放在身体两侧，收紧肩胛把手肘和手抬离地面，停 3 秒，做 12 次"
            ),
            Some(58)
        );
        assert_eq!(duration("走 2 分钟"), Some(120));
        assert_eq!(duration("仰躺，膝盖弯曲，一只手放肚子上"), None);
        let pics = |text: &str| stretches(text).iter().map(illustration).collect::<Vec<_>>();
        assert_eq!(
            pics(DEFAULT_STRETCHES),
            vec![
                "neck-side",
                "neck-side",
                "stretch",
                "stretch",
                "chest-doorway",
                "stretch"
            ]
        );
        assert_eq!(pics(DEFAULT_STRENGTH), vec!["shoulder-blades"]);
        assert_eq!(pics(DEFAULT_FLOOR), vec!["stretch", "belly-breathing"]);
        assert!(
            !DEFAULT_STRETCHES.contains("侧卧压") && !DEFAULT_FLOOR.contains("侧卧压"),
            "no sleeper stretch"
        );
    }

    #[test]
    fn plan_order_strength_every_other_day_and_short() {
        let secs = |plan: &[Stretch]| -> u32 {
            plan.iter()
                .flat_map(|s| s.steps.iter())
                .map(|l| duration(l).unwrap_or(SETUP_SECONDS))
                .sum()
        };
        let full = plan(
            DEFAULT_STRETCHES,
            Some(DEFAULT_STRENGTH),
            DEFAULT_FLOOR,
            false,
        );
        let names: Vec<String> = full
            .iter()
            .map(|s| crate::posture::split(&s.name).0)
            .collect();
        assert_eq!(
            names,
            vec![
                "斜角肌拉伸",
                "颈后斜拉",
                "横臂拉肩后侧",
                "背后拉手腕",
                "背后扣手抬臂",
                "网球放松",
                "肩袖力量",
                "猫牛式和穿针式",
                "仰躺腹式呼吸"
            ]
        );
        let rest = plan(DEFAULT_STRETCHES, None, DEFAULT_FLOOR, false);
        assert_eq!(rest.len(), 8);
        assert!(secs(&rest) <= 13 * 60, "{}", secs(&rest));
        assert!(secs(&full) - secs(&rest) <= 6 * 60);
        let short = plan(
            DEFAULT_STRETCHES,
            Some(DEFAULT_STRENGTH),
            DEFAULT_FLOOR,
            true,
        );
        assert_eq!(short.len(), 4);
        assert!(secs(&short) <= 6 * 60, "{}", secs(&short));
        let z = Zone::tokyo();
        let today = tokyo(2026, 10, 3, 21, 0, 0);
        let log = |d: &str| BTreeMap::from([(d.to_string(), 1u32)]);
        assert!(includes_strength(&BTreeMap::new(), today, z));
        assert!(!includes_strength(&log("2026-10-02"), today, z));
        assert!(!includes_strength(&log("2026-10-03"), today, z));
        assert!(includes_strength(&log("2026-10-01"), today, z));
    }

    #[test]
    fn breath_pacer_and_log() {
        assert_eq!(breath_total(), 30.0);
        assert_eq!(
            breath_state(0.0),
            BreathState {
                breath: 0,
                inhaling: true,
                remaining: 4,
                finished: false
            }
        );
        assert_eq!(breath_state(3.2).remaining, 1);
        assert_eq!(
            breath_state(4.0),
            BreathState {
                breath: 0,
                inhaling: false,
                remaining: 6,
                finished: false
            }
        );
        assert_eq!(
            breath_state(10.5),
            BreathState {
                breath: 1,
                inhaling: true,
                remaining: 4,
                finished: false
            }
        );
        assert!(breath_state(30.0).finished);
        let z = Zone::tokyo();
        let mut log = BTreeMap::new();
        record(&mut log, "2026-10-01");
        record(&mut log, "2026-10-01");
        record(&mut log, "2026-10-02");
        assert_eq!(log["2026-10-01"], 2);
        assert_eq!(streak(&log, tokyo(2026, 10, 2, 20, 0, 0), z), 2);
        assert_eq!(streak(&log, tokyo(2026, 10, 3, 8, 0, 0), z), 2);
        assert_eq!(streak(&log, tokyo(2026, 10, 5, 8, 0, 0), z), 0);
        for d in 1..=70u32 {
            let key = format!("2026-{:02}-{:02}", 7 + (d - 1) / 31, (d - 1) % 31 + 1);
            record(&mut log, &key);
        }
        assert_eq!(log.len(), 60);
    }

    #[test]
    fn full_width_digits_count_for_the_timer_too() {
        assert_eq!(duration("停 ２０ 秒"), Some(20));
        assert_eq!(duration("做 ８ 次"), Some(32));
        assert_eq!(duration("停 20 秒"), Some(20));
    }
}
