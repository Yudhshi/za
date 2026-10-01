import Foundation
import NippoCore

func runHabitsSyncTests() {
    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("yudh-habits-\(UUID().uuidString)")
    }

    T.run("habits: other devices add up per day; the own file is never read") {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        // Windows が書いたもの(yudh-core の書式:serde の整形)
        let windows = """
        {
          "ritual": {
            "2026-09-30": 1
          },
          "ritualStrength": {},
          "breath": {
            "2026-10-01": 2
          }
        }
        """
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? windows.write(to: root.appendingPathComponent("habits-DESKTOP-9F2.json"), atomically: true, encoding: .utf8)
        try? "{oops".write(to: root.appendingPathComponent("habits-broken.json"), atomically: true, encoding: .utf8)
        // 自分の古いファイル(読まない:手元の記録のほうが新しい)
        try? HabitsSync.render(Habits(breath: ["2026-10-01": 99]))
            .write(to: root.appendingPathComponent("habits-Yudh-MacBook.json"), atomically: true, encoding: .utf8)

        let own = Habits(ritual: ["2026-09-29": 1, "2026-10-01": 1], ritualStrength: ["2026-09-29": 1],
                         breath: ["2026-10-01": 1])
        let others = HabitsSync.others(device: "Yudh MacBook", root: root)
        T.expectEqual(others, Habits(ritual: ["2026-09-30": 1], breath: ["2026-10-01": 2]),
                      "Windows only; broken and own files skipped")
        let all = own.merged(with: others)
        T.expectEqual(all.breath["2026-10-01"], 3, "1 on the Mac + 2 on Windows")
        let today = tokyoDate(2026, 10, 1, 22)
        T.expectEqual(BreathLog.streak(all.ritual, today: today, calendar: tokyoCalendar), 3,
                      "9/29 Mac, 9/30 Windows, 10/1 Mac")
        T.expectEqual(BreathLog.streak(own.ritual, today: today, calendar: tokyoCalendar), 1,
                      "alone the Mac only sees today")
        T.expect(!Ritual.includesStrength(log: all.ritualStrength.merging(["2026-09-30": 1], uniquingKeysWith: +),
                                          today: today, calendar: tokyoCalendar),
                 "strength done on Windows yesterday → not today")
        T.expectEqual(HabitsSync.others(device: "Yudh MacBook", root: root.appendingPathComponent("nope")), Habits(),
                      "no folder: nothing")
    }

    T.run("habits: written once, same content is not rewritten, round trip") {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let own = Habits(ritual: ["2026-10-01": 1], breath: ["2026-10-01": 3])
        T.expect((try? HabitsSync.write(own, device: "Yudh MacBook", to: root)) == true, "first write")
        T.expect((try? HabitsSync.write(own, device: "Yudh MacBook", to: root)) == false, "same content: untouched")
        let data = try? Data(contentsOf: root.appendingPathComponent("habits-Yudh-MacBook.json"))
        T.expectEqual(data.flatMap(HabitsSync.parse), own, "round trip (empty logs stay empty)")
        T.expectEqual(HabitsSync.fileName(for: "Mac Book (Yudh)"), "habits-Mac-Book--Yudh.json", "same slug as the events")
        T.expectEqual(HabitsSync.parse(Data(#"{"ritualStrength":{"2026-10-01":1}}"#.utf8)),
                      Habits(ritualStrength: ["2026-10-01": 1]), "missing keys are empty")
        T.expectEqual(HabitsSync.parse(Data("[]".utf8)), nil, "not an object")
    }
}
