import Foundation
import NippoCore

func runEnglishSyncTests() {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yudh-sync-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    let cal = tokyoCalendar

    T.run("event line round-trips and device names become file names") {
        let e = SyncEvent(id: "abc", device: "Mac Book", at: tokyoDate(2026, 10, 1, 10, 0, 5), op: .rate,
                          card: "vocab:x", kind: "vocab", rating: "good")
        T.expectEqual(SyncEvent.parse(line: e.jsonLine()), e, "rate")
        let s = SyncEvent(id: "s1", device: "history", at: tokyoDate(2026, 9, 1), op: .snapshot,
                          card: "vocab:y", kind: "vocab", interval: 8, ease: 2.36, reps: 3, lapses: 1,
                          due: "2026-09-09", known: false, firstSeen: "2026-08-20")
        T.expectEqual(SyncEvent.parse(line: s.jsonLine()), s, "snapshot")
        T.expect(SyncEvent.parse(line: "not json") == nil, "garbage is skipped")
        T.expect(SyncEvent.parse(line: #"{"id":"x","device":"a","at":"2026-10-01T01:00:00Z","op":"dance"}"#) == nil,
                 "unknown op is skipped")
        T.expectEqual(EnglishSync.slug("Mac Book (Yudh)"), "Mac-Book--Yudh")
        T.expectEqual(EnglishSync.fileName(for: "DESKTOP-9F2"), "english-events-DESKTOP-9F2.jsonl")
    }

    T.run("two devices converge by replaying each other's events") {
        let dir = tempDir()
        let a = EnglishStore(db: try AppDatabase.inMemory(), device: "A")
        let b = EnglishStore(db: try AppDatabase.inMemory(), device: "B")
        let day1 = tokyoDate(2026, 10, 1, 10, 0)
        try a.record(id: "vocab:x", kind: .vocab, rating: .good, now: day1, calendar: cal)
        try a.markKnown(id: "vocab:k", kind: .vocab, now: day1.addingTimeInterval(60), calendar: cal)
        T.expect(try a.add(id: "dict:extra", kind: .vocab, now: day1.addingTimeInterval(120), calendar: cal), "added")
        let syncA = EnglishSync(root: dir, device: "A", store: a)
        let syncB = EnglishSync(root: dir, device: "B", store: b)
        T.expectEqual(try syncA.push(), 3, "A writes its three events")
        T.expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("english-events-A.jsonl").path),
                 "file named after the device")
        T.expectEqual(try syncB.pull(calendar: cal), 3, "B imports them")
        T.expectEqual(try b.card("vocab:x"), try a.card("vocab:x"), "same card state")
        T.expectEqual(try b.card("vocab:k")?.known, true, "known travels")
        T.expectEqual(try b.card("dict:extra")?.due, "2026-10-01", "added word is due the day it was added")
        T.expectEqual(try b.answeredCount(day: "2026-10-01"), 2, "log rows are rebuilt (rate + known)")
        T.expectEqual(try syncB.pull(calendar: cal), 0, "nothing new the second time")

        // B answers the same card the next day; A folds it on top of its own answer
        try b.record(id: "vocab:x", kind: .vocab, rating: .good, now: tokyoDate(2026, 10, 2, 9, 0), calendar: cal)
        try syncB.push()
        T.expectEqual(try syncA.pull(calendar: cal), 1, "A imports B's answer")
        T.expectEqual(try a.card("vocab:x")?.state.reps, 2, "two ratings in order")
        T.expectEqual(try a.card("vocab:x")?.due, "2026-10-05", "3 days after B's answer")
        T.expectEqual(try a.card("vocab:x"), try b.card("vocab:x"), "both sides agree")
        T.expectEqual(try a.streak(today: tokyoDate(2026, 10, 2, 20, 0), calendar: cal), 2, "streak counts both days")
        T.expectEqual(try syncA.push(), 3, "A still exports only its own events")
    }

    T.run("undo is replayed as an exclusion") {
        let dir = tempDir()
        let a = EnglishStore(db: try AppDatabase.inMemory(), device: "A")
        let b = EnglishStore(db: try AppDatabase.inMemory(), device: "B")
        let day1 = tokyoDate(2026, 10, 1, 10, 0)
        let point = try a.undoPoint(for: "vocab:y")
        try a.record(id: "vocab:y", kind: .vocab, rating: .easy, now: day1, calendar: cal)
        try a.undo(point, now: day1.addingTimeInterval(5), calendar: cal)
        T.expect(try a.card("vocab:y") == nil, "undone locally")
        try EnglishSync(root: dir, device: "A", store: a).push()
        T.expectEqual(try EnglishSync(root: dir, device: "B", store: b).pull(calendar: cal), 2, "rate + undo")
        T.expect(try b.card("vocab:y") == nil, "the undone rating never existed on B")
        T.expectEqual(try b.answeredCount(day: "2026-10-01"), 0, "no log row either")
    }

    T.run("undo only cancels its own card, even after a pull reshuffled the log") {
        let dir = tempDir()
        let a = EnglishStore(db: try AppDatabase.inMemory(), device: "A")
        let b = EnglishStore(db: try AppDatabase.inMemory(), device: "B")
        let day1 = tokyoDate(2026, 10, 1, 10, 0)
        try b.record(id: "vocab:from-b", kind: .vocab, rating: .good, now: day1, calendar: cal)
        try EnglishSync(root: dir, device: "B", store: b).push()

        let point = try a.undoPoint(for: "vocab:p")
        try a.record(id: "vocab:p", kind: .vocab, rating: .good, now: day1.addingTimeInterval(10), calendar: cal)
        try a.markKnown(id: "vocab:q", kind: .vocab, now: day1.addingTimeInterval(20), calendar: cal)
        T.expectEqual(try EnglishSync(root: dir, device: "A", store: a).pull(calendar: cal), 1, "B's answer arrives")
        try a.undo(point, now: day1.addingTimeInterval(30), calendar: cal)
        T.expect(try a.card("vocab:p") == nil, "the answer is undone")
        T.expectEqual(try a.card("vocab:q")?.known, true, "the other card is untouched")
        T.expect(try a.card("vocab:from-b") != nil, "the imported answer stays")
        T.expectEqual(try a.answeredCount(day: "2026-10-01"), 2, "B's answer + known")
    }

    T.run("rebuild is deterministic and idempotent") {
        let a = EnglishStore(db: try AppDatabase.inMemory(), device: "A")
        let day1 = tokyoDate(2026, 10, 1, 10, 0)
        try a.record(id: "vocab:z", kind: .vocab, rating: .again, now: day1, calendar: cal)
        try a.record(id: "vocab:z", kind: .vocab, rating: .good, now: day1.addingTimeInterval(30), calendar: cal)
        try a.record(id: "spell:insurance", kind: .spell, rating: .good, now: day1.addingTimeInterval(60), calendar: cal)
        let before = (try a.card("vocab:z"), try a.card("spell:insurance"), try a.answeredCount(day: "2026-10-01"))
        try a.rebuild(calendar: cal)
        let after = (try a.card("vocab:z"), try a.card("spell:insurance"), try a.answeredCount(day: "2026-10-01"))
        T.expectEqual(before.0, after.0, "card unchanged by rebuild")
        T.expectEqual(before.1, after.1, "other kind unchanged")
        T.expectEqual(before.2, after.2, "log count unchanged")
    }
}
