import Foundation
import NippoCore

func runEnglishTests() {
    T.run("SM-2 matches the IELTS app schedule") {
        var s = SRSState()
        s = s.applying(.good); T.expectEqual(s.interval, 1)
        s = s.applying(.good); T.expectEqual(s.interval, 3)
        s = s.applying(.good); T.expectEqual(s.interval, 8, "3 × 2.5 rounded")
        let hard = s.applying(.hard)
        T.expectEqual(hard.interval, 10, "8 × 1.2 rounded")
        T.expect(abs(hard.ease - 2.35) < 0.0001, "hard lowers ease")
        let again = s.applying(.again)
        T.expectEqual(again.interval, 0); T.expectEqual(again.reps, 0); T.expectEqual(again.lapses, 1)
        T.expectEqual(SRSState().applying(.easy).interval, 4)
        T.expectEqual(SRSState().applying(.hard).interval, 1, "new card hard → tomorrow")
        var floor = SRSState(ease: 1.35)
        floor = floor.applying(.again)
        T.expect(abs(floor.ease - 1.3) < 0.0001, "ease never below 1.3")
    }

    T.run("queue: due first, avoid the card just answered, then new within quota") {
        let pool = ["a", "b", "c"]
        T.expectEqual(EnglishQueue.next(due: ["x", "y"], pool: pool, seen: [], newToday: 0,
                                        newLimit: 10, avoid: "x"), "y")
        T.expectEqual(EnglishQueue.next(due: [], pool: pool, seen: ["a"], newToday: 3,
                                        newLimit: 10), "b")
        T.expectEqual(EnglishQueue.next(due: [], pool: pool, seen: [], newToday: 10,
                                        newLimit: 10), nil, "quota used up")
        T.expectEqual(EnglishQueue.next(due: ["x"], pool: pool, seen: [], newToday: 10,
                                        newLimit: 10, avoid: "x"), "x", "only the failed card left")
        T.expectEqual(EnglishQueue.remaining(due: 4, unseen: 2, newToday: 3, newLimit: 10), 6)
        T.expectEqual(EnglishQueue.remaining(due: 0, unseen: 50, newToday: 12, newLimit: 10), 0)
    }

    T.run("spell check: exact, almost (one letter off), wrong; ignores case and spacing") {
        T.expectEqual(SpellCheck.check("Accommodation", answer: "accommodation"), .correct)
        T.expectEqual(SpellCheck.check("  a  couple of ", answer: "a couple of"), .correct)
        T.expectEqual(SpellCheck.check("acommodation", answer: "accommodation"), .almost)
        T.expectEqual(SpellCheck.check("recieve", answer: "receive"), .wrong, "transposition = 2 edits")
        T.expectEqual(SpellCheck.check("tow", answer: "town"), .almost, "4 letters: one off is almost")
        T.expectEqual(SpellCheck.check("bas", answer: "bus"), .wrong, "under 4 letters must be exact")
        T.expectEqual(SpellCheck.check("", answer: "town"), .wrong)
        T.expectEqual(SpellCheck.check("ｔｏｗｎ", answer: "town"), .correct, "full-width")
        T.expectEqual(SpellCheck.levenshtein("kitten", "sitting"), 3)
    }

    T.run("paraphrase quiz: 4 distinct choices, one correct synonym, no leaks") {
        let pool = [
            ParaphraseEntry(w: "reserve", syn: ["book"], skill: "listening"),
            ParaphraseEntry(w: "adjust", syn: ["change", "alter"], skill: "listening"),
            ParaphraseEntry(w: "recognize", syn: ["identify", "realize"], skill: "reading"),
            ParaphraseEntry(w: "resemble", syn: ["be similar to"], skill: "reading"),
            ParaphraseEntry(w: "have to", syn: ["must"], skill: "listening"),
        ]
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<20 {
            guard let q = ParaphraseQuiz.make(entry: pool[1], pool: pool, using: &rng) else {
                T.expect(false, "question expected"); return
            }
            T.expectEqual(q.choices.count, 4)
            T.expectEqual(Set(q.choices).count, 4, "distinct")
            T.expect(pool[1].syn.contains(q.choices[q.answerIndex]), "answer is a synonym")
            let wrong = q.choices.enumerated().filter { $0.offset != q.answerIndex }.map(\.element)
            T.expect(!wrong.contains { pool[1].syn.contains($0) }, "no second correct answer")
        }
        T.expectEqual(ParaphraseQuiz.make(entry: pool[0], pool: Array(pool.prefix(2)), using: &rng), nil,
                      "not enough distractors")
    }

    T.run("dictionary lookup strips inflections") {
        let lib = EnglishLibrary(dictionary: ["study": ["ˈstʌdi", "v. 学习"], "run": ["rʌn", "v. 跑"],
                                              "abundant": ["ә'bʌndәnt", "a. 丰富的"]])
        T.expectEqual(lib.lookup(" Abundant ")?.zh, "a. 丰富的")
        T.expectEqual(lib.lookup("studies")?.word, "study")
        T.expectEqual(lib.lookup("running")?.word, "run")
        T.expectEqual(lib.lookup("zzz"), nil)
        T.expectEqual(lib.lookup(""), nil)
    }

    T.run("library loads JSON files and tolerates missing ones") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yudh-english-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"[{"id":"b1-1","w":"storey","ph":"/ˈstɔːri/","pos":"n.","zh":"层","lv":"b1"}]"#.utf8)
            .write(to: dir.appendingPathComponent("vocab.json"))
        try Data(#"[{"w":"reserve","syn":["book"],"skill":"listening"}]"#.utf8)
            .write(to: dir.appendingPathComponent("paraphrase.json"))
        let lib = EnglishLibrary.load(from: dir)
        T.expectEqual(lib.vocab.first?.w, "storey")
        T.expectEqual(lib.vocab.first?.ex, nil)
        T.expectEqual(lib.paraphrases.first?.syn, ["book"])
        T.expect(lib.dictation.isEmpty && lib.dictionary.isEmpty, "missing files are empty")
        T.expect(EnglishLibrary.load(from: dir.appendingPathComponent("nope")).isEmpty, "missing dir")
    }

    T.run("store: schedules, due list, known, quota, counts, streak") {
        let store = EnglishStore(db: try AppDatabase.inMemory())
        let day1 = tokyoDate(2026, 10, 1, 10, 0)
        let today = "2026-10-01"

        let c = try store.record(id: "vocab:b1-1", kind: .vocab, rating: .good, now: day1,
                                 calendar: tokyoCalendar)
        T.expectEqual(c.due, "2026-10-02")
        try store.record(id: "vocab:b1-2", kind: .vocab, rating: .again, now: day1, calendar: tokyoCalendar)
        T.expectEqual(try store.dueIDs(kind: .vocab, today: today), ["vocab:b1-2"])
        T.expectEqual(try store.dueIDs(kind: .vocab, today: "2026-10-02").count, 2)

        try store.markKnown(id: "vocab:b1-3", kind: .vocab, now: day1, calendar: tokyoCalendar)
        T.expectEqual(try store.seenIDs(kind: .vocab).count, 3)
        T.expect(!(try store.dueIDs(kind: .vocab, today: "2026-12-31")).contains("vocab:b1-3"),
                 "known cards never come back")

        T.expect(try store.add(id: "dict:abundant", kind: .vocab, now: day1, calendar: tokyoCalendar),
                 "added")
        T.expect(!(try store.add(id: "dict:abundant", kind: .vocab, now: day1, calendar: tokyoCalendar)),
                 "added once")
        T.expectEqual(try store.newCount(kind: .vocab, day: today), 3, "dictionary adds don't use the quota")
        T.expectEqual(try store.newCount(kind: .spell, day: today), 0)
        T.expectEqual(try store.answeredCount(day: today), 3)

        try store.record(id: "spell:town", kind: .spell, rating: .good,
                         now: tokyoDate(2026, 10, 2, 9, 0), calendar: tokyoCalendar)
        T.expectEqual(try store.streak(today: tokyoDate(2026, 10, 2, 20, 0), calendar: tokyoCalendar), 2)
        T.expectEqual(try store.streak(today: tokyoDate(2026, 10, 3, 8, 0), calendar: tokyoCalendar), 2,
                      "today not started yet: count up to yesterday")
        T.expectEqual(try store.streak(today: tokyoDate(2026, 10, 5, 8, 0), calendar: tokyoCalendar), 0)
    }

    T.run("store: undo the last answer, restore a known card, list cards") {
        let store = EnglishStore(db: try AppDatabase.inMemory())
        let now = tokyoDate(2026, 10, 1, 10, 0)
        let today = "2026-10-01"

        // 初めてのカードの答えを取り消すと、カードも記録も消える
        let first = try store.undoPoint(for: "vocab:a")
        try store.record(id: "vocab:a", kind: .vocab, rating: .good, now: now, calendar: tokyoCalendar)
        try store.undo(first, now: now, calendar: tokyoCalendar)
        T.expectEqual(try store.card("vocab:a"), nil)
        T.expectEqual(try store.answeredCount(day: today), 0)

        // 2 回目の答えを取り消すと、1 回目のあとの状態に戻る
        try store.record(id: "vocab:a", kind: .vocab, rating: .good, now: now, calendar: tokyoCalendar)
        let second = try store.undoPoint(for: "vocab:a")
        try store.record(id: "vocab:a", kind: .vocab, rating: .again, now: now, calendar: tokyoCalendar)
        try store.undo(second, now: now, calendar: tokyoCalendar)
        T.expectEqual(try store.card("vocab:a")?.due, "2026-10-02")
        T.expectEqual(try store.card("vocab:a")?.state.reps, 1)
        T.expectEqual(try store.answeredCount(day: today), 1)

        // 「知ってる」を戻すと今日の復習に並ぶ
        try store.markKnown(id: "vocab:b", kind: .vocab, now: now, calendar: tokyoCalendar)
        T.expect(!(try store.dueIDs(kind: .vocab, today: today)).contains("vocab:b"), "known is hidden")
        try store.restore(id: "vocab:b", now: now, calendar: tokyoCalendar)
        T.expect(try store.dueIDs(kind: .vocab, today: today).contains("vocab:b"), "restored is due today")

        T.expectEqual(try store.cards(kind: .vocab).map(\.id), ["vocab:b", "vocab:a"], "ordered by due")
        T.expectEqual(try store.cards(kind: .spell).count, 0)
    }
}
