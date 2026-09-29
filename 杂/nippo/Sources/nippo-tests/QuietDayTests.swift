import Foundation
import NippoCore

func runQuietDayTests() {
    T.run("weekday is not quiet, weekend is quiet") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 10), calendar: tokyoCalendar), false) // 金
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 11), calendar: tokyoCalendar), true)  // 土
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 12), calendar: tokyoCalendar), true)  // 日
    }

    T.run("JP holiday is quiet") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 20), calendar: tokyoCalendar), true)  // 海の日(月)
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 9, 22), calendar: tokyoCalendar), true)  // 国民の休日(火)
        T.expectEqual(try q.isQuietDay(tokyoDate(2028, 1, 10), calendar: tokyoCalendar), true)  // 旧リスト範囲外
    }

    T.run("reason distinguishes weekend, holiday and registered vacation") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        T.expectEqual(try q.reason(for: tokyoDate(2026, 7, 11), calendar: tokyoCalendar), .weekend)
        T.expectEqual(try q.reason(for: tokyoDate(2026, 7, 20), calendar: tokyoCalendar), .holiday)
        try q.addVacation("2026-12-29")
        T.expectEqual(try q.reason(for: tokyoDate(2026, 12, 29), calendar: tokyoCalendar), .vacation)
        T.expectEqual(try q.reason(for: tokyoDate(2026, 12, 30), calendar: tokyoCalendar), nil)
    }

    T.run("vacation add/remove/list") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        let day = tokyoDate(2026, 7, 15) // 水
        T.expectEqual(try q.isQuietDay(day, calendar: tokyoCalendar), false)
        try q.addVacation("2026-07-15")
        T.expectEqual(try q.isQuietDay(day, calendar: tokyoCalendar), true)
        T.expectEqual(try q.vacations(), ["2026-07-15"])
        try q.removeVacation("2026-07-15")
        T.expectEqual(try q.isQuietDay(day, calendar: tokyoCalendar), false)
    }
}
