import Foundation

/// 祝日法に基づく日本の祝日(振替休日・国民の休日を含む)を年ごとに計算する。
/// 2022 年以降の現行規定(五輪特例のあった 2020・2021 年は対象外)。
/// 春分・秋分は近似式で、2099 年まで官報の暦要項と一致する。
/// 法改正で臨時の祝日ができたら、設定の「休暇日」に追加すれば静かになる。
public enum JapaneseHolidays {
    /// "yyyy-MM-dd" の集合
    public static func holidays(year y: Int) -> Set<String> {
        let equinoxBase = 0.242194 * Double(y - 1980) - Double((y - 1980) / 4)
        let base: [(Int, Int)] = [
            (1, 1),                                   // 元日
            (1, nthMonday(2, month: 1, year: y)),     // 成人の日
            (2, 11),                                  // 建国記念の日
            (2, 23),                                  // 天皇誕生日
            (3, Int(20.8431 + equinoxBase)),          // 春分の日
            (4, 29),                                  // 昭和の日
            (5, 3), (5, 4), (5, 5),                   // 憲法記念日・みどりの日・こどもの日
            (7, nthMonday(3, month: 7, year: y)),     // 海の日
            (8, 11),                                  // 山の日
            (9, nthMonday(3, month: 9, year: y)),     // 敬老の日
            (9, Int(23.2488 + equinoxBase)),          // 秋分の日
            (10, nthMonday(2, month: 10, year: y)),   // スポーツの日
            (11, 3),                                  // 文化の日
            (11, 23),                                 // 勤労感謝の日
        ]
        let baseDates = base.map { date(y, $0.0, $0.1) }
        var result = Set(baseDates.map(key))

        // 国民の休日:前日と翌日がともに祝日である平日(敬老の日と秋分の日の間など)
        for d in baseDates {
            let next = addDays(d, 1), afterNext = addDays(d, 2)
            if !result.contains(key(next)), result.contains(key(afterNext)) {
                result.insert(key(next))
            }
        }
        // 振替休日:日曜の祝日の後で、最も近い祝日でない日
        for d in baseDates where weekday(d) == 1 {
            var sub = addDays(d, 1)
            while result.contains(key(sub)) { sub = addDays(sub, 1) }
            result.insert(key(sub))
        }
        return result
    }

    public static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let year = calendar.component(.year, from: date)
        return holidays(year: year).contains(DayKey.key(for: date, calendar: calendar))
    }

    // MARK: - 暦計算(日付のみ扱うので UTC 固定)

    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        gregorian.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private static func addDays(_ d: Date, _ n: Int) -> Date {
        gregorian.date(byAdding: .day, value: n, to: d)!
    }

    private static func weekday(_ d: Date) -> Int {
        gregorian.component(.weekday, from: d)   // 1 = 日曜
    }

    private static func key(_ d: Date) -> String {
        DayKey.key(for: d, calendar: gregorian)
    }

    /// その月の第 n 月曜日の日
    private static func nthMonday(_ n: Int, month: Int, year: Int) -> Int {
        let first = weekday(date(year, month, 1))
        let firstMonday = 1 + (9 - first) % 7      // 月曜 = 2
        return firstMonday + (n - 1) * 7
    }
}
