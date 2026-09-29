# 截图自动整理 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自动检测新截图(系统截图文件夹,默认桌面),本地 Vision OCR 读取内容 → Claude(禁网)起 15 字以内的日语描述名 → **重命名留原处**为「YYYY-MM-DD_日本語説明.png」。每 30 秒 tick 扫描,只处理当天的、匹配截图命名模式的文件;OCR 无文字或 CLI 失败时回退「YYYY-MM-DD_スクリーンショット_HHmm.png」。设置里可开关(默认开)。

**Architecture:** `TextRecognizing` 协议 + Vision 实现、`ScreenshotNamer`(prompt/清洗/回退名)、`ScreenshotOrganizer`(扫描/判定/重命名,注入 OCR 与 TextGenerator)进 NippoCore;coordinator 在 tick 接线。截图文件夹从 `defaults read com.apple.screencapture location` 读,失败回退 `~/Desktop`。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(blog 模块合入后应为 **64 tests**;计数不同则按差值顺延 Expected 并在 concerns 说明);分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**,锚点找不到报 BLOCKED。

---

### Task 1: ScreenshotNamer(prompt、清洗、回退名)

**Files:**
- Create: `Sources/NippoCore/Screenshots/ScreenshotNamer.swift`
- Create: `Sources/nippo-tests/ScreenshotNamerTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(最后一个 run 调用后追加 `runScreenshotNamerTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/ScreenshotNamerTests.swift`:

```swift
import Foundation
import NippoCore

func runScreenshotNamerTests() {
    T.run("prompt embeds OCR text and constraints") {
        let p = ScreenshotNamer.prompt(ocrText: "Figma のレイヤーパネル")
        T.expect(p.contains("Figma のレイヤーパネル"), "ocr embedded")
        T.expect(p.contains("15"), "length constraint")
        T.expect(p.contains("ファイル名"), "filename context")
    }

    T.run("sanitize strips forbidden characters and caps length") {
        T.expectEqual(ScreenshotNamer.sanitize("レイヤー/構造:確認 "), "レイヤー・構造・確認")
        let long = String(repeating: "あ", count: 40)
        T.expect(ScreenshotNamer.sanitize(long).count <= 20, "capped")
        T.expectEqual(ScreenshotNamer.sanitize("  \n"), "")
    }

    T.run("filename builds date_description.ext with fallback") {
        let named = ScreenshotNamer.filename(description: "LPの配色比較",
                                             date: tokyoDate(2026, 7, 10, 14, 32),
                                             ext: "png", calendar: tokyoCalendar)
        T.expectEqual(named, "2026-07-10_LPの配色比較.png")
        let fallback = ScreenshotNamer.filename(description: "",
                                                date: tokyoDate(2026, 7, 10, 14, 32),
                                                ext: "png", calendar: tokyoCalendar)
        T.expectEqual(fallback, "2026-07-10_スクリーンショット_1432.png")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'ScreenshotNamer' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Screenshots/ScreenshotNamer.swift`:

```swift
import Foundation

/// スクリーンショットの日本語ファイル名を作る(prompt 組み立てと整形)。
public enum ScreenshotNamer {
    public static func prompt(ocrText: String) -> String {
        """
        以下はスクリーンショットから OCR で読み取ったテキスト。この画像が何のスクリーン
        ショットかを表す、日本語のファイル名向け説明を 15 文字以内で 1 つだけ出力する。

        制約:
        - 出力は説明のみ(前置き・記号・拡張子・引用符なし)
        - 固有のツール名・画面名が読み取れればそれを優先(例: Figmaレイヤー整理)
        - 判別できなければ「画面キャプチャ」とだけ出力

        # OCR テキスト(先頭 1500 字)
        \(String(ocrText.prefix(1500)))
        """
    }

    /// ファイル名に使えない文字を除去し、20 字に丸める
    public static func sanitize(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "・")
            .replacingOccurrences(of: ":", with: "・")
            .replacingOccurrences(of: "\\", with: "・")
            .components(separatedBy: .newlines).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(20))
    }

    /// 「YYYY-MM-DD_説明.ext」。説明が空なら「…_スクリーンショット_HHmm.ext」
    public static func filename(description: String, date: Date, ext: String,
                                calendar: Calendar = .current) -> String {
        let day = DayKey.key(for: date, calendar: calendar)
        let desc = sanitize(description)
        if desc.isEmpty {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%@_スクリーンショット_%02d%02d.%@",
                          day, c.hour!, c.minute!, ext)
        }
        return "\(day)_\(desc).\(ext)"
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 67 tests`(64+3)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: screenshot namer (prompt, sanitize, fallback filename)"
```

---

### Task 2: ScreenshotOrganizer(扫描/判定/重命名)

**Files:**
- Create: `Sources/NippoCore/Screenshots/TextRecognizing.swift`
- Create: `Sources/NippoCore/Screenshots/ScreenshotOrganizer.swift`
- Create: `Sources/nippo-tests/ScreenshotOrganizerTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runScreenshotOrganizerTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/ScreenshotOrganizerTests.swift`:

```swift
import Foundation
import NippoCore

func runScreenshotOrganizerTests() {
    struct FakeOCR: TextRecognizing {
        var text: String
        func recognizeText(at url: URL) -> String { text }
    }
    struct FakeGen: TextGenerator {
        var name: String
        func generate(prompt: String) throws -> String { name }
    }

    func makeDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-ss-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    func touch(_ dir: URL, _ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        try! Data("x".utf8).write(to: url)
        return url
    }

    T.run("renames screenshot-pattern files in place, skips others and processed") {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = touch(dir, "スクリーンショット 2026-07-10 14.32.05.png")
        _ = touch(dir, "截屏2026-07-10 14.33.00.png")
        _ = touch(dir, "設計メモ.png")                       // 非スクショ → 対象外
        _ = touch(dir, "2026-07-10_既に整理済み.png")         // 命名済み → 対象外

        let organizer = ScreenshotOrganizer(
            ocr: FakeOCR(text: "何かのUI"), generator: FakeGen(name: "配色比較"),
            calendar: tokyoCalendar)
        let renamed = organizer.organize(directory: dir,
                                         now: tokyoDate(2026, 7, 10, 15, 0),
                                         maxPerRun: 10)
        T.expectEqual(renamed.count, 2, "two screenshots processed")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        T.expectEqual(names.filter { $0 == "2026-07-10_配色比較.png" }.count, 1)
        T.expect(names.contains("2026-07-10_配色比較-v2.png"),
                 "second gets -v2, got \(names)")
        T.expect(names.contains("設計メモ.png"), "non-screenshot untouched")

        // 再実行しても何も処理されない(命名済みパターンで除外)
        let again = organizer.organize(directory: dir,
                                       now: tokyoDate(2026, 7, 10, 15, 1),
                                       maxPerRun: 10)
        T.expectEqual(again.count, 0, "idempotent")
    }

    T.run("generator failure falls back to time-based name") {
        struct FailGen: TextGenerator {
            func generate(prompt: String) throws -> String {
                throw ClaudeCLI.CLIError.emptyOutput
            }
        }
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = touch(dir, "Screenshot 2026-07-10 at 14.32.05.png")
        let organizer = ScreenshotOrganizer(
            ocr: FakeOCR(text: "x"), generator: FailGen(), calendar: tokyoCalendar)
        let renamed = organizer.organize(directory: dir,
                                         now: tokyoDate(2026, 7, 10, 14, 32),
                                         maxPerRun: 10)
        T.expectEqual(renamed.count, 1)
        T.expect(renamed[0].lastPathComponent.contains("スクリーンショット_1432"),
                 "fallback name, got \(renamed[0].lastPathComponent)")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'ScreenshotOrganizer' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Screenshots/TextRecognizing.swift`:

```swift
import Foundation

public protocol TextRecognizing {
    func recognizeText(at url: URL) -> String
}
```

`Sources/NippoCore/Screenshots/ScreenshotOrganizer.swift`:

```swift
import Foundation

/// 新規スクリーンショットを OCR → 日本語名にリネーム(その場、移動しない)。
public struct ScreenshotOrganizer {
    let ocr: TextRecognizing
    let generator: TextGenerator
    let calendar: Calendar

    public init(ocr: TextRecognizing, generator: TextGenerator,
                calendar: Calendar = .current) {
        self.ocr = ocr
        self.generator = generator
        self.calendar = calendar
    }

    /// macOS 標準・日本語・中国語 UI のスクショ既定名にマッチ
    static let patterns = ["スクリーンショット", "Screenshot", "Screen Shot", "截屏", "截圖"]
    /// 整理済み(YYYY-MM-DD_ 始まり)
    static let organizedPrefix = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}_"#)

    static func isTargetName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        if organizedPrefix.firstMatch(in: name, range: range) != nil { return false }
        return patterns.contains { name.hasPrefix($0) }
    }

    /// directory 直下の当日作成の対象ファイルを最大 maxPerRun 件リネームし、新 URL を返す
    public func organize(directory: URL, now: Date, maxPerRun: Int = 2) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let today = DayKey.key(for: now, calendar: calendar)
        let targets = entries.filter { url in
            guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
            else { return false }
            guard Self.isTargetName(url.lastPathComponent) else { return false }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? .distantPast
            return DayKey.key(for: created, calendar: calendar) == today
        }.prefix(maxPerRun)

        var renamed: [URL] = []
        for url in targets {
            let text = ocr.recognizeText(at: url)
            let description: String
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                description = ""
            } else {
                description = (try? generator.generate(
                    prompt: ScreenshotNamer.prompt(ocrText: text))) ?? ""
            }
            let name = ScreenshotNamer.filename(description: description,
                                                date: now, ext: url.pathExtension,
                                                calendar: calendar)
            let dest = ReportService.uniqueURL(
                for: directory.appendingPathComponent(name))
            if (try? FileManager.default.moveItem(at: url, to: dest)) != nil {
                renamed.append(dest)
            }
        }
        return renamed
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 69 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: screenshot organizer (scan, ocr-name, rename in place)"
```

---

### Task 3: Vision OCR 实现 + coordinator 接线 + 设置

**Files:**
- Create: `Sources/NippoApp/VisionTextRecognizer.swift`
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`(blogRoot 之后追加)
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`
- Modify: `Sources/nippo-tests/SettingsTests.swift`(追加断言)

- [ ] **Step 1: 设置项(先测试后实现,TDD)**

`SettingsTests.swift`「defaults and roundtrip」末尾追加:

```swift
        T.expectEqual(s.screenshotsEnabled, true)
        s.screenshotsEnabled = false
        T.expectEqual(AppSettings(defaults: d).screenshotsEnabled, false)
```

确认失败(`has no member 'screenshotsEnabled'`)后,`AppSettings.swift` 的 `blogRoot` 之后追加:

```swift
    /// スクリーンショットの自動リネーム(その場、日本語名)
    public var screenshotsEnabled: Bool {
        get { d.object(forKey: "screenshotsEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "screenshotsEnabled"); objectWillChange.send() }
    }
```

- [ ] **Step 2: Vision 实现**

`Sources/NippoApp/VisionTextRecognizer.swift`:

```swift
import Foundation
import Vision
import NippoCore

/// Vision による完全ローカル OCR(日本語+英語)。
struct VisionTextRecognizer: TextRecognizing {
    func recognizeText(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        let handler = VNImageRequestHandler(data: data)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 3: coordinator 接线**

`AppCoordinator.swift`(先 Read):属性区(blog 属性之后)追加:

```swift
    private var screenshotBusy = false
    private lazy var screenshotOrganizer = ScreenshotOrganizer(
        ocr: VisionTextRecognizer(),
        generator: {
            var cli = ClaudeCLI(executable: ClaudeCLI.detect(customPath: "")
                ?? URL(fileURLWithPath: "/usr/bin/false"))
            cli.timeout = 60
            return cli
        }())

    /// システムのスクリーンショット保存先(既定: デスクトップ)
    static func screenshotDirectory() -> URL {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        if (try? task.run()) != nil {
            task.waitUntilExit()
            if task.terminationStatus == 0,
               let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) {
                let path = (out.trimmingCharacters(in: .whitespacesAndNewlines)
                    as NSString).expandingTildeInPath
                if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
    }
```

`tick()` 末尾(週報触发块之后)追加:

```swift
        // スクリーンショット自動リネーム(その場)
        if settings.screenshotsEnabled && !screenshotBusy {
            screenshotBusy = true
            let organizer = screenshotOrganizer
            let dir = Self.screenshotDirectory()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let renamed = organizer.organize(directory: dir, now: Date())
                DispatchQueue.main.async {
                    self?.screenshotBusy = false
                    if !renamed.isEmpty {
                        self?.statusMessage =
                            "スクリーンショットを整理: \(renamed.map(\.lastPathComponent).joined(separator: ", "))"
                    }
                }
            }
        }
```

`SettingsView.swift`:「ブログ支援」Section 之后追加:

```swift
            Section("スクリーンショット") {
                Toggle("新しいスクリーンショットを日本語名にリネームする", isOn: binding(\.screenshotsEnabled))
                Text("保存先はそのまま、名前だけ「日付_内容.png」に変わります(OCR はローカル処理)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: 测试 + 打包 + Commit**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 69 tests`,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: automatic screenshot renaming wired into tick with Vision OCR"
```

- [ ] **Step 5: 手动验证清单(跳过并汇报)**

1. 截一张图 → 30 秒内桌面弹「デスクトップフォルダへのアクセス」授权(如出现)→ 文件被改名为「2026-07-10_◯◯.png」且未移动
2. 纯图形截图(无文字)→ 回退名「2026-07-10_スクリーンショット_HHmm.png」
3. 设置关掉开关 → 新截图不再被处理
4. 已整理过的文件不会被二次处理

---

### Task 4: README 更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「使い方」列表末尾追加**

```markdown
- 新しいスクリーンショットは自動で「日付_日本語の内容.png」にリネーム
  (場所はそのまま・OCR はローカルの Vision。設定でオフにできる)
```

- [ ] **Step 2: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 69 tests`

```bash
git add -A && git commit -m "docs: screenshot organizer usage"
```

---

## 后续(不在本计划内)

- 1on1 助手(队列次棒)
- 截图与日报联动(「今日のスクリーンショット」一覧をメニューに出す等)
