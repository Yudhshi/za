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

func runCreatureFitTests() {
    print("CreatureFit")
    // 100 × 100 の枠、墨は全面、左の輪郭は全部 x = 0(四角い神兽)
    let art = CreatureFit.Art(box: CGSize(width: 100, height: 100),
                              ink: CGRect(x: 0, y: 0, width: 100, height: 100),
                              contour: Array(repeating: CGFloat(0), count: 10))

    T.run("creature takes 76% of the card when nothing is in the way") {
        let p = CreatureFit.place(art: art, card: CGSize(width: 400, height: 200), avoid: [])
        T.expect(p != nil, "placed")
        T.expectEqual(p.map { Double($0.scale * 100).rounded() }, 152, "ink height = 0.76 × 200")
        T.expectEqual(p.map { Double($0.origin.x + 100 * $0.scale).rounded() }, 394, "ink right = card − 6")
    }

    T.run("creature shrinks to keep 9pt away from the numeral, or is dropped") {
        let numeral = CGRect(x: 20, y: 60, width: 240, height: 100)
        let p = CreatureFit.place(art: art, card: CGSize(width: 400, height: 200), avoid: [numeral])
        if let p {
            T.expect(p.origin.x >= numeral.maxX + 9 - 0.001, "clear of the numeral")
            T.expect(p.scale * 100 >= 200 * 0.6 - 0.001, "not below the minimum")
        }
        let wide = CGRect(x: 20, y: 20, width: 360, height: 160)
        T.expect(CreatureFit.place(art: art, card: CGSize(width: 400, height: 200), avoid: [wide]) == nil,
                 "no room → no creature")
    }

    T.run("a holey contour lets the creature sit next to a short line") {
        // 上半分は墨が右寄り(x = 70)、下半分は左まで(x = 0)
        let bird = CreatureFit.Art(box: CGSize(width: 100, height: 100),
                                   ink: CGRect(x: 0, y: 0, width: 100, height: 100),
                                   contour: Array(repeating: CGFloat(70), count: 5) + Array(repeating: CGFloat(0), count: 5))
        let title = CGRect(x: 20, y: 30, width: 270, height: 26)
        let p = CreatureFit.place(art: bird, card: CGSize(width: 400, height: 200), avoid: [title])
        T.expect(p != nil && p!.scale * 100 >= 0.76 * 200 - 0.001, "full size: the title only meets the right-leaning upper half")
    }
}
