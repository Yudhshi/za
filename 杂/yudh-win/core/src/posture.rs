//! 坐站の切り替え(Swift の `BreakReminder` / `StretchGuide` / `AppCoordinator+Posture` の判定だけ)。
//! Windows はカレンダーを読まないので会議の判定は無い。代わりに全画面のゲーム中(`suppressed`)は小窓を出さない

use chrono::{DateTime, Duration, Utc};
use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Posture {
    Sitting,
    Standing,
}

/// 画面に出す小窓
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Prompt {
    /// 站起来了吗?
    AskStand,
    /// 立ち作業の残り時間 + 拉伸の手順
    Standing,
    /// 坐下了吗?
    AskSit,
}

/// 拉伸 1 つ:名前(目安時間つき)と手順
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Stretch {
    pub name: String,
    pub steps: Vec<String>,
}

/// Mac と同じ既定の拉伸(腕を頭より上げない穏やかな動きだけ。空行区切り、1 行目が名前)
pub const DEFAULT_STRETCHES: &str = "夹肩胛骨（约 1 分钟）
手臂自然垂在身体两侧，挺直背
不要耸肩，把肩胛骨往脊柱方向夹紧
保持 5 秒后放松。做 10 次

收下巴（约 30 秒）
目视前方，下巴水平向后收（做出双下巴）
脖子不要往下弯，保持 5 秒
放松还原。做 5 次

颈部侧拉（约 1 分钟）
放松肩膀，挺直背
头慢慢向左倾（左耳靠向左肩），肩膀不要抬
在舒服的拉伸位置停 20 秒。换另一侧

扩胸拉伸（约 1 分钟）
手肘贴在门框或墙角上，高度低于肩膀
一只脚向前迈一步，把胸口向前打开
20 秒 × 2 次。手臂不要高过肩膀

转肩（约 30 秒）
手臂放松垂下
肩膀按 前 → 上 → 后 → 下 慢慢大幅度地转
向后转 10 次。快要疼之前就停

腹式呼吸（约 1 分钟）
一只手放在肚子上
用鼻子吸气 4 秒，让肚子鼓起来（肩膀不要抬）
用嘴慢慢呼气 6 秒。做 5 次

走一走（1〜2 分钟）
离开座位去接杯水
手臂自然摆动地走
看窗外等远处 20 秒

肩颈三步（约 2 分钟）
夹肩胛骨：保持 5 秒 × 10 次
转肩：向后转 10 次
收下巴：保持 5 秒 × 5 次";

pub const CAUTION: &str = "※ 如有麻木或疼痛请停止";

/// 空行区切りのブロックを 1 つずつ読む(1 行目が名前、続く行が手順)
pub fn stretches(text: &str) -> Vec<Stretch> {
    let mut result = Vec::new();
    let mut block: Vec<String> = Vec::new();
    for raw in text.lines().chain(std::iter::once("")) {
        let line = raw.trim();
        if line.is_empty() {
            if let Some((name, steps)) = block.split_first() {
                result.push(Stretch {
                    name: name.clone(),
                    steps: steps.to_vec(),
                });
            }
            block.clear();
        } else {
            block.push(line.to_string());
        }
    }
    result
}

/// 順番に回す(リストが空なら「走一走」だけ)
pub fn stretch_at(index: usize, list: &[Stretch]) -> Stretch {
    if list.is_empty() {
        return Stretch {
            name: "走一走（1〜2 分钟）".into(),
            steps: vec!["离开座位走一走".into()],
        };
    }
    list[index % list.len()].clone()
}

/// 拉伸の絵(Mac の素材 pose-<name>)。名前と手順のキーワードで選ぶ
pub fn illustration(stretch: &Stretch) -> &'static str {
    let text = std::iter::once(stretch.name.as_str())
        .chain(stretch.steps.iter().map(String::as_str))
        .collect::<String>()
        .to_lowercase();
    let table: [(&[&str], &str); 7] = [
        (&["走", "歩", "walk"], "walk"),
        (&["呼吸", "息", "breath"], "belly-breathing"),
        (&["肩胛", "肩甲", "blade"], "shoulder-blades"),
        (&["转肩", "肩回", "转动肩", "roll"], "shoulder-rolls"),
        // 下巴は首より先に(收下巴の手順に「脖子」が出てくる)
        (&["下巴", "顎", "あご", "chin"], "chin-tuck"),
        (&["颈", "首", "脖", "neck"], "neck-side"),
        (&["胸", "chest"], "chest-doorway"),
    ];
    table
        .iter()
        .find(|(keys, _)| keys.iter().any(|k| text.contains(k)))
        .map_or("stretch", |(_, name)| name)
}

// MARK: 手順の数(秒・回・分)

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StepMeta {
    pub seconds: Option<u32>,
    pub reps: Option<u32>,
    pub minutes: Option<u32>,
}

fn halfwidth(text: &str) -> Vec<char> {
    text.chars()
        .map(|c| match c {
            '\u{FF01}'..='\u{FF5E}' => char::from_u32(c as u32 - 0xFEE0).unwrap_or(c),
            '\u{3000}' => ' ',
            _ => c,
        })
        .collect()
}

/// 数字の並びの後(空白を飛ばして)に unit のどれかが来る、最初の数
fn number_before(chars: &[char], units: &[char]) -> Option<u32> {
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
            if j < chars.len() && units.contains(&chars[j]) {
                return chars[start..i].iter().collect::<String>().parse().ok();
            }
        } else {
            i += 1;
        }
    }
    None
}

/// marker のどれかの後(空白を飛ばして)に来る、最初の数(「× 2」)
fn number_after(chars: &[char], markers: &[char]) -> Option<u32> {
    for (i, c) in chars.iter().enumerate() {
        if !markers.contains(c) {
            continue;
        }
        let mut j = i + 1;
        while j < chars.len() && chars[j].is_whitespace() {
            j += 1;
        }
        let start = j;
        while j < chars.len() && chars[j].is_ascii_digit() {
            j += 1;
        }
        if j > start {
            return chars[start..j].iter().collect::<String>().parse().ok();
        }
    }
    None
}

impl StepMeta {
    /// 「保持 5 秒后放松。做 10 次」→ 5 秒・10 回。「20 秒 × 2 次」→ 20 秒・2 回(× が先)。全角数字も読む
    pub fn parse(text: &str) -> StepMeta {
        let chars = halfwidth(text);
        StepMeta {
            seconds: number_before(&chars, &['秒']),
            reps: number_after(&chars, &['×', 'x', 'X'])
                .or_else(|| number_before(&chars, &['次', '回'])),
            minutes: number_before(&chars, &['分']),
        }
    }
}

// MARK: 拉伸の見せ方(StretchGuide)

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Step {
    /// 姿勢の絵の名前
    pub pose: String,
    /// 壁画带の札:姿勢が混ざるなら姿勢の名前、全部同じなら「第 N 步」
    pub name: String,
    pub text: String,
    /// 5 秒 · 10 次 / 10 次 / 20 秒 / 1 分钟
    pub meta: Option<String>,
}

/// 壁画带の絵がある姿勢と短い名前
pub fn frieze_name(pose: &str) -> Option<&'static str> {
    match pose {
        "shoulder-blades" => Some("夹肩胛骨"),
        "shoulder-rolls" => Some("转肩"),
        "chin-tuck" => Some("收下巴"),
        _ => None,
    }
}

/// 「夹肩胛骨（约 1 分钟）」→(夹肩胛骨, 1 分钟)
pub fn split(name: &str) -> (String, Option<String>) {
    let Some(open) = name.find(['（', '(']) else {
        return (name.trim().to_string(), None);
    };
    let title = name[..open].trim();
    let open_len = name[open..].chars().next().map_or(1, char::len_utf8);
    let mut inside = &name[open + open_len..];
    if let Some(close) = inside.rfind(['）', ')']) {
        inside = &inside[..close];
    }
    let mut note = inside.trim();
    if let Some(rest) = note.strip_prefix('约') {
        note = rest.trim();
    }
    let title = if title.is_empty() { name } else { title };
    (
        title.to_string(),
        (!note.is_empty()).then(|| note.to_string()),
    )
}

/// 「夹肩胛骨 · 1 分钟」
pub fn display_name(name: &str) -> String {
    match split(name) {
        (title, Some(note)) => format!("{title} · {note}"),
        (title, None) => title,
    }
}

pub fn meta_text(line: &str) -> Option<String> {
    let m = StepMeta::parse(line);
    match (m.seconds, m.reps, m.minutes) {
        (Some(s), Some(r), _) => Some(format!("{s} 秒 · {r} 次")),
        (Some(s), None, _) => Some(format!("{s} 秒")),
        (None, Some(r), _) => Some(format!("{r} 次")),
        (None, None, Some(min)) => Some(format!("{min} 分钟")),
        _ => None,
    }
}

/// 「转肩：向后转 10 次」→「向后转 10 次」(残りが空ならそのまま)
fn dropping(prefix: &str, line: &str) -> String {
    let Some(rest) = line.strip_prefix(prefix) else {
        return line.to_string();
    };
    let rest = rest.trim_start_matches(' ');
    let Some(rest) = rest.strip_prefix(['：', ':']) else {
        return line.to_string();
    };
    let text = rest.trim();
    if text.is_empty() {
        line.to_string()
    } else {
        text.to_string()
    }
}

/// 手順ごとの姿勢。手順の文が壁画带の姿勢を名指しているときだけ、それに替える
pub fn steps(stretch: &Stretch) -> Vec<Step> {
    let base = illustration(stretch);
    let poses: Vec<&str> = stretch
        .steps
        .iter()
        .map(|line| {
            let own = illustration(&Stretch {
                name: line.clone(),
                steps: vec![],
            });
            if frieze_name(own).is_some() {
                own
            } else {
                base
            }
        })
        .collect();
    let mut distinct = poses.clone();
    distinct.sort();
    distinct.dedup();
    let mixed = distinct.len() > 1;
    stretch
        .steps
        .iter()
        .enumerate()
        .map(|(i, line)| {
            let pose = poses[i];
            let named = if mixed { frieze_name(pose) } else { None };
            Step {
                pose: pose.to_string(),
                name: named.map_or_else(|| format!("第 {} 步", i + 1), str::to_string),
                text: named.map_or_else(|| line.clone(), |n| dropping(n, line)),
                meta: meta_text(line),
            }
        })
        .collect()
}

/// 壁画带にするか:2〜3 歩で、姿勢が全部違い、どれも壁画带の絵がある
pub fn shows_frieze(steps: &[Step]) -> bool {
    let mut poses: Vec<&str> = steps.iter().map(|s| s.pose.as_str()).collect();
    poses.sort();
    poses.dedup();
    (2..=3).contains(&steps.len())
        && poses.len() == steps.len()
        && steps.iter().all(|s| frieze_name(&s.pose).is_some())
}

/// 今の手順の見出し
pub fn heading(stretch: &Stretch, steps: &[Step], index: usize) -> String {
    let mixed = steps.iter().any(|s| s.pose != steps[0].pose);
    if mixed {
        if let Some(name) = steps.get(index).and_then(|s| frieze_name(&s.pose)) {
            return name.to_string();
        }
    }
    split(&stretch.name).0
}

/// 残り時間「12:30」(秒は切り上げ、分は 2 桁、過ぎたら 00:00)
pub fn clock(due: DateTime<Utc>, now: DateTime<Utc>) -> String {
    let millis = (due - now).num_milliseconds().max(0);
    let seconds = (millis + 999) / 1000;
    format!("{:02}:{:02}", seconds / 60, seconds % 60)
}

// MARK: 判定と状態

/// 30 秒ごとの判定:いま出すべき小窓。全画面のゲーム中は何も出さない。
/// 切り替え時刻を過ぎたら姿勢に応じて尋ね、立った後の手順は立ち作業の終わりまで出し続ける
pub fn desired_prompt(
    posture: Posture,
    now: DateTime<Utc>,
    due_at: DateTime<Utc>,
    suppressed: bool,
    guide_dismissed: bool,
) -> Option<Prompt> {
    if suppressed {
        return None;
    }
    if now >= due_at {
        return Some(match posture {
            Posture::Sitting => Prompt::AskStand,
            Posture::Standing => Prompt::AskSit,
        });
    }
    if posture == Posture::Standing && !guide_dismissed {
        return Some(Prompt::Standing);
    }
    None
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PostureSettings {
    pub enabled: bool,
    pub sit_minutes: i64,
    pub stand_minutes: i64,
    pub stretches: String,
}

impl Default for PostureSettings {
    fn default() -> Self {
        PostureSettings {
            enabled: true,
            sit_minutes: 45,
            stand_minutes: 15,
            stretches: DEFAULT_STRETCHES.to_string(),
        }
    }
}

/// 坐站の状態(Mac の AppCoordinator+Posture と同じ動き)
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PostureClock {
    pub posture: Posture,
    pub since: DateTime<Utc>,
    /// 「15 分后」などで決めた次の時刻(優先)
    pub remind_at: Option<DateTime<Utc>>,
    pub prompt: Option<Prompt>,
    /// 立ち作業中に自分で閉じた手順
    pub guide_dismissed: bool,
    /// トレイから自分で開いた「站起来了吗?」(時間前でも閉じない)
    pub pinned: bool,
    /// 次に出す拉伸の番号(実際に立ったときに進める)
    pub stretch_index: usize,
    pub stretch: Stretch,
    /// 手順の何番目か(steps.len() = 完了)
    pub step: usize,
}

/// 座っているあいだ、これだけ操作がなければ離席とみなして計り直す(秒)
pub const IDLE_RESET_SECONDS: u64 = 180;

impl PostureClock {
    pub fn new(now: DateTime<Utc>, stretch_index: usize) -> PostureClock {
        PostureClock {
            posture: Posture::Sitting,
            since: now,
            remind_at: None,
            prompt: None,
            guide_dismissed: false,
            pinned: false,
            stretch_index,
            stretch: Stretch {
                name: String::new(),
                steps: vec![],
            },
            step: 0,
        }
    }

    pub fn due_at(&self, settings: &PostureSettings) -> DateTime<Utc> {
        let minutes = match self.posture {
            Posture::Sitting => settings.sit_minutes,
            Posture::Standing => settings.stand_minutes,
        };
        self.remind_at
            .unwrap_or(self.since + Duration::minutes(minutes))
    }

    fn list(settings: &PostureSettings) -> Vec<Stretch> {
        stretches(&settings.stretches)
    }

    /// 次に出す拉伸(トレイのメニューにも予告する)
    pub fn next_stretch(&self, settings: &PostureSettings) -> Stretch {
        stretch_at(self.stretch_index, &Self::list(settings))
    }

    fn pick_stretch(&mut self, settings: &PostureSettings) {
        self.stretch = self.next_stretch(settings);
        self.step = 0;
    }

    pub fn reset(&mut self, now: DateTime<Utc>) {
        self.since = now;
        self.remind_at = None;
    }

    /// 定期の判定。小窓が変わったら true
    pub fn check(
        &mut self,
        now: DateTime<Utc>,
        settings: &PostureSettings,
        idle_seconds: u64,
        suppressed: bool,
    ) -> bool {
        if !settings.enabled {
            let changed = self.prompt.is_some();
            self.prompt = None;
            return changed;
        }
        // 座りっぱなしの計測だけ離席でリセット(立ち作業の残り時間は巻き戻さない)
        if self.posture == Posture::Sitting
            && self.prompt.is_none()
            && !suppressed
            && idle_seconds >= IDLE_RESET_SECONDS
        {
            self.reset(now);
        }
        let desired = desired_prompt(
            self.posture,
            now,
            self.due_at(settings),
            suppressed,
            self.guide_dismissed,
        );
        if desired.is_none() && self.pinned && self.prompt == Some(Prompt::AskStand) && !suppressed
        {
            return false;
        }
        if desired == self.prompt {
            return false;
        }
        self.pinned = false;
        if desired == Some(Prompt::AskStand) {
            self.pick_stretch(settings);
        }
        self.prompt = desired;
        true
    }

    /// 「站起来了」:立ち作業の残り時間と拉伸の手順を出す
    pub fn confirm_stood(&mut self, now: DateTime<Utc>, settings: &PostureSettings) {
        if self.prompt != Some(Prompt::AskStand) {
            self.pick_stretch(settings);
        }
        // 実際に立ったときに初めて「この拉伸はやった」と数える
        let count = Self::list(settings).len().max(1);
        self.stretch_index = (self.stretch_index + 1) % count;
        self.posture = Posture::Standing;
        self.reset(now);
        self.guide_dismissed = false;
        self.pinned = false;
        self.prompt = Some(Prompt::Standing);
    }

    /// 「坐下了」
    pub fn confirm_sat(&mut self, now: DateTime<Utc>) {
        self.posture = Posture::Sitting;
        self.reset(now);
        self.guide_dismissed = false;
        self.pinned = false;
        self.prompt = None;
    }

    /// 「15 分后」「再 5 分钟」
    pub fn snooze(&mut self, now: DateTime<Utc>, minutes: i64) {
        self.remind_at = Some(now + Duration::minutes(minutes));
        self.pinned = false;
        self.prompt = None;
    }

    /// トレイから開く:立ち作業中は手順、座り作業中は「站起来了吗?」(切り替え時刻は変えない)
    pub fn open_prompt(&mut self, settings: &PostureSettings) {
        match self.posture {
            Posture::Standing => {
                self.guide_dismissed = false;
                self.prompt = Some(Prompt::Standing);
            }
            Posture::Sitting => {
                self.pinned = true;
                if self.prompt != Some(Prompt::AskStand) {
                    self.pick_stretch(settings);
                }
                self.prompt = Some(Prompt::AskStand);
            }
        }
    }

    pub fn close_prompt(&mut self) {
        self.guide_dismissed = self.posture == Posture::Standing;
        self.pinned = false;
        self.prompt = None;
    }

    pub fn move_step(&mut self, delta: i64) {
        let max = self.stretch.steps.len() as i64;
        self.step = (self.step as i64 + delta).clamp(0, max) as usize;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::day::testing::tokyo;

    #[test]
    fn step_meta_reads_seconds_reps_minutes() {
        assert_eq!(
            StepMeta::parse("保持 5 秒后放松。做 10 次"),
            StepMeta {
                seconds: Some(5),
                reps: Some(10),
                minutes: None
            }
        );
        assert_eq!(
            StepMeta::parse("20 秒 × 2 次。手臂不要高过肩膀"),
            StepMeta {
                seconds: Some(20),
                reps: Some(2),
                minutes: None
            },
            "× 2 wins over 2 次"
        );
        assert_eq!(
            StepMeta::parse("用鼻子吸气 4 秒，让肚子鼓起来").seconds,
            Some(4)
        );
        assert_eq!(
            StepMeta::parse("向后转 １０ 次"),
            StepMeta {
                reps: Some(10),
                ..Default::default()
            }
        );
        assert_eq!(StepMeta::parse("放松肩膀"), StepMeta::default());
    }

    #[test]
    fn defaults_parse_and_pick_illustrations() {
        let list = stretches(DEFAULT_STRETCHES);
        assert_eq!(list.len(), 8);
        assert!(list.iter().all(|s| s.steps.len() >= 2));
        let pics: Vec<&str> = list.iter().map(illustration).collect();
        assert_eq!(
            pics,
            vec![
                "shoulder-blades",
                "chin-tuck",
                "neck-side",
                "chest-doorway",
                "shoulder-rolls",
                "belly-breathing",
                "walk",
                "shoulder-blades"
            ]
        );
        let custom = Stretch {
            name: "自定义".into(),
            steps: vec!["随便动一动".into()],
        };
        assert_eq!(illustration(&custom), "stretch");
        let parsed = stretches("\n  肩回し(約 30 秒)\n  肩を後ろへ回す\n\n\n首(1 分)\n");
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].steps, vec!["肩を後ろへ回す"]);
        assert!(parsed[1].steps.is_empty());
        assert_eq!(stretch_at(9, &list).name, list[1].name, "wraps around");
        assert_eq!(stretch_at(0, &[]).name, "走一走（1〜2 分钟）");
    }

    #[test]
    fn guide_names_frieze_and_clock() {
        assert_eq!(
            split("夹肩胛骨（约 1 分钟）"),
            ("夹肩胛骨".into(), Some("1 分钟".into()))
        );
        assert_eq!(split("走一走（1〜2 分钟）").1.as_deref(), Some("1〜2 分钟"));
        assert_eq!(split("肩回し(約 30 秒)").0, "肩回し");
        assert_eq!(split("自定义").1, None);
        assert_eq!(display_name("夹肩胛骨（约 1 分钟）"), "夹肩胛骨 · 1 分钟");
        assert_eq!(display_name("  自定义 "), "自定义");

        let list = stretches(DEFAULT_STRETCHES);
        let combo = &list[7];
        let s = steps(combo);
        let poses: Vec<&str> = s.iter().map(|x| x.pose.as_str()).collect();
        assert_eq!(
            poses,
            vec!["shoulder-blades", "shoulder-rolls", "chin-tuck"]
        );
        let names: Vec<&str> = s.iter().map(|x| x.name.as_str()).collect();
        assert_eq!(names, vec!["夹肩胛骨", "转肩", "收下巴"]);
        let texts: Vec<&str> = s.iter().map(|x| x.text.as_str()).collect();
        assert_eq!(
            texts,
            vec!["保持 5 秒 × 10 次", "向后转 10 次", "保持 5 秒 × 5 次"]
        );
        assert!(shows_frieze(&s));
        assert_eq!(heading(combo, &s, 1), "转肩");
        assert_eq!(heading(combo, &s, 3), "肩颈三步", "done → stretch title");

        let blades = steps(&list[0]);
        let names: Vec<&str> = blades.iter().map(|x| x.name.as_str()).collect();
        assert_eq!(names, vec!["第 1 步", "第 2 步", "第 3 步"]);
        assert!(!shows_frieze(&blades));
        assert_eq!(heading(&list[0], &blades, 0), "夹肩胛骨");
        let friezes: Vec<&str> = list
            .iter()
            .filter(|x| shows_frieze(&steps(x)))
            .map(|x| x.name.as_str())
            .collect();
        assert_eq!(friezes, vec!["肩颈三步（约 2 分钟）"]);
        let guide = |lines: &[&str]| {
            steps(&Stretch {
                name: "自定义".into(),
                steps: lines.iter().map(|l| l.to_string()).collect(),
            })
        };
        assert!(shows_frieze(&guide(&["夹肩胛骨 10 次", "收下巴 5 次"])));
        assert!(!shows_frieze(&guide(&["夹肩胛骨 10 次", "扩胸 20 秒"])));
        assert!(!shows_frieze(&guide(&["夹肩胛骨 10 次"])));
        assert!(!shows_frieze(&guide(&[
            "夹肩胛骨",
            "转肩",
            "收下巴",
            "夹肩胛骨 again"
        ])));
        assert!(!shows_frieze(&guide(&[])));
        let texts: Vec<String> = guide(&["夹肩胛骨：", "转肩: 向后 10 次"])
            .into_iter()
            .map(|x| x.text)
            .collect();
        assert_eq!(texts, vec!["夹肩胛骨：", "向后 10 次"]);

        assert_eq!(
            meta_text("保持 5 秒后放松。做 10 次").as_deref(),
            Some("5 秒 · 10 次")
        );
        assert_eq!(meta_text("向后转 10 次").as_deref(), Some("10 次"));
        assert_eq!(meta_text("看窗外等远处 20 秒").as_deref(), Some("20 秒"));
        assert_eq!(meta_text("走 2 分钟").as_deref(), Some("2 分钟"));
        assert_eq!(meta_text("放松肩膀"), None);
        let now = tokyo(2026, 10, 1, 10, 0, 0);
        assert_eq!(clock(now + Duration::seconds(750), now), "12:30");
        assert_eq!(
            clock(now + Duration::milliseconds(599_200), now),
            "10:00",
            "seconds round up"
        );
        assert_eq!(clock(now + Duration::seconds(59), now), "00:59");
        assert_eq!(clock(now - Duration::seconds(30), now), "00:00");
        assert_eq!(clock(now + Duration::minutes(100), now), "100:00");
    }

    #[test]
    fn prompts_follow_the_timer_and_stay_quiet_in_games() {
        let t0 = tokyo(2026, 10, 1, 20, 0, 0);
        let due = t0 + Duration::minutes(45);
        assert_eq!(
            desired_prompt(Posture::Sitting, t0, due, false, false),
            None
        );
        assert_eq!(
            desired_prompt(Posture::Sitting, due, due, false, false),
            Some(Prompt::AskStand)
        );
        assert_eq!(
            desired_prompt(Posture::Sitting, due, due, true, false),
            None,
            "fullscreen game"
        );
        assert_eq!(
            desired_prompt(Posture::Standing, t0, due, false, false),
            Some(Prompt::Standing)
        );
        assert_eq!(
            desired_prompt(Posture::Standing, t0, due, false, true),
            None,
            "guide closed"
        );
        assert_eq!(
            desired_prompt(Posture::Standing, due, due, false, true),
            Some(Prompt::AskSit)
        );
    }

    #[test]
    fn clock_runs_sit_stand_sit_with_idle_reset_and_snooze() {
        let settings = PostureSettings::default();
        let t0 = tokyo(2026, 10, 1, 20, 0, 0);
        let mut c = PostureClock::new(t0, 7);
        // 離席(3 分無操作)で座りの計測をやり直す
        assert!(!c.check(t0 + Duration::minutes(30), &settings, 200, false));
        assert_eq!(c.since, t0 + Duration::minutes(30));
        // 45 分たつと「站起来了吗?」、拉伸は 8 番目(肩颈三步)
        let ask = c.since + Duration::minutes(45);
        assert!(c.check(ask, &settings, 0, false));
        assert_eq!(c.prompt, Some(Prompt::AskStand));
        assert_eq!(c.stretch.name, "肩颈三步（约 2 分钟）");
        // ゲームを全画面にしたら引っ込む
        assert!(c.check(ask, &settings, 0, true));
        assert_eq!(c.prompt, None);
        assert!(c.check(ask + Duration::seconds(30), &settings, 0, false));
        c.confirm_stood(ask + Duration::minutes(1), &settings);
        assert_eq!(c.posture, Posture::Standing);
        assert_eq!(c.prompt, Some(Prompt::Standing));
        assert_eq!(
            c.stretch_index, 0,
            "next time starts over from the first stretch"
        );
        c.move_step(5);
        assert_eq!(c.step, 3, "clamped to done");
        c.move_step(-1);
        assert_eq!(c.step, 2);
        c.close_prompt();
        assert!(c.guide_dismissed);
        assert!(
            !c.check(ask + Duration::minutes(5), &settings, 0, false),
            "closed guide stays closed"
        );
        let sit = ask + Duration::minutes(16);
        assert!(c.check(sit, &settings, 0, false));
        assert_eq!(c.prompt, Some(Prompt::AskSit));
        c.snooze(sit, 5);
        assert_eq!(c.due_at(&settings), sit + Duration::minutes(5));
        assert!(!c.check(sit + Duration::minutes(4), &settings, 0, false));
        assert!(c.check(sit + Duration::minutes(5), &settings, 0, false));
        c.confirm_sat(sit + Duration::minutes(5));
        assert_eq!((c.posture, c.prompt), (Posture::Sitting, None));
        // トレイから開いた「站起来了吗?」は時間前でも閉じない
        c.open_prompt(&settings);
        assert!(c.pinned);
        assert!(!c.check(sit + Duration::minutes(6), &settings, 0, false));
        assert_eq!(c.prompt, Some(Prompt::AskStand));
        let off = PostureSettings {
            enabled: false,
            ..PostureSettings::default()
        };
        assert!(c.check(sit + Duration::minutes(7), &off, 0, false));
        assert_eq!(c.prompt, None);
    }
}
