# 今日のチェックリスト 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 工作日早上(默认 09:00,追赶式)自动从「昨日日报(尤其 04 ／ 明日)+ 今天的会议 + 上次未完成项」生成 3〜7 条当日待办,通知提醒;菜单里可勾选/添加/删除;勾选状态作为当日日报素材(完了=事实,未完了=明日候补)。

**Architecture:** DB 迁移 v2 加 `checklist_item` 表;`ChecklistService`(CRUD+前日未完了继承)与 `ChecklistBuilder`(prompt/解析/昨日日报定位)进 NippoCore(TDD);`PromptBuilder.factsSection` 与 `ReportService.generateDaily` 加带默认值的 checklist 参数(不破坏既有调用);AppCoordinator 加第二个 DailyTrigger 与编排;菜单加「今日のやること」区块。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(当前 41 tests 全绿);仓库 `/Users/lease-emp-mac-yudi-shi/Desktop/杂/nippo` 分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证项跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。**修改文件前先 Read 当前内容再 Edit**——多处文件与计划书写时相比可能有微小演进,以「锚点行」定位而非盲目全文替换;若锚点找不到,报 BLOCKED 而不是猜。

---

### Task 1: DB v2 + ChecklistItem + ChecklistService

**Files:**
- Modify: `Sources/NippoCore/Database/AppDatabase.swift`(migrator 里追加 v2)
- Create: `Sources/NippoCore/Checklist/ChecklistItem.swift`
- Create: `Sources/NippoCore/Checklist/ChecklistService.swift`
- Create: `Sources/nippo-tests/ChecklistTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(`runNextEventTests()` 后追加 `runChecklistTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/ChecklistTests.swift`:

```swift
import Foundation
import NippoCore

func runChecklistTests() {
    T.run("checklist crud and ordering") {
        let db = try AppDatabase.inMemory()
        let svc = ChecklistService(db: db)
        try svc.add(day: "2026-07-10", text: "資料を仕上げる", source: "ai", sortOrder: 1)
        let first = try svc.add(day: "2026-07-10", text: "レビュー依頼", source: "ai", sortOrder: 0)
        try svc.add(day: "2026-07-09", text: "別の日", source: "manual", sortOrder: 0)

        var items = try svc.items(on: "2026-07-10")
        T.expectEqual(items.count, 2)
        T.expectEqual(items[0].text, "レビュー依頼")   // sortOrder 順
        T.expectEqual(items[0].done, false)

        try svc.setDone(id: first.id!, done: true)
        items = try svc.items(on: "2026-07-10")
        T.expectEqual(items[0].done, true)

        try svc.delete(id: first.id!)
        T.expectEqual(try svc.items(on: "2026-07-10").count, 1)
    }

    T.run("carryover returns undone items from the most recent previous day") {
        let db = try AppDatabase.inMemory()
        let svc = ChecklistService(db: db)
        let old = try svc.add(day: "2026-07-08", text: "古い未完了", source: "ai")
        _ = old
        let done = try svc.add(day: "2026-07-09", text: "完了済み", source: "ai")
        try svc.setDone(id: done.id!, done: true)
        try svc.add(day: "2026-07-09", text: "昨日の未完了", source: "ai")

        let carry = try svc.carryover(before: "2026-07-10")
        // 直近の日(07-09)の未完了のみ。07-08 は対象外
        T.expectEqual(carry.map(\.text), ["昨日の未完了"])
        T.expectEqual(try svc.carryover(before: "2026-07-08").count, 0)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'ChecklistService' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Checklist/ChecklistItem.swift`:

```swift
import Foundation
import GRDB

public struct ChecklistItem: Codable, Equatable, Identifiable,
                             FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "checklist_item"

    public var id: Int64?
    public var day: String        // "yyyy-MM-dd"
    public var text: String
    public var done: Bool
    public var sortOrder: Int
    public var source: String     // "ai" | "manual"

    public init(id: Int64? = nil, day: String, text: String,
                done: Bool = false, sortOrder: Int = 0, source: String = "manual") {
        self.id = id
        self.day = day
        self.text = text
        self.done = done
        self.sortOrder = sortOrder
        self.source = source
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

`Sources/NippoCore/Checklist/ChecklistService.swift`:

```swift
import Foundation
import GRDB

public struct ChecklistService {
    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func items(on day: String) throws -> [ChecklistItem] {
        try db.dbQueue.read {
            try ChecklistItem
                .filter(Column("day") == day)
                .order(Column("sortOrder"), Column("id"))
                .fetchAll($0)
        }
    }

    @discardableResult
    public func add(day: String, text: String, source: String = "manual",
                    sortOrder: Int = 0) throws -> ChecklistItem {
        var item = ChecklistItem(day: day, text: text, sortOrder: sortOrder, source: source)
        try db.dbQueue.write { try item.insert($0) }
        return item
    }

    public func setDone(id: Int64, done: Bool) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "UPDATE checklist_item SET done = ? WHERE id = ?",
                           arguments: [done, id])
        }
    }

    public func delete(id: Int64) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "DELETE FROM checklist_item WHERE id = ?", arguments: [id])
        }
    }

    /// 直近の過去日(リストが存在する最新の day < before)の未完了項目
    public func carryover(before day: String) throws -> [ChecklistItem] {
        try db.dbQueue.read { dbc in
            guard let latest = try String.fetchOne(
                dbc, sql: "SELECT MAX(day) FROM checklist_item WHERE day < ?",
                arguments: [day]) else { return [] }
            return try ChecklistItem
                .filter(Column("day") == latest && Column("done") == false)
                .order(Column("sortOrder"), Column("id"))
                .fetchAll(dbc)
        }
    }
}
```

`AppDatabase.swift` 的 migrator(`registerMigration("v1")` 块之后、`return m` 之前)追加:

```swift
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 43 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: checklist storage (db v2, ChecklistService with carryover)"
```

---

### Task 2: ChecklistBuilder(prompt / 解析 / 昨日日报定位)

**Files:**
- Create: `Sources/NippoCore/Checklist/ChecklistBuilder.swift`
- Modify: `Sources/NippoCore/Report/ReportService.swift`(抽出 `baseReportURL` 静态方法并在 generateDaily 内使用)
- Create: `Sources/nippo-tests/ChecklistBuilderTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runChecklistBuilderTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/ChecklistBuilderTests.swift`:

```swift
import Foundation
import NippoCore

func runChecklistBuilderTests() {
    T.run("prompt embeds report, events, carryover and constraints") {
        let ev = MeetingEvent(id: "e", title: "定例MTG",
                              start: tokyoDate(2026, 7, 10, 10, 0),
                              end: tokyoDate(2026, 7, 10, 11, 0),
                              attendees: [], isAllDay: false)
        let p = ChecklistBuilder.prompt(
            date: tokyoDate(2026, 7, 10),
            yesterdayReport: "## 04 ／ 明日\n- バナーを仕上げる",
            events: [ev], carryover: ["レビュー依頼を出す"],
            calendar: tokyoCalendar)
        T.expect(p.contains("バナーを仕上げる"), "yesterday report embedded")
        T.expect(p.contains("定例MTG"), "events embedded")
        T.expect(p.contains("レビュー依頼を出す"), "carryover embedded")
        T.expect(p.contains("素材にない"), "no-invention constraint")
        T.expect(p.contains("「- 」で始まる行のみ"), "output format")
    }

    T.run("parseItems keeps dash lines, trims, dedupes, caps at 7") {
        let out = """
        前置きテキスト
        - 項目1
        - 項目2
        -  項目2
        - 項目3
        - 項目4
        - 項目5
        - 項目6
        - 項目7
        - 項目8
        """
        let items = ChecklistBuilder.parseItems(out)
        T.expectEqual(items.count, 7)
        T.expectEqual(items[0], "項目1")
        T.expectEqual(items.filter { $0 == "項目2" }.count, 1)
    }

    T.run("latestReport finds the newest base report within lookback") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-cl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let day8 = ReportService.baseReportURL(root: root,
                                               for: tokyoDate(2026, 7, 8),
                                               calendar: tokyoCalendar)
        try FileManager.default.createDirectory(
            at: day8.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "8日の日報".write(to: day8, atomically: true, encoding: .utf8)

        let found = ChecklistBuilder.latestReport(root: root,
                                                  before: tokyoDate(2026, 7, 10),
                                                  calendar: tokyoCalendar)
        T.expectEqual(found, "8日の日報")   // 7/9 が無ければ 7/8 に遡る
        T.expectEqual(ChecklistBuilder.latestReport(root: root,
                                                    before: tokyoDate(2026, 7, 8),
                                                    calendar: tokyoCalendar), nil)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'ChecklistBuilder' in scope`

- [ ] **Step 3: 写实现**

先在 `ReportService.swift` 中抽出路径方法:在 `uniqueURL` 方法之前追加:

```swift
    /// 当日の基準レポートパス: <root>/reports/YYYY/MM/YYYY-MM-DD-日報.md(-v2 等は含まない)
    public static func baseReportURL(root: URL, for date: Date,
                                     calendar: Calendar = .current) -> URL {
        let c = calendar.dateComponents([.year, .month], from: date)
        return root
            .appendingPathComponent("reports")
            .appendingPathComponent(String(format: "%04d", c.year!))
            .appendingPathComponent(String(format: "%02d", c.month!))
            .appendingPathComponent("\(DayKey.key(for: date, calendar: calendar))-日報.md")
    }
```

并把 `generateDaily` 内构建 `dir`/`base` 的四行(从 `let c = calendar.dateComponents...` 到 `let base = dir.appendingPathComponent(...)`)替换为:

```swift
        let base = Self.baseReportURL(root: reportsRoot, for: date, calendar: calendar)
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
```

`Sources/NippoCore/Checklist/ChecklistBuilder.swift`:

```swift
import Foundation

/// 「今日のやること」生成:素材の組み立てと出力の解析。
public enum ChecklistBuilder {
    public static func prompt(date: Date, yesterdayReport: String?,
                              events: [MeetingEvent], carryover: [String],
                              calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd(EEE)"

        let eventLines = events.isEmpty
            ? "(予定なし)"
            : events.filter { !$0.isAllDay }
                .map { e -> String in
                    let c = calendar.dateComponents([.hour, .minute], from: e.start)
                    return String(format: "- %02d:%02d %@", c.hour!, c.minute!, e.title)
                }.joined(separator: "\n")

        let carryLines = carryover.isEmpty
            ? "(なし)"
            : carryover.map { "- \($0)" }.joined(separator: "\n")

        return """
        あなたは仕事のプランニングアシスタント。以下の素材から、今日やるべきことのチェックリストを 3〜7 件作る。

        制約:
        - 素材にないタスクを発明しない
        - 昨日の日報の「04 ／ 明日」を最優先で反映する
        - 前回の未完了はそのまま(または文言を整えて)含める
        - 会議への出席自体は項目にしない(準備・フォローが素材から読み取れる場合のみ項目化)
        - 各項目は簡潔な日本語の行動文(〜する)
        - 出力は「- 」で始まる行のみ。前置き・後書き禁止

        # 今日
        \(f.string(from: date))

        # 素材: 昨日の日報
        \(yesterdayReport ?? "(なし)")

        # 素材: 今日の予定
        \(eventLines)

        # 素材: 前回の未完了
        \(carryLines)
        """
    }

    /// 「- 」行のみ抽出、トリム、重複除去、最大 max 件
    public static func parseItems(_ output: String, max: Int = 7) -> [String] {
        var seen = Set<String>()
        var items: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            let text = String(trimmed.dropFirst(2))
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !seen.contains(text) else { continue }
            seen.insert(text)
            items.append(text)
            if items.count >= max { break }
        }
        return items
    }

    /// before より前の直近 lookback 日以内で、存在する最初の基準日報を読む
    public static func latestReport(root: URL, before date: Date,
                                    calendar: Calendar = .current,
                                    maxLookbackDays: Int = 7) -> String? {
        for delta in 1...maxLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -delta, to: date)
            else { continue }
            let url = ReportService.baseReportURL(root: root, for: day, calendar: calendar)
            if let text = try? String(contentsOf: url, encoding: .utf8),
               !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 46 tests`(既有 41 + Task1 的 2 + 本任务 3)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ChecklistBuilder prompt/parse and report path extraction"
```

---

### Task 3: 日报素材接入 checklist(带默认值,不破坏既有调用)

**Files:**
- Modify: `Sources/NippoCore/Report/PromptBuilder.swift`(factsSection 签名扩展)
- Modify: `Sources/NippoCore/Report/ReportService.swift`(generateDaily 签名扩展并透传)
- Modify: `Sources/nippo-tests/PromptBuilderTests.swift`(追加断言)

- [ ] **Step 1: 写失败测试**

`PromptBuilderTests.swift` 的「factsSection contains date, notes and events」测试末尾追加:

```swift
        let withChecklist = PromptBuilder.factsSection(
            date: tokyoDate(2026, 7, 10, 17, 45),
            notes: notes, events: events,
            checklistDone: ["レビュー依頼を出した"],
            checklistOpen: ["バナー最終調整"],
            calendar: tokyoCalendar)
        T.expect(withChecklist.contains("チェックリスト(完了)"), "done block")
        T.expect(withChecklist.contains("レビュー依頼を出した"), "done item")
        T.expect(withChecklist.contains("未完了"), "open block")
        T.expect(withChecklist.contains("バナー最終調整"), "open item")
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `extra arguments at positions ... in call`(factsSection 尚无该参数)

- [ ] **Step 3: 实现**

`PromptBuilder.factsSection` 签名改为:

```swift
    public static func factsSection(date: Date, notes: [Note], events: [MeetingEvent],
                                    checklistDone: [String] = [],
                                    checklistOpen: [String] = [],
                                    calendar: Calendar = .current) -> String {
```

并在方法内 `return` 的字符串末尾(`\(eventLines)` 之后)追加两个块:

```swift
        let doneLines = checklistDone.isEmpty
            ? "(なし)"
            : checklistDone.map { "- \($0)" }.joined(separator: "\n")
        let openLines = checklistOpen.isEmpty
            ? "(なし)"
            : checklistOpen.map { "- \($0)" }.joined(separator: "\n")
```

return 字符串末尾追加:

```
        ## 本日のチェックリスト(完了)
        \(doneLines)

        ## 本日のチェックリスト(未完了 → 「04 ／ 明日」の候補)
        \(openLines)
```

`ReportService.generateDaily` 签名改为(checklist 参数带默认值,progress 保持最后):

```swift
    public func generateDaily(for date: Date, template: String,
                              events: [MeetingEvent],
                              checklistDone: [String] = [],
                              checklistOpen: [String] = [],
                              progress: ((String) -> Void)? = nil) throws -> Outcome {
```

素材判定行改为(有完成项也算有素材):

```swift
        guard !dayNotes.isEmpty || !events.isEmpty || !checklistDone.isEmpty
        else { return .skippedNoMaterial }
```

`facts` 构建行改为透传:

```swift
        let facts = PromptBuilder.factsSection(date: date, notes: dayNotes,
                                               events: events,
                                               checklistDone: checklistDone,
                                               checklistOpen: checklistOpen,
                                               calendar: calendar)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 46 tests`(断言增加,测试数不变)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: checklist state feeds daily report facts"
```

---

### Task 4: 设置项(checklistEnabled / checklistTime / lastChecklistDay)

**Files:**
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`
- Modify: `Sources/nippo-tests/SettingsTests.swift`

- [ ] **Step 1: 写失败测试**

「defaults and roundtrip」测试末尾(assistantTone 断言之后)追加:

```swift
        T.expectEqual(s.checklistEnabled, true)
        T.expectEqual(s.checklistTime, "09:00")
        T.expectEqual(s.lastChecklistDay, nil)
        s.checklistEnabled = false
        s.checklistTime = "08:30"
        s.lastChecklistDay = "2026-07-10"
        let s3 = AppSettings(defaults: d)
        T.expectEqual(s3.checklistEnabled, false)
        T.expectEqual(s3.checklistTime, "08:30")
        T.expectEqual(s3.lastChecklistDay, "2026-07-10")
        var ct = s3.checklistTimeComponents()
        T.expectEqual(ct.hour, 8); T.expectEqual(ct.minute, 30)
        s.checklistTime = "junk"
        ct = s.checklistTimeComponents()
        T.expectEqual(ct.hour, 9); T.expectEqual(ct.minute, 0)
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `has no member 'checklistEnabled'`

- [ ] **Step 3: 实现**

`AppSettings.swift` 中 `assistantTone` 属性之后追加:

```swift
    public var checklistEnabled: Bool {
        get { d.object(forKey: "checklistEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "checklistEnabled"); objectWillChange.send() }
    }

    public var checklistTime: String {   // "HH:mm"
        get { d.string(forKey: "checklistTime") ?? "09:00" }
        set { d.set(newValue, forKey: "checklistTime"); objectWillChange.send() }
    }

    public var lastChecklistDay: String? {   // "yyyy-MM-dd"
        get { d.string(forKey: "lastChecklistDay") }
        set { d.set(newValue, forKey: "lastChecklistDay"); objectWillChange.send() }
    }

    public func checklistTimeComponents() -> (hour: Int, minute: Int) {
        let parts = checklistTime.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return (h, m)
        }
        return (9, 0)
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 46 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: checklist settings"
```

---

### Task 5: AppCoordinator 编排(生成触发 + CRUD + 日报接入)

**Files:**
- Modify: `Sources/NippoApp/AppCoordinator.swift`

**注意:先 Read 当前文件。** 该文件近期演进频繁(已含 statusBarTitle、runJapaneseAssistant 等),以下改动以锚点定位。

- [ ] **Step 1: 属性与服务**

`quietDays` 声明行(`let quietDays: QuietDayChecker`)之后追加:

```swift
    let checklistService: ChecklistService
```

`@Published var todayNotes` 行之后追加:

```swift
    @Published var todayChecklist: [ChecklistItem] = []
```

类属性区(`assistantBusy` 之后)追加:

```swift
    private var checklistGenerating = false
```

`init()` 中 `quietDays = QuietDayChecker(db: db)` 之后追加:

```swift
        checklistService = ChecklistService(db: db)
```

`refreshNotes()` 调用处(init 内)之后追加一行:

```swift
        refreshChecklist()
```

- [ ] **Step 2: CRUD 与刷新方法**

`refreshTodayEvents()` 方法之后追加:

```swift
    func refreshChecklist() {
        todayChecklist = (try? checklistService.items(on: DayKey.key(for: Date()))) ?? []
    }

    func addChecklistItem(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let order = (todayChecklist.map(\.sortOrder).max() ?? -1) + 1
        try? checklistService.add(day: DayKey.key(for: Date()), text: trimmed,
                                  source: "manual", sortOrder: order)
        refreshChecklist()
    }

    func toggleChecklistItem(_ item: ChecklistItem) {
        guard let id = item.id else { return }
        try? checklistService.setDone(id: id, done: !item.done)
        refreshChecklist()
    }

    func deleteChecklistItem(_ item: ChecklistItem) {
        guard let id = item.id else { return }
        try? checklistService.delete(id: id)
        refreshChecklist()
    }
```

- [ ] **Step 3: 生成方法与 tick 触发**

上述方法之后追加:

```swift
    /// 朝のチェックリスト生成(1日1回、追いつき発火)
    func generateChecklist() {
        guard !checklistGenerating else { return }
        checklistGenerating = true
        let today = DayKey.key(for: Date())
        let yesterdayReport = ChecklistBuilder.latestReport(
            root: URL(fileURLWithPath: settings.reportsRoot), before: Date())
        let carryItems = (try? checklistService.carryover(before: today)) ?? []
        let prompt = ChecklistBuilder.prompt(
            date: Date(), yesterdayReport: yesterdayReport,
            events: todayEvents, carryover: carryItems.map(\.text))
        let customPath = settings.claudePath

        Task { @MainActor in
            defer { checklistGenerating = false }
            let output: String? = await Task.detached(priority: .utility) {
                guard let exe = ClaudeCLI.detect(customPath: customPath) else { return nil }
                var cli = ClaudeCLI(executable: exe)
                cli.timeout = 120
                return try? cli.generate(prompt: prompt)
            }.value

            guard let output else {
                NotificationService.shared.notify(
                    title: "チェックリスト生成に失敗",
                    body: "claude CLI の実行に失敗しました")
                return
            }
            let items = ChecklistBuilder.parseItems(output)
            guard !items.isEmpty else { return }
            for (i, text) in items.enumerated() {
                try? checklistService.add(day: today, text: text,
                                          source: "ai", sortOrder: i)
            }
            refreshChecklist()
            NotificationService.shared.notify(
                title: "今日のチェックリストができました",
                body: items.prefix(3).joined(separator: " / ")
                    + (items.count > 3 ? " ほか\(items.count - 3)件" : ""))
        }
    }
```

`tick()` 里日报触发块(`generateReport()` 调用所在 if 块)之后追加:

```swift
        // 朝のチェックリスト(1日1回、既にリストがある日は生成しない)
        if settings.checklistEnabled {
            let (ch, cm) = settings.checklistTimeComponents()
            if DailyTrigger.shouldFire(now: now, hour: ch, minute: cm,
                                       lastFiredDay: settings.lastChecklistDay) {
                settings.lastChecklistDay = DayKey.key(for: now)
                if todayChecklist.isEmpty {
                    generateChecklist()
                }
            }
        }
```

`tick()` 的日期变更块(`refreshNotes()` 调用处)追加一行 `refreshChecklist()`。

- [ ] **Step 4: 日报生成接入勾选状态**

`generateReport()` 中 `let events = ...` 行之后追加:

```swift
        let checklistDone = todayChecklist.filter(\.done).map(\.text)
        let checklistOpen = todayChecklist.filter { !$0.done }.map(\.text)
```

`try svc.generateDaily(for: Date(), template: template, events: events, progress: ...)` 调用改为:

```swift
                    try svc.generateDaily(for: Date(), template: template,
                                          events: events,
                                          checklistDone: checklistDone,
                                          checklistOpen: checklistOpen,
                                          progress: { stage in
```

(progress 闭包体保持不变)

- [ ] **Step 5: 测试 + 构建 + Commit**

Run: `swift run nippo-tests && swift build --target NippoApp`
Expected: `PASS: 46 tests`,编译通过

```bash
git add -A && git commit -m "feat: morning checklist generation wired into coordinator and report"
```

---

### Task 6: 菜单 UI(今日のやること)+ 设置界面

**Files:**
- Modify: `Sources/NippoApp/MenuContentView.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

**先 Read 两个文件再改。**

- [ ] **Step 1: MenuContentView 追加区块**

在「今日の会議」区块(整个 `if !coordinator.todayEvents.isEmpty { ... }`)之后、memo `TextField` 之前插入:

```swift
            Text("今日のやること")
                .font(.caption)
                .foregroundStyle(.secondary)
            if coordinator.todayChecklist.isEmpty {
                Text("まだありません(朝 9:00 に自動生成/下で追加)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.todayChecklist) { item in
                    ChecklistRow(item: item, coordinator: coordinator)
                }
            }
            TextField("やることを追加…", text: $checklistDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    coordinator.addChecklistItem(checklistDraft)
                    checklistDraft = ""
                }

            Divider()
```

`@State private var draft = ""` 之后追加:

```swift
    @State private var checklistDraft = ""
```

文件末尾(NoteRow 之前或之后均可)追加:

```swift
private struct ChecklistRow: View {
    let item: ChecklistItem
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 6) {
            Button {
                coordinator.toggleChecklistItem(item)
            } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            Text(item.text)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Button {
                coordinator.deleteChecklistItem(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: SettingsView 追加区块**

「日本語アシスタント」Section 之前插入:

```swift
            Section("今日のチェックリスト") {
                Toggle("朝に自動生成する", isOn: binding(\.checklistEnabled))
                TextField("生成時刻 (HH:mm)", text: binding(\.checklistTime))
            }
```

- [ ] **Step 3: 测试 + 打包 + Commit**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 46 tests`,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: checklist menu section and settings"
```

- [ ] **Step 4: 手动验证清单(跳过并汇报)**

1. 菜单出现「今日のやること」区块,可添加/勾选(划线)/删除,重开菜单状态保持
2. 设置里关掉「朝に自動生成」→ 次日不自动生成;改时刻生效
3. 明天早上 09:00 后首个 tick 弹「今日のチェックリストができました」,内容来自今天日报的「04 ／ 明日」与未完了项
4. 勾选若干项后点「日報を生成」→ 生成的日报把完了项写进事实、未完了项出现在「04 ／ 明日」候补

---

### Task 7: README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「使い方」列表 ⌥⌘P 行后追加**

```markdown
- 平日 9:00(設定可)に「今日のチェックリスト」を自動生成(昨日の日報の
  「明日」+ 今日の予定 + 未完了の繰り越し)。メニューでチェックでき、
  完了/未完了はその日の日報素材になる
```

- [ ] **Step 2: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 46 tests`

```bash
git add -A && git commit -m "docs: daily checklist usage"
```

---

## 后续(不在本计划内)

- 三期后:纪要 TODO 自动进当日/次日チェックリスト
- 截图自动整理、1on1 助手(队列中的下两项,另立计划)
