import Foundation

/// 今日の勤務時間を 15 分のコマに切った「褶皺の時間線」(メニューの関卡カードの下)。
/// 各コマに会議があるか・選んだ会議か・もう過ぎたか。文字は載せない
public enum DayTimeline {
    public struct Slot: Equatable, Sendable {
        public let meeting: Bool
        public let selected: Bool
        public let past: Bool

        public init(meeting: Bool, selected: Bool, past: Bool) {
            self.meeting = meeting
            self.selected = selected
            self.past = past
        }
    }

    /// start〜end(今日の時刻)を slotMinutes 刻みに切る。end ≦ start なら空
    public static func slots(events: [MeetingEvent], start: (hour: Int, minute: Int),
                             end: (hour: Int, minute: Int), now: Date, selectedID: String?,
                             slotMinutes: Int = 15, calendar: Calendar = .current) -> [Slot] {
        let day = calendar.startOfDay(for: now)
        guard slotMinutes > 0,
              let from = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day),
              let to = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: day),
              to > from else { return [] }
        let step = TimeInterval(slotMinutes * 60)
        let count = Int(to.timeIntervalSince(from) / step)
        return (0..<count).map { i in
            let a = from.addingTimeInterval(Double(i) * step)
            let b = a.addingTimeInterval(step)
            let hits = events.filter { !$0.isAllDay && $0.start < b && $0.end > a }
            return Slot(meeting: !hits.isEmpty,
                        selected: hits.contains { $0.id == selectedID },
                        past: b <= now)
        }
    }
}
