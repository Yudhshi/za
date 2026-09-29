# ブログ支援(トピックハンター + 1条ドラフト)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 两个菜单按钮:①「ブログ:トピックを探す」——联网(WebSearch/WebFetch)扫描设计话题 + 本月日报「学び」积累,产出候补清单到 `~/gp blog/topics/`;②「ブログ:1条を書く」——输入窗(话题+素材)→ 联网一次情报裏取り → 按 `~/gp blog/` 的规则文件(运行时读取)起草 400〜500 字の 1条 → 三视角对抗 review → 合并,产出到 `~/gp blog/outputs/drafts/`。**两个功能均只手动触发,绝不自动**(规格 §10-6)。

**Architecture:** ClaudeCLI 增加 research 模式(允许指定 `--tools "WebSearch,WebFetch"`,默认仍全禁);BlogRules(运行时读 gp blog 的 5 个规则文件)、ManabiDigest(抽取本月日报の学び)、TopicHunter、BlogDraftService(6 段流水线:裏取り→起草→review×3→合并)进 NippoCore;输入窗与编排进 NippoApp。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(週報功能合入后应为 **56 tests**;若实际计数不同,按差值顺延 Expected 并在 concerns 说明);仓库分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**。ブログ規則源=`/Users/lease-emp-mac-yudi-shi/gp blog/`(CLAUDE.md, reference/tonmana.md, reference/checklist.md, reference/anti-patterns.md, reference/examples-gold.md——先亲自读一遍再动工)。

---

### Task 1: ClaudeCLI research 模式(可选放开网络工具)

**Files:**
- Modify: `Sources/NippoCore/Claude/ClaudeCLI.swift`
- Modify: `Sources/nippo-tests/ClaudeCLITests.swift`
- Modify: `Sources/nippo-tests/main.swift` 不变(测试加在既有 runClaudeCLITests 内)

- [ ] **Step 1: 写失败测试**

`ClaudeCLITests.swift` 的 `runClaudeCLITests()` 末尾追加两个测试(fake 脚本改为回显参数以便断言 argv):

```swift
    T.run("default mode disables all tools") {
        let fake = try makeFakeCLI(script: #"echo "ARGS:$@"; cat > /dev/null"#)
        let cli = ClaudeCLI(executable: fake)
        let out = try cli.generate(prompt: "x")
        T.expect(out.contains(#"--tools"#) && out.contains("ARGS:"), "argv echoed")
        T.expect(!out.contains("WebSearch"), "no web tools by default")
    }

    T.run("research mode passes WebSearch,WebFetch and keeps strict-mcp") {
        let fake = try makeFakeCLI(script: #"echo "ARGS:$@"; cat > /dev/null"#)
        var cli = ClaudeCLI(executable: fake)
        cli.allowedTools = ["WebSearch", "WebFetch"]
        let out = try cli.generate(prompt: "x")
        T.expect(out.contains("WebSearch,WebFetch"), "web tools enabled, got \(out)")
        T.expect(out.contains("--strict-mcp-config"), "mcp still excluded")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `has no member 'allowedTools'` 编译错误

- [ ] **Step 3: 实现**

`ClaudeCLI.swift`:在 `public var timeout: TimeInterval = 300` 之后追加:

```swift
    /// 許可するツール。nil または空 = 全ツール無効(既定・日報等の生成用)。
    /// ブログのトピック探索・裏取りだけ ["WebSearch", "WebFetch"] を渡す(仕様 §10-6:
    /// プロンプトに個人・社内データを含めない用途に限る)。
    public var allowedTools: [String]?
```

`generate(prompt:)` 内构建 arguments 的部分改为:

```swift
        let toolsValue = (allowedTools?.isEmpty == false)
            ? allowedTools!.joined(separator: ",")
            : ""
        p.arguments = ["-p", "--output-format", "text",
                       "--tools", toolsValue, "--strict-mcp-config"]
```

(原来的固定 arguments 行删除;注释保留并补充 research 例外说明)

- [ ] **Step 4: 跑测试确认通过 + 真机冒烟**

Run: `swift run nippo-tests`
Expected: `PASS: 58 tests`(56+2)

Run: `echo "2026年7月のデザイン系の大きなニュースを1件、一次情報URL付きで1行で" | /Users/lease-emp-mac-yudi-shi/.local/bin/claude -p --output-format text --tools "WebSearch,WebFetch" --strict-mcp-config`
Expected: 返回含 URL 的一行(证明 CLI 网络工具可用;若参数报错,修正实现与该命令一致并重跑)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClaudeCLI research mode with opt-in web tools"
```

---

### Task 2: BlogRules(运行时读规则)+ ManabiDigest(本月学び抽取)

**Files:**
- Create: `Sources/NippoCore/Blog/BlogRules.swift`
- Create: `Sources/NippoCore/Blog/ManabiDigest.swift`
- Create: `Sources/nippo-tests/BlogRulesTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runBlogRulesTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/BlogRulesTests.swift`:

```swift
import Foundation
import NippoCore

func runBlogRulesTests() {
    T.run("BlogRules loads and concatenates rule files, nil if core missing") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-blog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        T.expectEqual(BlogRules.load(blogRoot: root), nil)

        let ref = root.appendingPathComponent("reference")
        try FileManager.default.createDirectory(at: ref, withIntermediateDirectories: true)
        try "# ガイド本文".write(to: root.appendingPathComponent("CLAUDE.md"),
                             atomically: true, encoding: .utf8)
        try "# トンマナ本文".write(to: ref.appendingPathComponent("tonmana.md"),
                              atomically: true, encoding: .utf8)
        try "# チェック本文".write(to: ref.appendingPathComponent("checklist.md"),
                              atomically: true, encoding: .utf8)
        let rules = BlogRules.load(blogRoot: root)
        T.expect(rules?.contains("ガイド本文") == true, "CLAUDE.md loaded")
        T.expect(rules?.contains("トンマナ本文") == true, "tonmana loaded")
        T.expect(rules?.contains("チェック本文") == true, "checklist loaded")
    }

    T.run("ManabiDigest extracts 学び sections from month's reports") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-mb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = ReportService.baseReportURL(root: root,
                                              for: tokyoDate(2026, 7, 3),
                                              calendar: tokyoCalendar)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ## 01 ／ 今日のこと
        - 何かをした
        ## 03 ／ 学び
        - 速度感は差で生まれる
        ## 04 ／ 明日
        - 次のこと
        """.write(to: url, atomically: true, encoding: .utf8)

        let digest = ManabiDigest.collect(root: root,
                                          month: tokyoDate(2026, 7, 10),
                                          calendar: tokyoCalendar)
        T.expect(digest.contains("速度感は差で生まれる"), "manabi extracted")
        T.expect(!digest.contains("次のこと"), "other sections excluded")
        T.expect(digest.contains("2026-07-03"), "dated")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'BlogRules' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Blog/BlogRules.swift`:

```swift
import Foundation

/// ブログ執筆規則をユーザーの gp blog 作業ディレクトリから実行時に読む。
/// 規則はチームが更新し続けるため、アプリ内に複製しない(仕様 §10-6)。
public enum BlogRules {
    public static let defaultBlogRoot =
        ("~/gp blog" as NSString).expandingTildeInPath

    /// CLAUDE.md + reference/ の規則を連結して返す。
    /// CLAUDE.md か tonmana.md が無ければ nil(規則なしで書くことは許さない)。
    public static func load(blogRoot: URL) -> String? {
        func read(_ rel: String) -> String? {
            try? String(contentsOf: blogRoot.appendingPathComponent(rel),
                        encoding: .utf8)
        }
        guard let guide = read("CLAUDE.md"),
              let tonmana = read("reference/tonmana.md") else { return nil }
        var parts = [
            "# 執筆ガイド(CLAUDE.md)\n\(guide)",
            "# トンマナ仕様\n\(tonmana)",
        ]
        if let checklist = read("reference/checklist.md") {
            parts.append("# 入稿前チェックリスト\n\(checklist)")
        }
        if let anti = read("reference/anti-patterns.md") {
            parts.append("# アンチパターン(Before/After)\n\(anti)")
        }
        if let gold = read("reference/examples-gold.md") {
            parts.append("# 実物のお手本\n\(gold)")
        }
        return parts.joined(separator: "\n\n---\n\n")
    }
}
```

`Sources/NippoCore/Blog/ManabiDigest.swift`:

```swift
import Foundation

/// 当月の日報から「学び」セクションを日付付きで抽出する(トピック探索の内部素材)。
public enum ManabiDigest {
    public static func collect(root: URL, month: Date,
                               calendar: Calendar = .current) -> String {
        guard let interval = calendar.dateInterval(of: .month, for: month)
        else { return "" }
        var lines: [String] = []
        var day = interval.start
        while day < interval.end {
            let url = ReportService.baseReportURL(root: root, for: day,
                                                  calendar: calendar)
            if let body = try? String(contentsOf: url, encoding: .utf8),
               let manabi = extractManabi(from: body) {
                lines.append("### \(DayKey.key(for: day, calendar: calendar))\n\(manabi)")
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day)
            else { break }
            day = next
        }
        return lines.joined(separator: "\n\n")
    }

    /// 「学び」見出し(## 03 ／ 学び 等)から次の ## 見出しまでを抜き出す
    static func extractManabi(from body: String) -> String? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var collecting = false
        var result: [String] = []
        for line in lines {
            if line.hasPrefix("##") {
                if collecting { break }
                if line.contains("学び") { collecting = true; continue }
            } else if collecting {
                result.append(String(line))
            }
        }
        let text = result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 60 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: blog rules runtime loader and monthly manabi digest"
```

---

### Task 3: TopicHunter(候补清单生成)

**Files:**
- Create: `Sources/NippoCore/Blog/TopicHunter.swift`
- Create: `Sources/nippo-tests/TopicHunterTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runTopicHunterTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/TopicHunterTests.swift`:

```swift
import Foundation
import NippoCore

func runTopicHunterTests() {
    T.run("hunt prompt embeds month, manabi digest, and output shape") {
        let p = TopicHunter.prompt(monthLabel: "2026年7月",
                                   manabiDigest: "### 2026-07-03\n- 速度感の学び")
        T.expect(p.contains("2026年7月"), "month")
        T.expect(p.contains("速度感の学び"), "manabi embedded")
        T.expect(p.contains("一次情報"), "primary-source requirement")
        T.expect(p.contains("WebSearch"), "instructs web search usage")
        T.expect(p.contains("自分の実践"), "own-practice angle")
    }

    T.run("hunt writes candidates file under gp blog/topics") {
        struct FakeGen: TextGenerator {
            func generate(prompt: String) throws -> String { "# 候補リスト" }
        }
        let blogRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-th-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blogRoot) }
        let url = try TopicHunter.hunt(generator: FakeGen(),
                                       blogRoot: blogRoot,
                                       reportsRoot: blogRoot, // 学びなしでも動く
                                       now: tokyoDate(2026, 7, 10),
                                       calendar: tokyoCalendar)
        T.expect(url.path.contains("topics"), "topics dir")
        T.expect(url.lastPathComponent.hasPrefix("2026-07"), "month-stamped name")
        T.expectEqual(try String(contentsOf: url, encoding: .utf8), "# 候補リスト")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'TopicHunter' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Blog/TopicHunter.swift`:

```swift
import Foundation

/// 月刊まとめ用のトピック候補リストを生成する(手動トリガー限定・Web ツール使用)。
public enum TopicHunter {
    public static func prompt(monthLabel: String, manabiDigest: String) -> String {
        """
        あなたは Goodpatch Blog 月刊連載「新しいものが大好きなGoodpatchで◯月話題になった
        アプリ、サービス、デザインまとめ」のトピックリサーチャー。WebSearch / WebFetch を
        使って、\(monthLabel)のブログ候補トピックを 8〜12 件挙げる。

        # 進め方
        1. まず下の「自分の実践からの学び」を読み、記事に育てられそうなテーマを拾う
           (自分の実践から書けるテーマを最優先。無ければ無理に作らない)
        2. 次に WebSearch で\(monthLabel)のデザイン・プロダクト・AI 関連の話題を探す
           (公式発表・一次報道を優先。個人ブログの又聞きは不可)
        3. 各候補は一次情報 URL を WebFetch で開いて実在と内容を確認してから載せる

        # 出力形式(Markdown、この形式のみ)
        ## 候補 n: (見出し案。「気づき」+「具体題」の和文寄り)
        - なぜ今: (1〜2行)
        - 一次情報: (確認済み URL)
        - カテゴリ: AI / サービス・プロダクト / ビジネス / イベント のいずれか
        - デザインの切り口: (デザイナーが明日の設計で意識できる粒度で 1〜2 行)
        - 自分の実践との接点: (下の学びと繋がる場合のみ。無ければ「なし」)

        # 制約
        - 確認できなかった話題は載せない。政治的にセンシティブな断定はしない
        - 出力は候補リストのみ。前置き・後書き禁止

        # 自分の実践からの学び(当月の日報より)
        \(manabiDigest.isEmpty ? "(当月の学びの記録なし)" : manabiDigest)
        """
    }

    /// 実行して候補ファイルを書き、URL を返す
    public static func hunt(generator: TextGenerator, blogRoot: URL,
                            reportsRoot: URL, now: Date,
                            calendar: Calendar = .current) throws -> URL {
        let c = calendar.dateComponents([.year, .month], from: now)
        let monthLabel = "\(c.year!)年\(c.month!)月"
        let digest = ManabiDigest.collect(root: reportsRoot, month: now,
                                          calendar: calendar)
        let body = try generator.generate(
            prompt: prompt(monthLabel: monthLabel, manabiDigest: digest))

        let dir = blogRoot.appendingPathComponent("topics")
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let base = dir.appendingPathComponent(
            String(format: "%04d-%02d-トピック候補.md", c.year!, c.month!))
        let url = ReportService.uniqueURL(for: base)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 62 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: blog topic hunter with web research prompt"
```

---

### Task 4: BlogDraftService(裏取り→起草→review×3→合并)

**Files:**
- Create: `Sources/NippoCore/Blog/BlogDraftService.swift`
- Create: `Sources/nippo-tests/BlogDraftTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runBlogDraftTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/BlogDraftTests.swift`:

```swift
import Foundation
import NippoCore

func runBlogDraftTests() {
    T.run("draft pipeline: verify, draft, 3 reviews, merge; file written") {
        final class SeqGen: TextGenerator {
            var prompts: [String] = []
            func generate(prompt: String) throws -> String {
                prompts.append(prompt)
                return "B出力\(prompts.count)"
            }
        }
        let blogRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-bd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blogRoot) }
        // 規則ファイル最小セット
        let ref = blogRoot.appendingPathComponent("reference")
        try FileManager.default.createDirectory(at: ref, withIntermediateDirectories: true)
        try "ガイド規則文".write(to: blogRoot.appendingPathComponent("CLAUDE.md"),
                            atomically: true, encoding: .utf8)
        try "トンマナ規則文".write(to: ref.appendingPathComponent("tonmana.md"),
                             atomically: true, encoding: .utf8)

        let gen = SeqGen()
        let svc = BlogDraftService(researcher: gen, writer: gen, blogRoot: blogRoot)
        var stages: [String] = []
        let url = try svc.draft(topic: "Claude Fable 5 のニュース",
                                material: "渡された要約テキスト",
                                sourceURL: "https://example.com/news",
                                progress: { stages.append($0) })

        T.expectEqual(gen.prompts.count, 6, "verify + draft + 3 reviews + merge")
        T.expect(gen.prompts[0].contains("一次情報") && gen.prompts[0].contains("example.com"),
                 "verify prompt has source")
        T.expect(gen.prompts[1].contains("B出力1") && gen.prompts[1].contains("トンマナ規則文"),
                 "draft sees verified facts and rules")
        T.expect(gen.prompts[5].contains("B出力3"), "merge sees reviews")
        T.expectEqual(stages.count, 6)
        T.expect(url.path.contains("outputs/drafts"), "drafts dir")
        T.expectEqual(try String(contentsOf: url, encoding: .utf8), "B出力6")
    }

    T.run("draft throws when rules missing") {
        struct NopGen: TextGenerator {
            func generate(prompt: String) throws -> String { "x" }
        }
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-bd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: empty) }
        let svc = BlogDraftService(researcher: NopGen(), writer: NopGen(),
                                   blogRoot: empty)
        do {
            _ = try svc.draft(topic: "t", material: nil, sourceURL: nil, progress: nil)
            T.expect(false, "should throw")
        } catch BlogDraftService.DraftError.rulesNotFound {
            // expected
        }
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'BlogDraftService' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Blog/BlogDraftService.swift`:

```swift
import Foundation

/// ブログ 1条の生成:一次情報裏取り(Web可) → 規則準拠の起草 → 観点別レビュー×3 →
/// 回源検証つき最終仕上げ。CLAUDE.md の三原則(裏取り/デザインの具体/問いに答え切る)を
/// パイプラインとして実装する。
public struct BlogDraftService {
    public enum DraftError: Error {
        case rulesNotFound
    }

    let researcher: TextGenerator   // Web ツール有効の CLI(裏取り用)
    let writer: TextGenerator       // ツール無効の CLI(起草・レビュー・合併用)
    let blogRoot: URL

    public init(researcher: TextGenerator, writer: TextGenerator, blogRoot: URL) {
        self.researcher = researcher
        self.writer = writer
        self.blogRoot = blogRoot
    }

    static let reviewLenses: [(key: String, instruction: String)] = [
        ("トンマナ適合", """
        トンマナ仕様・アンチパターン・実物のお手本と突き合わせ、書き出し(印象派の断片禁止)、
        転換句、結び(詰問・反語禁止)、一文の長さ、裸の英単語、平易な概念語への着地、
        話者の立ち位置のズレを指摘する。
        """),
        ("事実忠実", """
        本文を「確認済み事実メモ」と突き合わせ、メモにない事実・数字の記載、未確認事項の断定、
        別々の事象の混同、出典行が一次情報を指していない問題を指摘する。捏造は必ず high。
        """),
        ("チェックリスト", """
        入稿前チェックリストを一項目ずつ通し、落ちる項目を列挙する。特に「立てた問いに
        本文で具体的に答えているか」「デザインの具体に着地しているか」「400〜500字/3〜4段か」。
        """),
    ]

    public func draft(topic: String, material: String?, sourceURL: String?,
                      progress: ((String) -> Void)? = nil) throws -> URL {
        guard let rules = BlogRules.load(blogRoot: blogRoot) else {
            throw DraftError.rulesNotFound
        }

        // 1. 裏取り(Web)
        progress?("一次情報で裏取り中…(1/6)")
        let verifyPrompt = """
        あなたはニュースのファクトチェッカー。次のトピックについて、公式発表・公式ドキュメント・
        一次報道を WebSearch / WebFetch で確認し、「確認済み事実メモ」を作る。

        # トピック
        \(topic)

        # 渡された素材(要約。一次情報と食い違う可能性がある)
        \(material?.isEmpty == false ? material! : "(なし)")

        # 出典候補
        \(sourceURL?.isEmpty == false ? sourceURL! : "(なし。自分で一次情報を探す)")

        # 出力形式
        ## 確認済み事実(それぞれに確認元 URL を付す)
        ## 渡された素材との食い違い(あれば。なければ「なし」)
        ## 確認できなかった点(断定してはいけない事項)
        ## 一次情報リンク(出典行に使う本命 URL)
        """
        let facts = try researcher.generate(prompt: verifyPrompt)

        // 2. 起草
        progress?("1条を起草中…(2/6)")
        let draftPrompt = """
        あなたは Goodpatch Blog 月刊まとめの執筆者。以下の規則に完全準拠して、
        まとめ記事の「1条」(見出し+出典行+本文 400〜500 字/3〜4 段)を書く。

        # 執筆規則(絶対厳守)
        \(rules)

        # 確認済み事実メモ(本文で使ってよい事実はここにあるものだけ。
        「食い違い」「確認できなかった点」の内容は本文に書かない)
        \(facts)

        出力は 1条の Markdown のみ(見出し行 → 出典行 → 本文)。前置き・後書き禁止。
        """
        let draftText = try writer.generate(prompt: draftPrompt)

        // 3. レビュー×3
        var reviews: [(key: String, findings: String)] = []
        for (i, lens) in Self.reviewLenses.enumerated() {
            progress?("レビュー中(\(lens.key))…(\(i + 3)/6)")
            let findings = try writer.generate(prompt: """
            あなたはブログ 1条のレビュアー。観点は「\(lens.key)」のみ。

            # 指摘対象
            \(lens.instruction)

            # 出力形式
            - [high|low] 「該当箇所の引用」→ 問題点 → 修正案(なければ「指摘なし」)

            # 執筆規則
            \(rules)

            # 確認済み事実メモ
            \(facts)

            # 下書き
            \(draftText)
            """)
            reviews.append((key: lens.key, findings: findings))
        }

        // 4. 合併
        progress?("最終版に仕上げ中…(6/6)")
        let reviewBlocks = reviews.map { "## 観点: \($0.key)\n\($0.findings)" }
            .joined(separator: "\n\n")
        let body = try writer.generate(prompt: """
        あなたはブログ 1条の最終仕上げ担当。下書きにレビュー指摘を反映して最終版を作る。

        # 指摘の採用規則(最重要)
        - レビュアー自身も幻覚を起こす。high 指摘は採用前に「確認済み事実メモ」と
          突き合わせて根拠を検証する。メモに実在する記述への「捏造」指摘は棄却する
        - 反映の際も、メモにない事実・数字を新たに書かない

        # 執筆規則
        \(rules)

        # 確認済み事実メモ
        \(facts)

        # 下書き
        \(draftText)

        # レビュー指摘
        \(reviewBlocks)

        # 出力形式
        1 行目から次の HTML コメントブロック:
        <!--
        要確認:
        - (素材との食い違い・確認できなかった点があればここに転記。なければ「なし」)
        - 入稿前に examples-gold の実物と並べて音読すること
        -->
        その直後に 1条の Markdown(見出し → 出典行 → 本文)。それ以外は禁止。
        """)

        // 5. 保存
        let dir = blogRoot.appendingPathComponent("outputs/drafts")
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let slug = topic.prefix(24)
            .replacingOccurrences(of: "/", with: "・")
            .replacingOccurrences(of: " ", with: "")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let base = dir.appendingPathComponent("\(df.string(from: Date()))-\(slug).md")
        let url = ReportService.uniqueURL(for: base)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 64 tests`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: blog draft pipeline (verify, draft, 3-lens review, merge)"
```

---

### Task 5: UI 与编排(菜单区块 + 话题输入窗 + 设置)

**Files:**
- Create: `Sources/NippoApp/BlogDraftWindow.swift`
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Modify: `Sources/NippoApp/MenuContentView.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

**先 Read 三个既有文件。**

- [ ] **Step 1: 话题输入窗**

`Sources/NippoApp/BlogDraftWindow.swift`(仿 SupplementWindowController 结构):

```swift
import AppKit
import SwiftUI

/// ブログ 1条の入力ウィンドウ:トピック+出典URL+素材(任意)。
@MainActor
final class BlogDraftWindowController {
    private var window: NSWindow?
    private let onGenerate: (_ topic: String, _ sourceURL: String?, _ material: String?) -> Void

    init(onGenerate: @escaping (String, String?, String?) -> Void) {
        self.onGenerate = onGenerate
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "ブログ 1条を書く"
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: BlogDraftView(
            onGenerate: { [weak self] topic, url, material in
                self?.onGenerate(topic, url, material)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    private func close() {
        window?.close()
        window = nil
    }
}

private struct BlogDraftView: View {
    let onGenerate: (String, String?, String?) -> Void
    let onCancel: () -> Void
    @State private var topic = ""
    @State private var sourceURL = ""
    @State private var material = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("どのトピックで 1条を書きますか?").font(.headline)
            TextField("トピック(例: Claude Fable 5、提供3日でアクセス停止)", text: $topic)
                .textFieldStyle(.roundedBorder)
            TextField("一次情報 URL(あれば。無ければ自動で探します)", text: $sourceURL)
                .textFieldStyle(.roundedBorder)
            Text("渡された素材・要約(任意。一次情報と食い違えば「要確認」に出ます)")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $material)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("キャンセル") { onCancel() }
                Spacer()
                Button("裏取りして生成") {
                    onGenerate(
                        topic.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceURL.isEmpty ? nil : sourceURL,
                        material.isEmpty ? nil : material)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 2: AppCoordinator 编排**

属性区追加(weekly 属性之后):

```swift
    @Published var isHuntingTopics = false
    @Published var isBlogDrafting = false
    @Published var lastTopicsURL: URL?
    @Published var lastBlogDraftURL: URL?
    private lazy var blogDraftWindow = BlogDraftWindowController { [weak self] topic, url, material in
        self?.generateBlogDraft(topic: topic, sourceURL: url, material: material)
    }
```

方法区追加(weekly 方法之后):

```swift
    private func blogRootURL() -> URL {
        URL(fileURLWithPath: settings.blogRoot)
    }

    func huntBlogTopics() {
        guard !isHuntingTopics else { return }
        isHuntingTopics = true
        statusMessage = "トピックを探しています…(数分かかります)"
        let blogRoot = blogRootURL()
        let reportsRoot = URL(fileURLWithPath: settings.reportsRoot)
        let customPath = settings.claudePath

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<URL, Error>
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                var cli = ClaudeCLI(executable: exe)
                cli.allowedTools = ["WebSearch", "WebFetch"]
                cli.timeout = 600
                result = Result {
                    try TopicHunter.hunt(generator: cli, blogRoot: blogRoot,
                                         reportsRoot: reportsRoot, now: Date())
                }
            } else {
                result = .failure(ClaudeCLI.CLIError.exited(
                    code: -1, stderr: "claude CLI が見つかりません"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isHuntingTopics = false
                switch result {
                case .success(let url):
                    self.statusMessage = "トピック候補を保存しました"
                    self.lastTopicsURL = url
                    NotificationService.shared.notify(
                        title: "ブログのトピック候補ができました",
                        body: url.lastPathComponent)
                case .failure(let error):
                    self.statusMessage = "エラー: \(error.localizedDescription)"
                    NotificationService.shared.notify(
                        title: "トピック探索に失敗", body: error.localizedDescription)
                }
            }
        }
    }

    func startBlogDraftFlow() {
        blogDraftWindow.show()
    }

    func generateBlogDraft(topic: String, sourceURL: String?, material: String?) {
        guard !isBlogDrafting else { return }
        isBlogDrafting = true
        statusMessage = "ブログ 1条を生成中…"
        let blogRoot = blogRootURL()
        let customPath = settings.claudePath

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<URL, Error>
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                var researcher = ClaudeCLI(executable: exe)
                researcher.allowedTools = ["WebSearch", "WebFetch"]
                researcher.timeout = 600
                var writer = ClaudeCLI(executable: exe)
                writer.timeout = 180
                let svc = BlogDraftService(researcher: researcher, writer: writer,
                                           blogRoot: blogRoot)
                result = Result {
                    try svc.draft(topic: topic, material: material,
                                  sourceURL: sourceURL,
                                  progress: { stage in
                        DispatchQueue.main.async { [weak self] in
                            self?.statusMessage = stage
                        }
                    })
                }
            } else {
                result = .failure(ClaudeCLI.CLIError.exited(
                    code: -1, stderr: "claude CLI が見つかりません"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBlogDrafting = false
                switch result {
                case .success(let url):
                    self.statusMessage = "1条ドラフトを保存しました"
                    self.lastBlogDraftURL = url
                    NotificationService.shared.notify(
                        title: "ブログ 1条のドラフト完成",
                        body: "要確認を見てから入稿してください: \(url.lastPathComponent)")
                case .failure(let error):
                    self.statusMessage = "エラー: \(error.localizedDescription)"
                    NotificationService.shared.notify(
                        title: "1条生成に失敗", body: error.localizedDescription)
                }
            }
        }
    }
```

`AppSettings.swift`(`weeklyTimeComponents()` 之后)追加:

```swift
    /// gp blog 作業ディレクトリ(規則ファイルと出力先)
    public var blogRoot: String {
        get { d.string(forKey: "blogRoot") ?? BlogRules.defaultBlogRoot }
        set { d.set(newValue, forKey: "blogRoot"); objectWillChange.send() }
    }
```

- [ ] **Step 3: 菜单与设置**

`MenuContentView.swift`:「週報を生成」块之后追加:

```swift
            Divider()

            Text("ブログ").font(.caption).foregroundStyle(.secondary)
            Button(coordinator.isHuntingTopics ? "トピックを探しています…" : "ブログ:トピックを探す") {
                coordinator.huntBlogTopics()
            }
            .disabled(coordinator.isHuntingTopics)
            if let url = coordinator.lastTopicsURL {
                Button("候補リストを開く") { NSWorkspace.shared.open(url) }
            }
            Button(coordinator.isBlogDrafting ? "1条を生成中…" : "ブログ:1条を書く") {
                coordinator.startBlogDraftFlow()
            }
            .disabled(coordinator.isBlogDrafting)
            if let url = coordinator.lastBlogDraftURL {
                Button("ドラフトを開く") { NSWorkspace.shared.open(url) }
            }
```

同文件:チェックリスト空状态文案改为跟随设置(顺手修已记录的小尾巴)。找到:

```swift
                Text("まだありません(朝 9:00 に自動生成/下で追加)")
```

改为:

```swift
                Text("まだありません(朝 \(coordinator.settings.checklistTime) に自動生成/下で追加)")
```

`SettingsView.swift`:「週振り返り」Section 之后追加:

```swift
            Section("ブログ支援") {
                TextField("gp blog フォルダ", text: binding(\.blogRoot))
                Text("トピック探索と 1条執筆はメニューから手動でのみ実行されます。この 2 機能だけ Web 検索(WebSearch/WebFetch)を使います。日報・週報の生成は引き続きオフラインの文字生成のみです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: 测试 + 打包 + Commit**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 64 tests`,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: blog menu section, topic hunter and draft flow wiring"
```

- [ ] **Step 5: 手动验证清单(跳过并汇报)**

1. 菜单出现「ブログ」区块两个按钮
2. 「トピックを探す」→ 状态显示探索中(数分)→ 通知 →「候補リストを開く」打开 `~/gp blog/topics/2026-07-トピック候補.md`,内容含一次情报 URL 与「自分の実践との接点」
3. 「1条を書く」→ 输入窗(トピック必填,URL/素材任意)→ 生成 → 打开 drafts 下的 1条,开头有要確認块,本文 400〜500 字です・ます
4. 设置里「ブログ支援」区块显示且路径可改

---

### Task 6: README + 规格更新

**Files:**
- Modify: `README.md`(「使い方」列表末尾追加)

- [ ] **Step 1: 追加**

```markdown
- メニューの「ブログ」から手動で:トピック探索(Web 検索で候補リストを
  `~/gp blog/topics/` に生成)と 1条執筆(一次情報の裏取り → gp blog の
  規則ファイル準拠で `~/gp blog/outputs/drafts/` にドラフト生成)
```

- [ ] **Step 2: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 64 tests`

```bash
git add -A && git commit -m "docs: blog module usage"
```

---

## 后续(不在本计划内)

- 截图自动整理、1on1 助手(既定队列の次)
- 記事全体(導入文・目次)の生成は明示依頼時のみ(CLAUDE.md 準拠)——未実装
