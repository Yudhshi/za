import Foundation

/// 今日の主角卡(選んだ会議 1 つ)の状態と、大数字・時長の格・画面を描き直す時刻。
/// 静 = 開始 10 分より前 / 動 = 開始 10 分前から終わるまで(始まって 1 分は到点の 00)/ 終わった
public enum HeroPolicy {
    public enum Phase: Equatable, Sendable {
        case calm, event, zero, ended
    }

    /// 大数字の横の単位(文言は画面の側で決める)
    public enum Unit: Equatable, Sendable {
        /// 12 分钟后
        case minutesUntil
        /// 16:30 开始(60 分以上先)
        case startsAt
        /// 还剩 48 分钟
        case minutesLeft
        /// 17:30 结束(60 分以上続く)
        case endsAt
        /// 00 到点了
        case zero
        /// 已结束
        case ended
    }

    public struct Display: Equatable, Sendable {
        /// 大数字(分は 2 桁「04」、時刻「16:30」、到点「00」、終わった「-」)
        public var value: String
        public var unit: Unit

        public init(value: String, unit: Unit) {
            self.value = value
            self.unit = unit
        }
    }

    /// 動になるのは開始の何秒前から
    public static let eventLead: TimeInterval = 10 * 60
    /// 到点(00、橙)の長さ
    public static let zeroSpan: TimeInterval = 60

    public static func phase(for event: MeetingEvent, now: Date) -> Phase {
        guard event.end > now else { return .ended }
        if event.start <= now {
            return now.timeIntervalSince(event.start) < zeroSpan ? .zero : .event
        }
        return event.start.timeIntervalSince(now) <= eventLead ? .event : .calm
    }

    /// 大数字と単位。分は切り上げ(NextEventPolicy.heroCountdown と同じ数え方)で 2 桁にそろえる
    public static func display(for event: MeetingEvent, now: Date, calendar: Calendar = .current) -> Display {
        switch phase(for: event, now: now) {
        case .ended:
            return Display(value: "-", unit: .ended)
        case .zero:
            return Display(value: "00", unit: .zero)
        case .calm, .event:
            break
        }
        func ceilMinutes(_ interval: TimeInterval) -> Int { max(1, Int(ceil(interval / 60))) }
        func clock(_ date: Date) -> String {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        if event.start <= now {
            let left = ceilMinutes(event.end.timeIntervalSince(now))
            return left < 60 ? Display(value: String(format: "%02d", left), unit: .minutesLeft)
                             : Display(value: clock(event.end), unit: .endsAt)
        }
        let until = ceilMinutes(event.start.timeIntervalSince(now))
        return until < 60 ? Display(value: String(format: "%02d", until), unit: .minutesUntil)
                          : Display(value: clock(event.start), unit: .startsAt)
    }

    /// 時長の格:15 分 = 1 格(16 格まで)と、そのうち過ぎた格の数(進行中だけ。始まる前は 0)
    public static func durationCells(for event: MeetingEvent, now: Date) -> (count: Int, elapsed: Int) {
        let total = event.end.timeIntervalSince(event.start)
        let count = min(16, max(1, Int((total / 900).rounded(.up))))
        guard event.start <= now, total > 0 else { return (count, 0) }
        let fraction = min(1, now.timeIntervalSince(event.start) / total)
        return (count, min(count, Int((fraction * Double(count)).rounded())))
    }

    /// 画面が変わる時刻(now より後、古い順):数字が切り替わる 1 分ごと(開始前の最後の 1 時間と、開催中ずっと。
    /// 開催中は「已进行 N 分钟」と過ぎた格が毎分変わる)、動になる瞬間、00 の始まりと終わり、終了。
    /// それより前は「16:30 开始」のまま変わらない。TimelineView(.explicit(...)) に渡す
    public static func ticks(for event: MeetingEvent, after now: Date) -> [Date] {
        var dates: Set<Date> = [event.start.addingTimeInterval(-eventLead), event.start,
                                event.start.addingTimeInterval(zeroSpan), event.end]
        for k in 1...59 {
            dates.insert(event.start.addingTimeInterval(-60 * Double(k)))
        }
        // 開催中:開始から 1 分ごと + 終了の k 分前ごと(残り分の切り上げが変わる瞬間)。長い会議でも 1 日分まで
        let minutes = min(24 * 60, max(0, Int(event.end.timeIntervalSince(event.start) / 60)))
        if minutes > 0 {
            for k in 1...minutes {
                let elapsed = event.start.addingTimeInterval(60 * Double(k))
                if elapsed < event.end { dates.insert(elapsed) }
                let left = event.end.addingTimeInterval(-60 * Double(k))
                if left > event.start { dates.insert(left) }
            }
        }
        return dates.filter { $0 > now }.sorted()
    }
}
