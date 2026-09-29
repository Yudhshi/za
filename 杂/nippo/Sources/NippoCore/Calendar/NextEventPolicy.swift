import Foundation

/// メニューバータイトル用の「次の会議」選定と表示文字列。
public enum NextEventPolicy {
    /// パネルのヒーローカード用:開催中を含む「いまの/次の」会議。
    /// メニューバーの statusTitle(次の未開始のみ)とは意図的に別基準。
    public static func currentOrNext(events: [MeetingEvent], now: Date) -> MeetingEvent? {
        events
            .filter { !$0.isAllDay && $0.end > now }
            .min(by: { $0.start < $1.start })
    }

    public static func nextUpcoming(events: [MeetingEvent], now: Date) -> MeetingEvent? {
        events
            .filter { !$0.isAllDay && $0.start > now }
            .min(by: { $0.start < $1.start })
    }

    /// ヒーローカードの大きな数字と単位。分は切り上げ。
    /// 開始前 60 分未満「12 / 分後」、それ以上「15:37 / 開始」、開催中「23 / 分で終了」
    public static func heroCountdown(for event: MeetingEvent, now: Date,
                                     calendar: Calendar = .current) -> (value: String, unit: String) {
        func ceilMinutes(_ interval: TimeInterval) -> Int {
            max(1, Int(ceil(interval / 60)))
        }
        guard event.start > now else {
            return ("\(ceilMinutes(event.end.timeIntervalSince(now)))", "分で終了")
        }
        let minutes = ceilMinutes(event.start.timeIntervalSince(now))
        if minutes < 60 { return ("\(minutes)", "分後") }
        let c = calendar.dateComponents([.hour, .minute], from: event.start)
        return (String(format: "%d:%02d", c.hour!, c.minute!), "開始")
    }

    /// 件名にキーワードのどれかを含む、まだ終わっていない最初の予定(全角/半角・大小文字は区別しない)
    public static func nextMatching(_ keywords: [String], in events: [MeetingEvent],
                                    now: Date) -> MeetingEvent? {
        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
        }
        let words = keywords.map(fold).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return events
            .filter { e in e.end > now && words.contains { fold(e.title).contains($0) } }
            .min(by: { $0.start < $1.start })
    }

    /// 先の予定までの大きな数字と単位:「開催中」「25 / 分後」「2 / 時間後」「明日」「4 / 日後」
    public static func dayCountdown(to start: Date, now: Date,
                                    calendar: Calendar = .current) -> (value: String, unit: String) {
        guard start > now else { return ("開催中", "") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case 0:
            let minutes = max(1, Int(ceil(start.timeIntervalSince(now) / 60)))
            return minutes < 60 ? ("\(minutes)", "分後") : ("\(minutes / 60)", "時間後")
        case 1:
            return ("明日", "")
        default:
            return ("\(days)", "日後")
        }
    }

    /// 「定例MTGまで 5分」/ 60分以上は「定例MTGまで 1:23」。次の会議がなければ nil。
    /// 分は切り上げ(残り 4:30 → 「まで 5分」)。タイトルは maxTitleLength で省略。
    public static func statusTitle(events: [MeetingEvent], now: Date,
                                   maxTitleLength: Int = 10) -> String? {
        guard let next = nextUpcoming(events: events, now: now) else { return nil }
        let minutes = max(1, Int(ceil(next.start.timeIntervalSince(now) / 60)))
        let countdown: String
        if minutes < 60 {
            countdown = "\(minutes)分"
        } else {
            countdown = String(format: "%d:%02d", minutes / 60, minutes % 60)
        }
        var title = next.title
        if title.count > maxTitleLength {
            title = String(title.prefix(maxTitleLength)) + "…"
        }
        return "\(title)まで \(countdown)"
    }
}
