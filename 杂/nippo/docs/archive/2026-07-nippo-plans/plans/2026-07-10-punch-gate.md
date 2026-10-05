# 打刻门禁(バクラク勤怠・第二期)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 工作日未打刻时,菜单面板显示**打刻界面**(内嵌持久会话的バクラク勤怠 WKWebView + 「出勤打刻した」确认按钮 + 「他で打刻済み」/「今日はスキップ」逃生口);确认后记录到本地 DB 并切回正常面板。傍晚(默认 18:30)退勤提醒、21:00 漏打再提醒,通知点击打开独立打刻窗口。静默日全程无门禁无提醒。**绝不自动打刻,绝不在用户未确认时记录。**

**Architecture:** DB v3 `punch_record` + `PunchService`(NippoCore,TDD);`NotificationService` 增加 appAction 回调(通知点击→应用内动作);`PunchWebView`(WKWebView 持久会话)+ `PunchGateView`(菜单内)+ `PunchWindowController`(独立窗,退勤用)进 NippoApp;MenuContentView 按状态切换;coordinator 管理状态与两个傍晚触发。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(截图整理合入后应为 **69 tests**;不同则顺延并在 concerns 说明);分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**,锚点找不到报 BLOCKed。

---

### Task 1: DB v3 + PunchService

**Files:**
- Modify: `Sources/NippoCore/Database/AppDatabase.swift`(migrator 追加 v3)
- Create: `Sources/NippoCore/Punch/PunchRecord.swift`
- Create: `Sources/NippoCore/Punch/PunchService.swift`
- Create: `Sources/nippo-tests/PunchTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(最后一个 run 调用后追加 `runPunchTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/PunchTests.swift`:

```swift
import Foundation
import NippoCore

func runPunchTests() {
    T.run("record and query punch in/out per day") {
        let db = try AppDatabase.inMemory()
        let svc = PunchService(db: db)
        T.expectEqual(try svc.hasPunch(day: "2026-07-10", kind: .punchIn), false)

        try svc.record(day: "2026-07-10", kind: .punchIn, via: "webview",
                       at: tokyoDate(2026, 7, 10, 9, 1))
        T.expectEqual(try svc.hasPunch(day: "2026-07-10", kind: .punchIn), true)
        T.expectEqual(try svc.hasPunch(day: "2026-07-10", kind: .punchOut), false)
        T.expectEqual(try svc.hasPunch(day: "2026-07-11", kind: .punchIn), false)

        try svc.record(day: "2026-07-10", kind: .punchOut, via: "external",
                       at: tokyoDate(2026, 7, 10, 18, 31))
        T.expectEqual(try svc.hasPunch(day: "2026-07-10", kind: .punchOut), true)
    }

    T.run("duplicate record for same day+kind is ignored") {
        let db = try AppDatabase.inMemory()
        let svc = PunchService(db: db)
        try svc.record(day: "2026-07-10", kind: .punchIn, via: "webview",
                       at: tokyoDate(2026, 7, 10, 9, 1))
        try svc.record(day: "2026-07-10", kind: .punchIn, via: "external",
                       at: tokyoDate(2026, 7, 10, 9, 5))
        let rows = try svc.records(day: "2026-07-10")
        T.expectEqual(rows.filter { $0.kind == "in" }.count, 1, "no duplicate in")
        T.expectEqual(rows[0].via, "webview", "first record wins")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'PunchService' in scope`

- [ ] **Step 3: 实现**

`AppDatabase.swift` migrator(v2 块之后、`return m` 之前)追加:

```swift
        m.registerMigration("v3") { db in
            try db.create(table: "punch_record") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("day", .text).notNull()
                t.column("kind", .text).notNull()      // "in" / "out"
                t.column("at", .datetime).notNull()
                t.column("via", .text).notNull()       // "webview" / "external"
                t.uniqueKey(["day", "kind"])
            }
        }
```

`Sources/NippoCore/Punch/PunchRecord.swift`:

```swift
import Foundation
import GRDB

public struct PunchRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "punch_record"

    public var id: Int64?
    public var day: String       // "yyyy-MM-dd"
    public var kind: String      // "in" / "out"
    public var at: Date
    public var via: String       // "webview" / "external"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

`Sources/NippoCore/Punch/PunchService.swift`:

```swift
import Foundation
import GRDB

/// 打刻状態のローカル記録。実際の打刻はユーザーがバクラク勤怠の画面で行い、
/// ここには「ユーザーが確認した事実」だけを記録する(自動打刻はしない)。
public struct PunchService {
    public enum Kind: String {
        case punchIn = "in"
        case punchOut = "out"
    }

    let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func hasPunch(day: String, kind: Kind) throws -> Bool {
        try db.dbQueue.read {
            try Bool.fetchOne(
                $0,
                sql: "SELECT EXISTS(SELECT 1 FROM punch_record WHERE day = ? AND kind = ?)",
                arguments: [day, kind.rawValue]) ?? false
        }
    }

    /// 同日同種の二重記録は無視(先勝ち)
    public func record(day: String, kind: Kind, via: String, at: Date) throws {
        try db.dbQueue.write {
            try $0.execute(
                sql: """
                INSERT OR IGNORE INTO punch_record (day, kind, at, via)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [day, kind.rawValue, at, via])
        }
    }

    public func records(day: String) throws -> [PunchRecord] {
        try db.dbQueue.read {
            try PunchRecord
                .filter(Column("day") == day)
                .order(Column("at"))
                .fetchAll($0)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 71 tests`(69+2)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: punch record storage (db v3, PunchService)"
```

---

### Task 2: 设置项 + NotificationService appAction

**Files:**
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`(screenshotsEnabled 之后追加)
- Modify: `Sources/nippo-tests/SettingsTests.swift`(追加断言)
- Modify: `Sources/NippoCore/Notifications/NotificationService.swift`

- [ ] **Step 1: 设置 TDD**

`SettingsTests.swift`「defaults and roundtrip」末尾追加:

```swift
        T.expectEqual(s.punchEnabled, true)
        T.expect(s.punchURL.contains("bakuraku"), "default punch url")
        T.expectEqual(s.punchOutReminderTime, "18:30")
        T.expectEqual(s.punchRecheckTime, "21:00")
        s.punchEnabled = false
        s.punchURL = "https://example.com"
        T.expectEqual(AppSettings(defaults: d).punchEnabled, false)
        T.expectEqual(AppSettings(defaults: d).punchURL, "https://example.com")
```

确认失败后,`AppSettings.swift` 追加:

```swift
    /// 打刻ゲート(未打刻の平日はメニューが打刻画面になる)
    public var punchEnabled: Bool {
        get { d.object(forKey: "punchEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "punchEnabled"); objectWillChange.send() }
    }

    public var punchURL: String {
        get { d.string(forKey: "punchURL") ?? "https://kintai.bakuraku.jp/" }
        set { d.set(newValue, forKey: "punchURL"); objectWillChange.send() }
    }

    public var punchOutReminderTime: String {   // "HH:mm"
        get { d.string(forKey: "punchOutReminderTime") ?? "18:30" }
        set { d.set(newValue, forKey: "punchOutReminderTime"); objectWillChange.send() }
    }

    public var punchRecheckTime: String {       // "HH:mm"
        get { d.string(forKey: "punchRecheckTime") ?? "21:00" }
        set { d.set(newValue, forKey: "punchRecheckTime"); objectWillChange.send() }
    }

    public var lastPunchOutReminderDay: String? {
        get { d.string(forKey: "lastPunchOutReminderDay") }
        set { d.set(newValue, forKey: "lastPunchOutReminderDay"); objectWillChange.send() }
    }

    public var lastPunchRecheckDay: String? {
        get { d.string(forKey: "lastPunchRecheckDay") }
        set { d.set(newValue, forKey: "lastPunchRecheckDay"); objectWillChange.send() }
    }

    public func timeComponents(_ value: String,
                               fallback: (hour: Int, minute: Int)) -> (hour: Int, minute: Int) {
        let parts = value.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return (h, m)
        }
        return fallback
    }
```

- [ ] **Step 2: NotificationService appAction**

`NotificationService.swift`(先 Read):

`static let joinURLKey` 行附近追加:

```swift
    static let appActionKey = "appAction"

    /// 通知クリックでアプリ内アクションを実行するためのコールバック
    /// (AppCoordinator が起動時に設定する)
    public var onAppAction: ((String) -> Void)?
```

`notify(title:body:joinURL:)` 签名扩展为:

```swift
    public func notify(title: String, body: String, joinURL: URL? = nil,
                       appAction: String? = nil) {
```

方法体中 `if let joinURL { ... }` 块之后追加:

```swift
        if let appAction {
            content.userInfo[Self.appActionKey] = appAction
        }
```

`didReceive` 中 joinURL 处理之后追加:

```swift
        if let action = userInfo[Self.appActionKey] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onAppAction?(action)
            }
        }
```

- [ ] **Step 3: 测试 + Commit**

Run: `swift run nippo-tests && swift build --target NippoApp`
Expected: `PASS: 71 tests`,编译通过

```bash
git add -A && git commit -m "feat: punch settings and notification app-action callback"
```

---

### Task 3: 打刻 UI(WebView・门禁视图・独立窗)

**Files:**
- Create: `Sources/NippoApp/PunchViews.swift`

- [ ] **Step 1: 实现**

`Sources/NippoApp/PunchViews.swift`:

```swift
import AppKit
import SwiftUI
import WebKit
import NippoCore

/// バクラク勤怠を持久セッションで表示する WebView。
/// ログインは初回にこの中で行い、以後 Cookie が保持される。
struct PunchWebView: NSViewRepresentable {
    let url: URL

    static let shared: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // 永続セッション
        let view = WKWebView(frame: .zero, configuration: config)
        return view
    }()

    func makeNSView(context: Context) -> WKWebView {
        let view = Self.shared
        if view.url == nil {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// 未打刻の平日にメニュー本体として表示される打刻ゲート。
struct PunchGateView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("おはようございます。まず出勤打刻をどうぞ")
                .font(.headline)
            PunchWebView(url: URL(string: coordinator.settings.punchURL)
                ?? URL(string: "https://kintai.bakuraku.jp/")!)
                .frame(height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Button("出勤打刻した") {
                    coordinator.confirmPunch(kind: .punchIn, via: "webview")
                }
                .keyboardShortcut(.defaultAction)
                Button("他で打刻済み") {
                    coordinator.confirmPunch(kind: .punchIn, via: "external")
                }
                Spacer()
                Button("今日はスキップ") {
                    coordinator.skipPunchGateForSession()
                }
                .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                SettingsLink { Text("設定…") }
                Spacer()
                Button("終了") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 440)
    }
}

/// 退勤打刻・手動打刻用の独立ウィンドウ(通知クリックからも開く)。
@MainActor
final class PunchWindowController {
    private var window: NSWindow?
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let coordinator else { return }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        win.title = "バクラク勤怠"
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: PunchWindowView(coordinator: coordinator))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

private struct PunchWindowView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PunchWebView(url: URL(string: coordinator.settings.punchURL)
                ?? URL(string: "https://kintai.bakuraku.jp/")!)
            HStack {
                Button("出勤打刻した") {
                    coordinator.confirmPunch(kind: .punchIn, via: "webview")
                }
                Button("退勤打刻した") {
                    coordinator.confirmPunch(kind: .punchOut, via: "webview")
                }
                Button("他で打刻済み(退勤)") {
                    coordinator.confirmPunch(kind: .punchOut, via: "external")
                }
                Spacer()
            }
        }
        .padding(12)
    }
}
```

- [ ] **Step 2: 编译 + Commit**

Run: `swift build --target NippoApp`
Expected: 编译失败是预期的(coordinator 方法未实装)→ 本任务与 Task 4 **连续实施、合并验证**;若想单独编译通过,可先 stub。按顺序做 Task 4 后一起验证即可,提交也可合并到 Task 4。

---

### Task 4: coordinator 状态与触发 + 菜单门禁 + 设置界面

**Files:**
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Modify: `Sources/NippoApp/MenuContentView.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

**先 Read 三个文件。**

- [ ] **Step 1: AppCoordinator**

属性区追加(screenshot 属性之后):

```swift
    let punchService: PunchService
    @Published var punchedInToday = false
    @Published var punchGateSkippedToday: String?   // DayKey;当日限りのスキップ
    private lazy var punchWindow = PunchWindowController(coordinator: self)
```

`init()` 中 `checklistService = ChecklistService(db: db)` 之后追加:

```swift
        punchService = PunchService(db: db)
```

`init()` 中 NotificationService 权限申请行之后追加:

```swift
        NotificationService.shared.onAppAction = { [weak self] action in
            if action == "openPunch" { self?.punchWindow.show() }
        }
        refreshPunchState()
```

方法区追加:

```swift
    func refreshPunchState() {
        let today = DayKey.key(for: Date())
        punchedInToday = (try? punchService.hasPunch(day: today, kind: .punchIn)) ?? false
    }

    /// メニューを打刻ゲートにするか
    var showPunchGate: Bool {
        guard settings.punchEnabled else { return false }
        guard !((try? quietDays.isQuietDay(Date())) ?? false) else { return false }
        guard punchGateSkippedToday != DayKey.key(for: Date()) else { return false }
        return !punchedInToday
    }

    func confirmPunch(kind: PunchService.Kind, via: String) {
        try? punchService.record(day: DayKey.key(for: Date()), kind: kind,
                                 via: via, at: Date())
        refreshPunchState()
        statusMessage = kind == .punchIn ? "出勤打刻を記録しました" : "退勤打刻を記録しました"
    }

    func skipPunchGateForSession() {
        punchGateSkippedToday = DayKey.key(for: Date())
    }

    func openPunchWindow() {
        punchWindow.show()
    }
```

`tick()` 内日期变更块追加一行 `refreshPunchState()`;週報触发块之后追加:

```swift
        // 退勤リマインド(1日1回)と漏れ再確認(1日1回)。クワイエット日は上で return 済み
        if settings.punchEnabled {
            let today = DayKey.key(for: now)
            let outDone = (try? punchService.hasPunch(day: today, kind: .punchOut)) ?? false
            if !outDone {
                let (rh, rm) = settings.timeComponents(settings.punchOutReminderTime,
                                                       fallback: (18, 30))
                if DailyTrigger.shouldFire(now: now, hour: rh, minute: rm,
                                           lastFiredDay: settings.lastPunchOutReminderDay) {
                    settings.lastPunchOutReminderDay = today
                    NotificationService.shared.notify(
                        title: "退勤打刻の時間です",
                        body: "クリックで打刻画面を開きます",
                        appAction: "openPunch")
                }
                let (ch, cm) = settings.timeComponents(settings.punchRecheckTime,
                                                       fallback: (21, 0))
                if DailyTrigger.shouldFire(now: now, hour: ch, minute: cm,
                                           lastFiredDay: settings.lastPunchRecheckDay) {
                    settings.lastPunchRecheckDay = today
                    NotificationService.shared.notify(
                        title: "退勤打刻がまだのようです",
                        body: "打刻済みなら打刻画面で「退勤打刻した」を押してください",
                        appAction: "openPunch")
                }
            }
        }
```

- [ ] **Step 2: MenuContentView 门禁**

`body` 的最外层改为状态切换:现有 `VStack(alignment: .leading, spacing: 8) { ... }` 整体包进:

```swift
    var body: some View {
        if coordinator.showPunchGate {
            PunchGateView(coordinator: coordinator)
        } else {
            normalContent
        }
    }

    private var normalContent: some View {
        // ここに既存の VStack 全体を移す(内容は一切変えない)
    }
```

并在 normalContent 的「終了」按钮之前加一行(打刻窗口入口,退勤用):

```swift
            Button("打刻画面を開く") { coordinator.openPunchWindow() }
```

- [ ] **Step 3: SettingsView**

「スクリーンショット」Section 之后追加:

```swift
            Section("打刻(バクラク勤怠)") {
                Toggle("未打刻の平日はメニューを打刻画面にする", isOn: binding(\.punchEnabled))
                TextField("打刻ページ URL", text: binding(\.punchURL))
                TextField("退勤リマインド (HH:mm)", text: binding(\.punchOutReminderTime))
                TextField("漏れ再確認 (HH:mm)", text: binding(\.punchRecheckTime))
                Text("打刻はあなたがページ内で行い、アプリは確認ボタンで記録するだけです(自動打刻はしません)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: 测试 + 打包 + Commit(Task 3+4 合并验证)**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 71 tests`,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: punch gate menu, bakuraku webview, evening reminders"
```

- [ ] **Step 5: 手动验证清单(跳过并汇报)**

1. 工作日未打刻状态点开菜单 → 显示打刻界面(バクラク勤怠页面加载,首次需登录一次,会话此后保持)
2. 页面里打刻后点「出勤打刻した」→ 菜单切回正常面板;重开菜单不再出现门禁
3. 「他で打刻済み」同样解锁;「今日はスキップ」仅本次会话解锁(重启应用后门禁恢复)
4. 18:30 收到退勤提醒通知,点击打开打刻窗口;21:00 未记录退勤时再提醒
5. 周末/节假日/休暇日无门禁无提醒
6. 设置区块各项持久化;关掉开关后门禁消失

---

### Task 5: README + 完成

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「使い方」列表末尾追加**

```markdown
- 平日は出勤打刻がすむまでメニューが打刻画面(バクラク勤怠)になる。
  打刻はページ内で自分で行い、「出勤打刻した」で記録 → 通常メニューに切替。
  退勤は 18:30 リマインド+21:00 再確認(通知クリックで打刻画面)
```

- [ ] **Step 2: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 71 tests`

```bash
git add -A && git commit -m "docs: punch gate usage"
```

---

## 后续(不在本计划内)

- バクラク勤怠页面结构确认后的 JS 自动代点(仍需用户先点确认)
- 打刻時刻与日报/週報联动(用户已明确不要,勿实装)
- 1on1 助手(队列末棒)
