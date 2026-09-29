import Foundation

/// CLT 环境无 XCTest,用这个最小运行器。装上 Xcode 后可整体迁移到 XCTest。
enum T {
    static var testCount = 0
    static var failures: [String] = []
    private static var currentTest = ""

    static func run(_ name: String, _ body: () throws -> Void) {
        testCount += 1
        currentTest = name
        do {
            try body()
            print("  ✓ \(name)")
        } catch {
            failures.append("\(name): threw \(error)")
            print("  ✗ \(name) — threw \(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        if !condition {
            failures.append("\(currentTest): \(message) (\(file):\(line))")
            print("  ✗ \(currentTest) — \(message) (line \(line))")
        }
    }

    static func expectEqual<E: Equatable>(_ actual: E, _ expected: E, _ message: String = "",
                                          file: StaticString = #filePath, line: UInt = #line) {
        expect(actual == expected,
               "\(message) expected: \(expected), actual: \(actual)", file: file, line: line)
    }

    static func finish() -> Never {
        print("---")
        if failures.isEmpty {
            print("PASS: \(testCount) tests")
            exit(0)
        } else {
            print("FAIL: \(failures.count) failure(s) in \(testCount) tests")
            failures.forEach { print("  \($0)") }
            exit(1)
        }
    }
}

/// 测试用固定东京时区日历,避免测试依赖机器时区设置
let tokyoCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
}()

func tokyoDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    tokyoCalendar.date(from: DateComponents(year: y, month: mo, day: d,
                                            hour: h, minute: mi, second: s))!
}
