import Foundation

public protocol CalendarProviding {
    /// 権限リクエスト。付与済みなら即 true。
    func requestAccess() async -> Bool
    /// いま権限があるか(起動後にシステム設定で許可された場合に追従するため)
    var isAuthorized: Bool { get }
    func events(on day: Date) -> [MeetingEvent]
    /// [from, to) の予定(終日・キャンセル・欠席回答は除く)
    func events(from: Date, to: Date) -> [MeetingEvent]
    /// 日历のアカウント(Google など)に、古ければ取りに行かせる(臨時に入った会議を早く拾う)
    func refreshSources()
}
