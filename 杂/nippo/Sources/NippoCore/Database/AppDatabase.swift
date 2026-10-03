import Foundation
import GRDB

public struct AppDatabase {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        dbQueue = queue
        try Self.migrator.migrate(dbQueue)
    }

    /// 適用済みマイグレーションは消さない(既存 DB の整合のため)。
    /// note / checklist_item / punch_record / transcript_line は機能廃止後も既存データ保全のため残すが、もう読み書きしない
    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("text", .text).notNull()
            }
            try db.create(table: "vacation") { t in
                t.column("day", .text).primaryKey()   // "yyyy-MM-dd"
            }
        }
        m.registerMigration("v2") { db in
            try db.create(table: "checklist_item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("day", .text).notNull().indexed()
                t.column("text", .text).notNull()
                t.column("done", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("source", .text).notNull().defaults(to: "manual")
            }
        }
        m.registerMigration("v3") { db in
            try db.create(table: "punch_record") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("day", .text).notNull()
                t.column("kind", .text).notNull()      // "in" / "out"
                t.column("at", .datetime).notNull()
                t.column("via", .text).notNull()       // "webview" / "external"
                t.uniqueKey(["day", "kind"])
            }
        }
        m.registerMigration("v4") { db in
            try db.create(table: "transcript_line") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session", .text).notNull().indexed()
                t.column("day", .text).notNull().indexed()
                t.column("speaker", .text).notNull()
                t.column("text", .text).notNull()
                t.column("at", .datetime).notNull()
            }
        }
        m.registerMigration("v5") { db in
            // 英語タブ(2026-09-29):カードごとの復習状態と、答えた記録
            try db.create(table: "english_card") { t in
                t.column("id", .text).primaryKey()         // "vocab:b1-0807" など
                t.column("kind", .text).notNull()          // "vocab" / "para" / "spell"
                t.column("interval", .integer).notNull().defaults(to: 0)
                t.column("ease", .double).notNull().defaults(to: 2.5)
                t.column("reps", .integer).notNull().defaults(to: 0)
                t.column("lapses", .integer).notNull().defaults(to: 0)
                t.column("due", .text).notNull()           // "yyyy-MM-dd"
                t.column("known", .boolean).notNull().defaults(to: false)
                t.column("firstSeen", .text).notNull()     // "yyyy-MM-dd"
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "english_card_on_kind_due", on: "english_card", columns: ["kind", "due"])
            try db.create(table: "english_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("day", .text).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("result", .text).notNull()        // again/hard/good/easy/known
                t.column("at", .datetime).notNull()
            }
        }
        m.registerMigration("v6") { db in
            // 英語の進捗の同期(2026-09-30):出来事の記録。各端末は自分の出来事(local = 1)だけをファイルに書き出す
            try db.create(table: "sync_event") { t in
                t.autoIncrementedPrimaryKey("seq")
                t.column("id", .text).notNull().unique()
                t.column("device", .text).notNull()
                t.column("at", .datetime).notNull().indexed()
                t.column("op", .text).notNull()
                t.column("card", .text).indexed()
                t.column("json", .text).notNull()
                t.column("local", .boolean).notNull().defaults(to: true)
            }
            // 同期より前からあったカードと記録を、出来事として写しておく(再生で同じ状態になるように)
            try EnglishStore.backfillHistory(db)
        }
        return m
    }
}
