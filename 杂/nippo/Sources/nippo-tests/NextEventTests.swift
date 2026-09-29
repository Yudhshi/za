import Foundation
import NippoCore

func runNextEventTests() {
    func ev(_ id: String, _ title: String, startH: Int, startM: Int,
            allDay: Bool = false) -> MeetingEvent {
        MeetingEvent(id: id, title: title,
                     start: tokyoDate(2026, 7, 10, startH, startM),
                     end: tokyoDate(2026, 7, 10, startH + 1, startM),
                     attendees: [], isAllDay: allDay)
    }

    T.run("nextUpcoming skips past and all-day events") {
        let now = tokyoDate(2026, 7, 10, 15, 0)
        let events = [
            ev("past", "終わった会", startH: 12, startM: 0),
            ev("allday", "終日", startH: 16, startM: 0, allDay: true),
            ev("later", "定例MTG", startH: 17, startM: 30),
            ev("soonest", "1on1", startH: 16, startM: 30),
        ]
        T.expectEqual(NextEventPolicy.nextUpcoming(events: events, now: now)?.id, "soonest")
        T.expectEqual(NextEventPolicy.nextUpcoming(events: [], now: now)?.id, nil)
    }

    T.run("currentOrNext includes in-progress, statusTitle pick excludes it") {
        let now = tokyoDate(2026, 7, 10, 17, 40)
        let events = [
            ev("running", "1on1", startH: 17, startM: 30),           // 開催中(〜18:30)
            ev("later", "定例", startH: 19, startM: 0),
        ]
        T.expectEqual(NextEventPolicy.currentOrNext(events: events, now: now)?.id, "running")
        T.expectEqual(NextEventPolicy.nextUpcoming(events: events, now: now)?.id, "later")
        T.expectEqual(NextEventPolicy.currentOrNext(events: [], now: now)?.id, nil)
    }

    T.run("statusTitle formats minutes with round-up, hours, truncation") {
        // 残り 4:30 → 切り上げで「あと5分」
        let now1 = tokyoDate(2026, 7, 10, 16, 25, 30)
        let t1 = NextEventPolicy.statusTitle(events: [ev("a", "1on1", startH: 16, startM: 30)],
                                             now: now1)
        T.expectEqual(t1, "1on1 还有5分钟")

        // 83 分後 → 「还有1:23」
        let now2 = tokyoDate(2026, 7, 10, 16, 7)
        let t2 = NextEventPolicy.statusTitle(events: [ev("b", "定例MTG", startH: 17, startM: 30)],
                                             now: now2)
        T.expectEqual(t2, "定例MTG 还有1:23")

        // 長いタイトルは省略
        let t3 = NextEventPolicy.statusTitle(
            events: [ev("c", "RoadSyncチーム全体定例ミーティング", startH: 17, startM: 30)],
            now: tokyoDate(2026, 7, 10, 17, 0))
        T.expect(t3?.contains("… 还有") == true, "truncated, got \(String(describing: t3))")

        // 次がなければ nil
        T.expectEqual(NextEventPolicy.statusTitle(events: [], now: now1), nil)
    }

    T.run("heroCountdown: minutes before, start time when 60+ min away, minutes left when running") {
        let e = ev("x", "定例", startH: 16, startM: 30)   // 16:30–17:30
        func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { tokyoDate(2026, 7, 10, h, m, s) }
        let soon = NextEventPolicy.heroCountdown(for: e, now: at(16, 18, 30), calendar: tokyoCalendar)
        T.expectEqual(soon.value, "12"); T.expectEqual(soon.unit, "分钟后")   // 11:30 → 切り上げ 12
        let later = NextEventPolicy.heroCountdown(for: e, now: at(15, 0), calendar: tokyoCalendar)
        T.expectEqual(later.value, "16:30"); T.expectEqual(later.unit, "开始")
        let running = NextEventPolicy.heroCountdown(for: e, now: at(17, 7), calendar: tokyoCalendar)
        T.expectEqual(running.value, "23"); T.expectEqual(running.unit, "分钟后结束")
        let lastSecond = NextEventPolicy.heroCountdown(for: e, now: at(17, 29, 50), calendar: tokyoCalendar)
        T.expectEqual(lastSecond.value, "1", "never shows 0")
    }

    T.run("nextMatching: first unfinished event containing a keyword, width-insensitive") {
        let now = tokyoDate(2026, 7, 10, 12, 0)
        func day(_ d: Int, _ title: String, _ h: Int = 14) -> MeetingEvent {
            MeetingEvent(id: "\(d)-\(title)", title: title,
                         start: tokyoDate(2026, 7, d, h, 0), end: tokyoDate(2026, 7, d, h + 1, 0),
                         attendees: [], isAllDay: false)
        }
        let events = [day(9, "シャチョケン(先週)"), day(17, "ｼｬﾁｮｹﾝ 事例"), day(14, "シャチョケン"),
                      day(11, "定例")]
        T.expectEqual(NextEventPolicy.nextMatching(["シャチョケン"], in: events, now: now)?.id,
                      "14-シャチョケン")
        T.expectEqual(NextEventPolicy.nextMatching(["シャチョケン"], in: [day(17, "ｼｬﾁｮｹﾝ 事例")],
                                                   now: now)?.id, "17-ｼｬﾁｮｹﾝ 事例", "half-width kana")
        T.expectEqual(NextEventPolicy.nextMatching([""], in: events, now: now)?.id, nil)
        // 既定のキーワードで、正式名の件名(26卒_新卒社長研修)に当たる
        T.expectEqual(NextEventPolicy.nextMatching(["新卒社長研修", "シャチョケン"],
                                                   in: [day(11, "定例"), day(16, "26卒_新卒社長研修")],
                                                   now: now)?.id, "16-26卒_新卒社長研修")
    }

    T.run("dayCountdown: minutes, hours, tomorrow, days, running") {
        let now = tokyoDate(2026, 7, 10, 12, 0)
        func c(_ d: Date) -> String {
            let r = NextEventPolicy.dayCountdown(to: d, now: now, calendar: tokyoCalendar)
            return r.value + r.unit
        }
        T.expectEqual(c(tokyoDate(2026, 7, 10, 12, 25)), "25分钟后")
        T.expectEqual(c(tokyoDate(2026, 7, 10, 14, 30)), "2小时后")
        T.expectEqual(c(tokyoDate(2026, 7, 11, 9, 0)), "明天")
        T.expectEqual(c(tokyoDate(2026, 7, 14, 9, 0)), "4天后")
        T.expectEqual(c(tokyoDate(2026, 7, 10, 11, 0)), "进行中")
    }
}
