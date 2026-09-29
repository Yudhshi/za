import Foundation
import GRDB

public struct QuietDayChecker {
    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public enum Reason: String {
        case weekend = "週末"
        case holiday = "祝日"
        case vacation = "休暇日"
    }

    /// 静默日:周末、日本节假日(祝日法から自動計算)、用户登记的请假日。
    public func isQuietDay(_ date: Date, calendar: Calendar = .current) throws -> Bool {
        try reason(for: date, calendar: calendar) != nil
    }

    /// 静かにする理由(平日なら nil)。メニューに理由を出して誤判定に気づけるようにする
    public func reason(for date: Date, calendar: Calendar = .current) throws -> Reason? {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return .weekend }   // 日曜・土曜
        if JapaneseHolidays.isHoliday(date, calendar: calendar) { return .holiday }
        let key = DayKey.key(for: date, calendar: calendar)
        let registered = try db.dbQueue.read {
            try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM vacation WHERE day = ?)",
                              arguments: [key]) ?? false
        }
        return registered ? .vacation : nil
    }

    public func addVacation(_ day: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "INSERT OR IGNORE INTO vacation (day) VALUES (?)",
                           arguments: [day])
        }
    }

    public func removeVacation(_ day: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "DELETE FROM vacation WHERE day = ?", arguments: [day])
        }
    }

    public func vacations() throws -> [String] {
        try db.dbQueue.read {
            try String.fetchAll($0, sql: "SELECT day FROM vacation ORDER BY day")
        }
    }
}
