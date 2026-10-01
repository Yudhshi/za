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

    T.run("step meta: seconds / reps / minutes are read out of the sentence") {
        let a = BreakReminder.StepMeta.parse("保持 5 秒后放松。做 10 次")
        T.expectEqual(a, BreakReminder.StepMeta(seconds: 5, reps: 10), "秒 + 次")
        let b = BreakReminder.StepMeta.parse("20 秒 × 2 次。手臂不要高过肩膀")
        T.expectEqual(b, BreakReminder.StepMeta(seconds: 20, reps: 2), "× 2 wins over 2 次")
        let c = BreakReminder.StepMeta.parse("用鼻子吸气 4 秒，让肚子鼓起来")
        T.expectEqual(c, BreakReminder.StepMeta(seconds: 4), "seconds only")
        let d = BreakReminder.StepMeta.parse("向后转 １０ 次")
        T.expectEqual(d, BreakReminder.StepMeta(reps: 10), "full-width digits")
        T.expectEqual(BreakReminder.StepMeta.parse("放松肩膀"), BreakReminder.StepMeta(), "nothing")
    }

    T.run("stretch illustration picked by keyword, with a fallback") {
        let list = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        T.expectEqual(BreakReminder.illustration(for: list[0]), "shoulder-blades", "肩胛")
        T.expectEqual(BreakReminder.illustration(for: list[1]), "chin-tuck", "下巴")
        T.expectEqual(BreakReminder.illustration(for: list[2]), "neck-side", "颈")
        T.expectEqual(BreakReminder.illustration(for: list[3]), "chest-doorway", "胸")
        T.expectEqual(BreakReminder.illustration(for: list[4]), "shoulder-rolls", "转肩")
        T.expectEqual(BreakReminder.illustration(for: list[5]), "belly-breathing", "呼吸")
        T.expectEqual(BreakReminder.illustration(for: list[6]), "walk", "走")
        T.expectEqual(BreakReminder.illustration(for: list[7]), "shoulder-blades", "肩颈三步 starts with 肩胛")
        // 肩颈三步:手順ごとに別の姿勢(站立中の壁画带になる)
        T.expectEqual(list[7].steps.map { BreakReminder.illustration(for: BreakReminder.Stretch(name: $0, steps: [])) },
                      ["shoulder-blades", "shoulder-rolls", "chin-tuck"], "one pose per step")
        T.expectEqual(BreakReminder.illustration(for: BreakReminder.Stretch(name: "自定义", steps: ["随便动一动"])),
                      "stretch", "fallback")
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

    T.run("defaults: 8 gentle stretches, each with concrete steps, nothing overhead") {
        let defaults = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        T.expectEqual(defaults.count, 8)
        T.expect(defaults.allSatisfy { $0.steps.count >= 2 }, "every default has steps")
        T.expect(!BreakReminder.defaultStretches.contains("举过头")
                 && !BreakReminder.defaultStretches.contains("举起双手"), "no overhead moves")
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
        T.expectEqual(d(.standing, nil, due: later), .standing, "guide comes back after a meeting")
        T.expectEqual(BreakReminder.desiredPrompt(posture: .standing, current: nil, now: now, dueAt: later,
                                                  inMeeting: false, guideDismissed: true),
                      nil, "closed by hand stays closed")
    }

    T.run("stretch guide: name split into title · duration") {
        T.expectEqual(StretchGuide.split("夹肩胛骨（约 1 分钟）").title, "夹肩胛骨")
        T.expectEqual(StretchGuide.split("夹肩胛骨（约 1 分钟）").note, "1 分钟", "约 dropped")
        T.expectEqual(StretchGuide.split("走一走（1〜2 分钟）").note, "1〜2 分钟")
        T.expectEqual(StretchGuide.split("肩回し(約 30 秒)").title, "肩回し", "half-width brackets")
        T.expectEqual(StretchGuide.split("自定义").note, nil, "no brackets")
        T.expectEqual(StretchGuide.displayName("夹肩胛骨（约 1 分钟）"), "夹肩胛骨 · 1 分钟")
        T.expectEqual(StretchGuide.displayName("  自定义 "), "自定义")
    }

    T.run("stretch guide: 肩颈三步 = one pose per step, a frieze, names and numbers") {
        let list = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        let combo = list[7]
        let steps = StretchGuide.steps(of: combo)
        T.expectEqual(steps.map(\.pose), ["shoulder-blades", "shoulder-rolls", "chin-tuck"])
        T.expectEqual(steps.map(\.name), ["夹肩胛骨", "转肩", "收下巴"], "frieze labels")
        T.expectEqual(steps.map(\.text), ["保持 5 秒 × 10 次", "向后转 10 次", "保持 5 秒 × 5 次"],
                      "the heading's name is not repeated at the start of the line")
        T.expectEqual(steps.map(\.meta), ["5 秒 · 10 次", "10 次", "5 秒 · 5 次"], "number chips")
        T.expect(StretchGuide.showsFrieze(steps), "the frieze shows by default")
        T.expectEqual(StretchGuide.heading(of: combo, steps: steps, at: 1), "转肩", "heading = this step's pose")
        T.expectEqual(StretchGuide.heading(of: combo, steps: steps, at: 3), "肩颈三步", "done → stretch title")
    }

    T.run("stretch guide: single-pose stretches keep 第 N 步 and no frieze") {
        let list = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        let blades = StretchGuide.steps(of: list[0])
        T.expectEqual(Set(blades.map(\.pose)), ["shoulder-blades"], "same pose all through")
        T.expectEqual(blades.map(\.name), ["第 1 步", "第 2 步", "第 3 步"])
        T.expectEqual(blades.map(\.text), list[0].steps, "lines unchanged")
        T.expectEqual(blades[2].meta, "5 秒 · 10 次")
        T.expectEqual(blades[0].meta, nil, "no numbers → no chip")
        T.expect(!StretchGuide.showsFrieze(blades), "one figure repeated is not a frieze")
        T.expectEqual(StretchGuide.heading(of: list[0], steps: blades, at: 0), "夹肩胛骨", "stretch title")
        T.expectEqual(list.filter { StretchGuide.showsFrieze(StretchGuide.steps(of: $0)) }.map(\.name),
                      ["肩颈三步（约 2 分钟）"], "only the combo is a frieze among the defaults")
    }

    T.run("stretch guide: a frieze needs 2–3 different poses that all have frieze art") {
        func guide(_ steps: [String]) -> [StretchGuide.Step] {
            StretchGuide.steps(of: BreakReminder.Stretch(name: "自定义", steps: steps))
        }
        T.expect(StretchGuide.showsFrieze(guide(["夹肩胛骨 10 次", "收下巴 5 次"])), "two figures")
        T.expect(!StretchGuide.showsFrieze(guide(["夹肩胛骨 10 次", "扩胸 20 秒"])),
                 "扩胸 has no frieze figure → the stretch's pose repeats")
        T.expect(!StretchGuide.showsFrieze(guide(["夹肩胛骨 10 次"])), "one step")
        T.expect(!StretchGuide.showsFrieze(guide(["夹肩胛骨", "转肩", "收下巴", "夹肩胛骨 again"])), "four steps")
        T.expect(!StretchGuide.showsFrieze(guide([])), "no steps")
        T.expectEqual(guide(["夹肩胛骨：", "转肩: 向后 10 次"]).map(\.text), ["夹肩胛骨：", "向后 10 次"],
                      "the name prefix is dropped only when something is left")
    }

    T.run("stretch guide: step numbers and the countdown clock") {
        T.expectEqual(StretchGuide.metaText("保持 5 秒后放松。做 10 次"), "5 秒 · 10 次")
        T.expectEqual(StretchGuide.metaText("向后转 10 次"), "10 次")
        T.expectEqual(StretchGuide.metaText("看窗外等远处 20 秒"), "20 秒")
        T.expectEqual(StretchGuide.metaText("走 2 分钟"), "2 分钟")
        T.expectEqual(StretchGuide.metaText("放松肩膀"), nil)
        let now = tokyoDate(2026, 10, 1, 10, 0)
        T.expectEqual(StretchGuide.clock(until: now.addingTimeInterval(750), now: now), "12:30")
        T.expectEqual(StretchGuide.clock(until: now.addingTimeInterval(599.2), now: now), "10:00", "seconds round up")
        T.expectEqual(StretchGuide.clock(until: now.addingTimeInterval(59), now: now), "00:59", "minutes keep 2 digits")
        T.expectEqual(StretchGuide.clock(until: now.addingTimeInterval(-30), now: now), "00:00", "overdue")
        T.expectEqual(StretchGuide.clock(until: now.addingTimeInterval(100 * 60), now: now), "100:00")
    }
}
