import Foundation

/// 昇降デスクの座り/立ちの切り替えリマインド(判定だけ。通知・アイドル検出はアプリ側)。
/// 会議中と会議の直前は出さない:予定が終わったあとの tick で出る。
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

    /// 胸郭出口症候群(TOS)でもよく勧められる、腕を頭より上げない穏やかな動きだけ。
    /// 神経を引っぱる動き(腕を下に引きながら首を倒す等)や神経滑走は症状を誘発しうるので入れない。
    /// 担当医・理学療法士の指示があれば設定で置き換える前提。
    /// 形式:空行で区切った 1 ブロック = 1 つ。1 行目が名前、続く行が手順
    public static let defaultStretches = """
    肩甲骨寄せ(約 1 分)
    腕を体の横に下ろし、背すじを伸ばす
    肩をすくめずに、肩甲骨を背骨へ寄せる
    5 秒キープして力を抜く。10 回

    あご引き(約 30 秒)
    正面を見たまま、あごを水平に後ろへ引く(二重あごを作る)
    首を下に曲げずに 5 秒キープ
    力を抜いて戻す。5 回

    首の横伸ばし(約 1 分)
    肩の力を抜き、背すじを伸ばす
    頭をゆっくり左へ倒す(左耳を左肩へ)。肩は上げない
    心地よく伸びる所で 20 秒。反対側も

    胸のストレッチ(約 1 分)
    ドア枠や壁の角に、肘を肩より低い位置で当てる
    片足を一歩前へ出し、胸を前へ開く
    20 秒 × 2 回。腕は肩より上げない

    肩回し(約 30 秒)
    腕の力を抜いて下ろす
    肩を前→上→後ろ→下へ、ゆっくり大きく回す
    後ろ回しに 10 回。痛む手前で止める

    腹式呼吸(約 1 分)
    片手をお腹に置く
    鼻から 4 秒吸ってお腹をふくらませる(肩は上げない)
    口から 6 秒かけて吐く。5 回

    歩く(1〜2 分)
    デスクを離れて水を飲みに行く
    腕を自然に振って歩く
    窓の外など遠くを 20 秒見る
    """

    static let caution = "※しびれ・痛みが出たら中止"

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

    /// 画面上部に出す小窓の状態
    public enum Prompt: Equatable, Sendable {
        case askStand   // 「立ちましたか?」
        case standing   // 立ち作業の残り時間 + ストレッチの手順
        case askSit     // 「座りましたか?」
    }

    /// 30 秒ごとの判定:いま出すべき小窓(nil = 出さない)。
    /// Meet の会議中・直前は何も出さない。切り替え時刻を過ぎたら姿勢に応じて尋ね、
    /// 「立った」後の手順表示は立ち作業の終わりまで続ける
    public static func desiredPrompt(posture: Posture, current: Prompt?, now: Date,
                                     dueAt: Date, inMeeting: Bool) -> Prompt? {
        if inMeeting { return nil }
        if now >= dueAt { return posture == .sitting ? .askStand : .askSit }
        return current == .standing ? .standing : nil
    }

    /// 今の姿勢になってから interval 分以上たったか
    public static func isDue(now: Date, since: Date, intervalMinutes: Int) -> Bool {
        now.timeIntervalSince(since) >= TimeInterval(intervalMinutes * 60)
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
            return Stretch(name: "歩く(1〜2 分)", steps: ["デスクを離れて少し歩く"])
        }
        return list[((index % list.count) + list.count) % list.count]
    }

    /// 手順に ①②… を付け、最後に(あれば一言と)中止の目安を添える(メニューのホバー表示用)
    public static func body(for stretch: Stretch, extra: String? = nil) -> String {
        let marks = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
        let steps = stretch.steps.enumerated().map { i, step in
            (i < marks.count ? marks[i] : "\(i + 1).") + " " + step
        }
        return (steps + [extra, caution].compactMap { $0 }).joined(separator: "\n")
    }
}
