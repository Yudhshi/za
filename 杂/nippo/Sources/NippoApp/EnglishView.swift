import SwiftUI
import NippoCore

/// 英語タブ(v8)。主役は翠绿の関卡カード 1 枚(単語・考点词・语料・词典)。
/// 拼縫の左(色布)に題、右(黒い里布)に指令列——RPG の戦闘メニューのように縦に積む。
/// 答えたら里布の右上に NICE! / MISS の章、撤销はカードの下の 1 行。
/// OOUI:もの(单词・考点词・语料・词典)を選ぶ → カード(1 つ)か列表(まとまり)→ カードに付いた操作。
/// 1 問 10 秒前後、キーボードだけで回せる(单词:空格 → 1〜4、考点词:1〜4 → 回车、语料:输入 → 回车、⌘Z 撤销)
struct EnglishView: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.level) private var level

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                UnderlineTabs(items: EnglishCoordinator.Mode.allCases.map { mode in
                    TabItem(value: mode, title: mode.title, badge: english.remaining[mode])
                }, selection: $english.mode)
                Spacer(minLength: 8)
                progress
                if english.mode != .dict {
                    let showingList = english.presentation == .list
                    Button {
                        withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                            english.presentation = showingList ? .card : .list
                        }
                    } label: {
                        Image(systemName: showingList ? "rectangle.portrait" : "list.bullet")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.commandSquare(.quiet, size: 22))
                    .keyboardShortcut("l", modifiers: .command)
                    .help(showingList ? "回到卡片（⌘L）" : "查看列表（⌘L）")
                    .accessibilityLabel(showingList ? "回到卡片" : "查看列表")
                }
            }
            Group {
                if !english.loaded {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("加载中…")
                            .font(Theme.font(13, .regular))
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
            .padding(.top, 14)

            // 褶皺の計量条:今日 20 問。答えた分は灰、いま答える 1 問は関卡色
            if english.loaded && english.hasData {
                let goal = EnglishCoordinator.dailyGoal
                let count = min(english.todayCount, goal)
                HStack(spacing: 10) {
                    PleatGauge(states: (0..<goal).map { i -> PleatState in
                        if i < count { return .meeting }
                        return i == count ? .selected : .empty
                    })
                    Text("\(count) / \(goal)")
                        .font(Theme.font(12, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize()
                }
                .padding(.top, 14)
                .help("今天答了 \(english.todayCount) 题，目标 \(goal) 题")
            }
        }
    }

    /// 今天 12/20 · 连续 4 天(達成したら数字が関卡色)
    private var progress: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("今天 ")
            Text("\(english.todayCount)")
                .monospacedDigit()
                .foregroundStyle(english.todayCount >= EnglishCoordinator.dailyGoal ? level.color : Theme.white)
            Text("/\(EnglishCoordinator.dailyGoal)")
                .monospacedDigit()
            if english.streak > 0 {
                Text(" · 连续 \(english.streak) 天")
            }
        }
        .font(Theme.font(12, .medium))
        .foregroundStyle(Theme.textFaint)
        .fixedSize()
        .help("每天目标 \(EnglishCoordinator.dailyGoal) 题")
    }
}

// MARK: - 共通

/// 関卡カード:主役の面。答えたときの章を里布の右上に重ねる。撤销の行はカードの外(下)
private struct CardFrame<Content: View>: View {
    @ObservedObject var english: EnglishCoordinator
    var seam = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .hero(seam: seam)
                .overlay(alignment: .topTrailing) {
                    // 弾むのは章だけ(カード全体には animation を掛けない)
                    ZStack(alignment: .topTrailing) {
                        if let flash = english.flash {
                            Stamp(good: flash.good)
                                .offset(x: -36, y: 14)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                                .id(flash.id)
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.5), value: english.flash)
                }
            UndoLine(english: english)
        }
    }
}

/// 見出し語(大きく・まっすぐ・墨)
private struct HeadWord: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.font(54, .bold))
            .tracking(-1)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .textSelection(.enabled)
            .padding(.top, 10)
    }
}

/// 直前の答え(結果の一言)と「撤销 ⌘Z」
private struct UndoLine: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        // 语料は次の語を打っているあいだは出さない(⌘Z を入力欄の取り消しに譲る)
        if let action = english.lastAction, action.mode == english.mode,
           english.mode != .spell || english.spellResult != nil || english.spellInput.isEmpty {
            HStack(spacing: 8) {
                Text(action.message)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button("撤销 ⌘Z") { english.undoLast() }
                    .buttonStyle(.command(.quiet, height: 20))
                    .keyboardShortcut("z", modifiers: .command)
            }
            .font(Theme.font(12, .medium))
            .foregroundStyle(Theme.textFaint)
            .padding(.top, 10)
        }
    }
}

private func keyLabel(_ key: String, _ title: String) -> some View {
    HStack(spacing: 6) {
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
                SeamLayout {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: [card.level, card.pos].compactMap { $0 }.joined(separator: " · "),
                                trail: card.isNew && !card.known ? "NEW" : nil)
                        HeadWord(text: card.word)
                        HStack(spacing: 6) {
                            if let phonetic = card.phonetic {
                                Text(phonetic)
                                    .font(Theme.font(15, .regular))
                                    .opacity(0.8)
                            }
                            Button {
                                english.speakWord()
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.commandSquare(.quiet, size: 22))
                            .keyboardShortcut("r", modifiers: .command)
                            .help("听发音（⌘R）")
                        }
                        .padding(.top, 6)
                        if english.revealed || card.known {
                            Text(card.meaning)
                                .font(Theme.font(22, .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .padding(.top, 16)
                            if let example = card.example {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(example)
                                        .font(Theme.font(14, .regular))
                                        .opacity(0.85)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                    Button {
                                        english.speakExample()
                                    } label: {
                                        Image(systemName: "speaker.wave.2")
                                    }
                                    .buttonStyle(.commandSquare(.quiet, size: 20))
                                    .keyboardShortcut("r", modifiers: [.command, .shift])
                                    .help("听例句（⇧⌘R）")
                                }
                                .padding(.top, 6)
                            }
                        }
                        if card.known {
                            Text("你标记了「已经会了」，现在不会出题")
                                .font(Theme.font(13, .regular))
                                .opacity(0.75)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 12)
                        }
                    }
                } right: {
                    commands(card)
                }
            }
        } else {
            StageClear(english: english, message: "今天的单词做完了")
        }
    }

    /// 里布の指令列(下から積む)
    @ViewBuilder
    private func commands(_ card: EnglishCoordinator.VocabCard) -> some View {
        VStack(spacing: 8) {
            if card.known {
                Button("恢复出题") { english.restoreCurrent() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
            } else if english.revealed {
                rateButton("忘了", key: "1", rating: .again, kind: .secondary)
                rateButton("模糊", key: "2", rating: .hard, kind: .secondary)
                rateButton("记住了", key: "3", rating: .good, kind: .primary)
                rateButton("太简单", key: "4", rating: .easy, kind: .secondary)
                // 空格 = 记住了(1 問 1 キー:空格で見て、空格で次へ)
                Button("") { english.rate(.good) }
                    .keyboardShortcut(.space, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            } else {
                Button {
                    english.reveal()
                } label: {
                    keyLabel("空格", "看释义")
                }
                .buttonStyle(.command(.primary, height: 40, wide: true))
                .keyboardShortcut(.space, modifiers: [])
                Button("已经会了") { english.markKnown() }
                    .buttonStyle(.command(.secondary, height: 40, wide: true))
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
        .buttonStyle(.command(kind, height: 40, wide: true))
        .keyboardShortcut(key, modifiers: [])
    }
}

// MARK: - 考点词

private struct ParaphraseCard: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let q = english.question {
            CardFrame(english: english) {
                SeamLayout {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(lead: q.entry.skill == "listening" ? "LISTENING" : "READING", text: "考点词")
                        HeadWord(text: q.entry.w)
                        Text([q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.font(15, .regular))
                            .opacity(0.85)
                            .padding(.top, 6)
                        Text("真题里它会被换成哪个词？")
                            .font(Theme.font(13, .medium))
                            .opacity(0.75)
                            .padding(.top, 14)
                        if let picked = english.picked {
                            Text(picked == q.answerIndex ? "正确" : "错了，今天还会再出")
                                .font(Theme.font(15, .semibold))
                                .padding(.top, 14)
                            Text("可替换为：" + q.entry.syn.joined(separator: " · "))
                                .font(Theme.font(13, .regular))
                                .opacity(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .padding(.top, 3)
                        }
                    }
                } right: {
                    VStack(spacing: 8) {
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { index, choice in
                            choiceButton(index, choice, question: q)
                        }
                        if english.picked != nil {
                            Button {
                                english.nextParaphrase()
                            } label: {
                                keyLabel("⏎", "下一题")
                            }
                            .buttonStyle(.command(.primary, height: 40, wide: true))
                            .keyboardShortcut(.defaultAction)
                            .padding(.top, 4)
                        }
                    }
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
            HStack(spacing: 8) {
                KeyHint("\(index + 1)")
                Text(choice)
                    .font(Theme.font(15, .semibold))
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
        .buttonStyle(.command(isAnswer ? .primary : .secondary, height: 40, wide: true))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .opacity(picked != nil && !isAnswer && index != picked ? 0.4 : 1)
    }
}

// MARK: - 语料(听写)

private struct SpellCard: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.level) private var level
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            CardFrame(english: english) {
                SeamLayout {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(lead: "DICTATION", text: "王陆语料 · \(item.word.set)",
                                trail: item.isNew ? "NEW" : nil)
                        Text("听音写词")
                            .font(Theme.font(22, .semibold))
                            .padding(.top, 8)
                        HStack(spacing: 8) {
                            Button {
                                english.play()
                                focused = true
                            } label: {
                                Label("播放", systemImage: "play.fill")
                            }
                            .buttonStyle(.command(.secondary, height: 32))
                            .keyboardShortcut("r", modifiers: .command)
                            .help("播放（⌘R）")
                            Button("慢速") {
                                english.play(slow: true)
                                focused = true
                            }
                            .buttonStyle(.command(.secondary, height: 32))
                        }
                        .padding(.top, 14)
                        Text("英式发音 · 建议戴耳机")
                            .font(Theme.font(12, .medium))
                            .opacity(0.75)
                            .padding(.top, 8)
                        TextField("", text: $english.spellInput,
                                  prompt: Text("输入听到的单词，按回车").foregroundStyle(level.ink.opacity(0.5)))
                            .font(Theme.font(22, .semibold))
                            .autocorrectionDisabled(true)
                            .inputField(height: 48, focused: focused)
                            .focused($focused)
                            .onSubmit {
                                english.submitSpelling()
                                focused = true
                            }
                            .padding(.top, 12)
                        if let result = english.spellResult {
                            resultBox(result, item.word)
                                .padding(.top, 10)
                        }
                    }
                } right: {
                    VStack(spacing: 8) {
                        if english.spellResult == nil {
                            Button {
                                english.giveUpSpelling()
                            } label: {
                                keyLabel("⌘⌫", "不知道")
                            }
                            .buttonStyle(.command(.secondary, height: 40, wide: true))
                            .keyboardShortcut(.delete, modifiers: .command)
                            Button {
                                english.submitSpelling()
                            } label: {
                                keyLabel("⏎", "检查")
                            }
                            .buttonStyle(.command(.primary, height: 40, wide: true))
                        } else {
                            Button {
                                english.submitSpelling()
                                focused = true
                            } label: {
                                keyLabel("⏎", "下一个")
                            }
                            .buttonStyle(.command(.primary, height: 40, wide: true))
                        }
                    }
                }
            }
            // onAppear の時点では入力欄がまだ窓に入っていないことがあるので、少し待ってから焦点を当てる
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    focused = true
                }
            }
            .onChange(of: english.spellItem) { _, _ in focused = true }
        } else {
            StageClear(english: english, message: "今天的语料做完了")
        }
    }

    /// 判定:正确 = 墨の面に白字、差一点・错误 = 墨 12% の面に墨の字
    private func resultBox(_ result: SpellResult, _ word: DictationWord) -> some View {
        let title: String
        switch result {
        case .correct: title = "正确"
        case .almost: title = "差一点（错了 1 个字母）"
        case .wrong: title = "正确答案 · 今天再来一次"
        }
        let good = result == .correct
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(12, .semibold))
                .opacity(0.8)
            Text(word.w)
                .font(Theme.font(22, .bold))
                .textSelection(.enabled)
            Text([word.ipa.map { "/\($0)/" }, word.zh].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.font(13, .regular))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(good ? level.primaryText : level.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(good ? level.primaryFill : level.ink.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 词典

/// 入力欄は舞台の上、引けた語だけが関卡カードになる(縫い目なし)
private struct DictionaryCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $english.dictQuery,
                      prompt: Text("输入英文单词（例：sustainable）").foregroundStyle(Theme.textFaint))
                .font(Theme.font(20, .semibold))
                .autocorrectionDisabled(true)
                .inputField(height: 46, focused: focused)
                .focused($focused)
            if english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("工作中遇到的生词，随手查。查到的词可以加进单词卡，之后复习")
                    .font(Theme.font(13, .regular))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hit = english.dictHit {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(hit.word)
                            .font(Theme.font(34, .bold))
                            .textSelection(.enabled)
                        Text("/\(hit.ipa)/")
                            .font(Theme.font(15, .regular))
                            .opacity(0.8)
                        Button {
                            Speaker.shared.say(hit.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.commandSquare(.quiet, size: 22))
                        .help("听发音")
                        Spacer()
                    }
                    Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                        .font(Theme.font(15, .semibold))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 10)
                    HStack {
                        Spacer()
                        if english.isInDeck(hit) {
                            Text("已在单词卡里")
                                .font(Theme.font(12, .medium))
                                .opacity(0.75)
                        } else {
                            Button {
                                english.addToDeck(hit)
                            } label: {
                                Label("加入单词卡", systemImage: "plus")
                            }
                            .buttonStyle(.command(.primary))
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("加入单词卡（⌘⏎）")
                        }
                    }
                    .padding(.top, 14)
                }
                .padding(20)
                .padding(.trailing, Theme.padding)
                .hero(seam: false)
            } else {
                Text("没有找到「\(english.dictQuery)」")
                    .font(Theme.font(13, .regular))
                    .foregroundStyle(Theme.textSoft)
            }
        }
        // onAppear の時点では入力欄がまだ窓に入っていないことがあるので、少し待ってから焦点を当てる
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
        }
    }
}

// MARK: - 列表

/// 出现过的单词/考点词/语料。点一行就用卡片打开(提前复习、恢复「已掌握」都在卡片上)
private struct WordList: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.level) private var level

    var body: some View {
        let rows = english.listRows()
        VStack(alignment: .leading, spacing: 10) {
            PillTabs(items: EnglishCoordinator.ListFilter.allCases
                .filter { $0 != .known || english.mode == .vocab }
                .map { TabItem(value: $0, title: $0.title, badge: english.listCount($0)) },
                     selection: $english.listFilter, color: level.color, size: 12)
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(15, .regular))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        WordRow(row: row) { english.focus(row.id) }
                    }
                }
                if rows.count >= 200 {
                    Text("只显示前 200 条")
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(Theme.textFaint)
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

private struct WordRow: View {
    let row: EnglishCoordinator.ListRow
    let open: () -> Void
    @Environment(\.level) private var level
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Text(row.title)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.white)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
                Text(row.gloss)
                    .font(Theme.font(13, .regular))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.dueLabel)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(row.dueLabel == "今天" ? level.color : Theme.textFaint)
            }
            .frame(height: 34)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.card)
                        .padding(.horizontal, -8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("用卡片打开")
    }
}

// MARK: - 做完了・没有素材

/// 今日の分が終わった:玫瑰粉の関卡カードに CLEAR!
private struct StageClear: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String

    var body: some View {
        CardFrame(english: english, seam: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CLEAR!")
                    .font(Theme.shout(34))
                Text(message)
                    .font(Theme.font(15, .semibold))
                    .padding(.top, 10)
                Text("要复习的明天会再出现。还想继续的话，可以再加 10 个新的")
                    .font(Theme.font(13, .regular))
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Button {
                        english.addMoreNew()
                    } label: {
                        keyLabel("⌘N", "再来 10 个新的")
                    }
                    .buttonStyle(.command(.primary))
                    .keyboardShortcut("n", modifiers: .command)
                    Button("查看列表") { english.presentation = .list }
                        .buttonStyle(.command(.secondary))
                }
                .padding(.top, 16)
            }
            .padding(20)
            .padding(.trailing, Theme.padding)
        }
        .environment(\.level, .rose)
    }
}

private struct MissingData: View {
    @Environment(\.level) private var level

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有英语素材")
                .font(Theme.font(22, .semibold))
            Text("导入 IELTS app 的素材后就能用。在终端里指定 IELTS app 的文件夹重新构建：")
                .font(Theme.font(13, .regular))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(level.color)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 4)
        }
        .card()
    }
}
