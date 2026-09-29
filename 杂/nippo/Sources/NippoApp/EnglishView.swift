import SwiftUI
import NippoCore

/// 英語タブ(v6)。主役は 1 枚のカード(単語・考点词・语料・词典)。ほかは灰色で静かに。
/// OOUI:もの(单词・考点词・语料・词典)を選ぶ → カード(1 つ)か列表(まとまり)→ カードに付いた操作。
/// 1 問 10 秒前後、キーボードだけで回せる(单词:空格 → 1〜4、考点词:1〜4 → 回车、语料:输入 → 回车、⌘Z 撤销)
struct EnglishView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                UnderlineTabs(items: EnglishCoordinator.Mode.allCases.map { mode in
                    TabItem(value: mode, title: mode.title, badge: english.remaining[mode])
                }, selection: $english.mode)
                if english.mode != .dict {
                    Button(english.presentation == .card ? "列表" : "卡片") {
                        withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                            english.presentation = english.presentation == .card ? .list : .card
                        }
                    }
                    .buttonStyle(.command(.quiet, height: 20))
                    .help(english.presentation == .card ? "查看列表" : "回到卡片")
                }
                Spacer(minLength: 8)
                progress
            }
            Group {
                if !english.loaded {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("加载中…")
                            .font(Theme.font(14, .medium))
                            .foregroundStyle(Theme.textSoft)
                    }
                } else if !english.hasData {
                    MissingData()
                } else if english.presentation == .list && english.mode != .dict {
                    WordList(english: english)
                } else {
                    switch english.mode {
                    case .vocab: VocabView(english: english)
                    case .para: ParaphraseCard(english: english)
                    case .spell: SpellCard(english: english)
                    case .dict: DictionaryCard(english: english)
                    }
                }
            }
            .padding(.top, 20)
        }
    }

    /// 今天 12/20 · 连续 4 天
    private var progress: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("今天")
                .foregroundStyle(Theme.textSoft)
            Text("\(english.todayCount)")
                .font(Theme.font(13, .bold).monospacedDigit())
                .foregroundStyle(english.todayCount >= EnglishCoordinator.dailyGoal ? Theme.lime : Theme.white)
            Text("/\(EnglishCoordinator.dailyGoal)")
                .monospacedDigit()
                .foregroundStyle(Theme.textSoft)
            if english.streak > 0 {
                Text("· 连续 \(english.streak) 天")
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .font(Theme.font(13, .medium))
        .fixedSize()
        .help("每天目标 \(EnglishCoordinator.dailyGoal) 题")
    }
}

// MARK: - 共通

/// カードの外枠:余白だけ。答えたときのスタンプを右上に重ねる
private struct CardFrame<Content: View>: View {
    @ObservedObject var english: EnglishCoordinator
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if let flash = english.flash {
                    Stamp(good: flash.good)
                        .offset(x: -10, y: 20)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .id(flash.id)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.55), value: english.flash)
    }
}

/// 上の小さな一行(「B1 · n. 新词」など)
private struct Tagline: View {
    let text: String
    var highlight: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .foregroundStyle(Theme.textSoft)
            if let highlight {
                Text(highlight)
                    .foregroundStyle(Theme.lime)
            }
        }
        .font(Theme.font(13, .semibold))
    }
}

/// 見出し語(大きく・まっすぐ)
private struct HeadWord: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.font(62, .heavy))
            .foregroundStyle(Theme.white)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .textSelection(.enabled)
            .padding(.top, 6)
            .padding(.trailing, 150)
    }
}

/// 直前の答え(結果の一言)と「撤销 ⌘Z」
private struct UndoLine: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        // 语料は次の語を打っているあいだは出さない(⌘Z を入力欄の取り消しに譲る)
        if let action = english.lastAction, action.mode == english.mode,
           english.mode != .spell || english.spellResult != nil {
            HStack(spacing: 8) {
                Text(action.message)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button("撤销 ⌘Z") { english.undoLast() }
                    .buttonStyle(.command(.quiet, height: 20))
                    .keyboardShortcut("z", modifiers: .command)
            }
            .font(Theme.font(12, .medium))
            .foregroundStyle(Theme.textSoft)
            .padding(.top, 14)
        }
    }
}

private func keyLabel(_ key: String, _ title: String) -> some View {
    HStack(spacing: 8) {
        KeyHint(key)
        Text(title)
    }
}

// MARK: - 单词

private struct VocabView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let card = english.vocabCard {
            CardFrame(english: english) {
                VStack(alignment: .leading, spacing: 0) {
                    Tagline(text: [card.level, card.pos].compactMap { $0 }.joined(separator: " · "),
                            highlight: card.known ? "已掌握" : (card.isNew ? "新词" : nil))
                    HeadWord(text: card.word)
                    HStack(spacing: 8) {
                        if let phonetic = card.phonetic {
                            Text(phonetic)
                                .font(Theme.font(16, .regular))
                                .foregroundStyle(Theme.textSoft)
                        }
                        Button {
                            english.speakWord()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.command(.quiet, height: 20))
                        .help("听发音")
                    }
                    if english.revealed || card.known {
                        Text(card.meaning)
                            .font(Theme.font(24, .bold))
                            .foregroundStyle(Theme.lime)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, 18)
                        if let example = card.example {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(example)
                                    .font(Theme.font(15, .regular))
                                    .foregroundStyle(Theme.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                Button {
                                    english.speakExample()
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                }
                                .buttonStyle(.command(.quiet, height: 18))
                                .help("听例句")
                            }
                            .padding(.top, 6)
                        }
                    }
                    actions(card)
                        .padding(.top, 22)
                    UndoLine(english: english)
                }
            }
        } else {
            StageClear(english: english, message: "今天的单词做完了")
        }
    }

    @ViewBuilder
    private func actions(_ card: EnglishCoordinator.VocabCard) -> some View {
        if card.known {
            HStack(spacing: 12) {
                Text("你标记了「已经会了」，现在不会出题")
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.textSoft)
                Spacer()
                Button("恢复出题") { english.restoreCurrent() }
                    .buttonStyle(.command(.primary))
            }
        } else if english.revealed {
            HStack(spacing: 10) {
                rateButton("忘了", key: "1", rating: .again, kind: .ghost)
                rateButton("模糊", key: "2", rating: .hard, kind: .ghost)
                rateButton("记住了", key: "3", rating: .good, kind: .primary)
                rateButton("太简单", key: "4", rating: .easy, kind: .ghost)
            }
        } else {
            HStack(spacing: 10) {
                Button {
                    english.reveal()
                } label: {
                    keyLabel("空格", "看释义")
                }
                .buttonStyle(.command(.primary, height: 44, wide: true))
                .keyboardShortcut(.space, modifiers: [])
                Button("已经会了") { english.markKnown() }
                    .buttonStyle(.command(.ghost, height: 44))
                    .help("以后不再出这个词（可以在列表的「已掌握」里恢复）")
            }
        }
    }

    private func rateButton(_ title: String, key: KeyEquivalent, rating: SRSRating,
                            kind: CommandButtonStyle.Kind) -> some View {
        Button {
            english.rate(rating)
        } label: {
            keyLabel(String(key.character), title)
        }
        .buttonStyle(.command(kind, height: 42, wide: true))
        .keyboardShortcut(key, modifiers: [])
    }
}

// MARK: - 考点词

private struct ParaphraseCard: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let q = english.question {
            CardFrame(english: english) {
                VStack(alignment: .leading, spacing: 0) {
                    Tagline(text: (q.entry.skill == "listening" ? "听力考点词" : "阅读考点词")
                                + " · 真题里它会被换成哪个词？")
                    HeadWord(text: q.entry.w)
                    Text([q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.font(16, .regular))
                        .foregroundStyle(Theme.textSoft)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 10) {
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { index, choice in
                            choiceButton(index, choice, question: q)
                        }
                    }
                    .padding(.top, 20)
                    if let picked = english.picked {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(picked == q.answerIndex ? "正确" : "错了，今天还会再出")
                                    .font(Theme.font(15, .bold))
                                    .foregroundStyle(picked == q.answerIndex ? Theme.lime : Theme.white)
                                Text("可替换为：" + q.entry.syn.joined(separator: " · "))
                                    .font(Theme.font(14, .regular))
                                    .foregroundStyle(Theme.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button {
                                english.nextParaphrase()
                            } label: {
                                keyLabel("⏎", "下一题")
                            }
                            .buttonStyle(.command(.primary))
                            .keyboardShortcut(.defaultAction)
                        }
                        .padding(.top, 18)
                    }
                    UndoLine(english: english)
                }
            }
        } else {
            StageClear(english: english, message: "今天的考点词做完了")
        }
    }

    private func choiceButton(_ index: Int, _ choice: String, question q: ParaphraseQuestion) -> some View {
        let picked = english.picked
        let isAnswer = picked != nil && index == q.answerIndex
        return Button {
            english.choose(index)
        } label: {
            HStack(spacing: 10) {
                KeyHint("\(index + 1)")
                Text(choice)
                    .font(Theme.font(17, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .strikethrough(picked == index && !isAnswer)
                Spacer(minLength: 0)
                if isAnswer {
                    Image(systemName: "checkmark")
                } else if picked == index {
                    Image(systemName: "xmark")
                }
            }
        }
        .buttonStyle(.command(isAnswer ? .primary : .ghost, height: 46, wide: true))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .opacity(picked != nil && !isAnswer && index != picked ? 0.4 : 1)
    }
}

// MARK: - 语料(听写)

private struct SpellCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            CardFrame(english: english) {
                VStack(alignment: .leading, spacing: 0) {
                    Tagline(text: "王陆语料 · \(item.word.set)", highlight: item.isNew ? "新词" : nil)
                    Text("听音写词")
                        .font(Theme.font(30, .heavy))
                        .foregroundStyle(Theme.white)
                        .padding(.top, 6)
                    HStack(spacing: 10) {
                        Button {
                            english.play()
                            focused = true
                        } label: {
                            Label("播放", systemImage: "play.fill")
                        }
                        .buttonStyle(.command(.primary))
                        .keyboardShortcut("r", modifiers: .command)
                        .help("播放(⌘R)")
                        Button("慢速") {
                            english.play(slow: true)
                            focused = true
                        }
                        .buttonStyle(.command(.ghost))
                        Spacer()
                        Text("英式发音 · 建议戴耳机")
                            .font(Theme.font(12, .medium))
                            .foregroundStyle(Theme.textSoft)
                    }
                    .padding(.top, 14)
                    TextField("", text: $english.spellInput,
                              prompt: Text("输入听到的单词，按回车").foregroundStyle(Theme.textFaint))
                        .textFieldStyle(.plain)
                        .font(Theme.font(26, .bold))
                        .foregroundStyle(Theme.white)
                        .autocorrectionDisabled(true)
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background(Theme.tile)
                        .overlay(alignment: .bottom) { Theme.lime.frame(height: 2) }
                        .focused($focused)
                        .onSubmit {
                            english.submitSpelling()
                            focused = true
                        }
                        .padding(.top, 14)
                    if let result = english.spellResult {
                        resultBox(result, item.word)
                            .padding(.top, 12)
                    }
                    HStack(spacing: 10) {
                        if english.spellResult == nil {
                            Button("不知道") { english.giveUpSpelling() }
                                .buttonStyle(.command(.ghost))
                            Spacer()
                            Button {
                                english.submitSpelling()
                            } label: {
                                keyLabel("⏎", "检查")
                            }
                            .buttonStyle(.command(.primary))
                        } else {
                            Spacer()
                            Button {
                                english.submitSpelling()
                                focused = true
                            } label: {
                                keyLabel("⏎", "下一个")
                            }
                            .buttonStyle(.command(.primary))
                        }
                    }
                    .padding(.top, 14)
                    UndoLine(english: english)
                }
            }
            .onAppear { focused = true }
        } else {
            StageClear(english: english, message: "今天的语料做完了")
        }
    }

    /// 判定:正确 = 黄绿底黑字;差一点・错误 = 深灰底白字
    private func resultBox(_ result: SpellResult, _ word: DictationWord) -> some View {
        let title: String
        switch result {
        case .correct: title = "正确"
        case .almost: title = "差一点（错了 1 个字母）· 明天再来"
        case .wrong: title = "正确答案 · 今天再来一次"
        }
        let good = result == .correct
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(13, .bold))
            Text(word.w)
                .font(Theme.font(30, .heavy))
                .textSelection(.enabled)
            Text([word.ipa.map { "/\($0)/" }, word.zh].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.font(14, .regular))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(good ? Theme.black : Theme.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(good ? Theme.lime : Theme.tile)
    }
}

// MARK: - 词典

private struct DictionaryCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("", text: $english.dictQuery,
                      prompt: Text("输入英文单词（例：sustainable）").foregroundStyle(Theme.textFaint))
                .textFieldStyle(.plain)
                .font(Theme.font(22, .bold))
                .foregroundStyle(Theme.white)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Theme.tile)
                .overlay(alignment: .bottom) { Theme.lime.frame(height: 2) }
                .focused($focused)
            if english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("工作中遇到的生词，随手查。查到的词可以加进单词卡，之后复习")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hit = english.dictHit {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(hit.word)
                            .font(Theme.font(40, .heavy))
                            .foregroundStyle(Theme.white)
                            .textSelection(.enabled)
                        Text("/\(hit.ipa)/")
                            .font(Theme.font(16, .regular))
                            .foregroundStyle(Theme.textSoft)
                        Button {
                            Speaker.shared.say(hit.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.command(.quiet, height: 20))
                        .help("听发音")
                        Spacer()
                    }
                    Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                        .font(Theme.font(18, .bold))
                        .foregroundStyle(Theme.lime)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        if english.isInDeck(hit) {
                            Text("已在单词卡里")
                                .font(Theme.font(13, .medium))
                                .foregroundStyle(Theme.textSoft)
                        } else {
                            Button {
                                english.addToDeck(hit)
                            } label: {
                                Label("加入单词卡", systemImage: "plus")
                            }
                            .buttonStyle(.command(.primary))
                        }
                    }
                    .padding(.top, 6)
                }
            } else {
                Text("没有找到「\(english.dictQuery)」")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - 列表

/// 出现过的单词/考点词/语料。点一行就用卡片打开(提前复习、恢复「已掌握」都在卡片上)
private struct WordList: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        let rows = english.listRows()
        VStack(alignment: .leading, spacing: 8) {
            UnderlineTabs(items: EnglishCoordinator.ListFilter.allCases
                .filter { $0 != .known || english.mode == .vocab }
                .map { TabItem(value: $0, title: $0.title, badge: english.listCount($0)) },
                          selection: $english.listFilter, size: 13)
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        CollectionRow(row: row) { english.focus(row.id) }
                    }
                }
                if rows.count >= 200 {
                    Text("只显示前 200 条")
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(Theme.textSoft)
                }
            }
        }
    }

    private var emptyMessage: String {
        switch english.listFilter {
        case .today: return "今天没有要复习的"
        case .learning: return "还没有出现过的词。先从卡片开始吧"
        case .known: return "还没有标记「已经会了」的词"
        }
    }
}

private struct CollectionRow: View {
    let row: EnglishCoordinator.ListRow
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(row.title)
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.white)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)
                Text(row.gloss)
                    .font(Theme.font(13, .regular))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.dueLabel)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(row.dueLabel == "今天" ? Theme.lime : Theme.textSoft)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(hovering ? Theme.tile : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("用卡片打开")
    }
}

// MARK: - 做完了・没有素材

private struct StageClear: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String

    var body: some View {
        CardFrame(english: english) {
            VStack(alignment: .leading, spacing: 10) {
                Text("完成！")
                    .font(Theme.font(40, .heavy))
                    .foregroundStyle(Theme.lime)
                Text(message)
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(Theme.white)
                Text("要复习的明天会再出现。还想继续的话，可以再加 10 个新的")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("再来 10 个新的") { english.addMoreNew() }
                        .buttonStyle(.command(.primary))
                    Button("查看列表") { english.presentation = .list }
                        .buttonStyle(.command(.ghost))
                }
                .padding(.top, 6)
                UndoLine(english: english)
            }
        }
    }
}

private struct MissingData: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有英语素材")
                .font(Theme.font(26, .bold))
                .foregroundStyle(Theme.white)
            Text("导入 IELTS app 的素材后就能用。在终端里指定 IELTS app 的文件夹重新构建：")
                .font(Theme.font(14, .medium))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.lime)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tile)
        }
    }
}
