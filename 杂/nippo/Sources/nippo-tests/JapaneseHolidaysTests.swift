import Foundation
import NippoCore

func runJapaneseHolidaysTests() {
    T.run("computed holidays match the hand-maintained 2026-2027 list exactly") {
        // 旧 QuietDayChecker.jpHolidays(官報の暦要項から手で転記したもの)
        let y2026: Set<String> = [
            "2026-01-01", "2026-01-12", "2026-02-11", "2026-02-23", "2026-03-20",
            "2026-04-29", "2026-05-03", "2026-05-04", "2026-05-05", "2026-05-06",
            "2026-07-20", "2026-08-11", "2026-09-21", "2026-09-22", "2026-09-23",
            "2026-10-12", "2026-11-03", "2026-11-23",
        ]
        let y2027: Set<String> = [
            "2027-01-01", "2027-01-11", "2027-02-11", "2027-02-23",
            "2027-03-21", "2027-03-22", "2027-04-29", "2027-05-03",
            "2027-05-04", "2027-05-05", "2027-07-19", "2027-08-11",
            "2027-09-20", "2027-09-23", "2027-10-11", "2027-11-03",
            "2027-11-23",
        ]
        T.expectEqual(JapaneseHolidays.holidays(year: 2026), y2026)
        T.expectEqual(JapaneseHolidays.holidays(year: 2027), y2027)
    }

    T.run("2025 official list incl. two substitute holidays and Sunday 5/4") {
        let y2025: Set<String> = [
            "2025-01-01", "2025-01-13", "2025-02-11", "2025-02-23", "2025-02-24",
            "2025-03-20", "2025-04-29", "2025-05-03", "2025-05-04", "2025-05-05",
            "2025-05-06", "2025-07-21", "2025-08-11", "2025-09-15", "2025-09-23",
            "2025-10-13", "2025-11-03", "2025-11-23", "2025-11-24",
        ]
        T.expectEqual(JapaneseHolidays.holidays(year: 2025), y2025)
    }

    T.run("years beyond the old list: 2028 成人の日, equinoxes") {
        let y2028 = JapaneseHolidays.holidays(year: 2028)
        T.expect(y2028.contains("2028-01-10"), "成人の日 (2nd Monday)")
        T.expect(y2028.contains("2028-03-20"), "春分の日")
        T.expect(y2028.contains("2028-09-22"), "秋分の日")
        T.expect(JapaneseHolidays.isHoliday(tokyoDate(2028, 1, 10), calendar: tokyoCalendar),
                 "isHoliday via calendar")
        T.expect(!JapaneseHolidays.isHoliday(tokyoDate(2028, 1, 11), calendar: tokyoCalendar),
                 "ordinary Tuesday")
    }
}
