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

func runBoardSpanTests() {
    print("BoardSpan")
    /// 最後の格の右端 = 盤面の幅(格と隙間で 472 をちょうど埋める)
    func fills(_ span: BoardSpan) -> Bool {
        abs(span.cellX(span.count - 1) + span.cellWidth - span.totalWidth) < 0.0001
    }
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    T.run("board span: 9–18 is 36 cells of 10.5pt (15 min), labels 9…18 edge to edge") {
        let span = BoardSpan(startMinutes: 9 * 60, endMinutes: 18 * 60)
        T.expect(!span.isFallback, "the setting is used")
        T.expectEqual(span.slotMinutes, 15)
        T.expectEqual(span.count, 36)
        T.expect(near(span.cellWidth, 10.5), "cell 10.5pt, got \(span.cellWidth)")
        T.expect(near(span.gap, 2) && near(span.hourGap, 5), "default gaps 2 / 5")
        T.expect(fills(span), "fills 472")
        T.expectEqual(span.hourMarks.map(\.hour), Array(9...18))
        T.expect(near(span.hourMarks.first?.x ?? -1, 0) && near(span.hourMarks.last?.x ?? -1, 472),
                 "first label at 0, last at 472")
        T.expectEqual(span.text, "9:00–18:00")
    }

    T.run("board span: 9–17 keeps 15 min cells at 12.1pt and puts the rest into the hour gaps") {
        let span = BoardSpan(startMinutes: 9 * 60, endMinutes: 17 * 60)
        T.expectEqual(span.slotMinutes, 15)
        T.expectEqual(span.count, 32)
        T.expect(near(span.cellWidth, 12.1), "clamped to 12.1, got \(span.cellWidth)")
        T.expect(near(span.gap, 2), "plain gap unchanged")
        T.expect(near(span.hourGap, 5 + 1.8 / 7), "hour gap widened, got \(span.hourGap)")
        T.expect(fills(span), "fills 472")
    }

    T.run("board span: 10–17 clamps 15 min cells to 12.1pt with wide hour gaps") {
        let span = BoardSpan(startMinutes: 10 * 60, endMinutes: 17 * 60)
        T.expectEqual(span.slotMinutes, 15)
        T.expectEqual(span.count, 28)
        T.expect(near(span.cellWidth, 12.1), "clamped to 12.1, got \(span.cellWidth)")
        T.expect(near(span.hourGap, 15.2), "hour gap 15.2, got \(span.hourGap)")
        T.expect(fills(span), "fills 472")
    }

    T.run("board span: 8–20 switches to 30 min cells") {
        let span = BoardSpan(startMinutes: 8 * 60, endMinutes: 20 * 60)
        T.expectEqual(span.slotMinutes, 30)
        T.expectEqual(span.count, 24)
        T.expect(BoardSpan.wideRange.contains(span.cellWidth), "wide cell in 15.3–20.7, got \(span.cellWidth)")
        T.expect(near(span.hourGap, 5), "default hour gap")
        T.expect(fills(span), "fills 472")
        T.expectEqual(span.hourMarks.map(\.hour), Array(8...20))
    }

    T.run("board span: 8:00–18:30 uses 30 min cells and ends on the half hour") {
        let span = BoardSpan(startMinutes: 8 * 60, endMinutes: 18 * 60 + 30)
        T.expectEqual(span.slotMinutes, 30)
        T.expectEqual(span.count, 21)
        T.expect(near(span.cellWidth, 402.0 / 21), "cell \(402.0 / 21), got \(span.cellWidth)")
        T.expect(fills(span), "fills 472")
        T.expectEqual(span.hourMarks.map(\.hour), Array(8...18))
        // 18:00 は最後の格(18:00–18:30)の前の隙間の真ん中
        T.expect(near(span.hourMarks.last?.x ?? -1, span.cellX(20) - span.hourGap / 2), "18 sits in the gap before the last cell")
        T.expectEqual(span.text, "8:00–18:30")
    }

    T.run("board span: overnight and under-an-hour settings fall back to 9–18") {
        let overnight = BoardSpan(startMinutes: 22 * 60, endMinutes: 6 * 60)
        T.expect(overnight.isFallback, "overnight → fallback")
        T.expectEqual(overnight.start, 9 * 60)
        T.expectEqual(overnight.end, 18 * 60)
        T.expectEqual(overnight.count, 36)
        T.expectEqual(overnight.text, "9:00–18:00")
        T.expect(BoardSpan(startMinutes: 9 * 60, endMinutes: 9 * 60 + 45).isFallback, "45 min → fallback")
        let hour = BoardSpan(startMinutes: 9 * 60, endMinutes: 10 * 60)
        T.expect(!hour.isFallback && fills(hour), "exactly 1 hour is used and fills 472")
    }

    T.run("board span: now-x only moves right, and is nil outside the board") {
        let spans = [BoardSpan(startMinutes: 9 * 60, endMinutes: 18 * 60),
                     BoardSpan(startMinutes: 10 * 60, endMinutes: 17 * 60),
                     BoardSpan(startMinutes: 8 * 60, endMinutes: 20 * 60),
                     BoardSpan(startMinutes: 8 * 60, endMinutes: 18 * 60 + 30)]
        for span in spans {
            let first = Double(span.start)
            let last = Double(span.start + span.count * span.slotMinutes)
            var previous = -1.0
            var monotonic = true
            var inside = true
            var minute = first
            while minute < last {
                if let x = span.nowX(minute: minute) {
                    if x < previous { monotonic = false }
                    if x < 0 || x > span.totalWidth { inside = false }
                    previous = x
                } else {
                    inside = false
                }
                minute += 0.25
            }
            T.expect(monotonic, "\(span.text): now-x never moves left")
            T.expect(inside, "\(span.text): now-x stays on the board")
            T.expect(span.nowX(minute: first - 1) == nil && span.nowX(minute: last) == nil,
                     "\(span.text): nil before and after")
            T.expectEqual(span.currentHour(minute: first + 61), span.start / 60 + 1)
        }
    }
}
