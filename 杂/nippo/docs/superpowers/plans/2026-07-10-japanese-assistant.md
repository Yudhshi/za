# 日本語アシスタント(全局润色/中→日翻译)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在任意应用里选中文字 → 按 ⌥⌘P → 自动复制选区 → Claude 润色成自然商务日语(中文则译成日语,套用本地用语集)→ 自动回贴替换选区。

**Architecture:** 纯逻辑(语言判定、prompt 组装、用语集解析)进 `NippoCore/Assistant/`(可测试);CGEvent 模拟 ⌘C/⌘V 和辅助功能授权在 `NippoApp/TextCapture.swift`;AppCoordinator 注册第二个 HotKey 并编排全流程。生成走既有 `ClaudeCLI`。

**Tech Stack:** 既有栈 + ApplicationServices(AXIsProcessTrustedWithOptions)+ CoreGraphics(CGEvent)。

**环境事实(沿用一期计划,勿再验证):** 无 Xcode(测试=`swift run nippo-tests`,当前 35 tests 全绿);仓库 `/Users/lease-emp-mac-yudi-shi/Desktop/杂/nippo` 分支 phase-1;打包 `./build-app.sh`;claude CLI 在 `~/.local/bin/claude`;**绝不启动 GUI 应用**,手动验证项跳过并汇报;提交信息末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。

---

### Task 1: JapaneseAssistant 核心(语言判定 + prompt + 用语集)

**Files:**
- Create: `Sources/NippoCore/Assistant/JapaneseAssistant.swift`
- Create: `Sources/nippo-tests/AssistantTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(`runReminderTests()` 后追加一行 `runAssistantTests()`,保持 `runLinkExtractorTests()` 在其后或其前均可,但两者都必须保留)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/AssistantTests.swift`:

```swift
import Foundation
import NippoCore

func runAssistantTests() {
    T.run("mode detection: kana -> polish, han-only -> translate, ascii -> polish") {
        T.expectEqual(JapaneseAssistant.detectMode(for: "今日は資料を作成しました"), .polish)
        T.expectEqual(JapaneseAssistant.detectMode(for: "テスト"), .polish)
        T.expectEqual(JapaneseAssistant.detectMode(for: "今天完成了设计稿的评审"), .translate)
        T.expectEqual(JapaneseAssistant.detectMode(for: "follow up tomorrow"), .polish)
    }

    T.run("polish prompt embeds tone, constraints and text") {
        let p = JapaneseAssistant.prompt(for: "会議で決めた", mode: .polish,
                                         tone: .internalCasual, glossary: nil)
        T.expect(p.contains("会議で決めた"), "text embedded")
        T.expect(p.contains("意味を変えない"), "no-meaning-change constraint")
        T.expect(p.contains("社内向け"), "tone")
        T.expect(p.contains("修正後のテキストのみ"), "output constraint")
    }

    T.run("translate prompt embeds glossary when present") {
        let p = JapaneseAssistant.prompt(for: "完成了评审", mode: .translate,
                                         tone: .externalPolite,
                                         glossary: "- デザインレビュー: 設計評審の正式表記")
        T.expect(p.contains("日本語に翻訳"), "translate instruction")
        T.expect(p.contains("デザインレビュー"), "glossary embedded")
        T.expect(p.contains("敬語"), "polite tone")
    }

    T.run("glossary loads from file, nil when absent") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-glossary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        T.expectEqual(JapaneseAssistant.loadGlossary(root: dir), nil)
        let file = dir.appendingPathComponent("用語集.md")
        try "- ADR: アーキテクチャ決定記録".write(to: file, atomically: true, encoding: .utf8)
        T.expect(JapaneseAssistant.loadGlossary(root: dir)?.contains("ADR") == true,
                 "glossary content loaded")
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'JapaneseAssistant' in scope`

- [ ] **Step 3: 写实现**

`Sources/NippoCore/Assistant/JapaneseAssistant.swift`:

```swift
import Foundation

/// 選択テキストの日本語化アシスタント:
/// かなを含む → 日本語ブラッシュアップ、漢字のみ(中国語とみなす)→ 日訳。
public enum JapaneseAssistant {
    public enum Mode: Equatable {
        case polish      // 自然なビジネス日本語に整える
        case translate   // 中国語 → 日本語
    }

    public enum Tone: String, CaseIterable {
        case internalCasual = "internalCasual"   // 社内向け(です・ます基調で柔らかく)
        case externalPolite = "externalPolite"   // 社外向け(丁寧な敬語)

        public var label: String {
            switch self {
            case .internalCasual: return "社内向けカジュアル"
            case .externalPolite: return "社外向け丁寧(敬語)"
            }
        }
    }

    public static func detectMode(for text: String) -> Mode {
        let hasKana = text.unicodeScalars.contains {
            (0x3040...0x30FF).contains(Int($0.value))   // ひらがな+カタカナ
        }
        if hasKana { return .polish }
        let hasHan = text.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }
        return hasHan ? .translate : .polish
    }

    /// `<root>/用語集.md` があれば中身を返す(ユーザーが自由に育てるローカル用語集)
    public static func loadGlossary(root: URL) -> String? {
        let file = root.appendingPathComponent("用語集.md")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    public static func prompt(for text: String, mode: Mode, tone: Tone,
                              glossary: String?) -> String {
        let toneLine: String
        switch tone {
        case .internalCasual:
            toneLine = "トーン: 社内向けカジュアル。です・ます基調で柔らかく、堅すぎない"
        case .externalPolite:
            toneLine = "トーン: 社外向け丁寧。正しい敬語で失礼のない文面にする"
        }

        let task: String
        switch mode {
        case .polish:
            task = "以下のテキストを、意味を保ったまま自然で正確なビジネス日本語に直す。"
        case .translate:
            task = "以下の中国語テキストを自然なビジネス日本語に翻訳する。"
        }

        let glossaryBlock = glossary.map {
            """

            # 用語集(以下の正式表記に統一する)
            \($0)
            """
        } ?? ""

        return """
        あなたは日本語ネイティブの編集者。\(task)

        制約:
        - \(toneLine)
        - 意味を変えない。情報を足さない・削らない
        - 元の構造(改行・箇条書き・Markdown)を保つ
        - 出力は修正後のテキストのみ(前置き・後書き・説明・コードブロック囲いは禁止)
        \(glossaryBlock)
        # テキスト
        \(text)
        """
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 39 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: JapaneseAssistant core (mode detection, prompts, local glossary)"
```

---

### Task 2: 设置项(トーン)

**Files:**
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`
- Modify: `Sources/nippo-tests/SettingsTests.swift`

- [ ] **Step 1: 写失败测试**

在 `SettingsTests.swift` 的 `runSettingsTests()` 里「defaults and roundtrip」测试的末尾(`T.expectEqual(s2.lastReportFiredDay, "2026-07-10")` 之后)追加:

```swift
        T.expectEqual(s.assistantTone, "internalCasual")
        s.assistantTone = "externalPolite"
        T.expectEqual(AppSettings(defaults: d).assistantTone, "externalPolite")
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `value of type 'AppSettings' has no member 'assistantTone'`

- [ ] **Step 3: 实现**

`AppSettings.swift` 中 `lastReportFiredDay` 属性之后追加:

```swift
    /// 日本語アシスタントのトーン(JapaneseAssistant.Tone の rawValue)
    public var assistantTone: String {
        get { d.string(forKey: "assistantTone") ?? "internalCasual" }
        set { d.set(newValue, forKey: "assistantTone"); objectWillChange.send() }
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 39 tests`(断言数增加,测试数不变)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: assistantTone setting"
```

---

### Task 3: TextCapture(辅助功能授权 + ⌘C/⌘V 模拟)

**Files:**
- Create: `Sources/NippoApp/TextCapture.swift`

纯系统交互,无法单元测试;以编译通过收尾,行为在 Task 4 的手动清单验证。

- [ ] **Step 1: 写实现**

`Sources/NippoApp/TextCapture.swift`:

```swift
import AppKit
import ApplicationServices

/// 前面アプリの選択テキストを ⌘C 模擬で取得し、変換結果を ⌘V 模擬で書き戻す。
/// CGEvent の投递には「アクセシビリティ」権限が必要。
@MainActor
enum TextCapture {

    /// 権限がなければシステムのプロンプトを出しつつ false を返す
    static func ensureAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 選択テキストを取得。取得できなければ nil。
    /// クリップボードの元の文字列は戻り値と一緒に返す(後で復元するため)。
    static func copySelection() async -> (selection: String, previousClipboard: String?)? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let beforeCount = pb.changeCount

        postKeystroke(keyCode: 8, flags: .maskCommand)   // ⌘C (kVK_ANSI_C = 8)

        // 最大 1 秒、クリップボード更新を待つ
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if pb.changeCount != beforeCount { break }
        }
        guard pb.changeCount != beforeCount,
              let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return (text, previous)
    }

    /// クリップボードに結果を置いて ⌘V を投げ、少し待ってから元の内容を復元する
    static func pasteReplacing(with text: String, restoring previous: String?) async {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        postKeystroke(keyCode: 9, flags: .maskCommand)   // ⌘V (kVK_ANSI_V = 9)

        // 貼り付けが完了するのを待ってから元のクリップボードを復元
        try? await Task.sleep(nanoseconds: 600_000_000)
        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
    }

    private static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: 编译确认**

Run: `swift build --target NippoApp`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: TextCapture with accessibility-gated cmd-C/cmd-V simulation"
```

---

### Task 4: AppCoordinator 编排 + ⌥⌘P 快捷键 + 设置界面加トーン选择

**Files:**
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

- [ ] **Step 1: AppCoordinator 追加**

属性区(`private var hotKey: HotKey?` 之后)追加:

```swift
    private var assistantHotKey: HotKey?
    private var assistantBusy = false
```

`init()` 中现有 hotKey 设置之后追加:

```swift
        assistantHotKey = HotKey(key: .p, modifiers: [.command, .option])
        assistantHotKey?.keyDownHandler = { [weak self] in
            self?.runJapaneseAssistant()
        }
```

类内追加方法:

```swift
    /// ⌥⌘P: 前面アプリの選択テキストを日本語ブラッシュアップ/日訳して書き戻す
    func runJapaneseAssistant() {
        guard !assistantBusy else { return }
        guard TextCapture.ensureAccessibility() else {
            NotificationService.shared.notify(
                title: "アクセシビリティ権限が必要です",
                body: "システム設定 > プライバシーとセキュリティ > アクセシビリティ で Nippo を許可してください")
            return
        }
        assistantBusy = true
        Task { @MainActor in
            defer { assistantBusy = false }
            guard let captured = await TextCapture.copySelection() else {
                NotificationService.shared.notify(
                    title: "選択テキストが見つかりません",
                    body: "変換したいテキストを選択してから ⌥⌘P を押してください")
                return
            }
            let mode = JapaneseAssistant.detectMode(for: captured.selection)
            let tone = JapaneseAssistant.Tone(rawValue: settings.assistantTone) ?? .internalCasual
            let glossary = JapaneseAssistant.loadGlossary(
                root: URL(fileURLWithPath: settings.reportsRoot))
            let prompt = JapaneseAssistant.prompt(
                for: captured.selection, mode: mode, tone: tone, glossary: glossary)
            statusMessage = mode == .translate ? "日本語に翻訳中…" : "日本語を整え中…"

            let customPath = settings.claudePath
            let result: String? = await Task.detached(priority: .userInitiated) {
                guard let exe = ClaudeCLI.detect(customPath: customPath) else { return nil }
                var cli = ClaudeCLI(executable: exe)
                cli.timeout = 120
                return try? cli.generate(prompt: prompt)
            }.value

            guard let result, !result.isEmpty else {
                statusMessage = "変換に失敗しました"
                NotificationService.shared.notify(
                    title: "変換に失敗しました",
                    body: "claude CLI の実行に失敗しました。もう一度お試しください")
                return
            }
            await TextCapture.pasteReplacing(with: result,
                                             restoring: captured.previousClipboard)
            statusMessage = "貼り付けました"
        }
    }
```

- [ ] **Step 2: SettingsView 追加トーン选择**

`SettingsView.swift` 的 `Section("Claude CLI")` 之前插入:

```swift
            Section("日本語アシスタント (⌥⌘P)") {
                Picker("トーン", selection: binding(\.assistantTone)) {
                    ForEach(JapaneseAssistant.Tone.allCases, id: \.rawValue) { tone in
                        Text(tone.label).tag(tone.rawValue)
                    }
                }
                Text("任意のアプリでテキストを選択して ⌥⌘P → 自然な日本語に置き換わります。中国語は日本語に翻訳されます。用語集: 保存先フォルダの「用語集.md」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 3: 全量测试 + 构建**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 39 tests`,构建成功

- [ ] **Step 4: 手动验证清单(跳过并汇报)**

1. `open dist/Nippo.app` → 在任意应用选中一段日语按 ⌥⌘P → 首次弹辅助功能引导通知 → 系统设置里勾选 Nippo → 再按 ⌥⌘P → 数秒后选区被替换为润色后的日语,剪贴板恢复原内容
2. 选中一段中文按 ⌥⌘P → 被替换为日语翻译
3. 什么都不选按 ⌥⌘P → 通知「選択テキストが見つかりません」
4. 在保存先フォルダ放一个 `用語集.md` 写入术语 → 翻译时正式表记生效
5. 設定窗口出现「日本語アシスタント」区块,トーン切换持久化

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: opt-cmd-P Japanese assistant with tone setting"
```

---

### Task 5: README 更新

**Files:**
- Modify: `README.md`(「使い方」小节 ⌥⌘N 行之后追加一行)

- [ ] **Step 1: 追加使用说明**

在 README「使い方」列表 `- ⌥⌘N: ...` 行后追加:

```markdown
- ⌥⌘P: 選択テキストを自然な日本語に(中国語は日訳)。要アクセシビリティ権限。
  用語集: 保存先フォルダの「用語集.md」に正式表記を書くと統一される
```

- [ ] **Step 2: 全量确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 39 tests`

```bash
git add -A && git commit -m "docs: Japanese assistant usage"
```

---

## 后续(不在本计划内)

- 用语集接 Notion(需要向运营申请正规 token,不复用泄漏的 token)
- 快捷键自定义(与 ⌥⌘N 一起,待引入 KeyboardShortcuts 库时统一解决)
- 今日のチェックリスト、截图整理、1on1 助手(按序另立计划)
