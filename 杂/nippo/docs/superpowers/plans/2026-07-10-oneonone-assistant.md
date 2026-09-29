# 1on1 助手 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日程标题含「1on1」(不区分大小写)的会议:**会前 30 分钟**(可改)自动生成 talking points(本周日报+当天记录+未完了+上次 1on1 文件+目标)存 `~/Documents/日報/1on1/`,通知点击直接打开;**会议结束 5 分钟后**弹「1on1 で言われたことをメモしましょう」,点击打开随手记悬浮窗(预填「1on1: 」),记录自然成为当天日报的「学び」素材。

**Architecture:** `OneOnOneEngine`(纯逻辑:pre/post 判定与去重,TDD)+ `OneOnOnePrep`(素材组装/prompt/写文件,TDD)进 NippoCore;coordinator 在 tick 接线,QuickNotePanelController 加预填参数。生成走既有 ClaudeCLI(禁网)。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(打刻门禁合入后应为 **71 tests**;不同则顺延 Expected 并在 concerns 说明);分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**,锚点找不到报 BLOCKED。

---

### Task 1: OneOnOneEngine(会前/会后判定)

**Files:**
- Create: `Sources/NippoCore/OneOnOne/OneOnOneEngine.swift`
- Create: `Sources/nippo-tests/OneOnOneTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(最后一个 run 调用后追加 `runOneOnOneTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/OneOnOneTests.swift`:

```swift
import Foundation
import NippoCore

func runOneOnOneTests() {
    func ev(_ id: String, _ title: String, startH: Int, startM: Int,
            endH: Int, endM: Int) -> MeetingEvent {
        MeetingEvent(id: id, title: title,
                     start: tokyoDate(2026, 7, 10, startH, startM),
                     end: tokyoDate(2026, 7, 10, endH, endM),
                     attendees: [], isAllDay: false)
    }

    T.run("preDue matches 1on1 titles within lead window, dedupes") {
        let engine = OneOnOneEngine()
        let events = [
            ev("a", "1on1_yudi", startH: 17, startM: 30, endH: 18, endM: 0),
            ev("b", "RoadSyncチーム全体定例", startH: 17, startM: 30, endH: 18, endM: 0),
            ev("c", "1ON1 と雑談", startH: 19, startM: 0, endH: 19, endM: 30),
        ]
        // 17:05 → a は 25 分前(30 分ウィンドウ内)、c はまだ
        let now = tokyoDate(2026, 7, 10, 17, 5)
        let due = engine.preDue(events: events, now: now,
                                keyword: "1on1", leadMinutes: 30)
        T.expectEqual(due.map(\.id), ["a"], "only 1on1 within lead")
        T.expectEqual(engine.preDue(events: events, now: now,
                                    keyword: "1on1", leadMinutes: 30).count, 0,
                      "deduped")
    }

    T.run("postDue fires 5-20 minutes after end, once") {
        let engine = OneOnOneEngine()
        let events = [ev("a", "1on1_yudi", startH: 17, startM: 30, endH: 18, endM: 0)]
        T.expectEqual(engine.postDue(events: events,
                                     now: tokyoDate(2026, 7, 10, 18, 2),
                                     keyword: "1on1").count, 0, "too early")
        T.expectEqual(engine.postDue(events: events,
                                     now: tokyoDate(2026, 7, 10, 18, 7),
                                     keyword: "1on1").map(\.id), ["a"])
        T.expectEqual(engine.postDue(events: events,
                                     now: tokyoDate(2026, 7, 10, 18, 8),
                                     keyword: "1on1").count, 0, "deduped")
        let engine2 = OneOnOneEngine()
        T.expectEqual(engine2.postDue(events: events,
                                      now: tokyoDate(2026, 7, 10, 18, 25),
                                      keyword: "1on1").count, 0, "window closed")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'OneOnOneEngine' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/OneOnOne/OneOnOneEngine.swift`:

```swift
import Foundation

/// 1on1 の会前・会後トリガー判定(タイトルにキーワードを含む予定が対象)。
public final class OneOnOneEngine {
    private var preNotified: Set<String> = []
    private var postNotified: Set<String> = []

    public init() {}

    static func matches(_ event: MeetingEvent, keyword: String) -> Bool {
        !event.isAllDay
            && event.title.lowercased().contains(keyword.lowercased())
    }

    /// 開始 lead 分前〜開始まで、1 回だけ
    public func preDue(events: [MeetingEvent], now: Date,
                       keyword: String, leadMinutes: Int) -> [MeetingEvent] {
        let due = events.filter { e in
            Self.matches(e, keyword: keyword)
                && !preNotified.contains(e.id)
                && e.start > now
                && e.start.timeIntervalSince(now) <= Double(leadMinutes * 60)
        }
        due.forEach { preNotified.insert($0.id) }
        return due
    }

    /// 終了 5〜20 分後、1 回だけ
    public func postDue(events: [MeetingEvent], now: Date,
                        keyword: String) -> [MeetingEvent] {
        let due = events.filter { e in
            Self.matches(e, keyword: keyword)
                && !postNotified.contains(e.id)
                && now.timeIntervalSince(e.end) >= 5 * 60
                && now.timeIntervalSince(e.end) <= 20 * 60
        }
        due.forEach { postNotified.insert($0.id) }
        return due
    }

    public func resetForNewDay() {
        preNotified.removeAll()
        postNotified.removeAll()
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 73 tests`(71+2)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: one-on-one pre/post trigger engine"
```

---

### Task 2: OneOnOnePrep(talking points 生成)

**Files:**
- Create: `Sources/NippoCore/OneOnOne/OneOnOnePrep.swift`
- Create: `Sources/nippo-tests/OneOnOnePrepTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runOneOnOnePrepTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/OneOnOnePrepTests.swift`:

```swift
import Foundation
import NippoCore

func runOneOnOnePrepTests() {
    T.run("prep prompt embeds materials and structure") {
        let p = OneOnOnePrep.prompt(
            meetingTitle: "1on1_yudi",
            weekDailies: "### 2026-07-09\n木曜の日報本文",
            todayNotes: ["トンマナ整理をした"],
            openChecklist: ["レビュー依頼"],
            previousPrep: "前回: mock の相談",
            goal: "行動指標テキスト")
        T.expect(p.contains("1on1_yudi"), "title")
        T.expect(p.contains("木曜の日報本文"), "dailies")
        T.expect(p.contains("トンマナ整理をした"), "notes")
        T.expect(p.contains("レビュー依頼"), "open checklist")
        T.expect(p.contains("前回: mock の相談"), "previous prep")
        T.expect(p.contains("相談したいこと"), "structure")
        T.expect(p.contains("素材にない"), "no-invention rule")
    }

    T.run("prepare writes dated file under 1on1 dir") {
        struct FakeGen: TextGenerator {
            func generate(prompt: String) throws -> String { "# 準備メモ" }
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-oo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try OneOnOnePrep.prepare(
            generator: FakeGen(), reportsRoot: root,
            meetingTitle: "1on1_yudi",
            todayNotes: [], openChecklist: [],
            date: tokyoDate(2026, 7, 10, 17, 0), calendar: tokyoCalendar)
        T.expect(url.path.contains("1on1"), "1on1 dir")
        T.expect(url.lastPathComponent.hasPrefix("2026-07-10"), "dated")
        T.expectEqual(try String(contentsOf: url, encoding: .utf8), "# 準備メモ")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'OneOnOnePrep' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/OneOnOne/OneOnOnePrep.swift`:

```swift
import Foundation

/// 1on1 の準備メモ(talking points)生成。
public enum OneOnOnePrep {
    public static func prompt(meetingTitle: String, weekDailies: String,
                              todayNotes: [String], openChecklist: [String],
                              previousPrep: String?, goal: String?) -> String {
        let notes = todayNotes.isEmpty
            ? "(なし)" : todayNotes.map { "- \($0)" }.joined(separator: "\n")
        let open = openChecklist.isEmpty
            ? "(なし)" : openChecklist.map { "- \($0)" }.joined(separator: "\n")
        return """
        あなたは 1on1 の準備アシスタント。まもなく「\(meetingTitle)」が始まる。
        以下の素材から、メンターとの 1on1 で使う準備メモを作る。

        # 構成(この見出しで)
        ## 今週の進捗ハイライト(3〜5 点。事実ベース、簡潔に)
        ## 相談したいこと(2〜4 点。改善点・未完了・判断に迷っている点から)
        ## 前回の宿題・話題の続き(前回メモがあれば。なければ見出しごと省略)

        # 制約
        - 素材にない事実を発明しない。常体で簡潔に
        - 「相談したいこと」は具体的な質問文の形にする

        # 素材: 今週の日報
        \(weekDailies.isEmpty ? "(なし)" : weekDailies)

        # 素材: 今日のメモ
        \(notes)

        # 素材: 未完了のチェックリスト
        \(open)

        # 素材: 前回の 1on1 メモ
        \(previousPrep ?? "(なし)")

        # 素材: 目標と行動指標
        \(goal ?? "(なし)")

        出力は準備メモの Markdown 本文のみ。
        """
    }

    /// 直近の 1on1 ファイル(前回分)
    static func loadPrevious(dir: URL) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let newest = entries
            .filter { $0.pathExtension.lowercased() == "md" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return da < db
            }
        guard let newest else { return nil }
        return try? String(contentsOf: newest, encoding: .utf8)
    }

    public static func prepare(generator: TextGenerator, reportsRoot: URL,
                               meetingTitle: String,
                               todayNotes: [String], openChecklist: [String],
                               date: Date, calendar: Calendar = .current) throws -> URL {
        let dir = reportsRoot.appendingPathComponent("1on1")
        let previous = loadPrevious(dir: dir)
        let dailies = WeeklyBuilder.weekDailyReports(root: reportsRoot, upTo: date,
                                                     calendar: calendar)
            .map { "### \($0.day)\n\($0.body)" }.joined(separator: "\n\n")
        let goal = WeeklyBuilder.loadGoal(
            weeklyDir: reportsRoot.appendingPathComponent("週報"))

        let body = try generator.generate(prompt: prompt(
            meetingTitle: meetingTitle, weekDailies: dailies,
            todayNotes: todayNotes, openChecklist: openChecklist,
            previousPrep: previous, goal: goal))

        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let base = dir.appendingPathComponent(
            "\(DayKey.key(for: date, calendar: calendar))-1on1準備.md")
        let url = ReportService.uniqueURL(for: base)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 75 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: one-on-one prep note generation"
```

---

### Task 3: 设置 + coordinator 接线 + 随手记预填

**Files:**
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`
- Modify: `Sources/nippo-tests/SettingsTests.swift`
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Modify: `Sources/NippoApp/QuickNotePanel.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

**先 Read 各文件。**

- [ ] **Step 1: 设置 TDD**

`SettingsTests.swift`「defaults and roundtrip」末尾追加:

```swift
        T.expectEqual(s.oneOnOneEnabled, true)
        T.expectEqual(s.oneOnOneKeyword, "1on1")
        T.expectEqual(s.oneOnOneLeadMinutes, 30)
        s.oneOnOneLeadMinutes = 15
        T.expectEqual(AppSettings(defaults: d).oneOnOneLeadMinutes, 15)
```

确认失败后 `AppSettings.swift` 追加(punch 设置之后):

```swift
    public var oneOnOneEnabled: Bool {
        get { d.object(forKey: "oneOnOneEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "oneOnOneEnabled"); objectWillChange.send() }
    }

    public var oneOnOneKeyword: String {
        get { d.string(forKey: "oneOnOneKeyword") ?? "1on1" }
        set { d.set(newValue, forKey: "oneOnOneKeyword"); objectWillChange.send() }
    }

    public var oneOnOneLeadMinutes: Int {
        get { d.object(forKey: "oneOnOneLeadMinutes") as? Int ?? 30 }
        set { d.set(newValue, forKey: "oneOnOneLeadMinutes"); objectWillChange.send() }
    }
```

- [ ] **Step 2: QuickNotePanel 预填**

`QuickNotePanel.swift`:`QuickNotePanelController` 的 `toggle()` 旁追加:

```swift
    func show(prefill: String) {
        close()
        showInternal(prefill: prefill)
    }
```

并把现有 `show()` 私有方法改名为 `showInternal(prefill: String = "")`(`toggle()` 内调用处同步改为 `showInternal(prefill: "")`;若现有实现无 `close()` 公开方法,按现有结构等价调整,保持既有行为不变)。`QuickNoteView` 增加 `init` 预填:`@State private var text: String` 由构造参数初始化(`init(prefill: String, onSave:, onCancel:)` → `_text = State(initialValue: prefill)`),`showInternal` 创建 `QuickNoteView(prefill: prefill, ...)`。

- [ ] **Step 3: coordinator 接线**

`AppCoordinator.swift`:属性区追加:

```swift
    let oneOnOneEngine = OneOnOneEngine()
    private var oneOnOnePrepBusy = false
```

`init()` 的 `onAppAction` 闭包改为(先 Read 现状,在 openPunch 分支后追加):

```swift
            if action == "oneOnOneNote" {
                self?.quickNotePanel.show(prefill: "1on1: ")
            }
```

`tick()` 的日期变更块追加 `oneOnOneEngine.resetForNewDay()`;会議リマインド块之后追加:

```swift
        // 1on1 会前準備・会後メモ
        if settings.oneOnOneEnabled && calendarAuthorized {
            let pre = oneOnOneEngine.preDue(events: todayEvents, now: now,
                                            keyword: settings.oneOnOneKeyword,
                                            leadMinutes: settings.oneOnOneLeadMinutes)
            for e in pre { prepareOneOnOne(for: e) }

            let post = oneOnOneEngine.postDue(events: todayEvents, now: now,
                                              keyword: settings.oneOnOneKeyword)
            if !post.isEmpty {
                NotificationService.shared.notify(
                    title: "1on1 おつかれさまでした",
                    body: "言われたこと・宿題をメモしましょう(クリックで入力)",
                    appAction: "oneOnOneNote")
            }
        }
```

方法区追加:

```swift
    func prepareOneOnOne(for event: MeetingEvent) {
        guard !oneOnOnePrepBusy else { return }
        oneOnOnePrepBusy = true
        let root = URL(fileURLWithPath: settings.reportsRoot)
        let customPath = settings.claudePath
        let title = event.title
        let notes = todayNotes.map(\.text)
        let open = todayChecklist.filter { !$0.done }.map(\.text)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var resultURL: URL?
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                var cli = ClaudeCLI(executable: exe)
                cli.timeout = 120
                resultURL = try? OneOnOnePrep.prepare(
                    generator: cli, reportsRoot: root, meetingTitle: title,
                    todayNotes: notes, openChecklist: open, date: Date())
            }
            DispatchQueue.main.async {
                self?.oneOnOnePrepBusy = false
                if let url = resultURL {
                    NotificationService.shared.notify(
                        title: "1on1 の準備メモができました",
                        body: "クリックで開く: \(url.lastPathComponent)",
                        joinURL: url)
                } else {
                    NotificationService.shared.notify(
                        title: "1on1 準備メモの生成に失敗",
                        body: "メニューから日報素材を確認してください")
                }
            }
        }
    }
```

`SettingsView.swift`:「打刻(バクラク勤怠)」Section 之后追加:

```swift
            Section("1on1 助手") {
                Toggle("1on1 の前に準備メモ、後にメモ促しを出す", isOn: binding(\.oneOnOneEnabled))
                TextField("検出キーワード", text: binding(\.oneOnOneKeyword))
                Stepper("開始 \(settings.oneOnOneLeadMinutes) 分前に準備",
                        value: binding(\.oneOnOneLeadMinutes), in: 5...60, step: 5)
            }
```

- [ ] **Step 4: 测试 + 打包 + Commit**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 75 tests`,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: one-on-one assistant wired (prep notes, post-meeting note prompt)"
```

- [ ] **Step 5: 手动验证清单(跳过并汇报)**

1. 建一个标题含 1on1、35 分钟后开始的日程 → 30 分钟前收到「準備メモができました」,点击打开 `~/Documents/日報/1on1/…-1on1準備.md`
2. 会议结束 5-20 分钟内收到「おつかれさまでした」,点击弹出随手记悬浮窗且预填「1on1: 」
3. 非 1on1 会议不触发;设置改 keyword/lead 生效;开关关闭后全部不触发

---

### Task 4: README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「使い方」列表末尾追加**

```markdown
- タイトルに「1on1」を含む予定は、30 分前に準備メモ(今週の日報・未完了・
  前回メモから)を自動生成して通知、終了後はメモ促し(クリックで入力窓)
```

- [ ] **Step 2: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 75 tests`

```bash
git add -A && git commit -m "docs: one-on-one assistant usage"
```

---

## 后续(不在本计划内)

- 三期后:1on1 の議事録(録音転写)を準備メモ・学びに自動接続
