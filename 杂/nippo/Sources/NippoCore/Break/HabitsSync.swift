import Foundation

/// 日课・腹式呼吸の記録を端末どうしで足し合わせる(docs/sync-format.md の habits-<端末>.json。
/// Windows の yudh-core/src/habits.rs と同じ書式)。各端末は自分のファイルだけを書き、ほかの端末の分を読んで日ごとに足す。
/// Mac で泡完澡の日课をして、Windows で呼吸をしても、連続日数・隔天の力量・今日の呼吸の回数が続くように
public struct Habits: Equatable, Sendable {
    /// 日课をやり終えた回数("yyyy-MM-dd" → 回数)
    public var ritual: [String: Int]
    /// 日课に肩袖の力量が入っていた回数(隔天の判定)
    public var ritualStrength: [String: Int]
    /// 腹式呼吸 3 回をやった回数
    public var breath: [String: Int]

    public init(ritual: [String: Int] = [:], ritualStrength: [String: Int] = [:], breath: [String: Int] = [:]) {
        self.ritual = ritual
        self.ritualStrength = ritualStrength
        self.breath = breath
    }

    /// 日ごとに足す
    public func merged(with other: Habits) -> Habits {
        func add(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
            a.merging(b, uniquingKeysWith: +)
        }
        return Habits(ritual: add(ritual, other.ritual),
                      ritualStrength: add(ritualStrength, other.ritualStrength),
                      breath: add(breath, other.breath))
    }
}

public enum HabitsSync {
    public static func fileName(for device: String) -> String {
        "habits-\(EnglishSync.slug(device)).json"
    }

    /// JSON(キーは並べて整形。中身が同じなら同じ文字列になる)
    public static func render(_ habits: Habits) -> String {
        let object: [String: Any] = ["ritual": habits.ritual,
                                     "ritualStrength": habits.ritualStrength,
                                     "breath": habits.breath]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}\n" }
        return text + "\n"
    }

    /// 読む。無いキーは空、数でない値は飛ばす。JSON でなければ nil
    public static func parse(_ data: Data) -> Habits? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func log(_ key: String) -> [String: Int] {
            guard let values = object[key] as? [String: Any] else { return [:] }
            return values.compactMapValues { ($0 as? NSNumber)?.intValue }
        }
        return Habits(ritual: log("ritual"), ritualStrength: log("ritualStrength"), breath: log("breath"))
    }

    /// 自分の記録を書く。中身が前と同じなら触らずに false(同期盘が同じ内容を何度も上げないように)。
    /// 一時ファイルに書いてから置き換える(Windows が書きかけを読まないように)
    @discardableResult
    public static func write(_ own: Habits, device: String, to root: URL) throws -> Bool {
        let file = root.appendingPathComponent(fileName(for: device))
        let text = render(own)
        if let existing = try? String(contentsOf: file, encoding: .utf8), existing == text { return false }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temp = root.appendingPathComponent(".\(file.lastPathComponent).tmp")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: file)
        }
        return true
    }

    /// ほかの端末の記録を足したもの(自分のファイルは読まない:手元の記録のほうが新しい)。読めないファイルは飛ばす
    public static func others(device: String, root: URL) -> Habits {
        let mine = fileName(for: device)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names
            .filter { $0.hasPrefix("habits-") && $0.hasSuffix(".json") && $0 != mine }
            .sorted()
            .compactMap { (try? Data(contentsOf: root.appendingPathComponent($0))).flatMap(parse) }
            .reduce(Habits()) { $0.merged(with: $1) }
    }
}
