import Foundation
import NippoCore

func runDayKeyTests() {
    T.run("DayKey formats") {
        T.expectEqual(DayKey.key(for: tokyoDate(2026, 7, 10, 23, 59), calendar: tokyoCalendar),
                      "2026-07-10")
    }
}
