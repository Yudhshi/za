import Foundation
import Combine

public final class AppSettings: ObservableObject {
    private let d: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
    }

    public var reminderLeadMinutes: Int {
        get { d.object(forKey: "reminderLeadMinutes") as? Int ?? 5 }
        set { d.set(newValue, forKey: "reminderLeadMinutes"); objectWillChange.send() }
    }

    /// データ保存先(DB・ログ)。既存データのためパス名は据え置き
    public var reportsRoot: String {
        get {
            d.string(forKey: "reportsRoot")
                ?? ("~/Documents/日報" as NSString).expandingTildeInPath
        }
        set { d.set(newValue, forKey: "reportsRoot"); objectWillChange.send() }
    }

    /// ログイン項目の自動登録を一度だけ行うためのフラグ
    public var autoLaunchApplied: Bool {
        get { d.bool(forKey: "autoLaunchApplied") }
        set { d.set(newValue, forKey: "autoLaunchApplied"); objectWillChange.send() }
    }

    /// 勤務時間("HH:mm")。立ち作業リマインドはこの時間帯だけ動く
    public var workStartTime: String {
        get { d.string(forKey: "workStartTime") ?? "09:00" }
        set { d.set(newValue, forKey: "workStartTime"); objectWillChange.send() }
    }

    public var workEndTime: String {
        get { d.string(forKey: "workEndTime") ?? "18:00" }
        set { d.set(newValue, forKey: "workEndTime"); objectWillChange.send() }
    }

    /// 今日の出勤時刻(メニューで手入力。"HH:mm")と、その日付("yyyy-MM-dd")。日付が違えば未入力扱い
    public var workBeganTime: String? {
        get { d.string(forKey: "workBeganTime") }
        set { d.set(newValue, forKey: "workBeganTime"); objectWillChange.send() }
    }

    public var workBeganDay: String? {
        get { d.string(forKey: "workBeganDay") }
        set { d.set(newValue, forKey: "workBeganDay"); objectWillChange.send() }
    }

    /// 勤務時間内か(開始 ≦ 今 < 終了。不正な値は 9:00–18:00 とみなす)
    public func isWithinWorkHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let start = timeComponents(workStartTime, fallback: (9, 0))
        let end = timeComponents(workEndTime, fallback: (18, 0))
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let now = c.hour! * 60 + c.minute!
        return now >= start.hour * 60 + start.minute && now < end.hour * 60 + end.minute
    }

    /// 「いまのタスク」メモ(字下げで階層。TaskOutline で解釈)
    public var taskMemo: String {
        get { d.string(forKey: "taskMemo") ?? "" }
        set { d.set(newValue, forKey: "taskMemo"); objectWillChange.send() }
    }

    /// 「次のシャチョケン」を探す件名キーワード(カンマ区切り)
    public var shachokenKeywords: String {
        get { d.string(forKey: "shachokenKeywords") ?? "シャチョケン" }
        set { d.set(newValue, forKey: "shachokenKeywords"); objectWillChange.send() }
    }

    /// 昇降デスクの座り/立ち切り替えリマインド
    public var postureEnabled: Bool {
        get { d.object(forKey: "postureEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "postureEnabled"); objectWillChange.send() }
    }

    public var sitMinutes: Int {
        get { d.object(forKey: "sitMinutes") as? Int ?? 45 }
        set { d.set(newValue, forKey: "sitMinutes"); objectWillChange.send() }
    }

    public var standMinutes: Int {
        get { d.object(forKey: "standMinutes") as? Int ?? 15 }
        set { d.set(newValue, forKey: "standMinutes"); objectWillChange.send() }
    }

    /// 切り替え時に 1 つずつ出すストレッチ(1 行 1 つ)
    public var stretches: String {
        get { d.string(forKey: "stretches") ?? BreakReminder.defaultStretches }
        set { d.set(newValue, forKey: "stretches"); objectWillChange.send() }
    }

    public var lastStretchIndex: Int {
        get { d.integer(forKey: "lastStretchIndex") }
        set { d.set(newValue, forKey: "lastStretchIndex") }
    }

    public func timeComponents(_ value: String,
                               fallback: (hour: Int, minute: Int)) -> (hour: Int, minute: Int) {
        let parts = value.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return (h, m)
        }
        return fallback
    }
}
