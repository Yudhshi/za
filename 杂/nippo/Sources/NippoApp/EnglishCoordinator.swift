import Foundation
import NippoCore

/// 英語タブ(すきま時間の英語)の状態と操作。
/// OOUI:まず「もの」(単語・考点词・語料・辞書)を選び、そのカード(1 つ)か一覧(まとまり)を見て、
/// カードに付いた操作(覚えた・言い換えを選ぶ・書き取る・単語に足す・戻す)をする。
/// 素材は IELTS アプリから取り込んだもの:単語 = 分層詞池 / 考点词 = 刘洪波 考点词真经の同義替換 /
/// 語料 = 王陆 语料库(聴写)/ 辞書 = ECDICT の抜粋
@MainActor
final class EnglishCoordinator: ObservableObject {
    /// もの(オブジェクト)の種類。名前は名詞にそろえる
    enum Mode: String, CaseIterable, Identifiable {
        case vocab, para, spell, dict

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vocab: return "单词"
            case .para: return "考点词"
            case .spell: return "语料"
            case .dict: return "词典"
            }
        }

        /// カードでやること(ツールチップ用)
        var detail: String {
            switch self {
            case .vocab: return "单词卡（IELTS 分级词池，从 B1 开始）。先回想意思，再给记忆程度打分"
            case .para: return "考点词（刘洪波《考点词真经》）。四选一：真题里它会被换成哪个词"
            case .spell: return "语料（王陆语料库）。听朗读，写出单词"
            case .dict: return "词典(ECDICT)。查到的词可以加进单词卡"
            }
        }

        var kind: EnglishKind? {
            switch self {
            case .vocab: return .vocab
            case .para: return .para
            case .spell: return .spell
            case .dict: return nil
            }
        }

        /// 1 日に新しく出す数(復習は別枠で全部出す)
        var newLimit: Int {
            switch self {
            case .vocab: return 10
            case .para: return 10
            case .spell: return 15
            case .dict: return 0
            }
        }
    }

    /// 1 つのカードを見るか、まとまり(一覧)を見るか
    enum Presentation: String {
        case card, list
    }

    /// 一覧の絞り込み
    enum ListFilter: String, CaseIterable, Identifiable {
        case today, learning, known

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "今天"
            case .learning: return "学习中"
            case .known: return "已掌握"
            }
        }
    }

    /// 単語カードの表示内容(詞池の語か、辞書から足した語)
    struct VocabCard: Equatable {
        let id: String
        let word: String
        let phonetic: String?
        let pos: String?
        let meaning: String
        let example: String?
        let level: String
        let isNew: Bool
        /// 「知ってる」にしてあるカード(一覧から開いたとき)
        let known: Bool
    }

    struct SpellItem: Equatable {
        let id: String
        let word: DictationWord
        let isNew: Bool
    }

    /// 一覧の 1 行
    struct ListRow: Identifiable, Equatable {
        let id: String
        let title: String
        let gloss: String
        let dueLabel: String
    }

    /// いま答えたこと(結果の一言と「元に戻す」)
    struct LastAction: Equatable {
        let mode: Mode
        let message: String
        let undo: EnglishUndo
    }

    /// 答えた直後のスタンプ(NICE! / MISS)。少しして自然に消える
    struct Flash: Equatable {
        let id = UUID()
        let good: Bool
    }

    /// 1 日の目標(問)
    static let dailyGoal = 20

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "englishMode")
            if oldValue != mode {
                lastAction = nil
                // 「已掌握」は単語だけの絞り込み。ほかの種類へ移ったら「今天」に戻す
                if mode != .vocab, listFilter == .known { listFilter = .today }
                prepare()
            }
        }
    }
    @Published var presentation: Presentation = .card
    @Published var listFilter: ListFilter = .today
    @Published private(set) var loaded = false
    @Published private(set) var library = EnglishLibrary()

    @Published private(set) var vocabCard: VocabCard?
    @Published private(set) var revealed = false

    @Published private(set) var question: ParaphraseQuestion?
    @Published private(set) var picked: Int?

    @Published private(set) var spellItem: SpellItem?
    @Published var spellInput = ""
    @Published private(set) var spellResult: SpellResult?

    @Published var dictQuery = ""

    @Published private(set) var lastAction: LastAction?
    @Published private(set) var flash: Flash?
    @Published private(set) var todayCount = 0
    @Published private(set) var streak = 0
    @Published private(set) var remaining: [Mode: Int] = [:]

    private var store: EnglishStore
    private var loading = false
    /// 同期フォルダ(AppCoordinator が設定から注入)。nil なら同期しない
    var syncRoot: () -> String? = { nil }
    /// 出来事に付ける端末名(設定で変えたら次の同期から使う)
    var deviceName: () -> String = { "Mac" } {
        didSet { store.device = deviceName() }
    }
    @Published private(set) var syncStatus: String?
    private var syncing = false
    private var exportTask: Task<Void, Never>?
    private var questionID: String?
    /// 語料で一度でも自分で再生したら、以後は「次へ」で自動再生する(職場でいきなり音を出さない)
    private var listened = false
    /// いま Meet の会議中か(AppCoordinator が注入)。会議中は語料を自動再生しない
    var isInMeeting: () -> Bool = { false }
    /// いま答えたカード(「もう一回」がすぐ戻ってこないように)
    private var lastAnswered: [Mode: String] = [:]
    /// 「もう 10 問」で今日だけ増やした新規枠
    private var extraNew: [Mode: Int] = [:]
    private var extraNewDay = ""
    private var rng = SystemRandomNumberGenerator()

    private var vocabByID: [String: VocabWord] = [:]
    private var paraByID: [String: ParaphraseEntry] = [:]
    private var spellByID: [String: DictationWord] = [:]
    private var vocabPool: [String] = []
    private var paraPool: [String] = []
    private var spellPool: [String] = []

    init(db: AppDatabase) {
        store = EnglishStore(db: db)
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "englishMode") ?? "") ?? .vocab
    }

    /// 素材の置き場所:.app の Resources/English(swift run のときはリポジトリの Resources/English)
    static func dataDirectory() -> URL {
        if let url = Bundle.main.url(forResource: "English", withExtension: nil) { return url }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NippoApp
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/English")
    }

    /// パネルを閉じた:次に開いたときの最初の 1 問は、また自分で「播放」を押す(職場でいきなり音を出さない)
    func panelClosed() {
        listened = false
    }

    /// 初回だけ素材を読む(辞書が 2MB あるので裏で)。開くたびに同期も走らせる
    func loadIfNeeded() {
        guard !loaded else {
            prepare()
            syncNow()
            return
        }
        guard !loading else { return }
        loading = true
        let dir = Self.dataDirectory()
        Task.detached(priority: .userInitiated) { [weak self] in
            let library = EnglishLibrary.load(from: dir)
            await MainActor.run {
                self?.finishLoading(library)
            }
        }
    }

    private func finishLoading(_ library: EnglishLibrary) {
        self.library = library
        vocabPool = library.vocab.map { "vocab:" + $0.id }
        vocabByID = Dictionary(zip(vocabPool, library.vocab), uniquingKeysWith: { first, _ in first })
        paraPool = library.paraphrases.map { "para:\($0.skill):\($0.w)" }
        paraByID = Dictionary(zip(paraPool, library.paraphrases), uniquingKeysWith: { first, _ in first })
        spellPool = library.dictation.map { "spell:" + $0.w.lowercased() }
        spellByID = Dictionary(zip(spellPool, library.dictation), uniquingKeysWith: { first, _ in first })
        loaded = true
        loading = false
        AppLog.shared.log("english", "loaded vocab \(vocabPool.count) para \(paraPool.count) "
                          + "spell \(spellPool.count) dict \(library.dictionary.count)")
        prepare()
        syncNow()
    }

    // MARK: - 同期(Mac と Windows で進捗を共有)

    /// 同期フォルダがあれば:ほかの端末の出来事を取り込み(あれば出題を組み直す)、自分の出来事を書き出す。裏で動く
    func syncNow() {
        guard let root = syncRoot(), !syncing else { return }
        syncing = true
        store.device = deviceName()
        let sync = EnglishSync(root: URL(fileURLWithPath: root), device: store.device, store: store)
        Task.detached(priority: .utility) { [weak self] in
            let imported: Int
            let failure: String?
            do {
                imported = try sync.pull()
                try sync.push()
                failure = nil
            } catch {
                imported = 0
                failure = "\(error)"
            }
            await MainActor.run {
                guard let self else { return }
                self.syncing = false
                if let failure {
                    self.syncStatus = "同步失败：\(failure)"
                    AppLog.shared.log("english", "sync failed: \(failure)")
                } else {
                    self.syncStatus = imported > 0 ? "已同步（合并了 \(imported) 条记录）" : "已同步"
                    if imported > 0 {
                        AppLog.shared.log("english", "sync merged \(imported) events")
                        self.afterImport()
                    }
                }
            }
        }
    }

    /// ほかの端末の答えを取り込んだ:控えは無効、出ている問題も組み直す
    private func afterImport() {
        lastAction = nil
        vocabCard = nil
        revealed = false
        question = nil
        questionID = nil
        picked = nil
        spellItem = nil
        spellResult = nil
        spellInput = ""
        prepare()
    }

    /// 答えたあと少し待ってから書き出す(連打しても 1 回)
    private func scheduleExport() {
        guard syncRoot() != nil else { return }
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// いまの種類の 1 問を用意する(出ている問題はそのまま)
    func prepare() {
        refreshStats()
        guard loaded else { return }
        switch mode {
        case .vocab: if vocabCard == nil { nextVocab() }
        case .para: if question == nil { nextPara() }
        case .spell: if spellItem == nil { nextSpell(autoplay: false) }
        case .dict: break
        }
    }

    /// 今日の分が終わったあと、新しいものをもう 10 問
    func addMoreNew() {
        resetExtraIfNewDay()
        extraNew[mode, default: 0] += 10
        advance()
        refreshStats()
    }

    // MARK: - 一覧(まとまり)→ カード(1 つ)

    /// 一覧の行:今日 = 今日の復習、学習中 = 出題中のもの全部、知ってる = 出題から外したもの
    func listRows() -> [ListRow] {
        guard let kind = mode.kind, loaded else { return [] }
        let today = DayKey.key(for: Date())
        let cards = ((try? store.cards(kind: kind)) ?? []).filter { isResolvable($0.id) }
        let chosen: [EnglishCard]
        switch listFilter {
        case .today: chosen = cards.filter { !$0.known && $0.due <= today }
        case .learning: chosen = cards.filter { !$0.known }
        case .known: chosen = cards.filter(\.known)
        }
        return chosen.prefix(200).map { card in
            let (title, gloss) = describe(card.id)
            return ListRow(id: card.id, title: title, gloss: gloss,
                           dueLabel: card.known ? "已掌握" : Self.dueLabel(card.due, today: today))
        }
    }

    /// 一覧で数を出す(絞り込みの横)
    func listCount(_ filter: ListFilter) -> Int {
        guard let kind = mode.kind, loaded else { return 0 }
        let today = DayKey.key(for: Date())
        let cards = ((try? store.cards(kind: kind)) ?? []).filter { isResolvable($0.id) }
        switch filter {
        case .today: return cards.filter { !$0.known && $0.due <= today }.count
        case .learning: return cards.filter { !$0.known }.count
        case .known: return cards.filter(\.known).count
        }
    }

    /// 一覧で選んだものをカードで開く(期限前でも復習できる)
    func focus(_ id: String) {
        let known = (try? store.card(id))?.known ?? false
        switch mode {
        case .vocab:
            revealed = false
            vocabCard = makeVocabCard(id: id, isNew: false, known: known)
        case .para:
            picked = nil
            if let entry = paraByID[id] {
                question = ParaphraseQuiz.make(entry: entry, pool: library.paraphrases, using: &rng)
                questionID = id
            }
        case .spell:
            spellInput = ""
            spellResult = nil
            if let word = spellByID[id] { spellItem = SpellItem(id: id, word: word, isNew: false) }
        case .dict:
            break
        }
        presentation = .card
    }

    private func describe(_ id: String) -> (String, String) {
        if let w = vocabByID[id] { return (w.w, w.zh) }
        if let p = paraByID[id] { return (p.w, p.syn.joined(separator: " · ")) }
        if let d = spellByID[id] { return (d.w, d.zh ?? "") }
        if id.hasPrefix("dict:"), let hit = library.lookup(String(id.dropFirst(5))) { return (hit.word, hit.zh) }
        return (id, "")
    }

    /// 「今天」「明天」「3天后」「10/12」
    static func dueLabel(_ due: String, today: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: due), let t = f.date(from: today) else { return due }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: t, to: d).day ?? 0
        switch days {
        case ..<1: return "今天"
        case 1: return "明天"
        case 2...30: return "\(days) 天后"
        default:
            if days > 365 { return "\(days) 天后" }
            let c = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: d)
            return "\(c.month ?? 0)/\(c.day ?? 0)"
        }
    }

    // MARK: - 単語

    func reveal() {
        guard vocabCard != nil else { return }
        revealed = true
    }

    func rate(_ rating: SRSRating) {
        guard let card = vocabCard, revealed, !card.known else { return }
        let point = try? store.undoPoint(for: card.id)
        let saved = record(card.id, kind: .vocab, rating: rating)
        remember(.vocab, point, "\(card.word) → \(saved.map { Self.intervalLabel($0.state.interval) } ?? "已记录")")
        switch rating {
        case .good, .easy: celebrate(true)
        case .again: celebrate(false)
        case .hard: break
        }
        lastAnswered[.vocab] = card.id
        nextVocab()
        refreshStats()
    }

    /// 「知ってる」:もう出さない(一覧の「知ってる」から戻せる)
    func markKnown() {
        guard let card = vocabCard, !card.known else { return }
        let point = try? store.undoPoint(for: card.id)
        do {
            try store.markKnown(id: card.id, kind: .vocab)
        } catch {
            AppLog.shared.log("english", "markKnown failed: \(error)")
        }
        remember(.vocab, point, "\(card.word) → 已掌握（不再出现）")
        lastAnswered[.vocab] = card.id
        nextVocab()
        refreshStats()
    }

    /// 「知ってる」にしたカードを出題に戻す
    func restoreCurrent() {
        guard let card = vocabCard, card.known else { return }
        do {
            try store.restore(id: card.id)
        } catch {
            AppLog.shared.log("english", "restore failed: \(error)")
        }
        vocabCard = makeVocabCard(id: card.id, isNew: false, known: false)
        revealed = false
        refreshStats()
    }

    func speakWord() {
        guard let card = vocabCard else { return }
        Speaker.shared.say(card.word)
    }

    func speakExample() {
        guard let example = vocabCard?.example else { return }
        Speaker.shared.say(example)
    }

    private func nextVocab() {
        revealed = false
        guard let next = nextID(.vocab, pool: vocabPool) else {
            vocabCard = nil
            return
        }
        vocabCard = makeVocabCard(id: next.id, isNew: next.isNew, known: false)
    }

    private func makeVocabCard(id: String, isNew: Bool, known: Bool) -> VocabCard? {
        if let w = vocabByID[id] {
            return VocabCard(id: id, word: w.w, phonetic: w.ph, pos: w.pos, meaning: w.zh,
                             example: w.ex, level: w.lv.uppercased(), isNew: isNew, known: known)
        }
        if id.hasPrefix("dict:"), let hit = library.lookup(String(id.dropFirst(5))) {
            return VocabCard(id: id, word: hit.word, phonetic: "/\(hit.ipa)/", pos: nil,
                             meaning: hit.zh, example: nil, level: "词典", isNew: false, known: known)
        }
        return nil
    }

    // MARK: - 考点词

    func choose(_ index: Int) {
        guard picked == nil, let q = question, let id = questionID,
              q.choices.indices.contains(index) else { return }
        picked = index
        let point = try? store.undoPoint(for: id)
        let correct = index == q.answerIndex
        record(id, kind: .para, rating: correct ? .good : .again)
        remember(.para, point, "\(q.entry.w) → " + (correct ? "正确" : "今天再来一次"))
        celebrate(correct)
        lastAnswered[.para] = id
        refreshStats()
    }

    func nextParaphrase() {
        nextPara()
    }

    private func nextPara() {
        picked = nil
        guard let next = nextID(.para, pool: paraPool), let entry = paraByID[next.id] else {
            question = nil
            questionID = nil
            return
        }
        question = ParaphraseQuiz.make(entry: entry, pool: library.paraphrases, using: &rng)
        questionID = next.id
    }

    // MARK: - 語料(聴写)

    func play(slow: Bool = false) {
        guard let item = spellItem else { return }
        listened = true
        Speaker.shared.say(item.word.w, slow: slow)
    }

    /// Enter:未採点なら採点、採点済みなら次へ
    func submitSpelling() {
        guard let item = spellItem else { return }
        if spellResult != nil {
            nextSpell(autoplay: true)
            return
        }
        guard !spellInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let result = SpellCheck.check(spellInput, answer: item.word.w)
        spellResult = result
        let rating: SRSRating
        switch result {
        case .correct: rating = .good
        case .almost: rating = .hard
        case .wrong: rating = .again
        }
        let point = try? store.undoPoint(for: item.id)
        let saved = record(item.id, kind: .spell, rating: rating)
        // 「差一点」は復習カードなら数日〜数十日後になる。実際の間隔で言う
        let message: String
        switch result {
        case .correct: message = "正确"
        case .almost: message = "差一点 · " + (saved.map { Self.intervalLabel($0.state.interval) } ?? "明天再来")
        case .wrong: message = "今天再来一次"
        }
        remember(.spell, point, "\(item.word.w) → \(message)")
        if result != .almost { celebrate(result == .correct) }
        lastAnswered[.spell] = item.id
        refreshStats()
    }

    /// 「わからない」:答えを見せて、今日もう一度
    func giveUpSpelling() {
        guard let item = spellItem, spellResult == nil else { return }
        spellResult = .wrong
        let point = try? store.undoPoint(for: item.id)
        record(item.id, kind: .spell, rating: .again)
        remember(.spell, point, "\(item.word.w) → 今天再来一次")
        celebrate(false)
        lastAnswered[.spell] = item.id
        refreshStats()
    }

    private func nextSpell(autoplay: Bool) {
        spellInput = ""
        spellResult = nil
        guard let next = nextID(.spell, pool: spellPool), let word = spellByID[next.id] else {
            spellItem = nil
            return
        }
        spellItem = SpellItem(id: next.id, word: word, isNew: next.isNew)
        if autoplay && listened && !isInMeeting() { Speaker.shared.say(word.w) }
    }

    // MARK: - 辞書

    var dictHit: DictHit? { library.lookup(dictQuery) }

    func isInDeck(_ hit: DictHit) -> Bool {
        (try? store.card("dict:" + hit.word)) != nil
    }

    func addToDeck(_ hit: DictHit) {
        do {
            try store.add(id: "dict:" + hit.word, kind: .vocab)
        } catch {
            AppLog.shared.log("english", "add failed: \(error)")
        }
        objectWillChange.send()
        refreshStats()
    }

    // MARK: - 元に戻す

    /// ⌘Z:いま答えたことを取り消して、そのカードをもう一度出す
    func undoLast() {
        guard let action = lastAction else { return }
        do {
            try store.undo(action.undo)
        } catch {
            AppLog.shared.log("english", "undo failed: \(error)")
        }
        lastAction = nil
        lastAnswered[action.mode] = nil
        if mode != action.mode { mode = action.mode }
        focus(action.undo.id)
        refreshStats()
    }

    private func celebrate(_ good: Bool) {
        let stamp = Flash(good: good)
        flash = stamp
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            if self?.flash == stamp { self?.flash = nil }
        }
    }

    private func remember(_ mode: Mode, _ point: EnglishUndo?, _ message: String) {
        guard let point else {
            lastAction = nil
            return
        }
        lastAction = LastAction(mode: mode, message: message, undo: point)
    }

    /// 「明天再复习」「3 天后再复习」「今天再来一次」
    static func intervalLabel(_ days: Int) -> String {
        switch days {
        case ..<1: return "今天再来一次"
        case 1: return "明天再复习"
        default: return "\(days) 天后再复习"
        }
    }

    // MARK: - 出題・記録

    private func advance() {
        switch mode {
        case .vocab: nextVocab()
        case .para: nextPara()
        case .spell: nextSpell(autoplay: false)
        case .dict: break
        }
    }

    private func nextID(_ mode: Mode, pool: [String]) -> (id: String, isNew: Bool)? {
        guard let kind = mode.kind else { return nil }
        let today = DayKey.key(for: Date())
        resetExtraIfNewDay()
        do {
            let due = try store.dueIDs(kind: kind, today: today).filter { isResolvable($0) }
            let seen = try store.seenIDs(kind: kind)
            let newToday = try store.newCount(kind: kind, day: today)
            guard let id = EnglishQueue.next(due: due, pool: pool, seen: seen, newToday: newToday,
                                             newLimit: newLimit(mode), avoid: lastAnswered[mode])
            else { return nil }
            return (id, !seen.contains(id))
        } catch {
            AppLog.shared.log("english", "queue failed: \(error)")
            return nil
        }
    }

    private func newLimit(_ mode: Mode) -> Int {
        mode.newLimit + extraNew[mode, default: 0]
    }

    private func resetExtraIfNewDay() {
        let today = DayKey.key(for: Date())
        if extraNewDay != today {
            extraNewDay = today
            extraNew = [:]
        }
    }

    /// 取り込み直しで素材から消えたカードは出さない
    private func isResolvable(_ id: String) -> Bool {
        if vocabByID[id] != nil || paraByID[id] != nil || spellByID[id] != nil { return true }
        if id.hasPrefix("dict:") { return library.lookup(String(id.dropFirst(5))) != nil }
        return false
    }

    @discardableResult
    private func record(_ id: String, kind: EnglishKind, rating: SRSRating) -> EnglishCard? {
        do {
            return try store.record(id: id, kind: kind, rating: rating)
        } catch {
            AppLog.shared.log("english", "record failed: \(error)")
            return nil
        }
    }

    /// 今日の数・連続日数・各種類の残り(変更のあとに呼ばれるので、同期の書き出しもここで予約する)
    func refreshStats() {
        scheduleExport()
        let now = Date()
        let today = DayKey.key(for: now)
        todayCount = (try? store.answeredCount(day: today)) ?? 0
        streak = (try? store.streak(today: now)) ?? 0
        guard loaded else { return }
        resetExtraIfNewDay()
        var counts: [Mode: Int] = [:]
        for (mode, pool) in [(Mode.vocab, vocabPool), (Mode.para, paraPool), (Mode.spell, spellPool)] {
            guard let kind = mode.kind else { continue }
            let due = ((try? store.dueIDs(kind: kind, today: today)) ?? []).filter { isResolvable($0) }
            let seen = (try? store.seenIDs(kind: kind)) ?? []
            let newToday = (try? store.newCount(kind: kind, day: today)) ?? 0
            let unseen = pool.reduce(0) { seen.contains($1) ? $0 : $0 + 1 }
            counts[mode] = EnglishQueue.remaining(due: due.count, unseen: unseen, newToday: newToday,
                                                  newLimit: newLimit(mode))
        }
        remaining = counts
    }

    /// タブの見出しに出す、今日の残り(復習 + 新規)
    var remainingTotal: Int {
        remaining.values.reduce(0, +)
    }

    var hasData: Bool { !library.isEmpty }
}
