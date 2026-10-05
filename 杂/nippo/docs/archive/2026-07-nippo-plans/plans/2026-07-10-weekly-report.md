# 週振り返り自動生成 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本周最后一个工作日(通常周五)早上(默认 09:30)自动触发週報生成:先弹补充输入窗(用户可补内容或跳过)→ 以「本周日报全文 + 上周週報 + 目標7指標 + 本周チェックリスト完成状況 + 用户补充」为素材,按 `docs/nippo-weekly-rules.md` 的结构与闭环规则走 4 阶段对抗流水线 → 输出到 `~/Documents/日報/週報/YYYY-Wnn-週振り返り.md`。菜单有「週報を生成」按钮随时手动触发。

**Architecture:** 纯逻辑(WeeklyRules 常量、WeeklyTrigger 最终营业日判定、WeeklyBuilder 素材组装与 prompt、WeeklyReportService 流水线)进 NippoCore(TDD);补充输入窗与编排进 NippoApp。复用 TextGenerator/ClaudeCLI/uniqueURL。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(当前 **48 tests** 全绿);仓库 `/Users/lease-emp-mac-yudi-shi/Desktop/杂/nippo` 分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证项跳过并汇报;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。**改既有文件前先 Read**,锚点找不到报 BLOCKED。週報の実物規則は仓库 `docs/nippo-weekly-rules.md`(已存在,先读它再写 WeeklyRules)。

---

### Task 1: WeeklyTrigger(最终营业日判定)+ 设置项

**Files:**
- Create: `Sources/NippoCore/Weekly/WeeklyTrigger.swift`
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`(`checklistTimeComponents()` 方法之后追加)
- Create: `Sources/nippo-tests/WeeklyTriggerTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(`runExemplarTests()` 后追加 `runWeeklyTriggerTests()`)
- Modify: `Sources/nippo-tests/SettingsTests.swift`(「defaults and roundtrip」末尾追加断言)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/WeeklyTriggerTests.swift`:

```swift
import Foundation
import NippoCore

func runWeeklyTriggerTests() {
    // 2026-07: 6(月) 7(火) 8(水) 9(木) 10(金) 11(土) 12(日)
    let weekend: (Date) -> Bool = { date in
        let wd = tokyoCalendar.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    T.run("weekKey is ISO based") {
        T.expectEqual(WeeklyTrigger.weekKey(for: tokyoDate(2026, 7, 10),
                                            calendar: tokyoCalendar), "2026-W28")
        T.expectEqual(WeeklyTrigger.weekKey(for: tokyoDate(2026, 7, 13),
                                            calendar: tokyoCalendar), "2026-W29")
    }

    T.run("fires on Friday at/after time, once per week; not on Thursday") {
        // 木曜(まだ金曜が残っている)→ 発火しない
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 9, 10, 0), hour: 9, minute: 30,
            lastFiredWeek: nil, isQuietDay: weekend, calendar: tokyoCalendar), false)
        // 金曜 9:29 → まだ
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 10, 9, 29), hour: 9, minute: 30,
            lastFiredWeek: nil, isQuietDay: weekend, calendar: tokyoCalendar), false)
        // 金曜 9:30 → 発火
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 10, 9, 30), hour: 9, minute: 30,
            lastFiredWeek: nil, isQuietDay: weekend, calendar: tokyoCalendar), true)
        // 同週既発火 → しない
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 10, 15, 0), hour: 9, minute: 30,
            lastFiredWeek: "2026-W28", isQuietDay: weekend, calendar: tokyoCalendar), false)
        // 土曜(クワイエット日)→ しない
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 11, 10, 0), hour: 9, minute: 30,
            lastFiredWeek: nil, isQuietDay: weekend, calendar: tokyoCalendar), false)
    }

    T.run("Friday holiday shifts fire to Thursday") {
        let holidayFriday: (Date) -> Bool = { date in
            weekend(date) || DayKey.key(for: date, calendar: tokyoCalendar) == "2026-07-10"
        }
        // 金曜が祝日 → 木曜に発火
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 9, 9, 30), hour: 9, minute: 30,
            lastFiredWeek: nil, isQuietDay: holidayFriday, calendar: tokyoCalendar), true)
        // その金曜自体はクワイエットなので発火しない
        T.expectEqual(WeeklyTrigger.shouldFire(
            now: tokyoDate(2026, 7, 10, 9, 30), hour: 9, minute: 30,
            lastFiredWeek: nil, isQuietDay: holidayFriday, calendar: tokyoCalendar), false)
    }
}
```

`SettingsTests.swift` 的「defaults and roundtrip」末尾(checklist 断言之后)追加:

```swift
        T.expectEqual(s.weeklyEnabled, true)
        T.expectEqual(s.weeklyTime, "09:30")
        T.expectEqual(s.lastWeeklyWeek, nil)
        s.weeklyTime = "10:00"
        s.lastWeeklyWeek = "2026-W28"
        T.expectEqual(AppSettings(defaults: d).weeklyTime, "10:00")
        T.expectEqual(AppSettings(defaults: d).lastWeeklyWeek, "2026-W28")
        var wt = s.weeklyTimeComponents()
        T.expectEqual(wt.hour, 10); T.expectEqual(wt.minute, 0)
        s.weeklyTime = "junk"
        wt = s.weeklyTimeComponents()
        T.expectEqual(wt.hour, 9); T.expectEqual(wt.minute, 30)
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'WeeklyTrigger' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Weekly/WeeklyTrigger.swift`:

```swift
import Foundation

/// 週の最終営業日(その日以降、週末まで全てクワイエット日)の指定時刻以降に週1回発火。
/// 金曜が祝日なら木曜に繰り上がる。
public enum WeeklyTrigger {
    public static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }

    public static func shouldFire(now: Date, hour: Int, minute: Int,
                                  lastFiredWeek: String?,
                                  isQuietDay: (Date) -> Bool,
                                  calendar: Calendar = .current) -> Bool {
        let week = weekKey(for: now, calendar: calendar)
        guard lastFiredWeek != week else { return false }
        guard !isQuietDay(now) else { return false }

        // 今週の残りの日が全てクワイエットか(=今日が最終営業日か)
        var day = now
        while let next = calendar.date(byAdding: .day, value: 1, to: day),
              weekKey(for: next, calendar: calendar) == week {
            if !isQuietDay(next) { return false }
            day = next
        }

        let c = calendar.dateComponents([.hour, .minute], from: now)
        return c.hour! * 60 + c.minute! >= hour * 60 + minute
    }
}
```

`AppSettings.swift` 的 `checklistTimeComponents()` 之后追加:

```swift
    public var weeklyEnabled: Bool {
        get { d.object(forKey: "weeklyEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "weeklyEnabled"); objectWillChange.send() }
    }

    public var weeklyTime: String {   // "HH:mm"
        get { d.string(forKey: "weeklyTime") ?? "09:30" }
        set { d.set(newValue, forKey: "weeklyTime"); objectWillChange.send() }
    }

    public var lastWeeklyWeek: String? {   // "2026-W28"
        get { d.string(forKey: "lastWeeklyWeek") }
        set { d.set(newValue, forKey: "lastWeeklyWeek"); objectWillChange.send() }
    }

    public func weeklyTimeComponents() -> (hour: Int, minute: Int) {
        let parts = weeklyTime.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return (h, m)
        }
        return (9, 30)
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 51 tests`(48 + 本任务 3)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: weekly trigger (last workday of week) and weekly settings"
```

---

### Task 2: WeeklyRules + WeeklyBuilder(素材组装与 prompt)

**Files:**
- Create: `Sources/NippoCore/Weekly/WeeklyRules.swift`
- Create: `Sources/NippoCore/Weekly/WeeklyBuilder.swift`
- Create: `Sources/nippo-tests/WeeklyBuilderTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runWeeklyBuilderTests()`)

- [ ] **Step 1: 先读 `docs/nippo-weekly-rules.md` 全文**(WeeklyRules 的内容以它为准,下方代码已是其浓缩,如有出入以 docs 为准并在 concerns 注明)

- [ ] **Step 2: 写失败测试**

`Sources/nippo-tests/WeeklyBuilderTests.swift`:

```swift
import Foundation
import NippoCore

func runWeeklyBuilderTests() {
    T.run("weekDailyReports collects Monday..today base reports in order") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-wk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (d, body) in [(7, "火の日報"), (9, "木の日報")] {
            let url = ReportService.baseReportURL(root: root,
                                                  for: tokyoDate(2026, 7, d),
                                                  calendar: tokyoCalendar)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        let dailies = WeeklyBuilder.weekDailyReports(
            root: root, upTo: tokyoDate(2026, 7, 10, 9, 30), calendar: tokyoCalendar)
        T.expectEqual(dailies.map(\.day), ["2026-07-07", "2026-07-09"])
        T.expectEqual(dailies[0].body, "火の日報")
    }

    T.run("facts embeds goal, previous weekly, dailies, checklist and supplement") {
        let facts = WeeklyBuilder.factsSection(
            weekLabel: "2026-W28(7/6〜7/10)",
            dailies: [(day: "2026-07-09", body: "木曜の内容")],
            checklistSummary: "完了 3 / 未完了 1",
            previousWeekly: "前週:次週のトライ=mock提示",
            goal: "7件の行動指標テキスト",
            supplement: "ユーザー補足:シャチョケンで発表した")
        T.expect(facts.contains("木曜の内容"), "daily embedded")
        T.expect(facts.contains("mock提示"), "previous weekly embedded")
        T.expect(facts.contains("7件の行動指標"), "goal embedded")
        T.expect(facts.contains("シャチョケンで発表した"), "supplement embedded")
        T.expect(facts.contains("唯一の根拠"), "sole-source marker")
    }

    T.run("draft prompt embeds loop-closure rule; merge prompt guards hallucination") {
        let draft = WeeklyBuilder.draftPrompt(facts: "素材X")
        T.expect(draft.contains("素材X"), "facts")
        T.expect(draft.contains("次週のトライ"), "structure")
        T.expect(draft.contains("逐条"), "loop-closure rule")
        let merge = WeeklyBuilder.mergePrompt(
            facts: "素材X", draft: "下書きY",
            reviews: [(key: "ループ閉環", findings: "指摘Z")])
        T.expect(merge.contains("下書きY") && merge.contains("指摘Z"), "inputs")
        T.expect(merge.contains("幻覚"), "hallucination guard")
        T.expect(merge.contains("要確認"), "confirm block")
    }
}
```

- [ ] **Step 3: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'WeeklyBuilder' in scope`

- [ ] **Step 4: 实现**

`Sources/NippoCore/Weekly/WeeklyRules.swift`:

```swift
import Foundation

/// 週振り返りの執筆規則(docs/nippo-weekly-rules.md の実装。実物 W1〜W9 由来)
public enum WeeklyRules {
    public static let writingRules = """
    # 読者と目的
    社内振り返りツールへの投稿。読者はメンター・QM・チーム。評価フレームは
    「独力での課題解決と戦略的な合意形成」+ 7件の行動指標(素材の目標参照)。

    # 構造(この順で、この見出し名で書く)
    今週やったこと   … 太字タイトル+2〜4行の説明 × 3〜5件。事実+位置づけ
    よかったこと     … 箇条書き 5〜9件。行動指標につながる事実
    改善点           … 太字の課題タイトル+「指摘/事実 → 原因 → 来週の運用」× 2〜3件
    次週のトライ     … 具体タスクレベル 3〜5件
    次週の改善       … 運用・習慣レベル 2〜3件(トライと粒度を分ける)
    今週の一言       … 週のナラティブ総括(前進と課題を一段抽象で)

    # ループ閉環(最重要)
    - 前週の「次週のトライ/改善」を逐条照合し、達成したものは明示的に回収する
      (例:「Week6 の課題『…』を今週クリア」)。素材に根拠がある場合のみ達成と書く
    - 宣言→兌現を言語化する(「先週整理していた◯◯を今週実物にした」)
    - 未達は正直に持ち越し、改善点に理由と来週の扱いを書く
    - メンター・上長・前輩の feedback は最優先素材:指摘 → 週内の実装 → 結果、の
      変換サイクルを見せる
    - 課題の系譜を追う(「先週の指摘『…』と同根」)

    # 評価シグナル
    - 行動指標の言葉をラベルとして貼らず、事実の描写に自然に埋め込む
      (「自分起点で」「独力で」「一次情報で裏取り」「誰に・いつ・どう話を通すか」)
    - 「指示を受けて遂行する」→「自分で計画・推進する」への移行を具体例で示す
    - 今週の一言は自己認識の更新を書く(「成果の定義を〜に置き換える」型)

    # 事実忠実(最優先)
    - 唯一の根拠 = 与えられた素材(本週の日報・前週の週報・チェックリスト・ユーザー補足)のみ
    - 効果・成果は素材に報告があるものだけ。数字を盛らない。他人の意図を断定しない
    - 改善点は自己否定でなく「事実 → 原因 → 来週の運用」の前向き構造
    - 文体は常体基調(「〜できた」「〜する」)。日報と同じく謙虚に

    # 分量
    実物準拠:全体で日報の 2〜3 倍程度。素材が薄い週は無理に膨らませない
    """

    public struct ReviewLens {
        public let key: String
        public let instruction: String
        public init(key: String, instruction: String) {
            self.key = key
            self.instruction = instruction
        }
    }

    public static let reviewLenses: [ReviewLens] = [
        ReviewLens(key: "日本語自然度", instruction: """
        翻訳腔、助詞の誤り、文体の不統一(常体基調か)、同語反復を指摘する。
        """),
        ReviewLens(key: "事実忠実", instruction: """
        下書きを素材と突き合わせ、素材にない事実・数字・効果の捏造、達成していない前週項目を
        「クリア」と書く誇張、他人の意図の断定を指摘する。捏造・誇張は必ず high。
        """),
        ReviewLens(key: "ループ閉環", instruction: """
        素材内の「前週の週報」の『次週のトライ』『次週の改善』を逐条列挙し、下書きが
        各項目を回収(達成の明示 or 持ち越しの明示)しているか検査する。取りこぼしは high。
        """),
    ]
}
```

`Sources/NippoCore/Weekly/WeeklyBuilder.swift`:

```swift
import Foundation

/// 週振り返りの素材組み立てとプロンプト。
public enum WeeklyBuilder {
    /// 今週月曜〜upTo 当日の基準日報を日付順に収集(存在するもののみ)
    public static func weekDailyReports(root: URL, upTo date: Date,
                                        calendar: Calendar = .current)
        -> [(day: String, body: String)] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        guard let monday = iso.dateInterval(of: .weekOfYear, for: date)?.start
        else { return [] }
        var result: [(day: String, body: String)] = []
        var day = monday
        while day <= date {
            let url = ReportService.baseReportURL(root: root, for: day, calendar: calendar)
            if let body = try? String(contentsOf: url, encoding: .utf8),
               !body.isEmpty {
                result.append((day: DayKey.key(for: day, calendar: calendar), body: body))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// 目標ファイル(<weeklyDir>/目標と行動指標.md)
    public static func loadGoal(weeklyDir: URL) -> String? {
        let url = weeklyDir.appendingPathComponent("目標と行動指標.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 前週の週報:<weeklyDir> 内の最新の「*週振り返り*.md」、無ければ
    /// 「*アーカイブ*.md」の末尾 8000 字(直近の週=末尾にある想定)
    public static func loadPreviousWeekly(weeklyDir: URL) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: weeklyDir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let generated = entries
            .filter { $0.lastPathComponent.contains("週振り返り")
                   && $0.pathExtension.lowercased() == "md" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return da > db
            }
        if let newest = generated.first,
           let text = try? String(contentsOf: newest, encoding: .utf8) {
            return text
        }
        if let archive = entries.first(where: { $0.lastPathComponent.contains("アーカイブ") }),
           let text = try? String(contentsOf: archive, encoding: .utf8) {
            return String(text.suffix(8000))
        }
        return nil
    }

    public static func factsSection(weekLabel: String,
                                    dailies: [(day: String, body: String)],
                                    checklistSummary: String,
                                    previousWeekly: String?,
                                    goal: String?,
                                    supplement: String?) -> String {
        let dailyBlocks = dailies.isEmpty
            ? "(今週の日報なし)"
            : dailies.map { "### \($0.day)\n\($0.body)" }.joined(separator: "\n\n")
        return """
        # 対象週
        \(weekLabel)

        # 素材リスト(唯一の根拠。ここにないことは書けない)
        ## 目標と行動指標(評価フレーム)
        \(goal ?? "(なし)")

        ## 前週の週報(『次週のトライ』『次週の改善』の逐条回収に使う)
        \(previousWeekly ?? "(なし)")

        ## 今週の日報(日付順)
        \(dailyBlocks)

        ## 今週のチェックリスト
        \(checklistSummary)

        ## ユーザーの補足(そのまま事実として扱ってよい)
        \(supplement?.isEmpty == false ? supplement! : "(なし)")
        """
    }

    public static func draftPrompt(facts: String) -> String {
        """
        あなたは Yudi の週次振り返りの下書きを書くアシスタント。

        \(WeeklyRules.writingRules)

        \(facts)

        出力は週報の Markdown 本文のみ(前置き・後書き・コードブロック囲いは禁止)。
        """
    }

    public static func reviewPrompt(lens: WeeklyRules.ReviewLens,
                                    draft: String, facts: String) -> String {
        """
        あなたは週報下書きのレビュアー。観点は「\(lens.key)」のみ。他の観点には触れない。

        # 指摘対象
        \(lens.instruction)

        # 出力形式
        指摘は次の形式の箇条書きのみ。指摘がなければ「指摘なし」とだけ出力する。
        - [high|low] 「該当箇所の引用」→ 問題点 → 修正案

        # 執筆規則(判断基準)
        \(WeeklyRules.writingRules)

        \(facts)

        # 下書き
        \(draft)
        """
    }

    public static func mergePrompt(facts: String, draft: String,
                                   reviews: [(key: String, findings: String)]) -> String {
        let blocks = reviews.map { "## 観点: \($0.key)\n\($0.findings)" }
            .joined(separator: "\n\n")
        return """
        あなたは Yudi の週次振り返りの最終仕上げ担当。下書きにレビュー指摘を反映して最終版を作る。

        # 指摘の採用規則(最重要)
        - レビュアー自身も幻覚を起こす。high 指摘は種類を問わず、採用前に素材と突き合わせて
          指摘自体の根拠を検証する。素材に実在する記述への「捏造」指摘は棄却する
        - 指摘を反映する際も、素材にない事実・数字を新たに書かない
        - 表現・語気・自然さの修正は積極的に採用する

        \(WeeklyRules.writingRules)

        \(facts)

        # 下書き
        \(draft)

        # レビュー指摘
        \(blocks)

        # 出力形式
        1 行目から次の HTML コメントブロックを出力する:
        <!--
        要確認:
        - (アウトプット欄のスクリーンショット・URL は手動で追加してください)
        - (前週項目で未回収のもの、判断に迷った点があればここに列挙。なければ「なし」)
        -->
        その直後に週報の Markdown 本文。それ以外の前置き・後書き・コードブロック囲いは禁止。
        """
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 54 tests`(51 + 3)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: weekly rules and builder (facts, prompts, loop-closure lens)"
```

---

### Task 3: WeeklyReportService(流水线与写文件)

**Files:**
- Create: `Sources/NippoCore/Weekly/WeeklyReportService.swift`
- Modify: `Sources/NippoCore/Report/ReportService.swift`(`uniqueURL` 从 `static` 改为 `public static`,其余不动)
- Create: `Sources/nippo-tests/WeeklyServiceTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runWeeklyServiceTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/WeeklyServiceTests.swift`:

```swift
import Foundation
import NippoCore

func runWeeklyServiceTests() {
    T.run("weekly pipeline: draft, 3 reviews, merge; file written to weekly dir") {
        final class SeqGen: TextGenerator {
            var prompts: [String] = []
            func generate(prompt: String) throws -> String {
                prompts.append(prompt)
                return "W出力\(prompts.count)"
            }
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // 今週の日報を1件置く
        let daily = ReportService.baseReportURL(root: root,
                                                for: tokyoDate(2026, 7, 9),
                                                calendar: tokyoCalendar)
        try FileManager.default.createDirectory(
            at: daily.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "木曜の日報".write(to: daily, atomically: true, encoding: .utf8)

        let gen = SeqGen()
        let svc = WeeklyReportService(generator: gen, reportsRoot: root,
                                      calendar: tokyoCalendar)
        var stages: [String] = []
        let outcome = try svc.generate(for: tokyoDate(2026, 7, 10, 9, 30),
                                       checklistSummary: "完了2/未完了1",
                                       supplement: "補足A",
                                       progress: { stages.append($0) })

        T.expectEqual(gen.prompts.count, 5, "1 draft + 3 reviews + 1 merge")
        T.expect(gen.prompts[0].contains("木曜の日報") && gen.prompts[0].contains("補足A"),
                 "draft facts embed daily and supplement")
        T.expect(gen.prompts[4].contains("W出力2") && gen.prompts[4].contains("W出力4"),
                 "merge sees reviews")
        T.expectEqual(stages.count, 5)

        guard case .written(let url) = outcome else {
            T.expect(false, "expected .written"); return
        }
        T.expect(url.lastPathComponent == "2026-W28-週振り返り.md",
                 "filename, got \(url.lastPathComponent)")
        T.expect(url.path.contains("週報"), "written under 週報 dir")
        T.expectEqual(try String(contentsOf: url, encoding: .utf8), "W出力5")
    }

    T.run("no dailies and no supplement -> skipped") {
        struct NopGen: TextGenerator {
            func generate(prompt: String) throws -> String { "x" }
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = WeeklyReportService(generator: NopGen(), reportsRoot: root,
                                      calendar: tokyoCalendar)
        let outcome = try svc.generate(for: tokyoDate(2026, 7, 10),
                                       checklistSummary: "", supplement: nil,
                                       progress: nil)
        T.expect(outcome == .skippedNoMaterial, "expected skip")
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `swift run nippo-tests`
Expected: `cannot find 'WeeklyReportService' in scope`

- [ ] **Step 3: 实现**

`ReportService.swift`:把 `static func uniqueURL(for base: URL) -> URL` 改为 `public static func uniqueURL(for base: URL) -> URL`(仅访问级别,逻辑不动)。

`Sources/NippoCore/Weekly/WeeklyReportService.swift`:

```swift
import Foundation

/// 週振り返りの生成:素材収集 → 下書き → 観点別レビュー×3 → 回源検証つき最終仕上げ。
public struct WeeklyReportService {
    public enum Outcome: Equatable {
        case written(URL)
        case skippedNoMaterial
    }

    let generator: TextGenerator
    let reportsRoot: URL
    let calendar: Calendar

    public init(generator: TextGenerator, reportsRoot: URL,
                calendar: Calendar = .current) {
        self.generator = generator
        self.reportsRoot = reportsRoot
        self.calendar = calendar
    }

    var weeklyDir: URL { reportsRoot.appendingPathComponent("週報") }

    public func generate(for date: Date, checklistSummary: String,
                         supplement: String?,
                         progress: ((String) -> Void)? = nil) throws -> Outcome {
        let dailies = WeeklyBuilder.weekDailyReports(root: reportsRoot, upTo: date,
                                                     calendar: calendar)
        let hasSupplement = (supplement?.isEmpty == false)
        guard !dailies.isEmpty || hasSupplement else { return .skippedNoMaterial }

        let week = WeeklyTrigger.weekKey(for: date, calendar: calendar)
        let facts = WeeklyBuilder.factsSection(
            weekLabel: week,
            dailies: dailies,
            checklistSummary: checklistSummary.isEmpty ? "(記録なし)" : checklistSummary,
            previousWeekly: WeeklyBuilder.loadPreviousWeekly(weeklyDir: weeklyDir),
            goal: WeeklyBuilder.loadGoal(weeklyDir: weeklyDir),
            supplement: supplement)

        progress?("週報の下書きを作成中…(1/5)")
        let draft = try generator.generate(prompt: WeeklyBuilder.draftPrompt(facts: facts))

        var reviews: [(key: String, findings: String)] = []
        for (i, lens) in WeeklyRules.reviewLenses.enumerated() {
            progress?("レビュー中(\(lens.key))…(\(i + 2)/5)")
            let findings = try generator.generate(
                prompt: WeeklyBuilder.reviewPrompt(lens: lens, draft: draft, facts: facts))
            reviews.append((key: lens.key, findings: findings))
        }

        progress?("最終版に仕上げ中…(5/5)")
        let body = try generator.generate(
            prompt: WeeklyBuilder.mergePrompt(facts: facts, draft: draft, reviews: reviews))

        try FileManager.default.createDirectory(at: weeklyDir,
                                                withIntermediateDirectories: true)
        let base = weeklyDir.appendingPathComponent("\(week)-週振り返り.md")
        let url = ReportService.uniqueURL(for: base)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return .written(url)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run nippo-tests`
Expected: `PASS: 56 tests`(54 + 2)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: WeeklyReportService pipeline writing to 週報 dir"
```

---

### Task 4: 补充输入窗(SupplementWindow)

**Files:**
- Create: `Sources/NippoApp/SupplementWindow.swift`

纯 UI,无单元测试,编译通过收尾。

- [ ] **Step 1: 实现**

`Sources/NippoApp/SupplementWindow.swift`:

```swift
import AppKit
import SwiftUI

/// 週報生成前の補足入力ウィンドウ。
/// 「補足を反映して生成」→ onGenerate(text)、「補足なしで生成」→ onGenerate(nil)。
/// 閉じるだけなら何もしない(メニューからいつでも再実行できる)。
@MainActor
final class SupplementWindowController {
    private var window: NSWindow?
    private let onGenerate: (String?) -> Void

    init(onGenerate: @escaping (String?) -> Void) {
        self.onGenerate = onGenerate
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "週報の補足"
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: SupplementView(
            onGenerate: { [weak self] text in
                self?.onGenerate(text)
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

private struct SupplementView: View {
    let onGenerate: (String?) -> Void
    let onCancel: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今週の週報に補足したいことがあれば書いてください")
                .font(.headline)
            Text("日報に書いていない出来事・数字・もらった feedback など。そのまま事実として週報の素材になります。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))
            HStack {
                Button("キャンセル") { onCancel() }
                Spacer()
                Button("補足なしで生成") { onGenerate(nil) }
                Button("補足を反映して生成") {
                    onGenerate(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 2: 编译确认 + Commit**

Run: `swift build --target NippoApp`
Expected: `Build complete!`

```bash
git add -A && git commit -m "feat: weekly supplement input window"
```

---

### Task 5: AppCoordinator 编排 + 菜单/设置

**Files:**
- Modify: `Sources/NippoApp/AppCoordinator.swift`
- Modify: `Sources/NippoApp/MenuContentView.swift`
- Modify: `Sources/NippoApp/SettingsView.swift`

**先 Read 三个文件,以锚点定位。**

- [ ] **Step 1: AppCoordinator 属性与窗口**

`@Published var isGenerating = false` 行之后追加:

```swift
    @Published var isWeeklyGenerating = false
    @Published var lastWeeklyURL: URL?
```

`checklistGenerating` 属性行之后追加:

```swift
    private lazy var supplementWindow = SupplementWindowController { [weak self] text in
        self?.generateWeekly(supplement: text)
    }
```

- [ ] **Step 2: 编排方法**

`generateChecklist()` 方法之后追加:

```swift
    /// 週報フロー:補足入力ウィンドウを開く(自動トリガー/メニュー両方の入口)
    func startWeeklyFlow() {
        supplementWindow.show()
    }

    func generateWeekly(supplement: String?) {
        guard !isWeeklyGenerating else { return }
        isWeeklyGenerating = true
        statusMessage = "週報を生成中…"
        let root = URL(fileURLWithPath: settings.reportsRoot)
        let customPath = settings.claudePath

        // 今週のチェックリスト集計(月曜〜今日)
        var summaryLines: [String] = []
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = Calendar.current.timeZone
        if let monday = iso.dateInterval(of: .weekOfYear, for: Date())?.start {
            var day = monday
            while day <= Date() {
                let key = DayKey.key(for: day)
                if let items = try? checklistService.items(on: key), !items.isEmpty {
                    let done = items.filter(\.done).map { "✔ \($0.text)" }
                    let open = items.filter { !$0.done }.map { "・\($0.text)" }
                    summaryLines.append("\(key): " + (done + open).joined(separator: " / "))
                }
                guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day)
                else { break }
                day = next
            }
        }
        let checklistSummary = summaryLines.joined(separator: "\n")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<WeeklyReportService.Outcome, Error>
            if let exe = ClaudeCLI.detect(customPath: customPath) {
                let svc = WeeklyReportService(generator: ClaudeCLI(executable: exe),
                                              reportsRoot: root)
                result = Result {
                    try svc.generate(for: Date(),
                                     checklistSummary: checklistSummary,
                                     supplement: supplement,
                                     progress: { stage in
                        DispatchQueue.main.async { [weak self] in
                            self?.statusMessage = stage
                        }
                    })
                }
            } else {
                result = .failure(ClaudeCLI.CLIError.exited(
                    code: -1, stderr: "claude CLI が見つかりません(設定でパスを指定)"))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWeeklyGenerating = false
                switch result {
                case .success(.written(let url)):
                    self.statusMessage = "週報を保存しました"
                    self.lastWeeklyURL = url
                    NotificationService.shared.notify(
                        title: "週報ドラフト完成",
                        body: "レビューして投稿してください: \(url.lastPathComponent)")
                case .success(.skippedNoMaterial):
                    self.statusMessage = "今週の素材がないためスキップしました"
                    NotificationService.shared.notify(
                        title: "週報をスキップしました",
                        body: "今週の日報・補足が見つかりません")
                case .failure(let error):
                    self.statusMessage = "エラー: \(error.localizedDescription)"
                    NotificationService.shared.notify(
                        title: "週報生成に失敗",
                        body: error.localizedDescription)
                }
            }
        }
    }
```

- [ ] **Step 3: tick 触发**

`tick()` 内チェックリスト触发块之后追加:

```swift
        // 週報(週の最終営業日、1週1回。補足入力ウィンドウを開く)
        if settings.weeklyEnabled {
            let (wh, wm) = settings.weeklyTimeComponents()
            let quiet: (Date) -> Bool = { [weak self] d in
                guard let self else { return false }
                return (try? self.quietDays.isQuietDay(d)) ?? false
            }
            if WeeklyTrigger.shouldFire(now: now, hour: wh, minute: wm,
                                        lastFiredWeek: settings.lastWeeklyWeek,
                                        isQuietDay: quiet) {
                settings.lastWeeklyWeek = WeeklyTrigger.weekKey(for: now)
                NotificationService.shared.notify(
                    title: "週報の時間です",
                    body: "補足があれば入力してください。ウィンドウを開きました")
                startWeeklyFlow()
            }
        }
```

- [ ] **Step 4: 菜单与设置**

`MenuContentView.swift`:「日報を生成」按钮块之后(`lastReportURL` 的 if 块之后)追加:

```swift
            Button(coordinator.isWeeklyGenerating ? "週報を生成中…" : "週報を生成") {
                coordinator.startWeeklyFlow()
            }
            .disabled(coordinator.isWeeklyGenerating)
            if let url = coordinator.lastWeeklyURL {
                Button("週報を開く") { NSWorkspace.shared.open(url) }
            }
```

`SettingsView.swift`:「今日のチェックリスト」Section 之后追加:

```swift
            Section("週振り返り") {
                Toggle("週の最終営業日に自動生成する", isOn: binding(\.weeklyEnabled))
                TextField("生成時刻 (HH:mm)", text: binding(\.weeklyTime))
                Text("素材: 今週の日報+前週の週報+目標(週報フォルダ)+チェックリスト+補足入力")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 5: 测试 + 打包 + Commit**

Run: `swift run nippo-tests && ./build-app.sh`
Expected: `PASS: 56 tests`,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: weekly report flow — trigger, supplement window, menu and settings"
```

- [ ] **Step 6: 手动验证清单(跳过并汇报)**

1. 菜单出现「週報を生成」→ 点击弹出「週報の補足」窗口
2. 窗口三个按钮行为:キャンセル(仅关闭)/補足なしで生成/補足を反映して生成(空文本时禁用)
3. 生成中菜单按钮变「週報を生成中…」灰置,状态栏显示 5 阶段进度
4. 完成后通知「週報ドラフト完成」,「週報を開く」打开 `~/Documents/日報/週報/2026-Wnn-週振り返り.md`
5. 内容检查:前周(存档 W9)的「次週のトライ/改善」被逐条回收或明示持ち越し;补充的内容被采纳为事实
6. 设置里「週振り返り」区块开关与时刻持久化
7. 下周五 09:30 首个 tick:通知+补足窗自动弹出

---

### Task 6: README 更新

**Files:**
- Modify: `README.md`(「使い方」列表 checklist 行后追加)

- [ ] **Step 1: 追加**

```markdown
- 週の最終営業日 9:30(設定可)に週報フローが起動:補足入力ウィンドウ →
  今週の日報+前週の週報+目標+チェックリストから週振り返りを生成 →
  `~/Documents/日報/週報/` に保存(メニューの「週報を生成」でいつでも手動実行可)
```

- [ ] **Step 2: 确认 + Commit**

Run: `swift run nippo-tests`
Expected: `PASS: 56 tests`

```bash
git add -A && git commit -m "docs: weekly report usage"
```

---

## 后续(不在本计划内)

- アウトプット欄(スクショ/URL)の自動収集
- blog トピックハンター/1条ドラフト、截图整理、1on1 助手(既定队列)
