# 四期完结:月発表底稿 + 全文搜索 + 「初めて聞いた言葉」ログ 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 三个独立功能,共用既有基建:
1. **月発表底稿**:月末最终工作日自动(+菜单手动)把当月日报+週報 → Claude 三视角流水线 → `reports/YYYY/MM/YYYY-MM-月発表.md`(構成:成果/数字/学び/来月の計画)。
2. **全文搜索**:搜索窗(菜单打开),一个关键词横扫 memo(DB)/转写(DB)/日报/週報/議事録/月発表(文件),点结果打开。
3. **生词日志**:每次录音/字幕转写落库后,从转写文本抽「用語集にない新語」(片假名词/英字缩写),按日追记 `<reportsRoot>/初めて聞いた言葉.md`(去重)。

**Architecture(模仿既有模式,不发明新形状):**
- 月発表 = Weekly 一套的月版:`Sources/NippoCore/Monthly/{MonthlyBuilder,MonthlyTrigger,MonthlyReportService}.swift` 模仿 `Sources/NippoCore/Weekly/` 同名文件(先 Read 它们);review 用 `ReportRules.reviewLenses`(通用三视角),不复用 Weekly 专属的ループ閉環 lens。
- 搜索 = `Sources/NippoCore/Search/SearchService.swift`(纯逻辑:SQL LIKE + 文件扫描)+ `Sources/NippoApp/SearchWindow.swift`(模仿 `SupplementWindowController` 的 NSWindow+NSHostingView 形状)。
- 生词 = `Sources/NippoCore/Vocab/VocabExtractor.swift`(纯逻辑,正则抽取)+ coordinator 挂钩(转写落库处)。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(仓库根,当前 **93 tests** 全绿;计数不同按差值顺延并在 concerns 说明);打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并逐条放进 pendingManual;shell 用 `set -o pipefail`;提交末尾加空行和 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**,锚点找不到报 BLOCKED;不改 docs/ 下的规格计划。用語集在 `<reportsRoot>/用語集.md`(运行时可能不存在,要容错)。ClaudeCLI 假二进制测试模式参考 `Sources/nippo-tests/WeeklyServiceTests.swift` 现成写法。

---

### Task 1: MonthlyBuilder + MonthlyTrigger(TDD)

**Files:** Create `Sources/NippoCore/Monthly/MonthlyBuilder.swift`、`Sources/NippoCore/Monthly/MonthlyTrigger.swift`、`Sources/nippo-tests/MonthlyTests.swift`;Modify `Sources/nippo-tests/main.swift`(T.finish() 前追加 `runMonthlyTests()`)。

**先 Read** `Sources/NippoCore/Weekly/WeeklyBuilder.swift` 与 `WeeklyTrigger.swift`,逐一模仿其结构与容错。

- [ ] **Step 1: 失败测试**(6 个,固定东京时区用既有 `tokyoDate`/`tokyoCalendar` helper):
  - `MonthlyTrigger.monthKey(for:)` → "2026-07"
  - `MonthlyTrigger.lastWorkday(of:isQuiet:)`:2026-07(7/31 金曜非静默)→ 7/31;传 isQuiet 把 7/31 设静默 → 7/30
  - `MonthlyTrigger.shouldFire(now:hour:minute:lastFiredMonth:isQuiet:)`:月末最终工作日到点未 fire → true;lastFiredMonth 同月 → false;非月末最终工作日 → false
  - `MonthlyBuilder.monthDailyReports(root:month:)`:临时目录造 `reports/2026/07/2026-07-08-日報.md` 与 `-v2` 版 → 只取每日最新版,按日排序;空月 → 空数组
  - `MonthlyBuilder.factsSection(monthLabel:dailies:weeklies:goal:)`:含月份标签、日报正文、週報正文、目标;素材空时有占位标记
  - `MonthlyBuilder.draftPrompt(facts:)`:含「成果」「数字」「学び」「来月の計画」四见出し要求、事实忠实规则(唯一の根拠/捏造禁止)、常体、「Markdown 本文のみ」输出约束
- [ ] **Step 2: 确认失败**(cannot find 'MonthlyTrigger' in scope)
- [ ] **Step 3: 实现**。要点:monthDailyReports 扫 `reports/YYYY/MM/` 下 `YYYY-MM-DD-日報*.md`,同日取最高 `-vN`(模仿 `ReportService.latestReportURL` 的版本选择逻辑);weeklies 参数由调用方传入(coordinator 从 週報/ 目录读当月 W 文件);draftPrompt 嵌入 `ReportRules` 的事实忠实规则文本(Read 后引用其公开常量,若无合适常量则内联同义规则并在 concerns 说明)
- [ ] **Step 4: 确认通过**(基线 +6 → 99)
- [ ] **Step 5: Commit** `feat: monthly presentation builder and last-workday trigger`

### Task 2: MonthlyReportService(TDD,假 CLI)

**Files:** Create `Sources/NippoCore/Monthly/MonthlyReportService.swift`、`Sources/nippo-tests/MonthlyServiceTests.swift`;Modify `main.swift`。

**先 Read** `Sources/NippoCore/Weekly/WeeklyReportService.swift` 与 `Sources/nippo-tests/WeeklyServiceTests.swift`(假 claude 二进制的现成手法),照抄形状。

- [ ] **Step 1: 失败测试**(3 个):generate 成功写 `reports/2026/07/2026-07-月発表.md` 且内容来自 merge 输出;当月无任何日报 → `.noMaterial` 不写文件;目标文件已存在 → 写 `-v2` 不覆盖
- [ ] **Step 2: 确认失败** → **Step 3: 实现**(draft → `ReportRules.reviewLenses` 三视角 review → merge,全走注入的 generator 闭包,与 Weekly 同构)→ **Step 4: 通过**(+3 → 102)
- [ ] **Step 5: Commit** `feat: monthly presentation service (draft, 3-lens review, merge)`

### Task 3: 月発表接线(设置+tick+菜单)

**Files:** Modify `AppSettings.swift`(monthlyEnabled 默认 true / monthlyTime 默认 "15:00" / lastMonthlyMonth,+SettingsTests 断言)、`AppCoordinator.swift`(tick 内模仿 weekly 块:静默日跳过、MonthlyTrigger.shouldFire → generateMonthly,记 lastMonthlyMonth)、Create `AppCoordinator+Monthly.swift`(generateMonthly:后台线程收集当月 dailies+weeklies+goal → MonthlyReportService → monthlyStage 进度 → 通知+lastMonthlyURL)、`MenuContentView.swift`(toolsSection 内模仿週報 pipelineRow 加「月発表」行:手动生成+打开)、`SettingsView.swift`(月発表 Section:开关+时刻)。

**先 Read** 上述每个文件;monthlyStage/isMonthlyGenerating/lastMonthlyURL 模仿 weekly 同名属性;tick 的 weekly 块就是锚点参照。

- [ ] Step 1: 设置 TDD(断言先行)→ Step 2: coordinator + 菜单 + 设置界面 → Step 3: `swift run nippo-tests && ./build-app.sh` 全绿 → Step 4: Commit `feat: monthly presentation wiring (trigger, menu, settings)`
- [ ] 手动清单:月末最终工作日 15:00 自动生成;菜单手动生成→打开文件;静默日不触发

### Task 4: SearchService(TDD)

**Files:** Create `Sources/NippoCore/Search/SearchService.swift`、`Sources/nippo-tests/SearchTests.swift`;Modify `main.swift`。

```swift
public struct SearchHit: Equatable {
    public enum Source: String { case note, transcript, report, weekly, minutes, monthly }
    public let source: Source
    public let title: String      // 例 "2026-07-10 メモ" / ファイル名
    public let snippet: String    // 命中行±0(前後 40 字で切る)
    public let url: URL?          // ファイル系のみ。note/transcript は nil
    public let day: String        // "yyyy-MM-dd" ソート用(不明は "")
}
public struct SearchService {
    public init(db: AppDatabase, root: URL)
    /// query 空/空白 → []。大文字小文字・全半角は素朴一致(LIKE %q%)。上限 100 件、day 降順
    public func search(_ query: String) throws -> [SearchHit]
}
```

- [ ] **Step 1: 失败测试**(4 个):note 命中(in-memory DB 插入后可搜到,snippet 含关键词);transcript_line 命中(speaker: text 形式);文件命中(临时 root 下造 `reports/2026/07/2026-07-10-日報.md`、`週報/2026-W28-週振り返り.md`、`minutes/2026-07-10-定例.md` 各一个含关键词 → 三种 source 正确、url 非 nil);空查询 → 空、无命中 → 空
- [ ] **Step 2: 确认失败** → **Step 3: 实现**(DB 用 `Note`/`TranscriptLine` 的 filter LIKE;文件系扫 root 下 reports/週報/minutes 三目录的 .md,逐文件读内容找首个命中行)→ **Step 4: 通过**(+4 → 106)
- [ ] **Step 5: Commit** `feat: full-text search service over notes, transcripts and report files`

### Task 5: 搜索窗 UI + 菜单入口

**Files:** Create `Sources/NippoApp/SearchWindow.swift`(SearchWindowController:NSWindow 560×420 + NSHostingView;SearchView:顶部 TextField(onSubmit 检索)+ List 结果行(source 图标+title+snippet),点行 url 有则 NSWorkspace.open,note/transcript 行不可点只展示;空结果显示「見つかりませんでした」);Modify `AppCoordinator.swift`(lazy searchWindow + `func openSearch()`,SearchService 用 db+reportsRoot 构造)、`MenuContentView.swift`(toolsSection 加「検索」行,systemImage "magnifyingglass")。

**先 Read** `SupplementWindowController`(窗口形状参照)与 MenuContentView 的 toolsSection。

- [ ] Step 1: 实现 → Step 2: `swift run nippo-tests && ./build-app.sh` 全绿 → Step 3: Commit `feat: search window and menu entry`
- [ ] 手动清单:菜单「検索」开窗;关键词回车出结果;点文件行打开对应 md

### Task 6: VocabExtractor(TDD)

**Files:** Create `Sources/NippoCore/Vocab/VocabExtractor.swift`、`Sources/nippo-tests/VocabTests.swift`;Modify `main.swift`。

```swift
public enum VocabExtractor {
    /// 転写テキストから「初めて聞いた言葉」候補を抽出。
    /// 候補 = カタカナ 4 文字以上の連続 or 大文字英字 2〜10 文字の略語。
    /// known(用語集+既録)に含まれるもの・数字だけのものは除外。出現順・重複排除。
    public static func candidates(transcript: String, known: Set<String>) -> [String]
    /// 用語集 md から既知語集合を作る(見出し・表・箇条書きの行頭語を素朴に収集。無ければ空)
    public static func knownWords(glossary: String) -> Set<String>
    /// ログ md(## yyyy-MM-dd 見出し+箇条書き)へ追記する本文を組む。既録語は追加しない。
    /// 追加ゼロなら nil
    public static func appendedLog(existing: String, day: String, newTerms: [String]) -> String?
}
```

- [ ] **Step 1: 失败测试**(4 个):候补抽取(「アジャイルで進める。API は REST。」+known 含 "REST" → ["アジャイル", "API"];三文字カタカナ「バグ」不取);knownWords(表行 `| ダイレクション | 意味 |` と `- スプリント: 说明` → 两词都进集合);appendedLog 新增(existing 已含 "アジャイル" → 只追加新词,见出し正确);appendedLog 全部既録 → nil
- [ ] **Step 2: 确认失败** → **Step 3: 实现** → **Step 4: 通过**(+4 → 110)
- [ ] **Step 5: Commit** `feat: first-heard-words extractor (katakana/acronym vs glossary)`

### Task 7: 生词接线 + 文档

**Files:** Modify `AppCoordinator+Meeting.swift`(receiveCaption 落库后不做——太频;在 `createMinutes` 成功回调里,与 `AppCoordinator+Recording.swift` 的 stopRecording 转写完成处,各调一次新方法)、Create 该新方法于 `AppCoordinator+Meeting.swift`:

```swift
/// 転写テキストから新語を抽出して 初めて聞いた言葉.md に追記(ローカルのみ・失敗は握りつぶし)
func logNewVocabulary(transcript: String) {
    let root = URL(fileURLWithPath: settings.reportsRoot)
    let glossary = (try? String(contentsOf: root.appendingPathComponent("用語集.md"),
                                encoding: .utf8)) ?? ""
    let logURL = root.appendingPathComponent("初めて聞いた言葉.md")
    let existing = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    var known = VocabExtractor.knownWords(glossary: glossary)
    known.formUnion(VocabExtractor.knownWords(glossary: existing))
    let terms = VocabExtractor.candidates(transcript: transcript, known: known)
    guard let updated = VocabExtractor.appendedLog(existing: existing,
                                                   day: DayKey.key(for: Date()),
                                                   newTerms: terms) else { return }
    try? updated.write(to: logURL, atomically: true, encoding: .utf8)
    AppLog.shared.log("vocab", "logged \(terms.count) new terms")
}
```

调用点:①`createMinutes` 里生成议事录前已取得 `transcript` → 主线程回调里 `self.logNewVocabulary(transcript: transcript)`(注意 transcript 要传进闭包);②`stopRecording` 转写行落库后用 `lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")` 调用。MenuContentView toolsSection 加「初めて聞いた言葉」行(book 图标,存在时 NSWorkspace.open,不存在 disabled)。README「使い方」末尾补月発表/検索/生词三行。

- [ ] Step 1: 接线 + 菜单 + README → Step 2: `swift run nippo-tests && ./build-app.sh` 全绿 → Step 3: Commit `feat: first-heard-words wiring, menu entry; docs for phase-4 features`
- [ ] 手动清单:字幕会议生成议事录后 初めて聞いた言葉.md 出现候补;録音停止转写后同样;菜单行可打开文件

---

## 后续(不在本计划内)
- 搜索命中高亮/预览面板;FTS5 化(量大时)
- 生词卡片 UI(现为 md 追记)
- 月発表 supplement 对话框(週報同款)
