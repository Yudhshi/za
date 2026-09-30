import Foundation
import GRDB

/// 英語タブのカードの種類(カード id の頭にも付ける:「vocab:b1-0807」「dict:abundant」「para:listening:reserve」「spell:insurance」)
public enum EnglishKind: String, Sendable, CaseIterable {
    /// 単語カード(辞書から追加した語も含む)
    case vocab
    /// 同義替換の 4 択
    case para
    /// 聴写
    case spell
}

/// カード 1 枚の保存状態
public struct EnglishCard: Equatable, Sendable {
    public let id: String
    public let kind: EnglishKind
    public var state: SRSState
    /// 次の復習日("yyyy-MM-dd")
    public var due: String
    /// 「知ってる」で出題から外した
    public var known: Bool
    /// 初めて出た日(今日の新規枠の数え方に使う)
    public var firstSeen: String
}

/// 「元に戻す」ための控え(答える直前のカードと、記録・出来事の最後の番号)
public struct EnglishUndo: Equatable, Sendable {
    public let id: String
    let previous: EnglishCard?
    let lastLogID: Int64
    let lastSeq: Int64
}

/// 英語の学習記録(english_card / english_log)。カードは SM-2 で復習日を決め、答えるたびに log に 1 行残す。
/// 変更のたびに同期用の出来事(sync_event)も 1 行残す(EnglishSync が書き出す・取り込む)
public struct EnglishStore {
    let db: AppDatabase
    /// 出来事に付ける、この端末の名前
    public var device: String

    public init(db: AppDatabase, device: String = "local") {
        self.db = db
        self.device = device
    }

    public func card(_ id: String) throws -> EnglishCard? {
        try db.dbQueue.read { try Self.fetchCard($0, id: id) }
    }

    /// 答えを記録して、次の復習日を決める(初めてのカードなら作る)
    @discardableResult
    public func record(id: String, kind: EnglishKind, rating: SRSRating, now: Date = Date(),
                       calendar: Calendar = .current) throws -> EnglishCard {
        let today = DayKey.key(for: now, calendar: calendar)
        return try db.dbQueue.write { db in
            var card = try Self.fetchCard(db, id: id)
                ?? EnglishCard(id: id, kind: kind, state: SRSState(), due: today, known: false,
                               firstSeen: today)
            card.state = card.state.applying(rating)
            let dueDate = calendar.date(byAdding: .day, value: card.state.interval, to: now) ?? now
            card.due = DayKey.key(for: dueDate, calendar: calendar)
            try Self.save(db, card, now: now)
            try Self.log(db, kind: kind, result: rating.rawValue, day: today, now: now)
            try Self.append(db, SyncEvent(device: device, at: now, op: .rate, card: id, kind: kind.rawValue,
                                          rating: rating.rawValue))
            return card
        }
    }

    /// 「知ってる」:出題から外す(もう出さない)
    public func markKnown(id: String, kind: EnglishKind, now: Date = Date(),
                          calendar: Calendar = .current) throws {
        let today = DayKey.key(for: now, calendar: calendar)
        try db.dbQueue.write { db in
            var card = try Self.fetchCard(db, id: id)
                ?? EnglishCard(id: id, kind: kind, state: SRSState(), due: today, known: true,
                               firstSeen: today)
            card.known = true
            try Self.save(db, card, now: now)
            try Self.log(db, kind: kind, result: "known", day: today, now: now)
            try Self.append(db, SyncEvent(device: device, at: now, op: .known, card: id, kind: kind.rawValue))
        }
    }

    /// 辞書で引いた語を単語カードに足す(すでにあれば何もしない)。今日の復習に並ぶ
    @discardableResult
    public func add(id: String, kind: EnglishKind, now: Date = Date(),
                    calendar: Calendar = .current) throws -> Bool {
        let today = DayKey.key(for: now, calendar: calendar)
        return try db.dbQueue.write { db in
            if try Self.fetchCard(db, id: id) != nil { return false }
            try Self.save(db, EnglishCard(id: id, kind: kind, state: SRSState(), due: today,
                                          known: false, firstSeen: today), now: now)
            try Self.append(db, SyncEvent(device: device, at: now, op: .add, card: id, kind: kind.rawValue))
            return true
        }
    }

    /// 「知ってる」にしたカードを出題に戻す(今日の復習に並ぶ)
    public func restore(id: String, now: Date = Date(), calendar: Calendar = .current) throws {
        let today = DayKey.key(for: now, calendar: calendar)
        try db.dbQueue.write { db in
            guard var card = try Self.fetchCard(db, id: id) else { return }
            card.known = false
            card.due = today
            try Self.save(db, card, now: now)
            try Self.append(db, SyncEvent(device: device, at: now, op: .restore, card: id, kind: card.kind.rawValue))
        }
    }

    /// その種類のカード全部(一覧用。復習日の近い順)
    public func cards(kind: EnglishKind) throws -> [EnglishCard] {
        try db.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM english_card WHERE kind = ? ORDER BY due, id",
                             arguments: [kind.rawValue])
                .compactMap(Self.card(from:))
        }
    }

    /// 答える直前の状態(「元に戻す」用)
    public func undoPoint(for id: String) throws -> EnglishUndo {
        try db.dbQueue.read { db in
            EnglishUndo(id: id, previous: try Self.fetchCard(db, id: id),
                        lastLogID: try Int64.fetchOne(db, sql: "SELECT MAX(id) FROM english_log") ?? 0,
                        lastSeq: try Int64.fetchOne(db, sql: "SELECT MAX(seq) FROM sync_event") ?? 0)
        }
    }

    /// 元に戻す:カードを答える前の状態に戻し(初めてのカードなら消し)、その後の記録を消す。
    /// 同期には「取り消した」出来事を残す(ほかの端末は再生でその出来事を飛ばす)
    public func undo(_ point: EnglishUndo, now: Date = Date()) throws {
        try db.dbQueue.write { db in
            if let previous = point.previous {
                try Self.save(db, previous, now: now)
            } else {
                try db.execute(sql: "DELETE FROM english_card WHERE id = ?", arguments: [point.id])
            }
            try db.execute(sql: "DELETE FROM english_log WHERE id > ?", arguments: [point.lastLogID])
            let undone = try String.fetchAll(db, sql: """
                SELECT id FROM sync_event WHERE seq > ? AND local = 1 AND op != 'undo' ORDER BY seq
                """, arguments: [point.lastSeq])
            for id in undone {
                try Self.append(db, SyncEvent(device: device, at: now, op: .undo, card: point.id, target: id))
            }
        }
    }

    /// 期限の来たカード(古い順。「知ってる」は除く)
    public func dueIDs(kind: EnglishKind, today: String) throws -> [String] {
        try db.dbQueue.read {
            try String.fetchAll($0, sql: """
                SELECT id FROM english_card
                WHERE kind = ? AND known = 0 AND due <= ?
                ORDER BY due, updatedAt
                """, arguments: [kind.rawValue, today])
        }
    }

    /// 一度でも出た(または「知ってる」にした)カード
    public func seenIDs(kind: EnglishKind) throws -> Set<String> {
        try db.dbQueue.read {
            Set(try String.fetchAll($0, sql: "SELECT id FROM english_card WHERE kind = ?",
                                    arguments: [kind.rawValue]))
        }
    }

    /// その日に初めて出したカードの数(新規枠)。辞書から足した語は数えない
    public func newCount(kind: EnglishKind, day: String) throws -> Int {
        try db.dbQueue.read {
            try Int.fetchOne($0, sql: """
                SELECT COUNT(*) FROM english_card
                WHERE kind = ? AND firstSeen = ? AND id NOT LIKE 'dict:%'
                """, arguments: [kind.rawValue, day]) ?? 0
        }
    }

    /// その日に答えた数(「知ってる」も 1 問と数える)
    public func answeredCount(day: String) throws -> Int {
        try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM english_log WHERE day = ?",
                             arguments: [day]) ?? 0
        }
    }

    /// 連続日数(今日まだなら昨日までで数える)
    public func streak(today: Date = Date(), calendar: Calendar = .current) throws -> Int {
        let days = try db.dbQueue.read {
            Set(try String.fetchAll($0, sql: "SELECT DISTINCT day FROM english_log"))
        }
        var date = today
        if !days.contains(DayKey.key(for: date, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var count = 0
        while days.contains(DayKey.key(for: date, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    // MARK: - SQL

    private static func fetchCard(_ db: Database, id: String) throws -> EnglishCard? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM english_card WHERE id = ?",
                                         arguments: [id]) else { return nil }
        return card(from: row)
    }

    private static func card(from row: Row) -> EnglishCard? {
        guard let kind = EnglishKind(rawValue: row["kind"]) else { return nil }
        return EnglishCard(
            id: row["id"], kind: kind,
            state: SRSState(interval: row["interval"], ease: row["ease"], reps: row["reps"],
                            lapses: row["lapses"]),
            due: row["due"], known: row["known"], firstSeen: row["firstSeen"])
    }

    private static func save(_ db: Database, _ card: EnglishCard, now: Date) throws {
        try db.execute(sql: """
            INSERT INTO english_card (id, kind, interval, ease, reps, lapses, due, known, firstSeen, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                interval = excluded.interval, ease = excluded.ease, reps = excluded.reps,
                lapses = excluded.lapses, due = excluded.due, known = excluded.known,
                updatedAt = excluded.updatedAt
            """, arguments: [card.id, card.kind.rawValue, card.state.interval, card.state.ease,
                             card.state.reps, card.state.lapses, card.due, card.known,
                             card.firstSeen, now])
    }

    private static func log(_ db: Database, kind: EnglishKind, result: String, day: String,
                            now: Date) throws {
        try db.execute(sql: "INSERT INTO english_log (day, kind, result, at) VALUES (?, ?, ?, ?)",
                       arguments: [day, kind.rawValue, result, now])
    }

    // MARK: - 同期用の出来事(sync_event)

    /// この端末の出来事として 1 行残す(同じ id は無視)
    static func append(_ db: Database, _ event: SyncEvent, local: Bool = true) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO sync_event (id, device, at, op, card, json, local)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [event.id, event.device, event.at, event.op.rawValue, event.card,
                             event.jsonLine(), local])
    }

    /// v6 移行:同期より前からあったカードと記録を、出来事として写す(再生で同じ状態になるように)
    static func backfillHistory(_ db: Database) throws {
        let device = "history"
        for row in try Row.fetchAll(db, sql: "SELECT * FROM english_card ORDER BY updatedAt, id") {
            let at: Date = row["updatedAt"]
            try append(db, SyncEvent(device: device, at: at, op: .snapshot, card: row["id"], kind: row["kind"],
                                     interval: row["interval"], ease: row["ease"], reps: row["reps"],
                                     lapses: row["lapses"], due: row["due"], known: row["known"],
                                     firstSeen: row["firstSeen"]))
        }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM english_log ORDER BY at, id") {
            let at: Date = row["at"]
            try append(db, SyncEvent(device: device, at: at, op: .log, kind: row["kind"],
                                     day: row["day"], result: row["result"]))
        }
    }

    /// この端末で起きた出来事(書き出す分)。移行時の "history" も含む
    public func localEvents() throws -> [SyncEvent] {
        try db.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM sync_event WHERE local = 1 ORDER BY seq")
                .compactMap { SyncEvent.parse(line: $0) }
        }
    }

    public func allEvents() throws -> [SyncEvent] {
        try db.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM sync_event ORDER BY seq")
                .compactMap { SyncEvent.parse(line: $0) }
        }
    }

    public func eventIDs() throws -> Set<String> {
        try db.dbQueue.read { Set(try String.fetchAll($0, sql: "SELECT id FROM sync_event")) }
    }

    /// ほかの端末の出来事を控える(書き出しはしない)
    public func insertForeign(_ events: [SyncEvent]) throws {
        try db.dbQueue.write { db in
            for event in events {
                try Self.append(db, event, local: false)
            }
        }
    }

    /// 出来事を時刻順(同時刻なら id 順)に再生して、カードと記録を作り直す。取り消された出来事は飛ばす
    public func rebuild(calendar: Calendar = .current) throws {
        let events = try allEvents()
        let undone = Set(events.filter { $0.op == .undo }.compactMap(\.target))
        let ordered = events
            .filter { $0.op != .undo && !undone.contains($0.id) }
            .sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        try db.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM english_card")
            try db.execute(sql: "DELETE FROM english_log")
            for event in ordered {
                try Self.apply(event, db, calendar: calendar)
            }
        }
    }

    /// 1 つの出来事を状態に反映する(record / markKnown / add / restore と同じ規則。時刻は出来事のもの)
    private static func apply(_ e: SyncEvent, _ db: Database, calendar: Calendar) throws {
        let day = DayKey.key(for: e.at, calendar: calendar)
        switch e.op {
        case .snapshot:
            guard let id = e.card, let kind = e.kind.flatMap(EnglishKind.init(rawValue:)) else { return }
            try save(db, EnglishCard(id: id, kind: kind,
                                     state: SRSState(interval: e.interval ?? 0, ease: e.ease ?? 2.5,
                                                     reps: e.reps ?? 0, lapses: e.lapses ?? 0),
                                     due: e.due ?? day, known: e.known ?? false, firstSeen: e.firstSeen ?? day),
                     now: e.at)
        case .log:
            guard let kind = e.kind.flatMap(EnglishKind.init(rawValue:)), let result = e.result else { return }
            try log(db, kind: kind, result: result, day: e.day ?? day, now: e.at)
        case .rate:
            guard let id = e.card, let kind = e.kind.flatMap(EnglishKind.init(rawValue:)),
                  let rating = e.rating.flatMap(SRSRating.init(rawValue:)) else { return }
            var card = try fetchCard(db, id: id)
                ?? EnglishCard(id: id, kind: kind, state: SRSState(), due: day, known: false, firstSeen: day)
            card.state = card.state.applying(rating)
            let dueDate = calendar.date(byAdding: .day, value: card.state.interval, to: e.at) ?? e.at
            card.due = DayKey.key(for: dueDate, calendar: calendar)
            try save(db, card, now: e.at)
            try log(db, kind: kind, result: rating.rawValue, day: day, now: e.at)
        case .known:
            guard let id = e.card, let kind = e.kind.flatMap(EnglishKind.init(rawValue:)) else { return }
            var card = try fetchCard(db, id: id)
                ?? EnglishCard(id: id, kind: kind, state: SRSState(), due: day, known: true, firstSeen: day)
            card.known = true
            try save(db, card, now: e.at)
            try log(db, kind: kind, result: "known", day: day, now: e.at)
        case .add:
            guard let id = e.card, let kind = e.kind.flatMap(EnglishKind.init(rawValue:)) else { return }
            if try fetchCard(db, id: id) == nil {
                try save(db, EnglishCard(id: id, kind: kind, state: SRSState(), due: day, known: false,
                                         firstSeen: day), now: e.at)
            }
        case .restore:
            guard let id = e.card, var card = try fetchCard(db, id: id) else { return }
            card.known = false
            card.due = day
            try save(db, card, now: e.at)
        case .undo:
            break
        }
    }
}
