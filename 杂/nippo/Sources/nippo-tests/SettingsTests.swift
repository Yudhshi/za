import Foundation
import NippoCore

func runSettingsTests() {
    T.run("defaults and roundtrip") {
        let suite = "nippo-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: d)

        T.expectEqual(s.reminderLeadMinutes, 5)
        T.expect(s.reportsRoot.hasSuffix("Documents/日報"), "default root, got \(s.reportsRoot)")

        s.reminderLeadMinutes = 10
        T.expectEqual(AppSettings(defaults: d).reminderLeadMinutes, 10)

        T.expectEqual(s.workStartTime, "09:00")
        T.expectEqual(s.workEndTime, "18:00")
        T.expect(s.isWithinWorkHours(tokyoDate(2026, 10, 1, 9, 0), calendar: tokyoCalendar), "start inclusive")
        T.expect(!s.isWithinWorkHours(tokyoDate(2026, 10, 1, 18, 0), calendar: tokyoCalendar), "end exclusive")
        s.workStartTime = "8:45"
        T.expect(s.isWithinWorkHours(tokyoDate(2026, 10, 1, 8, 50), calendar: tokyoCalendar), "custom start")
        s.workEndTime = "junk"
        T.expect(!s.isWithinWorkHours(tokyoDate(2026, 10, 1, 18, 30), calendar: tokyoCalendar), "bad end falls back to 18:00")

        T.expectEqual(s.workBeganTime, nil)
        T.expectEqual(s.workBeganDay, nil)
        s.workBeganTime = "08:53"
        s.workBeganDay = "2026-09-29"
        T.expectEqual(AppSettings(defaults: d).workBeganTime, "08:53")
        T.expectEqual(AppSettings(defaults: d).workBeganDay, "2026-09-29")

        T.expectEqual(s.taskMemo, "")
        s.taskMemo = "事例公開\n\t- 電話"
        T.expectEqual(AppSettings(defaults: d).taskMemo, "事例公開\n\t- 電話")
        T.expectEqual(s.shachokenKeywords, "新卒社長研修, シャチョケン")
        s.shachokenKeywords = "シャチョケン"
        T.expectEqual(s.shachokenKeywords, AppSettings.defaultShachokenKeywords, "old default is upgraded")
        s.shachokenKeywords = "社長研修"
        T.expectEqual(AppSettings(defaults: d).shachokenKeywords, "社長研修")
        T.expectEqual(s.loginItemMovedToYudh, false)

        T.expectEqual(s.postureEnabled, true)
        T.expectEqual(s.sitMinutes, 45)
        T.expectEqual(s.standMinutes, 15)
        T.expectEqual(s.stretches, BreakReminder.defaultStretches)
        s.sitMinutes = 30
        s.stretches = "肩回し"
        T.expectEqual(AppSettings(defaults: d).sitMinutes, 30)
        T.expectEqual(AppSettings(defaults: d).stretches, "肩回し")
        T.expectEqual(s.lastStretchIndex, 0)
    }

    T.run("time parsing with fallback") {
        let suite = "nippo-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: d)
        var t = s.timeComponents("21:00", fallback: (21, 0))
        T.expectEqual(t.hour, 21); T.expectEqual(t.minute, 0)
        t = s.timeComponents("9:05", fallback: (21, 0))
        T.expectEqual(t.hour, 9); T.expectEqual(t.minute, 5)
        t = s.timeComponents("junk", fallback: (21, 0))
        T.expectEqual(t.hour, 21); T.expectEqual(t.minute, 0)
        t = s.timeComponents("24:00", fallback: (21, 0))
        T.expectEqual(t.hour, 21, "out-of-range hour falls back")
    }
}
