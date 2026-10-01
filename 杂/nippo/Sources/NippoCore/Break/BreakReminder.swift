import Foundation

/// 昇降デスクの座り/立ちの切り替えリマインド(判定だけ。通知・アイドル検出・通話の検出はアプリ側)。
/// 会議中と会議の直前・通話中(マイクかカメラが使われている)は出さない:終わって 1 分たってから出る。
/// 座っていて会議が近づいたら「站着开会？」と聞く(立って会議に出るのが好き、というユーザーの希望)。
public enum BreakReminder {
    /// 机の高さは測れないので、ユーザーの「立った/座った」で切り替える
    public enum Posture: String, Sendable {
        case sitting, standing
    }

    /// ストレッチ 1 つ:名前(目安時間つき)と手順
    public struct Stretch: Equatable, Sendable {
        public let name: String
        public let steps: [String]

        public init(name: String, steps: [String]) {
            self.name = name
            self.steps = steps
        }
    }

    /// 斜角肌の張り(首の横〜鎖骨の上)を狙う既定:斜角肌そのものを伸ばす(第一肋骨を手で押さえて頭を倒す)、
    /// 張りを作る癖を直す(胸で吸う → 腹式呼吸、頭が前に出る → 收下巴、肩をすくめる → 耸肩放松)、
    /// 肩甲骨を支える筋を使う(W 字收肩)。机の前で立ったままできるものだけで、腕を頭より上には上げない。
    /// 坐 / 站 1 回ごとに 1 つずつ回る(7 つ。斜角肌に効くものが半分以上)。担当医・理学療法士の指示があれば設定で置き換える。
    /// 形式:空行で区切った 1 ブロック = 1 つ。1 行目が名前、続く行が手順
    public static let defaultStretches = """
    斜角肌拉伸（约 2 分钟）
    右手按住右侧锁骨下方，固定住第一根肋骨
    头向左倒，拉伸右侧颈部，右肩放松下沉，停 10 秒
    再微微抬头停 10 秒，微微低头停 10 秒
    换另一侧（左手按左侧锁骨下方，头向右倒）

    W 字收肩（约 1 分钟）
    手肘贴着身体弯成 90°，手心朝前
    前臂向外打开，同时把肩胛骨往后、往中间收，不要耸肩
    停 5 秒后放松。做 12 次

    腹式呼吸（约 1 分钟）
    一只手放在肚子上，另一只手放在胸口
    用鼻子吸气 4 秒，只让肚子鼓起来，胸口和肩膀不动
    用嘴慢慢呼气 6 秒。做 6 次

    扩胸拉伸（约 1 分钟）
    前臂竖着贴在门框上，手肘和肩膀差不多高
    一只脚向前迈一步，把胸口向前打开
    停 30 秒 × 2 次

    肩颈三步（约 2 分钟）
    夹肩胛骨：保持 5 秒 × 10 次
    转肩：向后转 10 次
    收下巴：保持 5 秒 × 10 次

    耸肩放松（约 1 分钟）
    肩膀用力耸向耳朵，停 3 秒
    一下子完全放下，感觉脖子两侧松开。做 8 次
    最后向后转肩 10 次

    走一走（1〜2 分钟）
    离开座位去接杯水
    手臂自然摆动地走
    看窗外等远处 20 秒
    """

    public static let caution = "※ 拉伸感可以，发麻或刺痛传到手上就停"

    /// 手順の文の中の数(秒・回・分)。文字の代わりに図と数字で見せるために取り出す
    public struct StepMeta: Equatable, Sendable {
        public var seconds: Int?
        public var reps: Int?
        public var minutes: Int?

        public init(seconds: Int? = nil, reps: Int? = nil, minutes: Int? = nil) {
            self.seconds = seconds
            self.reps = reps
            self.minutes = minutes
        }

        /// 「保持 5 秒后放松。做 10 次」→ 5 秒・10 回。「20 秒 × 2 次」→ 20 秒・2 回。全角数字も読む
        public static func parse(_ text: String) -> StepMeta {
            let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
            func first(_ pattern: String) -> Int? {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                      let range = Range(match.range(at: 1), in: normalized) else { return nil }
                return Int(normalized[range])
            }
            return StepMeta(seconds: first(#"(\d+)\s*秒"#),
                            reps: first(#"(?:×|x|X)\s*(\d+)"#) ?? first(#"(\d+)\s*(?:次|回)"#),
                            minutes: first(#"(\d+)\s*分"#))
        }
    }

    /// ストレッチの絵(Resources/Material/pose-<name>@2x.png の name)。名前と手順のキーワードで選ぶので、設定で書き換えたものにも絵が付く。
    /// 絵は scripts/material/(src/poses/*.svg)で焼いている
    public static func illustration(for stretch: Stretch) -> String {
        let text = ([stretch.name] + stretch.steps).joined()
        let table: [(keys: [String], name: String)] = [
            (["走", "歩", "walk"], "walk"),
            (["呼吸", "息", "breath"], "belly-breathing"),
            (["肩胛", "肩甲", "blade"], "shoulder-blades"),
            (["转肩", "肩回", "转动肩", "roll"], "shoulder-rolls"),
            // 下巴は首より先に(収下巴の手順に「脖子」が出てくる)
            (["下巴", "顎", "あご", "chin"], "chin-tuck"),
            (["颈", "首", "脖", "neck"], "neck-side"),
            (["胸", "chest"], "chest-doorway"),
        ]
        for entry in table where entry.keys.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return entry.name
        }
        return "stretch"
    }

    /// 会議とみなす予定:Google Meet のリンクがあるものだけ(ユーザー指定。
    /// Meet の無い予定は、参加者がいても Zoom 等でも会議扱いしない)
    static func isMeeting(_ e: MeetingEvent) -> Bool {
        !e.isAllDay && e.joinURL?.host?.lowercased() == "meet.google.com"
    }

    /// 会議中、または開始 lead 秒前から開始まで(参加直前に割り込まない)
    public static func isInMeeting(events: [MeetingEvent], now: Date,
                                   lead: TimeInterval = 5 * 60) -> Bool {
        events.contains { e in
            isMeeting(e) && e.start.addingTimeInterval(-lead) <= now && now < e.end
        }
    }

    /// 会前に「站着开会？」と聞く時間:開始の 10 分前から開始まで
    public static let meetingAskWindow: TimeInterval = 10 * 60
    /// 座ってからこれより短ければ会前に聞かない(立ち終えて座った直後に、また立つか聞かない)
    public static let meetingAskMinimumSitting: TimeInterval = 10 * 60
    /// 会議・通話が終わってから小窓を出すまで待つ時間(会議が延びた・すぐ次の通話に入る)
    public static let afterMeetingGrace: TimeInterval = 60
    /// 「开完会了」と添えるのは、5 分以上続いた会議・通話が終わって 10 分以内(音声入力や短い通話には添えない)
    public static let afterMeetingMinimum: TimeInterval = 5 * 60
    public static let afterMeetingWording: TimeInterval = 10 * 60
    /// 水を持って入るほど長い会議
    public static let longMeeting: TimeInterval = 45 * 60

    /// 予定より早く終わった会議を除く:5 分以上続いた通話が会議の開始後に終わっていれば(いまは通話していない前提)、
    /// その会議は終わったとみなし、予定の終わりまで待たずに聞く。短いマイク(音声入力など)では終わらせない
    /// (電話で出ている会議の最中に音声入力しても、会議は続いている)。通話を見張っていないときは lastCall = nil
    public static func excludingEndedEarly(_ events: [MeetingEvent], now: Date,
                                           lastCall: DateInterval?) -> [MeetingEvent] {
        guard let call = lastCall, call.end <= now, call.duration >= afterMeetingMinimum else { return events }
        return events.filter { !($0.start < call.end && now < $0.end) }
    }

    /// 問いに「开完会了」と添えるか:busySince〜lastBusyAt の会議・通話が 5 分以上続き、終わって 10 分以内
    public static func saysAfterMeeting(now: Date, busySince: Date?, lastBusyAt: Date?) -> Bool {
        guard let since = busySince, let last = lastBusyAt else { return false }
        return last.timeIntervalSince(since) >= afterMeetingMinimum
            && now.timeIntervalSince(last) < afterMeetingWording
    }

    public static func isLong(_ meeting: MeetingEvent) -> Bool {
        meeting.end.timeIntervalSince(meeting.start) >= longMeeting
    }

    /// これから始まる会議のうち、いちばん近いもの(開始の window 秒前から開始まで。始まったものは含まない)
    public static func upcomingMeeting(events: [MeetingEvent], now: Date,
                                       window: TimeInterval = meetingAskWindow) -> MeetingEvent? {
        events
            .filter { isMeeting($0) && $0.start > now && $0.start.timeIntervalSince(now) <= window }
            .min { $0.start < $1.start }
    }

    /// 「站着开会？」と聞く会議(nil = 聞かない):座っていて(10 分以上)、10 分以内に会議が始まり、
    /// その会議にまだ答えていないとき。別の会議の最中は聞かない(連続した会議は前の会議が終わってから)
    public static func meetingStandAsk(events: [MeetingEvent], now: Date, posture: Posture,
                                       sittingSince: Date, answered: Set<String>) -> MeetingEvent? {
        guard posture == .sitting,
              now.timeIntervalSince(sittingSince) >= meetingAskMinimumSitting,
              !isInMeeting(events: events, now: now, lead: 0),
              let next = upcomingMeeting(events: events, now: now),
              !answered.contains(next.id) else { return nil }
        return next
    }

    /// 離席の判定に使う無操作の秒数:会議・通話のあいだの無操作は数えない
    /// (聞いているだけで操作しない。終わった瞬間に「3 分以上操作なし = 離席」と数えて座った時間を消さないように)
    public static func awayIdle(idle: TimeInterval, now: Date, lastBusyAt: Date?) -> TimeInterval {
        guard let lastBusyAt else { return idle }
        return min(idle, max(0, now.timeIntervalSince(lastBusyAt)))
    }

    /// 画面上部に出す小窓の状態
    public enum Prompt: Equatable, Sendable {
        case askStand   // 「立ちましたか?」
        case standing   // 立ち作業の残り時間 + ストレッチの手順
        case askSit     // 「座りましたか?」
        case standForMeeting   // 会前:「站着开会？」
    }

    /// 30 秒ごとの判定:いま出すべき小窓(nil = 出さない)。
    /// 通話中は何も出さない。座っていて会議が近ければ「站着开会？」(開始前 5 分の中でも聞く:会議の話なので割り込みではない)。
    /// Meet の会議中・直前と、会議・通話が終わって quietUntil までは出さない。
    /// 切り替え時刻を過ぎたら姿勢に応じて尋ね、「立った」後の手順表示は立ち作業の終わりまで続ける
    public static func desiredPrompt(posture: Posture, current: Prompt?, now: Date,
                                     dueAt: Date, inMeeting: Bool, guideDismissed: Bool = false,
                                     inCall: Bool = false, standForMeeting: Bool = false,
                                     quietUntil: Date? = nil) -> Prompt? {
        if inCall { return nil }
        if standForMeeting, posture == .sitting { return .standForMeeting }
        if inMeeting { return nil }
        if let quietUntil, now < quietUntil { return nil }
        if now >= dueAt { return posture == .sitting ? .askStand : .askSit }
        // 立ち作業中は(自分で閉じていなければ)手順の小窓を出し続ける。会議で隠れても終われば戻る
        if posture == .standing { return guideDismissed ? nil : .standing }
        return nil
    }

    /// 空行区切りのブロックを 1 つずつ読む(1 行目が名前、続く行が手順)。前後の空白は捨てる
    public static func stretches(from text: String) -> [Stretch] {
        var result: [Stretch] = []
        var block: [String] = []
        for raw in text.components(separatedBy: .newlines) + [""] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if let name = block.first {
                    result.append(Stretch(name: name, steps: Array(block.dropFirst())))
                }
                block = []
            } else {
                block.append(line)
            }
        }
        return result
    }

    /// 順番に回す(リストが空なら「歩く」だけ)
    public static func stretch(at index: Int, in list: [Stretch]) -> Stretch {
        guard !list.isEmpty else {
            return Stretch(name: "走一走（1〜2 分钟）", steps: ["离开座位走一走"])
        }
        return list[((index % list.count) + list.count) % list.count]
    }

}
