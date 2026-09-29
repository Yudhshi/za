import Foundation

public protocol CalendarProviding {
    /// 権限リクエスト。付与済みなら即 true。
    func requestAccess() async -> Bool
    func events(on day: Date) -> [MeetingEvent]
    /// [from, to) の予定(終日・キャンセル・欠席回答は除く)
    func events(from: Date, to: Date) -> [MeetingEvent]
}
