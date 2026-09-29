import Foundation
import NippoCore

func runDayTimelineTests() {
    T.run("day timeline: 9–18 is 36 pleats, a meeting fills its pleats, past is marked") {
        let meeting = MeetingEvent(id: "m", title: "定例", start: tokyoDate(2026, 10, 1, 14, 0),
                                   end: tokyoDate(2026, 10, 1, 15, 0), attendees: [], isAllDay: false)
        let slots = DayTimeline.slots(events: [meeting], start: (9, 0), end: (18, 0),
                                      now: tokyoDate(2026, 10, 1, 12, 0), selectedID: "m",
                                      calendar: tokyoCalendar)
        T.expectEqual(slots.count, 36)
        T.expectEqual(slots.filter(\.meeting).count, 4)
        T.expect(slots[20].meeting && slots[20].selected, "14:00 is pleat 20 and selected")
        T.expect(!slots[19].meeting, "13:45 is free")
        T.expect(slots[11].past && !slots[12].past, "12:00 is the past/future boundary")
        T.expect(!slots[20].past, "afternoon meeting is not past at noon")
    }

    T.run("day timeline: all-day events are ignored, empty when end <= start") {
        let allDay = MeetingEvent(id: "a", title: "出張", start: tokyoDate(2026, 10, 1, 0, 0),
                                  end: tokyoDate(2026, 10, 2, 0, 0), attendees: [], isAllDay: true)
        let slots = DayTimeline.slots(events: [allDay], start: (9, 0), end: (18, 0),
                                      now: tokyoDate(2026, 10, 1, 12, 0), selectedID: nil,
                                      calendar: tokyoCalendar)
        T.expectEqual(slots.filter(\.meeting).count, 0)
        T.expectEqual(DayTimeline.slots(events: [], start: (18, 0), end: (9, 0),
                                        now: tokyoDate(2026, 10, 1, 12, 0), selectedID: nil,
                                        calendar: tokyoCalendar).count, 0)
    }
}
