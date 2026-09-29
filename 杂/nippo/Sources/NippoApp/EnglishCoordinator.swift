import Foundation
import NippoCore

/// 英語タブ(すきま時間の英語)の状態と操作。素材は IELTS アプリから取り込んだもの:
/// 単語 = 分層詞池の間隔反復カード / 同替 = 刘洪波 考点词の同義替換 4 択 /
/// 聴写 = 王陆 语料库の書き取り(読み上げ)/ 辞書 = ECDICT の抜粋(引いた語は単語カードに足せる)
@MainActor
final class EnglishCoordinator: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case vocab, para, spell, dict

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vocab: return "単語"
            case .para: return "同替"
            case .spell: return "聴写"
            case .dict: return "辞書"
            }
        }

        var symbol: String {
            switch self {
            case .vocab: return "rectangle.stack.fill"
            case .para: return "arrow.left.arrow.right"
            case .spell: return "headphones"
            case .dict: return "magnifyingglass"
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
    }

    struct SpellItem: Equatable {
        let id: String
        let word: DictationWord
        let isNew: Bool
    }

    /// 1 日の目標(問)
    static let dailyGoal = 20

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "englishMode")
            if oldValue != mode { prepare() }
        }
    }
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

    @Published private(set) var todayCount = 0
    @Published private(set) var streak = 0
    @Published private(set) var remaining: [Mode: Int] = [:]

    private let store: EnglishStore
    private var loading = false
    private var questionID: String?
    /// 聴写で一度でも自分で再生したら、以後は「次へ」で自動再生する(職場でいきなり音を出さない)
    private var listened = false
    /// いま答えたカード(「もう一回」がすぐ戻ってこないように)
    private var lastAnswered: [Mode: String] = [:]
    /// 「もう 10 語」で今日だけ増やした新規枠
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

    /// 初回だけ素材を読む(辞書が 2MB あるので裏で)
    func loadIfNeeded() {
        guard !loaded else {
            prepare()
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
    }

    /// いまのモードの 1 問を用意する(出ている問題はそのまま)
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
        switch mode {
        case .vocab: nextVocab()
        case .para: nextPara()
        case .spell: nextSpell(autoplay: false)
        case .dict: break
        }
        refreshStats()
    }

    // MARK: - 単語

    func reveal() {
        guard vocabCard != nil else { return }
        revealed = true
    }

    func rate(_ rating: SRSRating) {
        guard let card = vocabCard, revealed else { return }
        record(card.id, kind: .vocab, rating: rating)
        lastAnswered[.vocab] = card.id
        nextVocab()
        refreshStats()
    }

    /// 「知ってる」:もう出さない
    func markKnown() {
        guard let card = vocabCard else { return }
        do {
            try store.markKnown(id: card.id, kind: .vocab)
        } catch {
            AppLog.shared.log("english", "markKnown failed: \(error)")
        }
        lastAnswered[.vocab] = card.id
        nextVocab()
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
        vocabCard = makeVocabCard(id: next.id, isNew: next.isNew)
    }

    private func makeVocabCard(id: String, isNew: Bool) -> VocabCard? {
        if let w = vocabByID[id] {
            return VocabCard(id: id, word: w.w, phonetic: w.ph, pos: w.pos, meaning: w.zh,
                             example: w.ex, level: w.lv.uppercased(), isNew: isNew)
        }
        if id.hasPrefix("dict:"), let hit = library.lookup(String(id.dropFirst(5))) {
            return VocabCard(id: id, word: hit.word, phonetic: "/\(hit.ipa)/", pos: nil,
                             meaning: hit.zh, example: nil, level: "辞書", isNew: false)
        }
        return nil
    }

    // MARK: - 同替

    func choose(_ index: Int) {
        guard picked == nil, let q = question, let id = questionID,
              q.choices.indices.contains(index) else { return }
        picked = index
        record(id, kind: .para, rating: index == q.answerIndex ? .good : .again)
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

    // MARK: - 聴写

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
        record(item.id, kind: .spell, rating: rating)
        lastAnswered[.spell] = item.id
        refreshStats()
    }

    /// 「わからない」:答えを見せて、今日もう一度
    func giveUpSpelling() {
        guard let item = spellItem, spellResult == nil else { return }
        spellResult = .wrong
        record(item.id, kind: .spell, rating: .again)
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
        if autoplay && listened { Speaker.shared.say(word.w) }
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

    // MARK: - 出題・記録

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

    private func record(_ id: String, kind: EnglishKind, rating: SRSRating) {
        do {
            try store.record(id: id, kind: kind, rating: rating)
        } catch {
            AppLog.shared.log("english", "record failed: \(error)")
        }
    }

    /// 今日の数・連続日数・各モードの残り
    func refreshStats() {
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
