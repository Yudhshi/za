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
        T.expectEqual(list.map { BreakReminder.illustration(for: $0) },
                      ["shoulder-blades", "belly-breathing", "chest-doorway",
                       "shoulder-blades", "shoulder-rolls", "walk"],
                      "W 字 → 肩胛 / 呼吸 / 胸 / 肩颈三步 starts with 肩胛 / 耸肩 → 转肩 / 走")
        T.expectEqual(BreakReminder.stretches(from: BreakReminder.defaultFixed).map { BreakReminder.illustration(for: $0) },
                      ["neck-side"], "斜角肌 → 颈")
        // 肩颈三步:手順ごとに別の姿勢(站立中の壁画带になる)
        T.expectEqual(list[3].steps.map { BreakReminder.illustration(for: BreakReminder.Stretch(name: $0, steps: [])) },
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

    T.run("defaults: the scalene stretch every time (20 s holds), then 6 in turn, nothing overhead") {
        let fixed = BreakReminder.stretches(from: BreakReminder.defaultFixed)
        T.expectEqual(fixed.map(\.name), ["斜角肌拉伸（约 1 分半）"])
        T.expectEqual(fixed[0].steps.map { StretchGuide.seconds(of: $0) }, [20, 20, 20, 20],
                      "both sides, two angles, 20 s each (10 s was too short)")
        let defaults = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        T.expectEqual(defaults.count, 6)
        T.expect(!defaults.contains { $0.name.hasPrefix("斜角肌") }, "the scalene stretch is not in the rotation")
        T.expect(defaults.allSatisfy { $0.steps.count >= 2 }, "every default has steps")
        let all = BreakReminder.defaultFixed + BreakReminder.defaultStretches
        T.expect(!all.contains("举过头") && !all.contains("举起双手"), "no overhead moves")
        T.expect(!all.contains("门框"), "no doorway needed")
    }

    T.run("routine: 斜角肌 first, then this turn's stretch; steps time themselves") {
        let fixed = BreakReminder.stretches(from: BreakReminder.defaultFixed)
        let list = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        let parts = fixed + [list[3]]
        let steps = StretchGuide.routineSteps(parts)
        T.expectEqual(steps.count, 7, "4 scalene steps + 肩颈三步")
        T.expectEqual(steps.map(\.seconds), [20, 20, 20, 20, 68, 40, 68],
                      "5 s × 10 = 50 + 9 gaps × 2; 10 turns × 4 s")
        T.expectEqual(StretchGuide.routineHeading(steps, at: 1), "斜角肌拉伸", "the stretch title while it is untitled")
        T.expectEqual(StretchGuide.routineHeading(steps, at: 5), "转肩", "a frieze figure names its own step")
        T.expectEqual(StretchGuide.routineHeading(steps, at: 7), "收下巴", "done → the last heading")
        T.expectEqual(StretchGuide.routineHeading([], at: 0), "")
        T.expect(StretchGuide.position(in: parts, at: 2) == (0, 2, 4), "third scalene step of four")
        T.expect(StretchGuide.position(in: parts, at: 4) == (1, 0, 3), "the dots restart with 肩颈三步")
        T.expect(StretchGuide.position(in: parts, at: 7) == (1, 3, 3), "done → the end of the last stretch")
        T.expect(StretchGuide.position(in: parts, at: -1) == (0, 0, 4), "never before the start")
        T.expect(StretchGuide.position(in: [], at: 0) == (0, 0, 0), "nothing to do")
        let empty = BreakReminder.Stretch(name: "空", steps: [])
        T.expect(StretchGuide.position(in: [empty] + parts, at: 0) == (1, 0, 4), "a stretch without steps is skipped")
        T.expectEqual(StretchGuide.seconds(of: "手肘贴着身体弯成 90°，手心朝前"), 10, "a setup line gets 10 s")
        T.expectEqual(StretchGuide.seconds(of: "肩膀用力耸向耳朵停 3 秒"), 10, "never shorter than 10 s")
        T.expectEqual(StretchGuide.seconds(of: "走 2 分钟"), 120)
    }

    T.run("migration: the old rotation drops its leading scalene stretch once") {
        let old = """
        斜角肌拉伸（约 2 分钟）
        右手按住右侧锁骨下方
        头向左倒

        W 字收肩（约 1 分钟）
        手肘贴着身体弯成 90°

        腹式呼吸（约 1 分钟）
        吸气 4 秒

        扩胸拉伸（约 1 分钟）
        前臂竖着贴在门框上

        肩颈三步（约 2 分钟）
        夹肩胛骨：保持 5 秒 × 10 次

        耸肩放松（约 1 分钟）
        做 8 次

        走一走（1〜2 分钟）
        走 1 分钟
        """
        T.expectEqual(BreakReminder.migratedStretches(old), nil, "the old default → today's default")
        let mine = "斜角肌（我的）\n按住锁骨\n\n转肩\n向后转 10 次\n\n走一走\n走 1 分钟"
        T.expectEqual(BreakReminder.migratedStretches(mine), "转肩\n向后转 10 次\n\n走一走\n走 1 分钟",
                      "my own list keeps everything but the scalene stretch")
        T.expectEqual(BreakReminder.migratedStretches("转肩\n向后转 10 次"), "转肩\n向后转 10 次",
                      "a list without the scalene stretch is left alone")
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

    T.run("upcoming meeting: the nearest Meet starting within 10 minutes, not one already running") {
        let now = tokyoDate(2026, 10, 1, 10, 22)
        let events = [ev("定例", 10, 30), ev("1on1", 10, 25, minutes: 30), ev("対面", 10, 24, link: nil),
                      ev("午後", 13, 0), ev("進行中", 10, 0, minutes: 30)]
        T.expectEqual(BreakReminder.upcomingMeeting(events: events, now: now)?.title, "1on1",
                      "nearest Meet; no-link events and running meetings are skipped")
        T.expectEqual(BreakReminder.upcomingMeeting(events: [ev("定例", 10, 33)], now: now)?.title, nil,
                      "11 minutes away is too early")
        T.expectEqual(BreakReminder.upcomingMeeting(events: [ev("定例", 10, 32)], now: now)?.title, "定例",
                      "exactly 10 minutes counts")
        T.expectEqual(BreakReminder.upcomingMeeting(events: [ev("定例", 10, 22)], now: now)?.title, nil,
                      "starting now is not upcoming")
        T.expectEqual(BreakReminder.upcomingMeeting(events: [ev("全天", 10, 25, allDay: true)], now: now)?.title, nil,
                      "all-day events never ask")
    }

    T.run("meeting stand ask: sitting 10+ minutes, a Meet soon, not answered, not inside another meeting") {
        let now = tokyoDate(2026, 10, 1, 10, 22)
        let events = [ev("定例", 10, 30)]
        func ask(_ p: BreakReminder.Posture = .sitting, sat minutes: Double = 25,
                 in list: [MeetingEvent]? = nil, answered: Set<String> = []) -> String? {
            BreakReminder.meetingStandAsk(events: list ?? events, now: now, posture: p,
                                          sittingSince: now.addingTimeInterval(-minutes * 60),
                                          answered: answered)?.title
        }
        T.expectEqual(ask(), "定例")
        T.expectEqual(ask(sat: 10), "定例", "exactly 10 minutes of sitting")
        T.expectEqual(ask(sat: 4), nil, "just sat down after standing: don't ask to stand again")
        T.expectEqual(ask(.standing), nil, "already standing")
        T.expectEqual(ask(answered: ["定例"]), nil, "answered once, not asked again")
        T.expectEqual(ask(in: events + [ev("前の会議", 9, 30, minutes: 60)]), nil,
                      "inside another meeting: wait until it ends")
        // 連続した会議:前の会議が 10:20 に終わって 10:30 から次。間の 10 分で聞く
        let backToBack = [ev("A", 9, 30, minutes: 50), ev("B", 10, 30)]
        T.expectEqual(ask(in: backToBack), "B", "the gap between back-to-back meetings")
        T.expectEqual(ask(in: [ev("Zoom", 10, 30, link: "https://zoom.us/j/1")]), nil, "Meet only")
        // 開始前 5 分(ほかの問いは出さない時間)の中でも聞く。始まったら聞かない
        let late = tokyoDate(2026, 10, 1, 10, 27)
        T.expect(BreakReminder.isInMeeting(events: events, now: late), "the 5-minute lead hides other prompts")
        T.expectEqual(BreakReminder.meetingStandAsk(events: events, now: late, posture: .sitting,
                                                    sittingSince: late.addingTimeInterval(-25 * 60),
                                                    answered: [])?.title,
                      "定例", "still asked inside the 5-minute lead")
        let start = tokyoDate(2026, 10, 1, 10, 30)
        T.expectEqual(BreakReminder.meetingStandAsk(events: events, now: start, posture: .sitting,
                                                    sittingSince: start.addingTimeInterval(-25 * 60),
                                                    answered: [])?.title,
                      nil, "closes when the meeting starts")
    }

    T.run("desiredPrompt: calls, the stand-for-meeting ask and the quiet minute after a meeting") {
        let now = tokyoDate(2026, 10, 1, 10, 0)
        let past = now.addingTimeInterval(-60), later = now.addingTimeInterval(600)
        func d(_ p: BreakReminder.Posture, due: Date, meeting: Bool = false, call: Bool = false,
               ask: Bool = false, quiet: Date? = nil) -> BreakReminder.Prompt? {
            BreakReminder.desiredPrompt(posture: p, current: nil, now: now, dueAt: due, inMeeting: meeting,
                                        inCall: call, standForMeeting: ask, quietUntil: quiet)
        }
        T.expectEqual(d(.sitting, due: past, call: true), nil, "never during a call, even when due")
        T.expectEqual(d(.standing, due: later, call: true), nil, "the standing guide hides in a call")
        T.expectEqual(d(.sitting, due: later, ask: true), .standForMeeting, "ask before the meeting, even if not due")
        T.expectEqual(d(.sitting, due: past, meeting: true, ask: true), .standForMeeting,
                      "the ask may show in the 5 minutes before start")
        T.expectEqual(d(.sitting, due: past, call: true, ask: true), nil, "joined early: no ask")
        T.expectEqual(d(.standing, due: later, ask: true), .standing, "standing: no meeting ask")
        T.expectEqual(d(.sitting, due: past, quiet: now.addingTimeInterval(30)), nil, "the minute after a meeting")
        T.expectEqual(d(.sitting, due: past, quiet: now), .askStand, "after the quiet minute")
        T.expectEqual(d(.standing, due: past, quiet: now.addingTimeInterval(30)), nil, "askSit waits too")
        T.expectEqual(d(.sitting, due: later, ask: true, quiet: now.addingTimeInterval(30)), .standForMeeting,
                      "back-to-back: the ask does not wait for the quiet minute")
        T.expectEqual(d(.standing, due: later, quiet: now.addingTimeInterval(30)), nil,
                      "the standing guide also waits out the quiet minute")
    }

    T.run("a meeting whose call ended (5+ min) is over, even before its scheduled end") {
        let meeting = ev("定例", 10, 30, minutes: 60)          // 10:30–11:30
        let now = tokyoDate(2026, 10, 1, 11, 10)
        func left(_ call: DateInterval?) -> [String] {
            BreakReminder.excludingEndedEarly([meeting, ev("午後", 13, 0)], now: now, lastCall: call).map(\.title)
        }
        let call = DateInterval(start: tokyoDate(2026, 10, 1, 10, 31), end: tokyoDate(2026, 10, 1, 11, 5))
        T.expectEqual(left(call), ["午後"], "hung up at 11:05: the 10:30 meeting is over")
        T.expectEqual(left(nil), ["定例", "午後"], "not watching calls: keep the calendar")
        let dictation = DateInterval(start: tokyoDate(2026, 10, 1, 10, 50), end: tokyoDate(2026, 10, 1, 10, 51))
        T.expectEqual(left(dictation), ["定例", "午後"], "a minute of voice typing does not end a meeting")
        let before = DateInterval(start: tokyoDate(2026, 10, 1, 9, 0), end: tokyoDate(2026, 10, 1, 10, 0))
        T.expectEqual(left(before), ["定例", "午後"], "a call that ended before the meeting started")
        let overran = DateInterval(start: tokyoDate(2026, 10, 1, 10, 0), end: tokyoDate(2026, 10, 1, 10, 35))
        T.expectEqual(left(overran), ["定例", "午後"],
                      "the previous meeting's call ran into this one: this meeting goes on")
        let early = DateInterval(start: tokyoDate(2026, 10, 1, 10, 26), end: tokyoDate(2026, 10, 1, 11, 5))
        T.expectEqual(left(early), ["午後"], "joined in the 5 minutes before start: still this meeting's call")
        T.expect(BreakReminder.isInMeeting(events: [meeting], now: now), "the calendar alone still says in meeting")
        T.expect(!BreakReminder.isInMeeting(events: BreakReminder.excludingEndedEarly([meeting], now: now,
                                                                                    lastCall: call), now: now),
                 "so the stand prompt is not held until 11:30")
    }

    T.run("开完会了: only after 5+ minutes of meeting or call, and for 10 minutes") {
        let end = tokyoDate(2026, 10, 1, 11, 0)
        let says = { (since: Date?, now: Date) in
            BreakReminder.saysAfterMeeting(now: now, busySince: since, lastBusyAt: end)
        }
        T.expect(says(end.addingTimeInterval(-3600), end.addingTimeInterval(60)), "an hour-long meeting, a minute ago")
        T.expect(!says(end.addingTimeInterval(-60), end.addingTimeInterval(60)), "a minute of voice typing")
        T.expect(says(end.addingTimeInterval(-300), end.addingTimeInterval(599)), "exactly 5 minutes, 9:59 ago")
        T.expect(!says(end.addingTimeInterval(-3600), end.addingTimeInterval(600)), "10 minutes later: no longer")
        T.expect(!BreakReminder.saysAfterMeeting(now: end, busySince: nil, lastBusyAt: nil), "no meeting today")
    }

    T.run("long meetings: 45 minutes or more") {
        T.expect(BreakReminder.isLong(ev("定例", 10, 0, minutes: 45)), "45 minutes")
        T.expect(!BreakReminder.isLong(ev("朝会", 10, 0, minutes: 30)), "30 minutes")
    }

    T.run("away idle: no input during a meeting or call is not leaving the desk") {
        let now = tokyoDate(2026, 10, 1, 11, 0)
        T.expectEqual(BreakReminder.awayIdle(idle: 3600, now: now, lastBusyAt: nil), 3600, "no meeting today")
        T.expectEqual(BreakReminder.awayIdle(idle: 3600, now: now, lastBusyAt: now.addingTimeInterval(-30)), 30,
                      "listened for an hour, call ended 30 s ago")
        T.expectEqual(BreakReminder.awayIdle(idle: 200, now: now, lastBusyAt: now.addingTimeInterval(-3600)), 200,
                      "meeting long over: real idle counts")
        T.expectEqual(BreakReminder.awayIdle(idle: 100, now: now, lastBusyAt: now.addingTimeInterval(60)), 0,
                      "clock skew never goes negative")
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
        let combo = list[3]
        let steps = StretchGuide.steps(of: combo)
        T.expectEqual(steps.map(\.pose), ["shoulder-blades", "shoulder-rolls", "chin-tuck"])
        T.expectEqual(steps.map(\.name), ["夹肩胛骨", "转肩", "收下巴"], "frieze labels")
        T.expectEqual(steps.map(\.text), ["保持 5 秒 × 10 次", "向后转 10 次", "保持 5 秒 × 10 次"],
                      "the heading's name is not repeated at the start of the line")
        T.expectEqual(steps.map(\.meta), ["5 秒 · 10 次", "10 次", "5 秒 · 10 次"], "number chips")
        T.expect(StretchGuide.showsFrieze(steps), "the frieze shows by default")
        T.expectEqual(StretchGuide.heading(of: combo, steps: steps, at: 1), "转肩", "heading = this step's pose")
        T.expectEqual(StretchGuide.heading(of: combo, steps: steps, at: 3), "肩颈三步", "done → stretch title")
    }

    T.run("stretch guide: single-pose stretches keep 第 N 步 and no frieze") {
        let list = BreakReminder.stretches(from: BreakReminder.defaultStretches)
        let fixed = BreakReminder.stretches(from: BreakReminder.defaultFixed)[0]
        let scalene = StretchGuide.steps(of: fixed)
        T.expectEqual(Set(scalene.map(\.pose)), ["neck-side"], "same pose all through")
        T.expectEqual(scalene.map(\.name), ["第 1 步", "第 2 步", "第 3 步", "第 4 步"])
        T.expectEqual(scalene.map(\.text), fixed.steps, "lines unchanged")
        T.expectEqual(scalene.map(\.meta), ["20 秒", "20 秒", "20 秒", "20 秒"], "both sides carry their times")
        T.expect(!StretchGuide.showsFrieze(scalene), "one figure repeated is not a frieze")
        T.expectEqual(StretchGuide.heading(of: fixed, steps: scalene, at: 0), "斜角肌拉伸", "stretch title")
        let blades = StretchGuide.steps(of: list[0])
        T.expectEqual(Set(blades.map(\.pose)), ["shoulder-blades"], "W 字收肩 is one figure")
        T.expectEqual(blades[2].meta, "5 秒 · 12 次")
        let shrug = StretchGuide.steps(of: list[4])
        T.expectEqual(Set(shrug.map(\.pose)), ["shoulder-rolls"], "耸肩放松 keeps one figure")
        T.expectEqual(list.filter { StretchGuide.showsFrieze(StretchGuide.steps(of: $0)) }.map(\.name),
                      ["肩颈三步（约 3 分钟）"], "only the combo is a frieze among the defaults")
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
