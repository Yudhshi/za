import Foundation

/// Mac が同期フォルダに書く「今日と明日の会議」(agenda.json)。Windows はカレンダーを読まず、これだけを読む。
/// 書くのは Mac だけ(1 ファイル・書き手は 1 台)。中身が変わったときだけ書き直す(同期盘が同じ内容を何度も上げないように)。
/// 参加者は書かない(Windows で要らない)。書式は docs/sync-format.md
public enum AgendaExport {
    public static let fileName = "agenda.json"
    public static let version = 1

    /// 1 日分("yyyy-MM-dd" と、その日の予定)
    public struct Day: Equatable {
        public var day: String
        public var events: [MeetingEvent]

        public init(day: String, events: [MeetingEvent]) {
            self.day = day
            self.events = events
        }
    }

    /// 1 件分(読み返したときの形。Windows 側の実装もこの項目だけを使う)
    public struct Entry: Equatable {
        public var id: String
        public var title: String
        public var start: Date
        public var end: Date
        public var allDay: Bool
        public var join: URL?

        public init(id: String, title: String, start: Date, end: Date, allDay: Bool, join: URL? = nil) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.allDay = allDay
            self.join = join
        }
    }

    /// 読み返した agenda.json
    public struct Snapshot: Equatable {
        public var device: String
        public var generatedAt: Date
        public var timeZone: String
        public var days: [String: [Entry]]
    }

    /// 時刻は ISO 8601(UTC・秒まで)。会議の時刻にミリ秒は要らない
    static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return timeFormatter.date(from: text) ?? fractionalFormatter.date(from: text)
    }

    /// generatedAt を除いた中身(書き直すかどうかの比較にも使う)
    static func payload(days: [Day], device: String, timeZone: TimeZone) -> [String: Any] {
        let dayObjects: [[String: Any]] = days.map { day in
            let events = day.events.sorted {
                ($0.start, $0.end, $0.title, $0.id) < ($1.start, $1.end, $1.title, $1.id)
            }
            return ["day": day.day, "events": events.map(eventObject)]
        }
        return ["version": version, "device": device, "timeZone": timeZone.identifier, "days": dayObjects]
    }

    static func eventObject(_ event: MeetingEvent) -> [String: Any] {
        var object: [String: Any] = [
            "id": event.id,
            "title": event.title,
            "start": timeFormatter.string(from: event.start),
            "end": timeFormatter.string(from: event.end),
            "allDay": event.isAllDay,
        ]
        if let url = event.joinURL { object["join"] = url.absoluteString }
        return object
    }

    private static func serialize(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text + "\n"
    }

    /// ファイルの中身(キーはアルファベット順で固定)
    public static func render(days: [Day], device: String, timeZone: TimeZone = .current,
                              generatedAt: Date) -> String {
        var object = payload(days: days, device: device, timeZone: timeZone)
        object["generatedAt"] = timeFormatter.string(from: generatedAt)
        return serialize(object) ?? "{}\n"
    }

    /// 同期フォルダに書く。中身(generatedAt 以外)が前と同じなら触らずに false。
    /// 一時ファイルに書いてから置き換える(Windows が書きかけを読まないように)
    @discardableResult
    public static func write(days: [Day], device: String, to root: URL, now: Date = Date(),
                             timeZone: TimeZone = .current) throws -> Bool {
        let file = root.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: file),
           var old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            old.removeValue(forKey: "generatedAt")
            if let previous = serialize(old),
               previous == serialize(payload(days: days, device: device, timeZone: timeZone)) {
                return false
            }
        }
        let text = render(days: days, device: device, timeZone: timeZone, generatedAt: now)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temp = root.appendingPathComponent(".\(fileName).tmp")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: file)
        }
        return true
    }

    /// 読む(テストと、Windows 側の実装の答え合わせ用)。壊れていれば nil、壊れた予定は読み飛ばす
    public static func parse(_ text: String) -> Snapshot? {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["version"] as? Int) == version,
              let generatedAt = date(object["generatedAt"]),
              let dayObjects = object["days"] as? [[String: Any]] else { return nil }
        var days: [String: [Entry]] = [:]
        for dayObject in dayObjects {
            guard let day = dayObject["day"] as? String else { continue }
            let events = dayObject["events"] as? [[String: Any]] ?? []
            days[day] = events.compactMap { e in
                guard let id = e["id"] as? String, let title = e["title"] as? String,
                      let start = date(e["start"]), let end = date(e["end"]) else { return nil }
                return Entry(id: id, title: title, start: start, end: end,
                             allDay: e["allDay"] as? Bool ?? false,
                             join: (e["join"] as? String).flatMap(URL.init(string:)))
            }
        }
        return Snapshot(device: object["device"] as? String ?? "",
                        generatedAt: generatedAt,
                        timeZone: object["timeZone"] as? String ?? "",
                        days: days)
    }
}
