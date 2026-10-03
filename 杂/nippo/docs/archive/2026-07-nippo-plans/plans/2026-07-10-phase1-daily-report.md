# Nippo 第一期(菜单栏骨架 + 随手记 + 日历&会议提醒 + 日报生成)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个常驻菜单栏的 macOS 应用:全局快捷键随手记、读取日历并在会议前通知、每个工作日 17:45 调用 Claude Code CLI 把当天素材生成日语日报 Markdown 到 `~/Documents/日報/`。

**Architecture:** SPM 三目标结构——`NippoCore`(全部业务逻辑,库,可测试)、`NippoApp`(SwiftUI MenuBarExtra 壳 + 系统集成)、`nippo-tests`(轻量测试运行器,普通可执行目标;本机 CLT 无 XCTest/Swift Testing,故自制断言框架)。数据:GRDB/SQLite(随手记、请假日)+ 普通 Markdown 文件(报告)。文案生成走 `claude -p` 无头模式子进程。

**Tech Stack:** Swift 6.3(v5 语言模式,规避严格并发迁移成本)、SwiftUI MenuBarExtra、GRDB 7、HotKey(全局快捷键)、EventKit、UserNotifications、Claude Code CLI。

**环境事实(已验证,勿再假设):**
- 本机无 Xcode,只有 CLT(`/Library/Developer/CommandLineTools`),`swift test` 不可用(无 XCTest、无 Testing 模块)→ 测试一律 `swift run nippo-tests`
- claude CLI:`/Users/lease-emp-mac-yudi-shi/.local/bin/claude`(v2.1.117)
- Swift 6.3,SDK macosx26.0;机器 M4 Pro / 48GB / macOS 26.5
- 项目根:`/Users/lease-emp-mac-yudi-shi/Desktop/杂/nippo/`(已有 git 仓库与 docs/)
- UserNotifications、EventKit、SMAppService 在**非 bundle 的裸可执行文件里不可用/行为异常**——涉及这些的手动验证必须用 Task 12 产出的 `dist/Nippo.app` 进行

---

### Task 1: 项目脚手架 + 轻量测试框架

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/NippoCore/Placeholder.swift`(本任务临时占位,Task 2 起被真实代码替代后删除)
- Create: `Sources/NippoApp/NippoApp.swift`(最小可编译壳,Task 11 扩充)
- Create: `Sources/nippo-tests/TestKit.swift`
- Create: `Sources/nippo-tests/main.swift`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nippo",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "NippoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NippoApp",
            dependencies: ["NippoCore", "HotKey"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "nippo-tests",
            dependencies: ["NippoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: 写 .gitignore**

```
.build/
dist/
.DS_Store
```

- [ ] **Step 3: 写最小源文件**

`Sources/NippoCore/Placeholder.swift`:

```swift
// Task 2 で実コードに置き換える
public enum NippoCoreVersion {
    public static let current = "0.1.0"
}
```

`Sources/NippoApp/NippoApp.swift`:

```swift
import SwiftUI
import NippoCore

@main
struct NippoApp: App {
    var body: some Scene {
        MenuBarExtra("Nippo", systemImage: "doc.text") {
            Text("Nippo \(NippoCoreVersion.current)")
            Button("終了") { NSApp.terminate(nil) }
        }
    }
}
```

- [ ] **Step 4: 写测试框架 TestKit**

`Sources/nippo-tests/TestKit.swift`:

```swift
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
```

`Sources/nippo-tests/main.swift`:

```swift
import Foundation
import NippoCore

print("nippo-tests")
T.run("sanity") {
    T.expectEqual(NippoCoreVersion.current, "0.1.0")
}
T.finish()
```

- [ ] **Step 5: 构建并跑测试**

Run: `cd /Users/lease-emp-mac-yudi-shi/Desktop/杂/nippo && swift run nippo-tests`
Expected: 首次会拉取 GRDB/HotKey 依赖(需网络,约 1-3 分钟),最终输出 `PASS: 1 tests`

- [ ] **Step 6: 确认 App 目标也能编译**

Run: `swift build --target NippoApp`
Expected: `Build complete!`(不运行,只验证编译)

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "chore: scaffold SPM package with NippoCore/NippoApp/nippo-tests targets"
```

---

### Task 2: 数据库层(AppDatabase + Note)

**Files:**
- Create: `Sources/NippoCore/Database/AppDatabase.swift`
- Create: `Sources/NippoCore/Database/Note.swift`
- Create: `Sources/nippo-tests/DatabaseTests.swift`
- Modify: `Sources/nippo-tests/main.swift`
- Delete: `Sources/NippoCore/Placeholder.swift`(NippoApp.swift 中对 `NippoCoreVersion` 的引用改为字符串字面量 `"Nippo 0.1.0"`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/DatabaseTests.swift`:

```swift
import Foundation
import NippoCore

func runDatabaseTests() {
    T.run("in-memory db migrates and stores a note") {
        let db = try AppDatabase.inMemory()
        var note = Note(createdAt: Date(), text: "テスト")
        try db.dbQueue.write { try note.insert($0) }
        T.expect(note.id != nil, "insert should set id")
        let all = try db.dbQueue.read { try Note.fetchAll($0) }
        T.expectEqual(all.count, 1)
        T.expectEqual(all[0].text, "テスト")
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
```

`Sources/nippo-tests/main.swift` 全文替换为:

```swift
import Foundation
import NippoCore

print("nippo-tests")
runDatabaseTests()
T.finish()
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: 编译错误 `cannot find 'AppDatabase' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Database/Note.swift`:

```swift
import Foundation
import GRDB

public struct Note: Codable, Equatable, Identifiable,
                    FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "note"

    public var id: Int64?
    public var createdAt: Date
    public var text: String

    public init(id: Int64? = nil, createdAt: Date, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

`Sources/NippoCore/Database/AppDatabase.swift`:

```swift
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
        return m
    }
}
```

同时删除 `Sources/NippoCore/Placeholder.swift`,并把 `Sources/NippoApp/NippoApp.swift` 中 `Text("Nippo \(NippoCoreVersion.current)")` 改为 `Text("Nippo 0.1.0")`(该行 Task 11 会整体重写)。

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests && swift build --target NippoApp`
Expected: `PASS: 2 tests`,NippoApp 编译通过

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add GRDB database layer with note and vacation tables"
```

---

### Task 3: NotesService(随手记增删改查)

**Files:**
- Create: `Sources/NippoCore/Notes/NotesService.swift`
- Create: `Sources/NippoCore/Schedule/DayKey.swift`(日期→"yyyy-MM-dd" 工具,多模块共用)
- Create: `Sources/nippo-tests/NotesTests.swift`
- Modify: `Sources/nippo-tests/main.swift`

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/NotesTests.swift`:

```swift
import Foundation
import NippoCore

/// 测试用固定东京时区日历,避免测试依赖机器时区设置
let tokyoCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
}()

func tokyoDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    tokyoCalendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

func runNotesTests() {
    T.run("add + fetch today's notes in time order") {
        let db = try AppDatabase.inMemory()
        let svc = NotesService(db: db, calendar: tokyoCalendar)
        try svc.add("午後のメモ", at: tokyoDate(2026, 7, 10, 15, 0))
        try svc.add("朝のメモ", at: tokyoDate(2026, 7, 10, 9, 0))
        try svc.add("前日のメモ", at: tokyoDate(2026, 7, 9, 18, 0))
        let notes = try svc.notes(on: tokyoDate(2026, 7, 10, 12, 0))
        T.expectEqual(notes.count, 2)
        T.expectEqual(notes[0].text, "朝のメモ")
        T.expectEqual(notes[1].text, "午後のメモ")
    }

    T.run("update and delete") {
        let db = try AppDatabase.inMemory()
        let svc = NotesService(db: db, calendar: tokyoCalendar)
        let note = try svc.add("原文", at: tokyoDate(2026, 7, 10, 9, 0))
        try svc.update(id: note.id!, text: "修正後")
        var notes = try svc.notes(on: tokyoDate(2026, 7, 10))
        T.expectEqual(notes[0].text, "修正後")
        try svc.delete(id: note.id!)
        notes = try svc.notes(on: tokyoDate(2026, 7, 10))
        T.expectEqual(notes.count, 0)
    }

    T.run("DayKey formats") {
        T.expectEqual(DayKey.key(for: tokyoDate(2026, 7, 10, 23, 59), calendar: tokyoCalendar),
                      "2026-07-10")
    }
}
```

`main.swift` 在 `runDatabaseTests()` 后追加一行 `runNotesTests()`。

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'NotesService' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Schedule/DayKey.swift`:

```swift
import Foundation

public enum DayKey {
    /// "yyyy-MM-dd"(所给 calendar 的时区)
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
```

`Sources/NippoCore/Notes/NotesService.swift`:

```swift
import Foundation
import GRDB

public struct NotesService {
    let db: AppDatabase
    let calendar: Calendar

    public init(db: AppDatabase, calendar: Calendar = .current) {
        self.db = db
        self.calendar = calendar
    }

    @discardableResult
    public func add(_ text: String, at date: Date = Date()) throws -> Note {
        var note = Note(createdAt: date, text: text)
        try db.dbQueue.write { try note.insert($0) }
        return note
    }

    public func notes(on day: Date) throws -> [Note] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try db.dbQueue.read {
            try Note
                .filter(Column("createdAt") >= start && Column("createdAt") < end)
                .order(Column("createdAt"))
                .fetchAll($0)
        }
    }

    public func update(id: Int64, text: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "UPDATE note SET text = ? WHERE id = ?",
                           arguments: [text, id])
        }
    }

    public func delete(id: Int64) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [id])
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 5 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add NotesService and DayKey"
```

---

### Task 4: AppSettings(设置存取)

**Files:**
- Create: `Sources/NippoCore/Settings/AppSettings.swift`
- Create: `Sources/nippo-tests/SettingsTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runSettingsTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/SettingsTests.swift`:

```swift
import Foundation
import NippoCore

func runSettingsTests() {
    T.run("defaults and roundtrip") {
        let suite = "nippo-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: d)

        T.expectEqual(s.reportTime, "17:45")
        T.expectEqual(s.reminderLeadMinutes, 5)
        T.expect(s.reportTemplate.contains("今日やったこと"), "default template")
        T.expect(s.reportsRoot.hasSuffix("Documents/日報"), "default root, got \(s.reportsRoot)")
        T.expectEqual(s.lastReportFiredDay, nil)

        s.reportTime = "18:30"
        s.reminderLeadMinutes = 10
        s.lastReportFiredDay = "2026-07-10"
        let s2 = AppSettings(defaults: d)
        T.expectEqual(s2.reportTime, "18:30")
        T.expectEqual(s2.reminderLeadMinutes, 10)
        T.expectEqual(s2.lastReportFiredDay, "2026-07-10")
    }

    T.run("reportTime parsing with fallback") {
        let suite = "nippo-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: d)
        var t = s.reportTimeComponents()
        T.expectEqual(t.hour, 17); T.expectEqual(t.minute, 45)
        s.reportTime = "9:05"
        t = s.reportTimeComponents()
        T.expectEqual(t.hour, 9); T.expectEqual(t.minute, 5)
        s.reportTime = "junk"
        t = s.reportTimeComponents()
        T.expectEqual(t.hour, 17); T.expectEqual(t.minute, 45)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'AppSettings' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Settings/AppSettings.swift`:

```swift
import Foundation
import Combine

public final class AppSettings: ObservableObject {
    private let d: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
    }

    public static let defaultTemplate = """
    ## 今日やったこと

    ## 明日の予定

    ## 課題・所感
    """

    public var reportTime: String {   // "HH:mm"
        get { d.string(forKey: "reportTime") ?? "17:45" }
        set { d.set(newValue, forKey: "reportTime"); objectWillChange.send() }
    }

    public var reminderLeadMinutes: Int {
        get { d.object(forKey: "reminderLeadMinutes") as? Int ?? 5 }
        set { d.set(newValue, forKey: "reminderLeadMinutes"); objectWillChange.send() }
    }

    public var reportTemplate: String {
        get { d.string(forKey: "reportTemplate") ?? Self.defaultTemplate }
        set { d.set(newValue, forKey: "reportTemplate"); objectWillChange.send() }
    }

    /// claude CLI のパス上書き(空なら自動検出)
    public var claudePath: String {
        get { d.string(forKey: "claudePath") ?? "" }
        set { d.set(newValue, forKey: "claudePath"); objectWillChange.send() }
    }

    public var reportsRoot: String {
        get {
            d.string(forKey: "reportsRoot")
                ?? ("~/Documents/日報" as NSString).expandingTildeInPath
        }
        set { d.set(newValue, forKey: "reportsRoot"); objectWillChange.send() }
    }

    public var lastReportFiredDay: String? {   // "yyyy-MM-dd"
        get { d.string(forKey: "lastReportFiredDay") }
        set { d.set(newValue, forKey: "lastReportFiredDay"); objectWillChange.send() }
    }

    public func reportTimeComponents() -> (hour: Int, minute: Int) {
        let parts = reportTime.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return (h, m)
        }
        return (17, 45)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 7 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add AppSettings backed by UserDefaults"
```

---

### Task 5: QuietDayChecker(周末/日本节假日/请假日)

**Files:**
- Create: `Sources/NippoCore/Schedule/QuietDayChecker.swift`
- Create: `Sources/nippo-tests/QuietDayTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runQuietDayTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/QuietDayTests.swift`:

```swift
import Foundation
import NippoCore

func runQuietDayTests() {
    T.run("weekday is not quiet, weekend is quiet") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 10), calendar: tokyoCalendar), false) // 金
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 11), calendar: tokyoCalendar), true)  // 土
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 12), calendar: tokyoCalendar), true)  // 日
    }

    T.run("JP holiday is quiet") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 7, 20), calendar: tokyoCalendar), true)  // 海の日(月)
        T.expectEqual(try q.isQuietDay(tokyoDate(2026, 9, 22), calendar: tokyoCalendar), true)  // 国民の休日(火)
    }

    T.run("vacation add/remove/list") {
        let db = try AppDatabase.inMemory()
        let q = QuietDayChecker(db: db)
        let day = tokyoDate(2026, 7, 15) // 水
        T.expectEqual(try q.isQuietDay(day, calendar: tokyoCalendar), false)
        try q.addVacation("2026-07-15")
        T.expectEqual(try q.isQuietDay(day, calendar: tokyoCalendar), true)
        T.expectEqual(try q.vacations(), ["2026-07-15"])
        try q.removeVacation("2026-07-15")
        T.expectEqual(try q.isQuietDay(day, calendar: tokyoCalendar), false)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'QuietDayChecker' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Schedule/QuietDayChecker.swift`:

```swift
import Foundation
import GRDB

public struct QuietDayChecker {
    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    /// 日本の祝日(振替休日・国民の休日を含む)。年ごとに追記して更新する。
    public static let jpHolidays: Set<String> = [
        // 2026
        "2026-01-01", "2026-01-12", "2026-02-11", "2026-02-23", "2026-03-20",
        "2026-04-29", "2026-05-03", "2026-05-04", "2026-05-05", "2026-05-06",
        "2026-07-20", "2026-08-11", "2026-09-21", "2026-09-22", "2026-09-23",
        "2026-10-12", "2026-11-03", "2026-11-23",
    ]

    /// 静默日:周末、日本节假日、用户登记的请假日。
    public func isQuietDay(_ date: Date, calendar: Calendar = .current) throws -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return true }   // 日曜・土曜
        let key = DayKey.key(for: date, calendar: calendar)
        if Self.jpHolidays.contains(key) { return true }
        return try db.dbQueue.read {
            try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM vacation WHERE day = ?)",
                              arguments: [key]) ?? false
        }
    }

    public func addVacation(_ day: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "INSERT OR IGNORE INTO vacation (day) VALUES (?)",
                           arguments: [day])
        }
    }

    public func removeVacation(_ day: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "DELETE FROM vacation WHERE day = ?", arguments: [day])
        }
    }

    public func vacations() throws -> [String] {
        try db.dbQueue.read {
            try String.fetchAll($0, sql: "SELECT day FROM vacation ORDER BY day")
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 10 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add QuietDayChecker with JP holidays and vacation days"
```

---

### Task 6: DailyTrigger(每日一次的触发判定)

**Files:**
- Create: `Sources/NippoCore/Schedule/DailyTrigger.swift`
- Create: `Sources/nippo-tests/DailyTriggerTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runDailyTriggerTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/DailyTriggerTests.swift`:

```swift
import Foundation
import NippoCore

func runDailyTriggerTests() {
    T.run("fires at/after configured time, once per day") {
        let at = { (h: Int, m: Int) in tokyoDate(2026, 7, 10, h, m) }
        // 時刻前 → 発火しない
        T.expectEqual(DailyTrigger.shouldFire(now: at(17, 44), hour: 17, minute: 45,
                                              lastFiredDay: nil, calendar: tokyoCalendar), false)
        // 時刻ちょうど → 発火
        T.expectEqual(DailyTrigger.shouldFire(now: at(17, 45), hour: 17, minute: 45,
                                              lastFiredDay: nil, calendar: tokyoCalendar), true)
        // 同日既発火 → 発火しない
        T.expectEqual(DailyTrigger.shouldFire(now: at(18, 0), hour: 17, minute: 45,
                                              lastFiredDay: "2026-07-10", calendar: tokyoCalendar), false)
        // 前日発火済みで翌日時刻超過 → 発火
        T.expectEqual(DailyTrigger.shouldFire(now: at(23, 0), hour: 17, minute: 45,
                                              lastFiredDay: "2026-07-09", calendar: tokyoCalendar), true)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'DailyTrigger' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Schedule/DailyTrigger.swift`:

```swift
import Foundation

public enum DailyTrigger {
    /// アプリ起動が遅れても同日中なら追いつき発火する(時刻「以降」判定)。
    public static func shouldFire(now: Date, hour: Int, minute: Int,
                                  lastFiredDay: String?,
                                  calendar: Calendar = .current) -> Bool {
        let today = DayKey.key(for: now, calendar: calendar)
        guard lastFiredDay != today else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = c.hour! * 60 + c.minute!
        return nowMinutes >= hour * 60 + minute
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 11 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add DailyTrigger once-per-day fire logic"
```

---

### Task 7: ClaudeCLI(文案生成子进程封装)

**Files:**
- Create: `Sources/NippoCore/Claude/TextGenerator.swift`
- Create: `Sources/NippoCore/Claude/ClaudeCLI.swift`
- Create: `Sources/nippo-tests/ClaudeCLITests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runClaudeCLITests()`)

- [ ] **Step 1: 写失败测试**

测试不调用真 claude(慢、耗额度),用临时 shell 脚本假扮。

`Sources/nippo-tests/ClaudeCLITests.swift`:

```swift
import Foundation
import NippoCore

private func makeFakeCLI(script: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nippo-fakecli-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("claude")
    try ("#!/bin/bash\n" + script).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

func runClaudeCLITests() {
    T.run("returns stdout for stdin prompt") {
        let fake = try makeFakeCLI(script: "cat > /dev/null; echo '# 日報'")
        let cli = ClaudeCLI(executable: fake)
        let out = try cli.generate(prompt: "hello")
        T.expectEqual(out, "# 日報")
    }

    T.run("nonzero exit throws with stderr") {
        let fake = try makeFakeCLI(script: "cat > /dev/null; echo 'boom' >&2; exit 3")
        let cli = ClaudeCLI(executable: fake)
        do {
            _ = try cli.generate(prompt: "hello")
            T.expect(false, "should have thrown")
        } catch let ClaudeCLI.CLIError.exited(code, stderr) {
            T.expectEqual(code, 3)
            T.expect(stderr.contains("boom"), "stderr captured")
        }
    }

    T.run("empty output throws") {
        let fake = try makeFakeCLI(script: "cat > /dev/null; echo ''")
        let cli = ClaudeCLI(executable: fake)
        do {
            _ = try cli.generate(prompt: "hello")
            T.expect(false, "should have thrown")
        } catch ClaudeCLI.CLIError.emptyOutput {
            // expected
        }
    }

    T.run("detect prefers custom path") {
        let fake = try makeFakeCLI(script: "true")
        let found = ClaudeCLI.detect(customPath: fake.path)
        T.expectEqual(found?.path, fake.path)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'ClaudeCLI' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Claude/TextGenerator.swift`:

```swift
import Foundation

public protocol TextGenerator {
    func generate(prompt: String) throws -> String
}
```

`Sources/NippoCore/Claude/ClaudeCLI.swift`:

```swift
import Foundation

/// `claude -p`(ヘッドレスモード)で文章生成する。プロンプトは stdin 経由。
public struct ClaudeCLI: TextGenerator {
    public enum CLIError: LocalizedError {
        case timedOut
        case exited(code: Int32, stderr: String)
        case emptyOutput

        public var errorDescription: String? {
            switch self {
            case .timedOut: return "claude CLI がタイムアウトしました"
            case .exited(let code, let stderr):
                return "claude CLI がエラー終了 (code \(code)): \(stderr.prefix(300))"
            case .emptyOutput: return "claude CLI の出力が空でした"
            }
        }
    }

    public let executable: URL
    public var timeout: TimeInterval = 300

    public init(executable: URL) {
        self.executable = executable
    }

    /// customPath(設定値)→ 既知の場所の順で探す。
    public static func detect(customPath: String? = nil) -> URL? {
        var candidates: [String] = []
        if let p = customPath, !p.isEmpty {
            candidates.append((p as NSString).expandingTildeInPath)
        }
        let home = NSHomeDirectory()
        candidates += [
            "\(home)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public func generate(prompt: String) throws -> String {
        let p = Process()
        p.executableURL = executable
        // --tools "" で全ツール無効、--strict-mcp-config で MCP も除外:
        // 生成にツールは不要。ローカルへのアクセスを遮断する(仕様 §5.3 の要件)
        p.arguments = ["-p", "--output-format", "text",
                       "--tools", "", "--strict-mcp-config"]

        var env = ProcessInfo.processInfo.environment
        let extra = "/usr/local/bin:/opt/homebrew/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = [env["PATH"], extra].compactMap { $0 }.joined(separator: ":")
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        try p.run()

        // タイムアウト保険
        var timedOut = false
        let killer = DispatchWorkItem {
            timedOut = true
            p.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        // プロンプトは数十KBを想定(パイプバッファ内)。フェーズ3で長大化したら
        // stdin書き込みをバックグラウンド化すること。
        inPipe.fileHandleForWriting.write(prompt.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()

        // デッドロック回避のため waitUntilExit の前に読み切る
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        if timedOut { throw CLIError.timedOut }
        guard p.terminationStatus == 0 else {
            throw CLIError.exited(code: p.terminationStatus,
                                  stderr: String(data: errData, encoding: .utf8) ?? "")
        }
        let text = (String(data: outData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CLIError.emptyOutput }
        return text
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 15 tests`

- [ ] **Step 5: 真机冒烟测试(一次性,验证参数正确)**

Run: `echo "「テスト成功」とだけ出力してください" | /Users/lease-emp-mac-yudi-shi/.local/bin/claude -p --output-format text --tools "" --strict-mcp-config`
Expected: 输出包含「テスト成功」。若该命令因版本差异报参数错误,修正 `ClaudeCLI.arguments` 与此命令一致并重跑 Step 4。

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add ClaudeCLI headless text generation wrapper"
```

---

### Task 8: MeetingEvent + PromptBuilder

**Files:**
- Create: `Sources/NippoCore/Calendar/MeetingEvent.swift`
- Create: `Sources/NippoCore/Report/PromptBuilder.swift`
- Create: `Sources/nippo-tests/PromptBuilderTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runPromptBuilderTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/PromptBuilderTests.swift`:

```swift
import Foundation
import NippoCore

func runPromptBuilderTests() {
    T.run("prompt contains date, template, notes and events") {
        let notes = [
            Note(id: 1, createdAt: tokyoDate(2026, 7, 10, 9, 12), text: "API設計レビュー"),
            Note(id: 2, createdAt: tokyoDate(2026, 7, 10, 15, 30), text: "バグ修正 #123"),
        ]
        let events = [
            MeetingEvent(id: "e1", title: "定例MTG",
                         start: tokyoDate(2026, 7, 10, 10, 0),
                         end: tokyoDate(2026, 7, 10, 11, 0),
                         attendees: ["田中", "佐藤"], isAllDay: false),
        ]
        let prompt = PromptBuilder.dailyReport(
            date: tokyoDate(2026, 7, 10, 17, 45),
            template: "## 今日やったこと",
            notes: notes, events: events, calendar: tokyoCalendar)

        T.expect(prompt.contains("2026-07-10"), "date")
        T.expect(prompt.contains("## 今日やったこと"), "template")
        T.expect(prompt.contains("09:12 API設計レビュー"), "note with time")
        T.expect(prompt.contains("10:00-11:00 定例MTG"), "event with span")
        T.expect(prompt.contains("田中"), "attendees")
        T.expect(prompt.contains("Markdown本文のみ"), "output constraint")
    }

    T.run("empty sections render placeholders") {
        let prompt = PromptBuilder.dailyReport(
            date: tokyoDate(2026, 7, 10), template: "T",
            notes: [], events: [], calendar: tokyoCalendar)
        T.expect(prompt.contains("(メモなし)"), "no-notes marker")
        T.expect(prompt.contains("(予定なし)"), "no-events marker")
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'MeetingEvent' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Calendar/MeetingEvent.swift`:

```swift
import Foundation

public struct MeetingEvent: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let attendees: [String]
    public let isAllDay: Bool

    public init(id: String, title: String, start: Date, end: Date,
                attendees: [String], isAllDay: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.isAllDay = isAllDay
    }
}
```

`Sources/NippoCore/Report/PromptBuilder.swift`:

```swift
import Foundation

public enum PromptBuilder {
    static func hhmm(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    static func japaneseDateLabel(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd(EEE)"
        return f.string(from: date)
    }

    public static func dailyReport(date: Date, template: String,
                                   notes: [Note], events: [MeetingEvent],
                                   calendar: Calendar = .current) -> String {
        let noteLines = notes.isEmpty
            ? "(メモなし)"
            : notes.map { "- \(hhmm($0.createdAt, calendar: calendar)) \($0.text)" }
                   .joined(separator: "\n")

        let eventLines = events.isEmpty
            ? "(予定なし)"
            : events.map { e -> String in
                let span = e.isAllDay
                    ? "終日"
                    : "\(hhmm(e.start, calendar: calendar))-\(hhmm(e.end, calendar: calendar))"
                let who = e.attendees.isEmpty ? "" : "(参加者: \(e.attendees.joined(separator: ", ")))"
                return "- \(span) \(e.title)\(who)"
              }.joined(separator: "\n")

        return """
        あなたは日本語のビジネス日報を書くアシスタントです。以下の素材をもとに、指定のテンプレート構成で本日の日報をMarkdownで書いてください。

        制約:
        - 素材にある事実だけを書く。推測や創作をしない
        - 簡潔なです・ます調
        - 出力はMarkdown本文のみ(前置き・後書き・コードブロック囲いは禁止)

        # 日付
        \(japaneseDateLabel(date, calendar: calendar))

        # テンプレート(この見出し構成に従う)
        \(template)

        # 素材: 本日のメモ(時刻順)
        \(noteLines)

        # 素材: 本日の予定
        \(eventLines)
        """
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 17 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add MeetingEvent and daily report PromptBuilder"
```

---

### Task 9: ReportService(素材→生成→写文件)

**Files:**
- Create: `Sources/NippoCore/Report/ReportService.swift`
- Create: `Sources/nippo-tests/ReportServiceTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runReportServiceTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/ReportServiceTests.swift`:

```swift
import Foundation
import NippoCore

private struct FakeGenerator: TextGenerator {
    var output = "# 生成された日報"
    func generate(prompt: String) throws -> String { output }
}

func runReportServiceTests() {
    func makeService(_ root: URL) throws -> (ReportService, NotesService) {
        let db = try AppDatabase.inMemory()
        let notes = NotesService(db: db, calendar: tokyoCalendar)
        let svc = ReportService(generator: FakeGenerator(), notes: notes,
                                reportsRoot: root, calendar: tokyoCalendar)
        return (svc, notes)
    }
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-report-\(UUID().uuidString)")
    }

    T.run("writes report file under yyyy/MM") {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (svc, notes) = try makeService(root)
        try notes.add("何かやった", at: tokyoDate(2026, 7, 10, 10, 0))
        let outcome = try svc.generateDaily(for: tokyoDate(2026, 7, 10, 17, 45),
                                            template: "T", events: [])
        guard case .written(let url) = outcome else {
            T.expect(false, "expected .written, got \(outcome)"); return
        }
        T.expect(url.path.hasSuffix("reports/2026/07/2026-07-10-日報.md"),
                 "path layout, got \(url.path)")
        T.expectEqual(try String(contentsOf: url, encoding: .utf8), "# 生成された日報")
    }

    T.run("no material -> skipped, no file") {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (svc, _) = try makeService(root)
        let outcome = try svc.generateDaily(for: tokyoDate(2026, 7, 10),
                                            template: "T", events: [])
        T.expect(outcome == .skippedNoMaterial, "expected skip")
        T.expect(!FileManager.default.fileExists(atPath: root.path), "no dir created")
    }

    T.run("existing file -> writes -v2 variant") {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (svc, notes) = try makeService(root)
        try notes.add("何かやった", at: tokyoDate(2026, 7, 10, 10, 0))
        _ = try svc.generateDaily(for: tokyoDate(2026, 7, 10), template: "T", events: [])
        let outcome2 = try svc.generateDaily(for: tokyoDate(2026, 7, 10), template: "T", events: [])
        guard case .written(let url2) = outcome2 else {
            T.expect(false, "expected .written"); return
        }
        T.expect(url2.lastPathComponent == "2026-07-10-日報-v2.md",
                 "v2 name, got \(url2.lastPathComponent)")
    }

    T.run("events alone count as material") {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (svc, _) = try makeService(root)
        let ev = MeetingEvent(id: "e", title: "MTG",
                              start: tokyoDate(2026, 7, 10, 10, 0),
                              end: tokyoDate(2026, 7, 10, 11, 0),
                              attendees: [], isAllDay: false)
        let outcome = try svc.generateDaily(for: tokyoDate(2026, 7, 10),
                                            template: "T", events: [ev])
        guard case .written = outcome else {
            T.expect(false, "expected .written"); return
        }
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'ReportService' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Report/ReportService.swift`:

```swift
import Foundation

public struct ReportService {
    public enum Outcome: Equatable {
        case written(URL)
        case skippedNoMaterial
    }

    let generator: TextGenerator
    let notes: NotesService
    let reportsRoot: URL
    let calendar: Calendar

    public init(generator: TextGenerator, notes: NotesService,
                reportsRoot: URL, calendar: Calendar = .current) {
        self.generator = generator
        self.notes = notes
        self.reportsRoot = reportsRoot
        self.calendar = calendar
    }

    public func generateDaily(for date: Date, template: String,
                              events: [MeetingEvent]) throws -> Outcome {
        let dayNotes = try notes.notes(on: date)
        guard !dayNotes.isEmpty || !events.isEmpty else { return .skippedNoMaterial }

        let prompt = PromptBuilder.dailyReport(date: date, template: template,
                                               notes: dayNotes, events: events,
                                               calendar: calendar)
        let body = try generator.generate(prompt: prompt)

        let c = calendar.dateComponents([.year, .month], from: date)
        let dir = reportsRoot
            .appendingPathComponent("reports")
            .appendingPathComponent(String(format: "%04d", c.year!))
            .appendingPathComponent(String(format: "%02d", c.month!))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let base = dir.appendingPathComponent(
            "\(DayKey.key(for: date, calendar: calendar))-日報.md")
        let url = Self.uniqueURL(for: base)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return .written(url)
    }

    /// 既存ファイルを上書きしない(ユーザー編集済みの可能性があるため)。-v2, -v3… を採番。
    static func uniqueURL(for base: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return base }
        let dir = base.deletingLastPathComponent()
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        var i = 2
        while true {
            let candidate = dir.appendingPathComponent("\(stem)-v\(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 21 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add ReportService with versioned markdown output"
```

---

### Task 10: 日历抽象 + MeetingReminderEngine

**Files:**
- Create: `Sources/NippoCore/Calendar/CalendarProviding.swift`
- Create: `Sources/NippoCore/Calendar/EventKitCalendar.swift`
- Create: `Sources/NippoCore/Calendar/MeetingReminderEngine.swift`
- Create: `Sources/nippo-tests/ReminderTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runReminderTests()`)

- [ ] **Step 1: 写失败测试**

EventKit 实体无法单元测试(需要 TCC 授权),所以只测纯逻辑 `MeetingReminderEngine`;EventKit 封装在 Task 14 手动验证。

`Sources/nippo-tests/ReminderTests.swift`:

```swift
import Foundation
import NippoCore

func runReminderTests() {
    func ev(_ id: String, startH: Int, startM: Int, allDay: Bool = false) -> MeetingEvent {
        MeetingEvent(id: id, title: "MTG-\(id)",
                     start: tokyoDate(2026, 7, 10, startH, startM),
                     end: tokyoDate(2026, 7, 10, startH + 1, startM),
                     attendees: [], isAllDay: allDay)
    }

    T.run("due within lead window, dedupes, skips all-day and started") {
        let engine = MeetingReminderEngine()
        let now = tokyoDate(2026, 7, 10, 9, 56)
        let events = [
            ev("soon", startH: 10, startM: 0),      // 4分後 → 対象
            ev("later", startH: 11, startM: 0),     // 64分後 → 対象外
            ev("started", startH: 9, startM: 30),   // 開始済み → 対象外
            ev("allday", startH: 10, startM: 0, allDay: true), // 終日 → 対象外
        ]
        let due = engine.dueReminders(events: events, now: now, leadMinutes: 5)
        T.expectEqual(due.map(\.id), ["soon"])
        // 同じ tick を繰り返しても再通知しない
        let again = engine.dueReminders(events: events, now: now, leadMinutes: 5)
        T.expectEqual(again.count, 0)
    }

    T.run("resetForNewDay clears dedupe set") {
        let engine = MeetingReminderEngine()
        let now = tokyoDate(2026, 7, 10, 9, 56)
        let events = [ev("soon", startH: 10, startM: 0)]
        _ = engine.dueReminders(events: events, now: now, leadMinutes: 5)
        engine.resetForNewDay()
        let due = engine.dueReminders(events: events, now: now, leadMinutes: 5)
        T.expectEqual(due.count, 1)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'MeetingReminderEngine' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Calendar/CalendarProviding.swift`:

```swift
import Foundation

public protocol CalendarProviding {
    /// 権限リクエスト。付与済みなら即 true。
    func requestAccess() async -> Bool
    func events(on day: Date) -> [MeetingEvent]
}
```

`Sources/NippoCore/Calendar/EventKitCalendar.swift`:

```swift
import Foundation
import EventKit

public final class EventKitCalendar: CalendarProviding {
    private let store = EKEventStore()
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func events(on day: Date) -> [MeetingEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                MeetingEvent(
                    id: e.eventIdentifier ?? UUID().uuidString,
                    title: e.title ?? "(無題)",
                    start: e.startDate,
                    end: e.endDate,
                    attendees: (e.attendees ?? []).compactMap(\.name),
                    isAllDay: e.isAllDay)
            }
    }
}
```

`Sources/NippoCore/Calendar/MeetingReminderEngine.swift`:

```swift
import Foundation

/// 「開始 lead 分前〜開始まで」の間に一度だけ通知対象として返す。
public final class MeetingReminderEngine {
    private var notifiedIDs: Set<String> = []

    public init() {}

    public func dueReminders(events: [MeetingEvent], now: Date,
                             leadMinutes: Int) -> [MeetingEvent] {
        let due = events.filter { e in
            !e.isAllDay
                && !notifiedIDs.contains(e.id)
                && e.start > now
                && e.start.timeIntervalSince(now) <= Double(leadMinutes * 60)
        }
        due.forEach { notifiedIDs.insert($0.id) }
        return due
    }

    public func resetForNewDay() {
        notifiedIDs.removeAll()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 23 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add calendar abstraction, EventKit impl, meeting reminder engine"
```

---

### Task 11: App 骨架(MenuBarExtra + AppCoordinator + 随手记 UI)

**Files:**
- Modify: `Sources/NippoApp/NippoApp.swift`(全文重写)
- Create: `Sources/NippoApp/AppCoordinator.swift`
- Create: `Sources/NippoApp/MenuContentView.swift`

本任务纯 UI 结线,无单元测试,以手动验证收尾。

- [ ] **Step 1: 写 AppCoordinator(本任务先支持随手记与手动生成;日历/通知/快捷键在 Task 13-14 接入)**

`Sources/NippoApp/AppCoordinator.swift`:

```swift
import Foundation
import AppKit
import NippoCore

@MainActor
final class AppCoordinator: ObservableObject {
    let settings = AppSettings()
    let db: AppDatabase
    let notesService: NotesService
    let quietDays: QuietDayChecker

    @Published var todayNotes: [Note] = []
    @Published var statusMessage: String?
    @Published var lastReportURL: URL?

    init() {
        let dbPath = (settings.reportsRoot as NSString)
            .appendingPathComponent("nippo.sqlite")
        do {
            db = try AppDatabase(path: dbPath)
        } catch {
            fatalError("DB 初期化失敗: \(error)")
        }
        notesService = NotesService(db: db)
        quietDays = QuietDayChecker(db: db)
        refreshNotes()
    }

    func refreshNotes() {
        todayNotes = (try? notesService.notes(on: Date())) ?? []
    }

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? notesService.add(trimmed)
        refreshNotes()
    }

    func updateNote(id: Int64, text: String) {
        try? notesService.update(id: id, text: text)
        refreshNotes()
    }

    func deleteNote(id: Int64) {
        try? notesService.delete(id: id)
        refreshNotes()
    }

    /// 手動生成(クワイエット日でも実行する)。Task 14 で予定連携を追加。
    func generateReport() {
        statusMessage = "日報を生成中…"
        let template = settings.reportTemplate
        let root = URL(fileURLWithPath: settings.reportsRoot)
        let customPath = settings.claudePath
        let notes = notesService

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<ReportService.Outcome, Error>
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                let svc = ReportService(generator: ClaudeCLI(executable: exe),
                                        notes: notes, reportsRoot: root)
                result = Result { try svc.generateDaily(for: Date(),
                                                        template: template,
                                                        events: []) }
            } else {
                result = .failure(ClaudeCLI.CLIError.exited(
                    code: -1, stderr: "claude CLI が見つかりません(設定でパスを指定)"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(.written(let url)):
                    self.statusMessage = "日報を保存しました"
                    self.lastReportURL = url
                case .success(.skippedNoMaterial):
                    self.statusMessage = "素材がないためスキップしました"
                case .failure(let error):
                    self.statusMessage = "エラー: \(error.localizedDescription)"
                }
            }
        }
    }
}
```

- [ ] **Step 2: 写 MenuContentView**

`Sources/NippoApp/MenuContentView.swift`:

```swift
import SwiftUI
import NippoCore

struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date(), format: .dateTime.year().month().day().weekday())
                .font(.headline)

            TextField("いまやったことをメモ…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    coordinator.addNote(draft)
                    draft = ""
                }

            Divider()

            if coordinator.todayNotes.isEmpty {
                Text("まだメモがありません")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.todayNotes) { note in
                            NoteRow(note: note, coordinator: coordinator)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            Button("日報を生成") { coordinator.generateReport() }
            if let message = coordinator.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let url = coordinator.lastReportURL {
                Button("日報を開く") { NSWorkspace.shared.open(url) }
            }

            Divider()

            SettingsLink { Text("設定…") }
            Button("終了") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { coordinator.refreshNotes() }
    }
}

private struct NoteRow: View {
    let note: Note
    @ObservedObject var coordinator: AppCoordinator
    @State private var text: String

    init(note: Note, coordinator: AppCoordinator) {
        self.note = note
        self.coordinator = coordinator
        _text = State(initialValue: note.text)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(note.createdAt, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .onSubmit { coordinator.updateNote(id: note.id!, text: text) }
            Button {
                coordinator.deleteNote(id: note.id!)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: 重写 NippoApp.swift**

```swift
import SwiftUI
import NippoCore

@main
struct NippoApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Nippo", systemImage: "doc.text") {
            MenuContentView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            // Task 15 で SettingsView に置き換える
            Text("設定は後のタスクで実装").padding(40)
        }
    }
}
```

- [ ] **Step 4: 构建 + 手动验证**

Run: `swift build && ./.build/debug/NippoApp`
手动检查清单(逐项确认):
1. 菜单栏出现文档图标,点击弹出面板
2. 输入框敲一条记录回车 → 出现在列表,时刻正确
3. 修改一条记录文本回车、点垃圾桶删除 → 均生效
4. 点「日報を生成」→ 状态先显示「生成中…」,数十秒后变为「保存しました」,点「日報を開く」能打开 `~/Documents/日報/reports/2026/…` 下的日语日报(此步骤调用真 claude,内容合理即可)
5. 「終了」能退出

Expected: 全部通过。Ctrl+C 或「終了」结束进程。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: menu bar app with quick notes and manual report generation"
```

---

### Task 12: App 打包(Info.plist + build-app.sh)

**Files:**
- Create: `Resources/Info.plist`
- Create: `build-app.sh`

之后所有涉及通知/日历/登录项的手动验证都用 `dist/Nippo.app`。

- [ ] **Step 1: 写 Info.plist**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>jp.michiteki.nippo</string>
    <key>CFBundleName</key>
    <string>Nippo</string>
    <key>CFBundleExecutable</key>
    <string>Nippo</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>本日の予定を日報に取り込み、会議前の通知を行うためにカレンダーへのアクセスが必要です。</string>
</dict>
</plist>
```

- [ ] **Step 2: 写 build-app.sh**

```bash
#!/bin/bash
# Nippo.app を dist/ に組み立てる(CLT のみ・Xcode 不要)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="dist/Nippo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NippoApp "$APP/Contents/MacOS/Nippo"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ad-hoc 署名。TCC 許可はバンドルIDに紐づくため再ビルド後も概ね保持されるが、
# 権限ダイアログが再出現したら再許可すること。
codesign --force -s - "$APP"

echo "Built: $APP"
```

Run: `chmod +x build-app.sh`

- [ ] **Step 3: 构建并手动验证**

Run: `./build-app.sh && open dist/Nippo.app`
手动检查清单:
1. 菜单栏出现 Nippo 图标,**Dock 中不出现**(LSUIElement 生效)
2. Task 11 的功能(记录/生成)在 .app 里同样工作
3. 活动监视器里进程名为 Nippo;从菜单「終了」退出

Expected: 全部通过

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "build: add app bundling script and Info.plist"
```

---

### Task 13: 全局快捷键 + 随手记悬浮窗

**Files:**
- Create: `Sources/NippoApp/QuickNotePanel.swift`
- Modify: `Sources/NippoApp/AppCoordinator.swift`

- [ ] **Step 1: 写悬浮窗**

`Sources/NippoApp/QuickNotePanel.swift`:

```swift
import AppKit
import SwiftUI

/// 非アクティブ化パネル:今のアプリからフォーカスを奪わずに入力できる。
final class QuickNotePanelController {
    private var panel: NSPanel?
    private let onSave: (String) -> Void

    init(onSave: @escaping (String) -> Void) {
        self.onSave = onSave
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    private func show() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 52),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: QuickNoteView(
            onSave: { [weak self] text in
                self?.onSave(text)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }))

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 210, y: f.maxY - 160))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func close() {
        panel?.close()
        panel = nil
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct QuickNoteView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("いまやったことをメモ… (Enterで保存 / Escで閉じる)", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .focused($focused)
            .onSubmit { onSave(text) }
            .onExitCommand { onCancel() }
            .padding(10)
            .onAppear { focused = true }
    }
}
```

- [ ] **Step 2: 在 AppCoordinator 接入 HotKey**

`Sources/NippoApp/AppCoordinator.swift` 顶部 import 区追加:

```swift
import HotKey
```

类内追加属性(放在 `@Published` 声明之后):

```swift
    private var hotKey: HotKey?
    private lazy var quickNotePanel = QuickNotePanelController { [weak self] text in
        self?.addNote(text)
    }
```

`init()` 末尾(`refreshNotes()` 之后)追加:

```swift
        hotKey = HotKey(key: .n, modifiers: [.command, .option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.quickNotePanel.toggle()
        }
```

- [ ] **Step 3: 构建并手动验证**

Run: `./build-app.sh && open dist/Nippo.app`
手动检查清单:
1. 在任意其他应用(如浏览器)前台时按 ⌥⌘N → 悬浮输入框出现在屏幕上方,焦点在输入框,**当前应用不失去激活状态**(菜单栏仍显示原应用名)
2. 输入文字回车 → 窗口关闭;打开菜单栏面板确认记录已保存
3. 再按 ⌥⌘N 打开后按 Esc → 关闭且不保存
4. 再次按 ⌥⌘N 两次 → 开、关(toggle 行为)

Expected: 全部通过

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: global hotkey quick note floating panel"
```

---

### Task 14: 通知 + 日历接入 + 定时日报/会议提醒

**Files:**
- Create: `Sources/NippoCore/Notifications/NotificationService.swift`
- Modify: `Sources/NippoApp/AppCoordinator.swift`

- [ ] **Step 1: 写 NotificationService**

`Sources/NippoCore/Notifications/NotificationService.swift`:

```swift
import Foundation
import UserNotifications

/// UNUserNotificationCenter は .app バンドル内でのみ動作する。
/// 裸バイナリ(swift run)ではクラッシュするため available ガード必須。
public final class NotificationService {
    public static let shared = NotificationService()

    public let available: Bool

    private init() {
        available = Bundle.main.bundleIdentifier != nil
    }

    public func requestPermission() {
        guard available else {
            print("[notify] skipped: not running from an app bundle")
            return
        }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func notify(title: String, body: String) {
        guard available else {
            print("[notify] \(title): \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: 扩充 AppCoordinator——日历、30 秒 tick、定时生成、会议提醒**

`Sources/NippoApp/AppCoordinator.swift` 修改如下。

import 区确认含有:

```swift
import Foundation
import AppKit
import NippoCore
import HotKey
```

类内属性区追加:

```swift
    let calendarProvider: CalendarProviding = EventKitCalendar()
    let reminderEngine = MeetingReminderEngine()
    private var timer: Timer?
    private var currentDayKey = DayKey.key(for: Date())
    @Published var calendarAuthorized = false
```

`init()` 末尾追加(hotKey 设置之后):

```swift
        NotificationService.shared.requestPermission()
        Task { [weak self] in
            let ok = await self?.calendarProvider.requestAccess() ?? false
            await MainActor.run { self?.calendarAuthorized = ok }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
```

类内追加方法:

```swift
    func tick() {
        let now = Date()

        // 日付が変わったらリセット
        let day = DayKey.key(for: now)
        if day != currentDayKey {
            currentDayKey = day
            reminderEngine.resetForNewDay()
            refreshNotes()
        }

        // クワイエット日(週末・祝日・休暇)は何もしない
        if (try? quietDays.isQuietDay(now)) ?? false { return }

        // 会議リマインド
        if calendarAuthorized {
            let events = calendarProvider.events(on: now)
            let due = reminderEngine.dueReminders(
                events: events, now: now,
                leadMinutes: settings.reminderLeadMinutes)
            for e in due {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                NotificationService.shared.notify(
                    title: "まもなく会議: \(e.title)",
                    body: "\(f.string(from: e.start)) 開始")
            }
        }

        // 日報の自動生成(1日1回)
        let (h, m) = settings.reportTimeComponents()
        if DailyTrigger.shouldFire(now: now, hour: h, minute: m,
                                   lastFiredDay: settings.lastReportFiredDay) {
            settings.lastReportFiredDay = DayKey.key(for: now)
            generateReport()
        }
    }
```

`generateReport()` 整体替换为(接入当天日程、生成后通知):

```swift
    func generateReport() {
        statusMessage = "日報を生成中…"
        let template = settings.reportTemplate
        let root = URL(fileURLWithPath: settings.reportsRoot)
        let customPath = settings.claudePath
        let notes = notesService
        let events = calendarAuthorized ? calendarProvider.events(on: Date()) : []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<ReportService.Outcome, Error>
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                let svc = ReportService(generator: ClaudeCLI(executable: exe),
                                        notes: notes, reportsRoot: root)
                result = Result { try svc.generateDaily(for: Date(),
                                                        template: template,
                                                        events: events) }
            } else {
                result = .failure(ClaudeCLI.CLIError.exited(
                    code: -1, stderr: "claude CLI が見つかりません(設定でパスを指定)"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(.written(let url)):
                    self.statusMessage = "日報を保存しました"
                    self.lastReportURL = url
                    NotificationService.shared.notify(
                        title: "日報ドラフト完成",
                        body: "レビューして提出してください: \(url.lastPathComponent)")
                case .success(.skippedNoMaterial):
                    self.statusMessage = "素材がないためスキップしました"
                    NotificationService.shared.notify(
                        title: "日報をスキップしました",
                        body: "本日の素材(メモ・予定)がありません")
                case .failure(let error):
                    self.statusMessage = "エラー: \(error.localizedDescription)"
                    NotificationService.shared.notify(
                        title: "日報生成に失敗",
                        body: error.localizedDescription)
                }
            }
        }
    }
```

- [ ] **Step 3: 跑既有测试防回归 + 构建**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 23 tests`,构建成功

- [ ] **Step 4: 手动验证(用 dist/Nippo.app)**

Run: `open dist/Nippo.app`
手动检查清单:
1. 首次启动弹「通知を送信」授权 → 允许;弹「カレンダーへのフルアクセス」授权(文案为 Info.plist 里的日语说明)→ 允许
2. 在日历 App 里建一个 3 分钟后开始的测试日程 → 等到提前量窗口内(默认 5 分钟)收到「まもなく会議」通知;同一日程不重复通知
3. 先退出 app,然后执行 `defaults delete jp.michiteki.nippo lastReportFiredDay`(清掉当日已触发标记——如果现在已过默认的 17:45,启动后首个 tick 的追赶发火会先消耗掉当天名额,导致本测试永远等不到通知),再 `defaults write jp.michiteki.nippo reportTime "HH:mm"`(替换为当前时间+2 分钟),重新 `open dist/Nippo.app` → 到点收到「日報ドラフト完成」通知,文件生成
4. `defaults delete jp.michiteki.nippo lastReportFiredDay && defaults write jp.michiteki.nippo reportTime "17:45"` 恢复设置

Expected: 全部通过。注意:今天若是周末/节假日,tick 会静默——测试时临时把系统日期无关的静默逻辑考虑进去(工作日测试,或暂时在日历里不设休假)。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: notifications, calendar integration, scheduled report and meeting reminders"
```

---

### Task 15: 设置界面 + 登录自启

**Files:**
- Create: `Sources/NippoApp/SettingsView.swift`
- Modify: `Sources/NippoApp/NippoApp.swift`(Settings scene 换成 SettingsView)

- [ ] **Step 1: 写 SettingsView**

`Sources/NippoApp/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement
import NippoCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var newVacation = Date()
    @State private var vacations: [String] = []

    var body: some View {
        Form {
            Section("日報") {
                TextField("生成時刻 (HH:mm)", text: binding(\.reportTime))
                TextField("保存先フォルダ", text: binding(\.reportsRoot))
                VStack(alignment: .leading) {
                    Text("テンプレート")
                    TextEditor(text: binding(\.reportTemplate))
                        .font(.body.monospaced())
                        .frame(height: 120)
                }
            }

            Section("会議リマインド") {
                Stepper("開始 \(settings.reminderLeadMinutes) 分前に通知",
                        value: binding(\.reminderLeadMinutes), in: 1...30)
            }

            Section("Claude CLI") {
                TextField("パス(空なら自動検出)", text: binding(\.claudePath))
            }

            Section("休暇日(打刻・日報を停止)") {
                HStack {
                    DatePicker("追加", selection: $newVacation, displayedComponents: .date)
                    Button("追加") {
                        try? coordinator.quietDays.addVacation(DayKey.key(for: newVacation))
                        reloadVacations()
                    }
                }
                ForEach(vacations, id: \.self) { day in
                    HStack {
                        Text(day)
                        Spacer()
                        Button("削除") {
                            try? coordinator.quietDays.removeVacation(day)
                            reloadVacations()
                        }
                    }
                }
            }

            Section("一般") {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onAppear { reloadVacations() }
    }

    private func reloadVacations() {
        vacations = (try? coordinator.quietDays.vacations()) ?? []
    }

    private func binding<V>(_ keyPath: ReferenceWritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { settings[keyPath: keyPath] = $0 })
    }
}
```

- [ ] **Step 2: 接入 Settings scene**

`Sources/NippoApp/NippoApp.swift` 中 `Settings { ... }` 整体替换为:

```swift
        Settings {
            SettingsView(coordinator: coordinator, settings: coordinator.settings)
        }
```

- [ ] **Step 3: 构建并手动验证**

Run: `swift run nippo-tests && ./build-app.sh && open dist/Nippo.app`
手动检查清单:
1. 菜单面板点「設定…」→ 设置窗口打开,各字段显示当前值
2. 改生成时刻为 `18:00` → 重开设置窗口仍是 `18:00`(持久化);改回 `17:45`
3. 模板里加一行文字,点「日報を生成」→ 生成物遵循新模板结构
4. 添加一个明天的休暇日 → 列表出现;删除 → 消失
5. 打开「ログイン時に起動」→ 系统设置 > 一般 > ログイン項目 里出现 Nippo;关掉 → 消失
   (注意:dist/ 下的 .app 每次重建路径不变,SMAppService 才能稳定;若登录项失效,重新开关一次)

Expected: 全部通过

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: settings window with template, times, vacations, login item"
```

---

### Task 16: README + 端到端验收

**Files:**
- Create: `README.md`

- [ ] **Step 1: 写 README**

`README.md`:

````markdown
# Nippo

日本語の日報・週振り返り・月発表ドラフトを自動生成し、バクラク勤怠の打刻を
半自動化する macOS メニューバーアプリ(個人用)。

## 現在のフェーズ

フェーズ1(メモ・カレンダー連携・日報生成)実装済み。
仕様: docs/superpowers/specs/2026-07-10-nippo-work-assistant-design.md

## ビルドと起動

```bash
./build-app.sh        # dist/Nippo.app を生成(要: CLT、Xcode 不要)
open dist/Nippo.app
```

初回起動時に通知とカレンダーの権限を許可すること。

## 使い方

- ⌥⌘N: どこからでもメモ入力(Enter 保存 / Esc 閉じる)
- メニューバーアイコン: 当日のメモ一覧・編集・日報の手動生成
- 平日 17:45(設定可)に日報ドラフトを自動生成 →
  `~/Documents/日報/reports/YYYY/MM/YYYY-MM-DD-日報.md`
- 会議の 5 分前(設定可)に通知
- 週末・日本の祝日・登録した休暇日は自動的に静かになる

## 開発

```bash
swift run nippo-tests   # テスト(CLT に XCTest が無いため自製ランナー)
swift build             # コンパイル確認
```

祝日データ: `Sources/NippoCore/Schedule/QuietDayChecker.swift` の
`jpHolidays` に年ごとに追記する。
````

- [ ] **Step 2: 端到端验收清单(手动)**

Run: `swift run nippo-tests && ./build-app.sh && open dist/Nippo.app`
验收清单(模拟一天的使用):
1. ⌥⌘N 记 2-3 条真实工作记录
2. 日历确认今天有 1 个以上日程(没有就建一个)
3. 菜单点「日報を生成」→ 打开生成的日报:结构符合模板、内容只含素材事实、日语自然
4. 生成第二次 → 产生 `-v2` 文件,原文件未被覆盖
5. `swift run nippo-tests` 全绿
6. `git status` 干净(所有变更已提交)

Expected: 全部通过

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs: add README with build and usage instructions"
```

---

## 后续(不在本计划内)

- **快捷键自定义**:规格 §5.1 的「⌥⌘N,可改」中的「可改」有意顺延——第一期固定为 ⌥⌘N(快捷键录制控件成本高;后续需要时加:AppSettings 持久化 keyCode/modifiers + 设置界面录制控件 + AppCoordinator 重注册)
- 第二期:バクラク勤怠打刻(WebView 会话 + 一键打刻 + 漏打检知)
- 第三期:会议录音 → SpeechAnalyzer/WhisperKit 转写 → 纪要
- 第四期:週振り返り・月発表・全文搜索
- 装上 Xcode 后:把 nippo-tests 迁移到 XCTest/Swift Testing(Self Service.app 里找 Xcode)
