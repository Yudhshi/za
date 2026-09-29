# 三期 A:Meet 字幕 → 議事録 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chrome 扩展读 Google Meet 字幕(多选择器容错+增量提取+说话人名)→ POST 到 Nippo 本地 `127.0.0.1` 监听端口(Network 框架,仅回环,绝不出网)→ 逐行存转写稿到 DB+文件。会议结束点菜单「議事録を作成」→ Claude 离线(`--tools "" --strict-mcp-config`)生成「決定事項/TODO/議論の要点」日语纪要 → 存 `~/Documents/日報/minutes/` + 自动进当天日报素材。零音频、只读屏上已显示的字幕。

**Architecture:** `TranscriptLine`/`TranscriptSession` + `TranscriptService`(DB v4,TDD)、`HTTPRequestParser`(纯字节解析,TDD)、`MinutesBuilder`(prompt/解析,TDD)、`CaptionServer`(NWListener 薄胶水,手动验证)进 NippoCore/NippoApp;coordinator 起停服务器 + 菜单「会議記録」区块;Chrome 扩展在 repo `browser-extension/nippo-meet/`。日报素材接入复用 factsSection 追加参数。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(当前 **80 tests**;计数不同按差值顺延 Expected 并在 concerns 说明);分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**,锚点找不到报 BLOCKED。Network 框架(`import Network`)在 SDK 内,无需外部依赖。参考:公司 meet-dictionary 扩展的字幕选择器 `div[jsname="YSxPC"]` / `div[jsname="dsyhDe"]` / `div[aria-live="polite"]` / `[role="region"][aria-label*="aption" i]`。

---

### Task 1: DB v4 + Transcript 模型 + TranscriptService

**Files:**
- Modify: `Sources/NippoCore/Database/AppDatabase.swift`(migrator 追加 v4)
- Create: `Sources/NippoCore/Meeting/TranscriptLine.swift`
- Create: `Sources/NippoCore/Meeting/TranscriptService.swift`
- Create: `Sources/nippo-tests/TranscriptTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(最后一个 run 调用后追加 `runTranscriptTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/TranscriptTests.swift`:

```swift
import Foundation
import NippoCore

func runTranscriptTests() {
    T.run("append and fetch lines by session in order") {
        let db = try AppDatabase.inMemory()
        let svc = TranscriptService(db: db)
        try svc.append(session: "s1", speaker: "田中", text: "まず前提を確認します",
                       at: tokyoDate(2026, 7, 10, 10, 0))
        try svc.append(session: "s1", speaker: "Yudi", text: "はい、資料はこちらです",
                       at: tokyoDate(2026, 7, 10, 10, 1))
        try svc.append(session: "s2", speaker: "佐藤", text: "別会議",
                       at: tokyoDate(2026, 7, 10, 11, 0))
        let lines = try svc.lines(session: "s1")
        T.expectEqual(lines.count, 2)
        T.expectEqual(lines[0].speaker, "田中")
        T.expectEqual(lines[1].text, "はい、資料はこちらです")
    }

    T.run("sessions on a day, and transcript text assembly") {
        let db = try AppDatabase.inMemory()
        let svc = TranscriptService(db: db)
        try svc.append(session: "2026-07-10-定例", speaker: "A", text: "決定した",
                       at: tokyoDate(2026, 7, 10, 10, 0))
        let sessions = try svc.sessions(on: "2026-07-10")
        T.expectEqual(sessions, ["2026-07-10-定例"])
        T.expect(try svc.transcriptText(session: "2026-07-10-定例").contains("A: 決定した"),
                 "assembled with speaker prefix")
        T.expectEqual(try svc.sessions(on: "2026-07-11"), [])
    }
}
```

`main.swift` 追加 `runTranscriptTests()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'TranscriptService' in scope`

- [ ] **Step 3: 实现**

`AppDatabase.swift` migrator(v3 块之后、`return m` 之前)追加:

```swift
        m.registerMigration("v4") { db in
            try db.create(table: "transcript_line") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session", .text).notNull().indexed()
                t.column("day", .text).notNull().indexed()
                t.column("speaker", .text).notNull()
                t.column("text", .text).notNull()
                t.column("at", .datetime).notNull()
            }
        }
```

`Sources/NippoCore/Meeting/TranscriptLine.swift`:

```swift
import Foundation
import GRDB

public struct TranscriptLine: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "transcript_line"

    public var id: Int64?
    public var session: String
    public var day: String        // "yyyy-MM-dd"
    public var speaker: String
    public var text: String
    public var at: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

`Sources/NippoCore/Meeting/TranscriptService.swift`:

```swift
import Foundation
import GRDB

/// 会議字幕の逐行保存と取り出し(セッション=会議単位)。
public struct TranscriptService {
    let db: AppDatabase
    let calendar: Calendar

    public init(db: AppDatabase, calendar: Calendar = .current) {
        self.db = db
        self.calendar = calendar
    }

    public func append(session: String, speaker: String, text: String,
                       at date: Date = Date()) throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var line = TranscriptLine(session: session,
                                  day: DayKey.key(for: date, calendar: calendar),
                                  speaker: speaker.isEmpty ? "不明" : speaker,
                                  text: clean, at: date)
        try db.dbQueue.write { try line.insert($0) }
    }

    public func lines(session: String) throws -> [TranscriptLine] {
        try db.dbQueue.read {
            try TranscriptLine
                .filter(Column("session") == session)
                .order(Column("at"), Column("id"))
                .fetchAll($0)
        }
    }

    public func sessions(on day: String) throws -> [String] {
        try db.dbQueue.read {
            try String.fetchAll($0,
                sql: "SELECT DISTINCT session FROM transcript_line WHERE day = ? ORDER BY session",
                arguments: [day])
        }
    }

    /// 「話者: 発言」を改行で連結した全文
    public func transcriptText(session: String) throws -> String {
        try lines(session: session)
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 82 tests`(80+2)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: transcript storage (db v4, TranscriptService)"
```

---

### Task 2: HTTPRequestParser(纯字节解析)

**Files:**
- Create: `Sources/NippoCore/Meeting/HTTPRequestParser.swift`
- Create: `Sources/nippo-tests/HTTPParserTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runHTTPParserTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/HTTPParserTests.swift`:

```swift
import Foundation
import NippoCore

func runHTTPParserTests() {
    T.run("parses POST with JSON body and Content-Length") {
        let body = #"{"session":"s1","speaker":"田中","text":"こんにちは"}"#
        let raw = "POST /caption HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let req = HTTPRequestParser.parse(Data(raw.utf8))
        T.expectEqual(req?.method, "POST")
        T.expectEqual(req?.path, "/caption")
        T.expect(req?.bodyComplete == true, "body fully received")
        T.expect(String(data: req!.body, encoding: .utf8)!.contains("田中"), "body carried")
    }

    T.run("reports incomplete body when short") {
        let raw = "POST /caption HTTP/1.1\r\nContent-Length: 50\r\n\r\n{\"a\":1}"
        let req = HTTPRequestParser.parse(Data(raw.utf8))
        T.expect(req != nil && req?.bodyComplete == false, "known-incomplete")
    }

    T.run("GET health has no body and is complete") {
        let raw = "GET /health HTTP/1.1\r\nHost: x\r\n\r\n"
        let req = HTTPRequestParser.parse(Data(raw.utf8))
        T.expectEqual(req?.method, "GET")
        T.expectEqual(req?.path, "/health")
        T.expect(req?.bodyComplete == true, "no-body complete")
    }

    T.run("returns nil before headers terminator arrives") {
        T.expect(HTTPRequestParser.parse(Data("POST /caption HTTP/1.1\r\nHost: x".utf8)) == nil,
                 "headers not terminated yet")
    }
}
```

`main.swift` 追加 `runHTTPParserTests()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'HTTPRequestParser' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Meeting/HTTPRequestParser.swift`:

```swift
import Foundation

/// 回環専用の極小 HTTP/1.1 リクエスト解析。ヘッダ終端(\r\n\r\n)まで来たら
/// メソッド・パスと、Content-Length 分の body が揃ったかを返す。
public enum HTTPRequestParser {
    public struct Request: Equatable {
        public let method: String
        public let path: String
        public let body: Data
        public let bodyComplete: Bool
    }

    public static func parse(_ data: Data) -> Request? {
        let terminator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: terminator) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2,
               kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let body = data.subdata(in: range.upperBound..<data.endIndex)
        let complete = body.count >= contentLength
        let trimmed = complete ? body.prefix(contentLength) : body
        return Request(method: method, path: path,
                       body: Data(trimmed), bodyComplete: complete)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 86 tests`(82+4)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: minimal HTTP request parser for loopback caption server"
```

---

### Task 3: MinutesBuilder(纪要 prompt/解析)

**Files:**
- Create: `Sources/NippoCore/Meeting/MinutesBuilder.swift`
- Create: `Sources/nippo-tests/MinutesBuilderTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runMinutesBuilderTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/MinutesBuilderTests.swift`:

```swift
import Foundation
import NippoCore

func runMinutesBuilderTests() {
    T.run("prompt embeds transcript, structure and fidelity rules") {
        let p = MinutesBuilder.prompt(meetingTitle: "定例MTG",
                                      transcript: "田中: 前提を確認\nYudi: 資料を共有")
        T.expect(p.contains("定例MTG"), "title")
        T.expect(p.contains("前提を確認"), "transcript embedded")
        T.expect(p.contains("決定事項"), "decisions section")
        T.expect(p.contains("TODO"), "todo section")
        T.expect(p.contains("議論の要点"), "points section")
        T.expect(p.contains("字幕にない"), "no-invention rule")
    }

    T.run("extractTodos pulls TODO bullet lines for checklist feed") {
        let minutes = """
        ## 決定事項
        - 静止画で進める
        ## TODO
        - [Yudi] 競合リサーチをまとめる
        - [田中] 承認ルートを確認する
        ## 議論の要点
        - 安全性の観点
        """
        let todos = MinutesBuilder.extractTodos(minutes)
        T.expectEqual(todos.count, 2)
        T.expect(todos[0].contains("競合リサーチ"), "first todo")
    }
}
```

`main.swift` 追加 `runMinutesBuilderTests()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'MinutesBuilder' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Meeting/MinutesBuilder.swift`:

```swift
import Foundation

/// 字幕トランスクリプトから日本語議事録を作るプロンプトと、TODO 抽出。
public enum MinutesBuilder {
    public static func prompt(meetingTitle: String, transcript: String) -> String {
        """
        あなたは会議の議事録を書くアシスタント。以下は「\(meetingTitle)」の字幕トランスクリプト
        (話者: 発言 の形式)。これだけを根拠に、日本語の議事録を Markdown で作る。

        制約:
        - 字幕にない事実・決定・数字を創作しない。聞き取れていない箇所は書かない
        - 話者の意図を過度に断定しない
        - 簡潔に。冗長な逐語再掲はしない

        構成(この見出しで、内容がなければ見出しごと省略):
        ## 決定事項
        ## TODO
        (担当が分かるものは行頭に [担当名] を付ける)
        ## 議論の要点

        出力は議事録の Markdown 本文のみ。

        # トランスクリプト
        \(transcript)
        """
    }

    /// 「## TODO」見出し以下の「- 」行を返す(チェックリスト連携用)
    public static func extractTodos(_ minutes: String) -> [String] {
        let lines = minutes.components(separatedBy: "\n")
        var inTodo = false
        var todos: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("##") {
                inTodo = t.contains("TODO")
                continue
            }
            if inTodo, t.hasPrefix("- ") {
                todos.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return todos
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 88 tests`(86+2)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: meeting minutes prompt builder and TODO extractor"
```

---

### Task 4: CaptionServer(NWListener 薄胶水)

**Files:**
- Create: `Sources/NippoApp/CaptionServer.swift`

纯系统交互(回環 socket),无单元测试;编译通过 + Task 6 手动验证。

- [ ] **Step 1: 实现**

`Sources/NippoApp/CaptionServer.swift`:

```swift
import Foundation
import Network
import NippoCore

/// 127.0.0.1 の回環専用リスナー。Chrome 拡張からの POST /caption(JSON)を受け、
/// 1 行ずつコールバックする。外部インターフェースには一切バインドしない。
final class CaptionServer {
    struct Caption: Decodable {
        let session: String
        let speaker: String
        let text: String
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "nippo.caption.server")
    private let onCaption: (Caption) -> Void
    let port: UInt16

    private(set) var isRunning = false

    init(port: UInt16 = 8787, onCaption: @escaping (Caption) -> Void) {
        self.port = port
        self.onCaption = onCaption
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback   // 回環のみ
            let listener = try NWListener(using: params,
                                          on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.isRunning = true }
                if case .failed = state {
                    self?.isRunning = false
                    AppLog.shared.log("caption", "listener failed on port \(self?.port ?? 0)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            AppLog.shared.log("caption", "listener started on 127.0.0.1:\(port)")
        } catch {
            AppLog.shared.log("caption", "listener start error: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let req = HTTPRequestParser.parse(buffer) {
                if req.bodyComplete {
                    self.respond(conn, to: req)
                    return
                }
                // body 未完 → 続きを読む
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: buffer)
        }
    }

    private func respond(_ conn: NWConnection, to req: HTTPRequestParser.Request) {
        if req.method == "POST", req.path == "/caption",
           let caption = try? JSONDecoder().decode(Caption.self, from: req.body) {
            DispatchQueue.main.async { self.onCaption(caption) }
        }
        // CORS 付き 204。Meet ページからの fetch を許可
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Content-Length: 0\r
        Connection: close\r
        \r

        """
        conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
```

- [ ] **Step 2: 编译确认 + Commit**

Run: `swift build --target NippoApp`
Expected: `Build complete!`

```bash
git add -A && git commit -m "feat: loopback caption server (NWListener, 127.0.0.1 only)"
```

---

### Task 5: 日报素材接入 + 设置 + coordinator + 菜单

**Files:**
- Modify: `Sources/NippoCore/Report/PromptBuilder.swift`(factsSection 追加 minutes 参数)
- Modify: `Sources/NippoCore/Report/ReportService.swift`(generateDaily 透传)
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`(captionServerEnabled + port)
- Modify: `Sources/nippo-tests/SettingsTests.swift`/`PromptBuilderTests.swift`(断言)
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Create: `Sources/NippoApp/AppCoordinator+Meeting.swift`
- Modify: `Sources/NippoApp/MenuContentView.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

**先 Read 各既有文件。**

- [ ] **Step 1: 日报素材接入(TDD)**

`PromptBuilderTests.swift` 的「factsSection contains date, notes and events」测试内(既有 checklist 断言之后)追加:

```swift
        let withMinutes = PromptBuilder.factsSection(
            date: tokyoDate(2026, 7, 10, 17, 45),
            notes: notes, events: events,
            meetingMinutes: ["## 決定事項\n- 静止画で進める"],
            calendar: tokyoCalendar)
        T.expect(withMinutes.contains("会議の議事録"), "minutes block header")
        T.expect(withMinutes.contains("静止画で進める"), "minutes content")
```

`PromptBuilder.factsSection` 签名追加参数(在 checklistOpen 之后、calendar 之前):

```swift
                                    meetingMinutes: [String] = [],
```

方法内 checklist 块之后追加:

```swift
        let minutesBlock = meetingMinutes.isEmpty ? "" : """


        ## 本日の会議の議事録
        \(meetingMinutes.joined(separator: "\n\n---\n\n"))
        """
```

并把 return 字符串末尾接上 `\(minutesBlock)`。

`ReportService.generateDaily` 签名追加(checklistOpen 之后、progress 之前):

```swift
                              meetingMinutes: [String] = [],
```

`facts` 构建透传 `meetingMinutes: meetingMinutes`;素材判定行追加 `|| !meetingMinutes.isEmpty`。

- [ ] **Step 2: 设置(TDD)**

`SettingsTests.swift`「defaults and roundtrip」末尾追加:

```swift
        T.expectEqual(s.captionServerEnabled, true)
        T.expectEqual(s.captionServerPort, 8787)
        s.captionServerEnabled = false
        T.expectEqual(AppSettings(defaults: d).captionServerEnabled, false)
```

`AppSettings.swift`(kousuURL 之后)追加:

```swift
    /// Meet 字幕サーバー(Chrome 拡張からの字幕を受ける回環リスナー)
    public var captionServerEnabled: Bool {
        get { d.object(forKey: "captionServerEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "captionServerEnabled"); objectWillChange.send() }
    }

    public var captionServerPort: Int {
        get { d.object(forKey: "captionServerPort") as? Int ?? 8787 }
        set { d.set(newValue, forKey: "captionServerPort"); objectWillChange.send() }
    }
```

- [ ] **Step 3: coordinator 属性 + 服务器起停**

`AppCoordinator.swift`:属性区(punchService 附近)追加:

```swift
    let transcriptService: TranscriptService
    @Published var activeMeetingSession: String?
    @Published var activeMeetingLineCount = 0
    @Published var lastMinutesURL: URL?
    var todayMinutes: [String] = []   // 当日の生成済み議事録(日報素材)
    private var captionServer: CaptionServer?
```

`init()` 中 `punchService = PunchService(db: db)` 之后追加:

```swift
        transcriptService = TranscriptService(db: db)
```

`init()` 末尾(timer 之后)追加:

```swift
        startCaptionServerIfEnabled()
```

- [ ] **Step 4: coordinator 会议扩展**

`Sources/NippoApp/AppCoordinator+Meeting.swift`:

```swift
import AppKit
import Foundation
import NippoCore

extension AppCoordinator {
    func startCaptionServerIfEnabled() {
        guard settings.captionServerEnabled, captionServer == nil else { return }
        let port = UInt16(settings.captionServerPort)
        let server = CaptionServer(port: port) { [weak self] caption in
            self?.receiveCaption(caption)
        }
        server.start()
        captionServer = server
    }

    private func receiveCaption(_ caption: CaptionServer.Caption) {
        try? transcriptService.append(session: caption.session,
                                      speaker: caption.speaker, text: caption.text)
        if activeMeetingSession != caption.session {
            activeMeetingSession = caption.session
            activeMeetingLineCount = 0
        }
        activeMeetingLineCount += 1
    }

    /// 進行中セッションの議事録を生成 → 保存 → 当日の日報素材へ
    func createMinutes() {
        guard let session = activeMeetingSession else { return }
        let root = URL(fileURLWithPath: settings.reportsRoot)
        let customPath = settings.claudePath
        let svc = transcriptService
        statusMessage = "議事録を生成中…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let transcript = try? svc.transcriptText(session: session),
                  !transcript.isEmpty else {
                DispatchQueue.main.async { self?.statusMessage = "字幕がまだありません" }
                return
            }
            let title = session
            var body: String?
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                var cli = ClaudeCLI(executable: exe)
                cli.timeout = 180
                body = try? cli.generate(
                    prompt: MinutesBuilder.prompt(meetingTitle: title, transcript: transcript))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let body, !body.isEmpty else {
                    self.statusMessage = "議事録の生成に失敗しました"
                    NotificationService.shared.notify(title: "議事録の生成に失敗",
                                                      body: "字幕サーバーと claude CLI を確認してください")
                    return
                }
                let dir = root.appendingPathComponent("minutes")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let safe = session.replacingOccurrences(of: "/", with: "・")
                let base = dir.appendingPathComponent("\(DayKey.key(for: Date()))-\(safe).md")
                let url = ReportService.uniqueURL(for: base)
                try? body.write(to: url, atomically: true, encoding: .utf8)
                self.lastMinutesURL = url
                self.todayMinutes.append(body)
                // TODO を当日チェックリストへ
                for todo in MinutesBuilder.extractTodos(body) {
                    self.addChecklistItem(todo)
                }
                self.statusMessage = "議事録を保存しました"
                AppLog.shared.log("minutes", "created for \(session)")
                NotificationService.shared.notify(title: "議事録ができました",
                                                  body: url.lastPathComponent, joinURL: url)
            }
        }
    }
}
```

`generateReport()`(在 `AppCoordinator+Reports.swift`)的 `let events = ...` 行之后追加 `let minutes = todayMinutes`,并把 `generateDaily(...)` 调用追加参数 `meetingMinutes: minutes`。日期变更 tick 块清空:`todayMinutes.removeAll()`、`activeMeetingSession = nil`、`lastMinutesURL = nil`。

- [ ] **Step 5: 菜单 + 设置界面**

`MenuContentView.swift`:在 `meetingsSection` 之后插入 `minutesSection`,并实现(会议进行中或有生成结果时才显示):

```swift
    @ViewBuilder
    private var minutesSection: some View {
        if coordinator.activeMeetingSession != nil || coordinator.lastMinutesURL != nil {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("captions.bubble", "会議の字幕")
                if let session = coordinator.activeMeetingSession {
                    Text("\(session)(\(coordinator.activeMeetingLineCount) 行)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button("議事録を作成") { coordinator.createMinutes() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                if let url = coordinator.lastMinutesURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("議事録を開く", systemImage: "doc.text").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
            }
            .sectionSurface()
        }
    }
```

`SettingsView.swift`:「打刻」Section 之后追加:

```swift
            Section("会議の字幕(Meet)") {
                Toggle("字幕サーバーを起動する(127.0.0.1)", isOn: binding(\.captionServerEnabled))
                Text("Google Meet で字幕を ON にし、Chrome 拡張「nippo-meet」を読み込むと、字幕がここに集まります。音声は一切録音しません。拡張は browser-extension/nippo-meet/ にあります")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

- [ ] **Step 6: 测试 + 打包 + Commit**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 88 tests`(断言增加,测试数不变),`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: caption server wiring, minutes generation, daily-report feed"
```

- [ ] **Step 7: 手动验证清单(跳过并汇报)**

1. 应用启动后 `curl -s -X POST 127.0.0.1:8787/caption -d '{"session":"test","speaker":"田中","text":"確認します"}'` → 返回 204;菜单出现「会議の字幕」区块显示 test(1 行)
2. 再 curl 几条 → 行数增加;点「議事録を作成」→ 数十秒后「議事録を開く」打开 `~/Documents/日報/minutes/…md`,内含決定事項/TODO/議論の要点
3. 生成的 TODO 出现在今日チェックリスト
4. 设置关掉「字幕サーバー」→ 重启后 curl 连接被拒
5. 从外部 IP(非 127.0.0.1)访问端口应失败(仅回環)

---

### Task 6: Chrome 扩展 + README

**Files:**
- Create: `browser-extension/nippo-meet/manifest.json`
- Create: `browser-extension/nippo-meet/content.js`
- Create: `browser-extension/nippo-meet/README.md`
- Modify: `README.md`

- [ ] **Step 1: manifest.json**

`browser-extension/nippo-meet/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "Nippo Meet 字幕キャプチャ",
  "version": "0.1.0",
  "description": "Google Meet の字幕を読み取り、ローカルの Nippo(127.0.0.1)へ送ります。音声は録音しません。",
  "permissions": [],
  "host_permissions": ["https://meet.google.com/*", "http://127.0.0.1/*"],
  "content_scripts": [
    {
      "matches": ["https://meet.google.com/*"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ]
}
```

- [ ] **Step 2: content.js**(仿 meet-dictionary 的字幕抓取:多选择器+末尾差分+说话人)

`browser-extension/nippo-meet/content.js`:

```javascript
// Nippo Meet 字幕キャプチャ:字幕 DOM を監視し、新規発言を 127.0.0.1 の Nippo に送る。
// 音声は一切扱わない。字幕 ON が前提。
(() => {
  "use strict";
  const PORT = 8787;
  const POLL_MS = 700;

  // 会議 URL の /xxx-yyyy-zzz 部分をセッション ID に
  const meetCode = (location.pathname.match(/[a-z]{3,}-[a-z]{3,}-[a-z]{3,}/) || ["meet"])[0];
  const today = new Date().toISOString().slice(0, 10);
  const session = `${today}-${meetCode}`;

  const CAPTION_SELECTORS = [
    'div[jsname="YSxPC"]',
    'div[jsname="dsyhDe"]',
    'div[aria-live="polite"]',
    '[role="region"][aria-label*="aption" i]',
  ];

  // 話者名の候補(字幕行の近傍に出る)
  function readCaptionBlocks() {
    for (const sel of CAPTION_SELECTORS) {
      const nodes = document.querySelectorAll(sel);
      if (!nodes.length) continue;
      const blocks = [];
      nodes.forEach((n) => {
        const text = (n.innerText || "").trim();
        if (text) blocks.push(text);
      });
      if (blocks.length) return blocks;
    }
    return [];
  }

  const lastSent = new Map(); // speaker -> last full text
  function extractDelta(prev, curr) {
    if (!prev) return curr;
    if (curr.startsWith(prev)) return curr.slice(prev.length).trim();
    return curr; // ローリングで先頭が消えた場合は全体を新規扱い
  }

  async function send(speaker, text) {
    try {
      await fetch(`http://127.0.0.1:${PORT}/caption`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session, speaker, text }),
      });
    } catch (_) {
      // Nippo 未起動時は黙って捨てる(次のポーリングで再挑戦)
    }
  }

  function tick() {
    const blocks = readCaptionBlocks();
    for (const block of blocks) {
      // 「話者名\n発言」の形が多い。1 行目を話者、残りを発言とみなす
      const nl = block.indexOf("\n");
      let speaker = "不明";
      let body = block;
      if (nl > 0 && nl < 24) {
        speaker = block.slice(0, nl).trim();
        body = block.slice(nl + 1).trim();
      }
      if (!body || body.length < 2) continue;
      const delta = extractDelta(lastSent.get(speaker) || "", body);
      lastSent.set(speaker, body);
      if (delta && delta.length >= 2) send(speaker, delta);
    }
  }

  setInterval(tick, POLL_MS);
  console.log("[Nippo Meet] capture ready. session:", session);
})();
```

- [ ] **Step 3: 扩展 README + 主 README**

`browser-extension/nippo-meet/README.md`:

```markdown
# Nippo Meet 字幕キャプチャ

Google Meet の字幕を読み取り、ローカルの Nippo(127.0.0.1:8787)へ送る Chrome 拡張。
**音声は録音しません。字幕を ON にした状態でのみ動きます。**

## インストール
1. Chrome で chrome://extensions/ を開く
2. 右上「デベロッパーモード」を ON
3. 「パッケージ化されていない拡張機能を読み込む」→ このフォルダを選択

## 使い方
1. Nippo を起動しておく(字幕サーバーが 127.0.0.1:8787 で待ち受け)
2. Google Meet に参加し、字幕を ON にする
3. 発言が Nippo に集まる。会議後、Nippo メニューの「議事録を作成」を押す

字幕の DOM は Meet の仕様変更で変わることがあります。動かなくなったら content.js の
CAPTION_SELECTORS を更新してください。
```

主 `README.md`「使い方」列表末尾追加:

```markdown
- 会議の字幕: Google Meet で字幕を ON にし、Chrome 拡張 browser-extension/nippo-meet
  を読み込むと発言がローカルに集まる(音声は録音しない)。会議後メニューの
  「議事録を作成」で決定事項/TODO/要点を生成 → 日報素材に。TODO はチェックリストへ
```

- [ ] **Step 4: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 88 tests`

```bash
git add -A && git commit -m "feat: nippo-meet Chrome extension and docs"
```

---

## 后续(不在本计划内)

- 三期 B:録音+本地转写(强制确认门)
- Zoom/Teams 字幕对应(选择器不同)
- 会议 session 与日历事件的自动关联(现按 meet code+日期)
- 「初めて聞いた言葉」ログ(转写×用语集)
