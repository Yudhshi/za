import Foundation
import EventKit

public final class EventKitCalendar: CalendarProviding {
    private let store = EKEventStore()
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    public func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func events(on day: Date) -> [MeetingEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end)
    }

    public func events(from start: Date, to end: Date) -> [MeetingEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { e in
                // 終日の予定は見ない(「休み」と書いてあっても休みとは扱わない)
                if e.isAllDay { return false }
                // 時刻つきの多日程(出張・研修 9:00–翌々日 18:00)も終日と同じ扱い:24 時間以上は会議ではない
                if e.endDate.timeIntervalSince(e.startDate) >= 24 * 3600 { return false }
                // キャンセル済み・自分が欠席回答した会議は一覧/リマインドから除外
                if e.status == .canceled { return false }
                if let me = e.attendees?.first(where: { $0.isCurrentUser }),
                   me.participantStatus == .declined { return false }
                return true
            }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                // eventIdentifier は繰り返しイベントの全オカレンスで同一。
                // 開始時刻を混ぜてオカレンス単位の安定 id にする(ForEach とリマインド重複排除の両方が id に依存)
                MeetingEvent(
                    id: "\(e.eventIdentifier ?? "no-id")-\(e.startDate.timeIntervalSince1970)",
                    title: e.title ?? "（无标题）",
                    start: e.startDate,
                    end: e.endDate,
                    attendees: (e.attendees ?? []).compactMap(\.name),
                    isAllDay: e.isAllDay,
                    joinURL: MeetingLinkExtractor.extract(
                        from: [e.url?.absoluteString, e.location, e.notes]))
            }
    }
}
