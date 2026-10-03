import Foundation

/// 泡澡のあとの日课:いつもの跟练の動画(順に)→ 肩・首の拉伸 → 仰向けの腹式呼吸。
/// 動画は落とさない(著作権と、公開リポジトリに載せないため)。各サイトの公式の埋め込みプレーヤーで順に流す。
/// 拉伸は BreakReminder.stretches と同じ書式(空行区切り、1 行目が名前)。動画は 1 行に 1 本「名前 URL」
public enum Ritual {
    /// 動画 1 本
    public struct Video: Equatable, Sendable {
        public enum Site: String, Sendable {
            case bilibili, youtube, other
        }

        public let title: String
        /// 元のページ(追跡用のクエリは落とす)
        public let page: URL
        public let site: Site
        /// BV 番号 / YouTube の動画 id
        public let id: String?

        /// アプリの中で流す埋め込みプレーヤー(無ければブラウザで開く)
        public var embed: URL? {
            guard let id else { return nil }
            switch site {
            case .bilibili:
                return URL(string: "https://player.bilibili.com/player.html?bvid=\(id)&page=1&autoplay=1&danmaku=0&high_quality=1")
            case .youtube:
                return URL(string: "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&rel=0&playsinline=1")
            case .other:
                return nil
            }
        }
    }

    /// いつもの 4 本(順番どおり)。名前は設定で書き換えられる
    public static let defaultVideos = """
    跟练 1 https://www.bilibili.com/video/BV1JW4y1k7F7/
    跟练 2 https://www.bilibili.com/video/BV1UL411F7Hk/
    跟练 3 https://www.youtube.com/watch?v=SGPBSqxKGAc
    跟练 4 https://www.youtube.com/watch?v=aHlNoTpXf_8
    """

    /// 跟练のあとの拉伸、立ってやる分(先に立ったまま全部やってから床へ。行き来しない)。体が温まっているので 1 回 20〜30 秒、
    /// 左右は別の歩(1 歩ごとに秒を数える)。斜角肌・首の後ろ(肩胛提肌)・肩の後ろ(三角肌後束・小圆肌)・
    /// 肩の上(冈上肌・三角肌中束。腱を挟むので軽く)・肩の前(三角肌前束)・網球でほぐす(壁)
    public static let defaultStretches = """
    斜角肌拉伸（约 2 分钟）
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
    换左边：腋窝后方 45 秒，肩后上方 45 秒
    """

    /// 隔天に足す肩袖の力(床の上。弾力帯は要らない:手で押し合う等長と、水 1 本)。
    /// 鼠标を持つ腕の肩袖は「縮んでいる」より「疲れて持たない」ことが多く、渐进の力量训练がいちばん効く
    public static let defaultStrength = """
    肩袖力量（隔天做，约 6 分钟）
    坐在地上，右手肘贴腰弯 90°，左手握住右手腕；右手往外推、左手顶住不让动，用 5 成力，停 10 秒 × 5 次
    换左手往外推，停 10 秒 × 5 次
    左侧躺，右手拿一瓶水，手肘贴腰弯 90°，前臂慢慢转向天花板再慢慢放下，做 15 次
    换右侧躺，左手拿水，做 15 次
    趴下，两手肘弯成 W 放在身体两侧，收紧肩胛把手肘和手抬离地面，停 3 秒，做 12 次
    """

    /// 床の上の拉伸(背中)と、最後に仰向けの收下巴と腹式呼吸 12 回 = 2 分(寝た姿勢がいちばん腹式呼吸を覚えやすい。
    /// 呼吸を整えるには 2 分くらい続けたい。Windows の DEFAULT_FLOOR と同じ)
    public static let defaultFloor = """
    猫牛式和穿针式（约 2 分钟）
    四点跪姿，吸气塌腰抬头，呼气拱背低头，慢慢做 8 次
    右手从左手下方穿过去，右肩和右耳贴地，停 30 秒
    换另一侧，停 30 秒

    仰躺腹式呼吸（约 3 分钟）
    仰躺，膝盖弯曲，一只手放肚子上，一只手放胸口
    收下巴，后脑轻轻压向地面，停 5 秒 × 5 次
    用鼻子吸气 4 秒只让肚子鼓起来，用嘴呼气 6 秒，做 12 次
    """

    /// 累的晚上の简版(約 5 分):斜角肌・肩の後ろ・網球 1 か所・仰向けの腹式呼吸。続けることが量より大事
    public static let shortStretches = """
    斜角肌拉伸（约 1 分钟）
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
    用鼻子吸气 4 秒只让肚子鼓起来，用嘴呼气 6 秒，做 6 次
    """

    /// 今日の日课に力量を入れるか:隔天(今日・昨日にやっていなければ入れる)
    public static func includesStrength(log: [String: Int], today: Date, calendar: Calendar = .current) -> Bool {
        let todayKey = DayKey.key(for: today, calendar: calendar)
        guard (log[todayKey] ?? 0) == 0 else { return false }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return true }
        return (log[DayKey.key(for: yesterday, calendar: calendar)] ?? 0) == 0
    }

    /// 今日の日课の拉伸の並び:立ってやる分 → (隔天)力量 → 床の上。简版なら简版だけ
    public static func plan(standing: String, strength: String?, floor: String, short: Bool) -> [BreakReminder.Stretch] {
        if short { return BreakReminder.stretches(from: shortStretches) }
        return BreakReminder.stretches(from: standing)
            + BreakReminder.stretches(from: strength ?? "")
            + BreakReminder.stretches(from: floor)
    }

    /// 1 行 1 本。行の中の最初の http(s) から URL、その前が名前(無ければ「视频 N」)
    public static func videos(from text: String) -> [Video] {
        var result: [Video] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let start = line.range(of: "http") else { continue }
            let urlText = line[start.lowerBound...].split(separator: " ").first.map(String.init) ?? ""
            guard let url = URL(string: urlText), url.host != nil else { continue }
            let name = line[..<start.lowerBound].trimmingCharacters(in: .whitespaces)
            result.append(video(url, title: name.isEmpty ? "视频 \(result.count + 1)" : name))
        }
        return result
    }

    static func video(_ url: URL, title: String) -> Video {
        let host = (url.host ?? "").lowercased()
        let parts = url.pathComponents
        if host.hasSuffix("bilibili.com"), let index = parts.firstIndex(of: "video"), index + 1 < parts.count,
           parts[index + 1].hasPrefix("BV") {
            let bv = parts[index + 1]
            return Video(title: title, page: URL(string: "https://www.bilibili.com/video/\(bv)/") ?? url,
                         site: .bilibili, id: bv)
        }
        var youtube: String?
        if host == "youtu.be" {
            youtube = parts.dropFirst().first
        } else if host.hasSuffix("youtube.com") {
            if parts.count >= 3, parts[1] == "shorts" || parts[1] == "embed" || parts[1] == "live" {
                youtube = parts[2]
            } else {
                youtube = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            }
        }
        if let id = youtube, !id.isEmpty {
            return Video(title: title, page: URL(string: "https://www.youtube.com/watch?v=\(id)") ?? url,
                         site: .youtube, id: id)
        }
        return Video(title: title, page: url, site: .other, id: nil)
    }

    /// 1 歩の長さ(秒)。数えられなければ nil(自分で「下一步」を押す)。
    /// 「停 5 秒 × 5 次」= (5 秒 × 5 回)+ 回の間 2 秒、「抬头停 15 秒，再低头停 15 秒」= 30 秒、
    /// 「慢慢做 8 次」= 1 回 4 秒、「走 2 分钟」= 120 秒
    public static func duration(of line: String) -> TimeInterval? {
        let normalized = line.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? line
        let seconds = numbers(in: normalized, pattern: #"(\d+)\s*秒"#)
        let reps = BreakReminder.StepMeta.parse(line).reps
        let total = seconds.reduce(0, +)
        if let reps, reps > 0, total > 0 {
            return TimeInterval(total * reps + (reps - 1) * 2)
        }
        if total > 0 { return TimeInterval(total) }
        if let reps, reps > 0 { return TimeInterval(reps * 4) }
        if let minutes = BreakReminder.StepMeta.parse(line).minutes { return TimeInterval(minutes * 60) }
        return nil
    }

    private static func numbers(in text: String, pattern: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
    }
}

/// 腹式呼吸の節拍(吸う 4 秒・吐く 6 秒を 3 回 = 30 秒)。碎片時間に挟む 1 回分
public enum BreathPacer {
    public static let inhale: TimeInterval = 4
    public static let exhale: TimeInterval = 6
    public static let breaths = 3
    public static var total: TimeInterval { (inhale + exhale) * TimeInterval(breaths) }

    public struct State: Equatable, Sendable {
        /// 何回目か(0 始まり。終わったら breaths)
        public let breath: Int
        public let inhaling: Bool
        /// いまの吸う / 吐くの残り秒(切り上げ)
        public let remaining: Int
        public let finished: Bool

        public init(breath: Int, inhaling: Bool, remaining: Int, finished: Bool) {
            self.breath = breath
            self.inhaling = inhaling
            self.remaining = remaining
            self.finished = finished
        }
    }

    public static func state(elapsed: TimeInterval) -> State {
        let t = max(0, elapsed)
        guard t < total else { return State(breath: breaths, inhaling: false, remaining: 0, finished: true) }
        let cycle = inhale + exhale
        let breath = Int(t / cycle)
        let inCycle = t - Double(breath) * cycle
        if inCycle < inhale {
            return State(breath: breath, inhaling: true, remaining: Int((inhale - inCycle).rounded(.up)),
                         finished: false)
        }
        return State(breath: breath, inhaling: false, remaining: Int((cycle - inCycle).rounded(.up)),
                     finished: false)
    }
}

/// 腹式呼吸の記録(日ごとの回数)。習慣にするための「今日 N 回目」と連続日数
public enum BreathLog {
    /// 古い記録は 60 日で捨てる
    public static func recording(_ log: [String: Int], day: String, keepDays: Int = 60) -> [String: Int] {
        var next = log
        next[day, default: 0] += 1
        if next.count > keepDays {
            for key in next.keys.sorted().prefix(next.count - keepDays) {
                next.removeValue(forKey: key)
            }
        }
        return next
    }

    /// 連続日数(今日まだなら昨日までで数える)
    public static func streak(_ log: [String: Int], today: Date, calendar: Calendar = .current) -> Int {
        var date = today
        if (log[DayKey.key(for: date, calendar: calendar)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var count = 0
        while (log[DayKey.key(for: date, calendar: calendar)] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }
}
