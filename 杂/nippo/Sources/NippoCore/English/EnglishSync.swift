import Foundation

/// 英語の進捗を Mac と Windows で共有するための「出来事」1 つ(答えた・知ってる・足した・戻した・取り消した)。
/// 各端末は自分の出来事だけを同期フォルダの自分のファイル(english-events-<端末>.jsonl)に書き出し、
/// 全端末の出来事を時刻順に再生して同じ状態を得る。サーバーは要らない。書式は docs/sync-format.md
public struct SyncEvent: Equatable, Sendable {
    public enum Op: String, Sendable, CaseIterable {
        /// 同期を始める前からあったカードの状態(移行時に 1 回だけ写す)
        case snapshot
        /// 同期を始める前の答えた記録(移行時に 1 回だけ写す)
        case log
        case rate, known, add, restore, undo
    }

    public var id: String
    public var device: String
    public var at: Date
    public var op: Op
    public var card: String?
    public var kind: String?
    public var rating: String?
    /// undo が取り消す出来事の id
    public var target: String?
    // snapshot の中身
    public var interval: Int?
    public var ease: Double?
    public var reps: Int?
    public var lapses: Int?
    public var due: String?
    public var known: Bool?
    public var firstSeen: String?
    // log の中身
    public var day: String?
    public var result: String?

    public init(id: String = UUID().uuidString.lowercased(), device: String, at: Date, op: Op,
                card: String? = nil, kind: String? = nil, rating: String? = nil, target: String? = nil,
                interval: Int? = nil, ease: Double? = nil, reps: Int? = nil, lapses: Int? = nil,
                due: String? = nil, known: Bool? = nil, firstSeen: String? = nil,
                day: String? = nil, result: String? = nil) {
        self.id = id
        self.device = device
        self.at = at
        self.op = op
        self.card = card
        self.kind = kind
        self.rating = rating
        self.target = target
        self.interval = interval
        self.ease = ease
        self.reps = reps
        self.lapses = lapses
        self.due = due
        self.known = known
        self.firstSeen = firstSeen
        self.day = day
        self.result = result
    }

    /// 時刻は ISO 8601(UTC、ミリ秒)。端末の時計がずれていても順番はこの値で決める
    static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plainTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 1 行の JSON(キーはアルファベット順で固定。空の項目は書かない)
    public func jsonLine() -> String {
        var o: [String: Any] = ["id": id, "device": device, "at": Self.timeFormatter.string(from: at), "op": op.rawValue]
        if let card { o["card"] = card }
        if let kind { o["kind"] = kind }
        if let rating { o["rating"] = rating }
        if let target { o["target"] = target }
        if let interval { o["interval"] = interval }
        if let ease { o["ease"] = ease }
        if let reps { o["reps"] = reps }
        if let lapses { o["lapses"] = lapses }
        if let due { o["due"] = due }
        if let known { o["known"] = known }
        if let firstSeen { o["firstSeen"] = firstSeen }
        if let day { o["day"] = day }
        if let result { o["result"] = result }
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// 1 行を読む。壊れた行・知らない op は nil(読み飛ばす)
    public static func parse(line: String) -> SyncEvent? {
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["id"] as? String, !id.isEmpty,
              let device = o["device"] as? String,
              let atText = o["at"] as? String,
              let at = timeFormatter.date(from: atText) ?? plainTimeFormatter.date(from: atText),
              let opRaw = o["op"] as? String, let op = Op(rawValue: opRaw) else { return nil }
        func int(_ key: String) -> Int? {
            if let v = o[key] as? Int { return v }
            if let v = o[key] as? Double { return Int(v) }
            return nil
        }
        return SyncEvent(id: id, device: device, at: at, op: op,
                         card: o["card"] as? String, kind: o["kind"] as? String, rating: o["rating"] as? String,
                         target: o["target"] as? String,
                         interval: int("interval"), ease: (o["ease"] as? NSNumber)?.doubleValue,
                         reps: int("reps"), lapses: int("lapses"),
                         due: o["due"] as? String, known: o["known"] as? Bool, firstSeen: o["firstSeen"] as? String,
                         day: o["day"] as? String, result: o["result"] as? String)
    }
}

/// 同期フォルダとのやりとり:自分の出来事を書き出す(push)、ほかの端末の出来事を取り込む(pull)。
/// フォルダは OneDrive / iCloud Drive / Dropbox など、ファイルを運んでくれるものなら何でもいい。
/// SQLite そのものは同期フォルダに置かない(壊れる)。各端末は自分のファイルにしか書かない
public final class EnglishSync {
    public let root: URL
    public let device: String
    private let store: EnglishStore

    public init(root: URL, device: String, store: EnglishStore) {
        self.root = root
        self.device = device
        self.store = store
    }

    /// ファイル名に使える端末名(英数字と - _ 以外は -)
    public static func slug(_ device: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = device.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("-") }
        let text = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return text.isEmpty ? "device" : text
    }

    public static func fileName(for device: String) -> String {
        "english-events-\(slug(device)).jsonl"
    }

    public var ownFile: URL { root.appendingPathComponent(Self.fileName(for: device)) }

    /// 自分の出来事を全部書き出す(同じ内容なら触らない)。一時ファイルに書いてから置き換える
    @discardableResult
    public func push() throws -> Int {
        let events = try store.localEvents()
        let text = events.map { $0.jsonLine() }.joined(separator: "\n") + (events.isEmpty ? "" : "\n")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: ownFile, encoding: .utf8), existing == text {
            return events.count
        }
        let temp = root.appendingPathComponent(".\(ownFile.lastPathComponent).tmp")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: ownFile.path) {
            _ = try FileManager.default.replaceItemAt(ownFile, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: ownFile)
        }
        return events.count
    }

    /// Windows が読む語表の置き場所(同期フォルダの english-library/)。書くのは Mac だけ
    public static let libraryFolder = "english-library"
    public static let libraryFiles = ["vocab.json", "paraphrase.json", "dictation.json", "dict.json", "LICENSES.txt"]

    /// 語表を同期フォルダへ写す(Windows は語表を持たないので、ここから読む)。
    /// 大きさが同じで写しの方が新しければ写さない(開くたびに 2MB の辞書を書き直さない)。写した数を返す
    @discardableResult
    public static func exportLibrary(from source: URL, to root: URL) throws -> Int {
        let fm = FileManager.default
        let target = root.appendingPathComponent(libraryFolder)
        var copied = 0
        for name in libraryFiles {
            let from = source.appendingPathComponent(name)
            guard let src = try? fm.attributesOfItem(atPath: from.path) else { continue }
            let to = target.appendingPathComponent(name)
            if let dst = try? fm.attributesOfItem(atPath: to.path),
               (dst[.size] as? NSNumber) == (src[.size] as? NSNumber),
               let srcDate = src[.modificationDate] as? Date, let dstDate = dst[.modificationDate] as? Date,
               dstDate >= srcDate {
                continue
            }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            // 一時ファイルに書いてから置き換える(Windows が書きかけを読まないように)
            try Data(contentsOf: from).write(to: to, options: .atomic)
            copied += 1
        }
        return copied
    }

    /// ほかの端末のファイルを読み、知らない出来事を取り込み、あれば状態を作り直す。取り込んだ数を返す
    @discardableResult
    public func pull(calendar: Calendar = .current) throws -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let known = try store.eventIDs()
        var fresh: [SyncEvent] = []
        var seen = Set<String>()
        for file in files
        where file.lastPathComponent.hasPrefix("english-events-") && file.pathExtension == "jsonl"
            && file.lastPathComponent != ownFile.lastPathComponent {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let event = SyncEvent.parse(line: String(line)),
                      !known.contains(event.id), !seen.contains(event.id) else { continue }
                seen.insert(event.id)
                fresh.append(event)
            }
        }
        guard !fresh.isEmpty else { return 0 }
        try store.insertForeign(fresh)
        try store.rebuild(calendar: calendar)
        return fresh.count
    }
}
