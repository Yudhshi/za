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
        return m
    }
}
