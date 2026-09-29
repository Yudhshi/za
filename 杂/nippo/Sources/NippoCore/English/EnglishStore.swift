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

/// 英語の学習記録(english_card / english_log)。カードは SM-2 で復習日を決め、答えるたびに log に 1 行残す
public struct EnglishStore {
    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
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
            return true
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
                                         arguments: [id]),
              let kind = EnglishKind(rawValue: row["kind"]) else { return nil }
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
}
