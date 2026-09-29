import Foundation
import NippoCore

func runBreakReminderTests() {
    func ev(_ title: String, _ h: Int, _ m: Int, minutes: Int = 60,
            attendees: [String] = ["田中"], link: String? = "https://meet.google.com/abc-defg-hij",
            allDay: Bool = false) -> MeetingEvent {
        let start = tokyoDate(2026, 10, 1, h, m)
        return MeetingEvent(id: title, title: title, start: start,
                            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                            attendees: attendees, isAllDay: allDay,
                            joinURL: link.flatMap(URL.init(string:)))
    }

    T.run("in meeting: during, and 5 min before start; not after end") {
        let events = [ev("定例", 10, 0)]
        T.expect(BreakReminder.isInMeeting(events: events, now: tokyoDate(2026, 10, 1, 10, 30)), "during")
        T.expect(BreakReminder.isInMeeting(events: events, now: tokyoDate(2026, 10, 1, 9, 56)), "right before")
        T.expect(!BreakReminder.isInMeeting(events: events, now: tokyoDate(2026, 10, 1, 9, 50)), "well before")
        T.expect(!BreakReminder.isInMeeting(events: events, now: tokyoDate(2026, 10, 1, 11, 0)), "ended")
    }

    T.run("only Google Meet events count as meetings") {
        let now = tokyoDate(2026, 10, 1, 13, 30)
        T.expect(BreakReminder.isInMeeting(events: [ev("Meet", 13, 0, attendees: [])], now: now),
                 "Meet link, no attendees")
        T.expect(!BreakReminder.isInMeeting(events: [ev("対面", 13, 0, link: nil)], now: now),
                 "attendees but no Meet link")
        T.expect(!BreakReminder.isInMeeting(events: [ev("Zoom", 13, 0, link: "https://us02web.zoom.us/j/1")],
                                            now: now), "Zoom is not a meeting here")
        T.expect(!BreakReminder.isInMeeting(events: [ev("作業", 13, 0, attendees: [], link: nil)], now: now),
                 "solo block")
    }

    T.run("due after interval since last break") {
        let last = tokyoDate(2026, 10, 1, 10, 0)
        T.expect(!BreakReminder.isDue(now: tokyoDate(2026, 10, 1, 10, 44), since: last,
                                      intervalMinutes: 45), "44 min")
        T.expect(BreakReminder.isDue(now: tokyoDate(2026, 10, 1, 10, 45), since: last,
                                     intervalMinutes: 45), "45 min")
    }

    T.run("stretch blocks: name + steps, blank-line separated, rotation") {
        let list = BreakReminder.stretches(from: """

          肩回し(約 30 秒)
          肩を後ろへ回す
          10 回


        あご引き
        """)
        T.expectEqual(list.count, 2)
        T.expectEqual(list[0], BreakReminder.Stretch(name: "肩回し(約 30 秒)",
                                                     steps: ["肩を後ろへ回す", "10 回"]))
        T.expectEqual(list[1].steps, [])
        T.expectEqual(BreakReminder.stretch(at: 3, in: list).name, "あご引き")
        T.expect(!BreakReminder.stretch(at: 0, in: []).name.isEmpty, "fallback when empty")
    }

    T.run("defaults: 7 gentle stretches, each with concrete steps, nothing overhead") {
        let defaults = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        T.expectEqual(defaults.count, 7)
        T.expect(defaults.allSatisfy { $0.steps.count >= 2 }, "every default has steps")
        T.expect(!BreakReminder.defaultStretches.contains("頭の上")
                 && !BreakReminder.defaultStretches.contains("バンザイ"), "no overhead moves")
    }

    T.run("body: numbered steps, optional extra line, caution last") {
        let s = BreakReminder.Stretch(name: "肩甲骨寄せ(約 1 分)", steps: ["腕を下ろす", "肩甲骨を寄せる"])
        T.expectEqual(BreakReminder.body(for: s), "① 腕を下ろす\n② 肩甲骨を寄せる\n※しびれ・痛みが出たら中止")
        T.expectEqual(BreakReminder.body(for: s, extra: "水を一杯"),
                      "① 腕を下ろす\n② 肩甲骨を寄せる\n水を一杯\n※しびれ・痛みが出たら中止")
    }

    T.run("desiredPrompt: ask when due, keep the standing guide, hide in Meet") {
        let now = tokyoDate(2026, 10, 1, 10, 0)
        let past = now.addingTimeInterval(-60), later = now.addingTimeInterval(600)
        func d(_ p: BreakReminder.Posture, _ c: BreakReminder.Prompt?, due: Date,
               meeting: Bool = false) -> BreakReminder.Prompt? {
            BreakReminder.desiredPrompt(posture: p, current: c, now: now, dueAt: due, inMeeting: meeting)
        }
        T.expectEqual(d(.sitting, nil, due: past), .askStand)
        T.expectEqual(d(.standing, .standing, due: past), .askSit, "standing time is up")
        T.expectEqual(d(.standing, .standing, due: later), .standing, "guide stays while standing")
        T.expectEqual(d(.sitting, .askStand, due: later), nil, "snoozed / away → close")
        T.expectEqual(d(.sitting, nil, due: past, meeting: true), nil, "never during Meet")
        T.expectEqual(d(.standing, .standing, due: later, meeting: true), nil, "guide hides in Meet")
    }
}
