import Foundation
import NippoCore

func runDatabaseTests() {
    T.run("in-memory db migrates all tables, legacy note/checklist/transcript tables kept") {
        let db = try AppDatabase.inMemory()
        for table in ["vacation", "punch_record", "transcript_line", "note", "checklist_item"] {
            T.expect(try db.dbQueue.read { try $0.tableExists(table) }, "\(table) exists")
        }
    }

    T.run("file-backed db creates parent directory") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-test-\(UUID().uuidString)")
        let path = dir.appendingPathComponent("sub/nippo.sqlite").path
        _ = try AppDatabase(path: path)
        T.expect(FileManager.default.fileExists(atPath: path), "sqlite file should exist")
        try? FileManager.default.removeItem(at: dir)
    }
}
