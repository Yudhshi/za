import Foundation
import NippoCore

func runWorkStartTests() {
    func p(_ s: String) -> String {
        WorkStart.parse(s).map { String(format: "%d:%02d", $0.hour, $0.minute) } ?? "nil"
    }

    T.run("parse: 3-4 digits, colon, 1-2 digit hours, full-width") {
        T.expectEqual(p("853"), "8:53")
        T.expectEqual(p("0853"), "8:53")
        T.expectEqual(p("1005"), "10:05")
        T.expectEqual(p("8:53"), "8:53")
        T.expectEqual(p("9"), "9:00")
        T.expectEqual(p("10"), "10:00")
        T.expectEqual(p(" 853 "), "8:53")
        T.expectEqual(p("８５３"), "8:53")
    }

    T.run("parse rejects out-of-range and junk") {
        for bad in ["", "860", "2400", "12345", "8:5", "abc", "8:60", "25"] {
            T.expectEqual(p(bad), "nil", "'\(bad)'")
        }
    }

    T.run("duration text") {
        let start = tokyoDate(2026, 10, 1, 8, 53)
        T.expectEqual(WorkStart.durationText(from: start, to: tokyoDate(2026, 10, 1, 9, 38)), "45分")
        T.expectEqual(WorkStart.durationText(from: start, to: tokyoDate(2026, 10, 1, 12, 5)), "3時間12分")
        T.expectEqual(WorkStart.durationText(from: start, to: tokyoDate(2026, 10, 1, 8, 50)), "0分")
    }
}
