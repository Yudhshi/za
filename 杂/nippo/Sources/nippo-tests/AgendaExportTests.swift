import Foundation
import NippoCore

func runAgendaExportTests() {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("yudh-agenda-\(UUID().uuidString)")
    }
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let standup = MeetingEvent(id: "e2", title: "朝会", start: tokyoDate(2026, 10, 2, 10, 0),
                               end: tokyoDate(2026, 10, 2, 10, 15), attendees: ["a@example.com"],
                               isAllDay: false, joinURL: URL(string: "https://meet.google.com/abc-defg-hij"))
    let review = MeetingEvent(id: "e1", title: "デザインレビュー", start: tokyoDate(2026, 10, 2, 9, 30),
                              end: tokyoDate(2026, 10, 2, 10, 0), attendees: [], isAllDay: false)
    let holiday = MeetingEvent(id: "e0", title: "全社休み", start: tokyoDate(2026, 10, 2),
                               end: tokyoDate(2026, 10, 3), attendees: [], isAllDay: true)
    let days = [AgendaExport.Day(day: "2026-10-01", events: []),
                AgendaExport.Day(day: "2026-10-02", events: [standup, holiday, review])]

    T.run("agenda.json round-trips, sorted by start, without attendees") {
        let text = AgendaExport.render(days: days, device: "MacBook", timeZone: tokyo,
                                       generatedAt: tokyoDate(2026, 10, 1, 21, 0))
        T.expect(!text.contains("a@example.com"), "attendees are not written")
        T.expect(text.contains("\"start\" : \"2026-10-02T00:30:00Z\""), "times are UTC: \(text)")
        guard let snapshot = AgendaExport.parse(text) else { return T.expect(false, "parses") }
        T.expectEqual(snapshot.device, "MacBook")
        T.expectEqual(snapshot.timeZone, "Asia/Tokyo")
        T.expectEqual(snapshot.generatedAt, tokyoDate(2026, 10, 1, 21, 0))
        T.expect(snapshot.days["2026-10-01"] == [], "an empty day is still listed")
        let tomorrow = snapshot.days["2026-10-02"] ?? []
        T.expectEqual(tomorrow.map(\.id), ["e0", "e1", "e2"], "all-day first, then by start")
        T.expectEqual(tomorrow.first?.allDay, true)
        T.expectEqual(tomorrow.last?.join?.absoluteString, "https://meet.google.com/abc-defg-hij")
        T.expectEqual(tomorrow[1].title, "デザインレビュー")
        T.expect(AgendaExport.parse("{\"version\":2}") == nil, "unknown versions are refused")
        T.expect(AgendaExport.parse("not json") == nil, "garbage is refused")
    }

    T.run("agenda.json is rewritten only when the meetings change") {
        let root = tempDir()
        let file = root.appendingPathComponent("agenda.json")
        let first = tokyoDate(2026, 10, 1, 21, 0)
        T.expect(try AgendaExport.write(days: days, device: "MacBook", to: root, now: first, timeZone: tokyo),
                 "first write creates the folder and the file")
        let written = try String(contentsOf: file, encoding: .utf8)
        let rewritten = try AgendaExport.write(days: days, device: "MacBook", to: root,
                                               now: first.addingTimeInterval(600), timeZone: tokyo)
        T.expect(!rewritten, "same meetings ten minutes later: untouched")
        T.expectEqual(try String(contentsOf: file, encoding: .utf8), written, "generatedAt stays as it was")

        var moved = days
        moved[1].events[0] = MeetingEvent(id: "e2", title: "朝会", start: tokyoDate(2026, 10, 2, 10, 30),
                                          end: tokyoDate(2026, 10, 2, 10, 45), attendees: [], isAllDay: false)
        let later = first.addingTimeInterval(1200)
        T.expect(try AgendaExport.write(days: moved, device: "MacBook", to: root, now: later, timeZone: tokyo),
                 "a moved meeting is written")
        let snapshot = AgendaExport.parse(try String(contentsOf: file, encoding: .utf8))
        T.expectEqual(snapshot?.generatedAt, later)
        T.expectEqual(snapshot?.days["2026-10-02"]?.last?.start, tokyoDate(2026, 10, 2, 10, 30))
        T.expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".agenda.json.tmp").path),
                 "no temp file left behind")
        try? FileManager.default.removeItem(at: root)
    }
}
