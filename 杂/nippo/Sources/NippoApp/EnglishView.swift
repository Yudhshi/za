import SwiftUI
import NippoCore

/// 英語タブ。OOUI:もの(単語・考点词・語料・辞書)を選ぶ → カード(1 つ)か一覧(まとまり)を見る →
/// カードに付いた操作をする。すきま時間向けに 1 問 10 秒前後、キーボードだけで回せる
/// (単語:Space → 1〜4、考点词:1〜4 → Enter、語料:入力 → Enter、⌘Z で直前の答えを取り消し)
struct EnglishView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(spacing: 10) {
                ObjectSwitch(english: english)
                if english.mode != .dict {
                    PresentationSwitch(english: english)
                }
                Spacer(minLength: 8)
                GoalMeter(count: english.todayCount, goal: EnglishCoordinator.dailyGoal,
                          streak: english.streak)
            }
            if !english.loaded {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("読み込み中…")
                        .font(Theme.font(Theme.Size.body, .bold))
                }
                .padding(16)
                .block()
            } else if !english.hasData {
                MissingDataBlock()
            } else if english.presentation == .list && english.mode != .dict {
                CollectionBlock(english: english)
            } else {
                switch english.mode {
                case .vocab: VocabCardBlock(english: english)
                case .para: ParaphraseCardBlock(english: english)
                case .spell: SpellCardBlock(english: english)
                case .dict: DictionaryBlock(english: english)
                }
            }
        }
    }
}

/// もの(オブジェクト)の切り替え:単語・考点词・語料・辞書。各々に今日の残り
private struct ObjectSwitch: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(EnglishCoordinator.Mode.allCases.enumerated()), id: \.element) { index, mode in
                if index > 0 {
                    Rectangle().fill(Theme.rule).frame(width: Theme.line, height: 32)
                }
                segment(mode)
            }
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
    }

    private func segment(_ mode: EnglishCoordinator.Mode) -> some View {
        let selected = english.mode == mode
        return Button {
            english.mode = mode
        } label: {
            HStack(spacing: 6) {
                Text(mode.title)
                    .font(Theme.font(14, .heavy))
                if let count = english.remaining[mode], count > 0 {
                    CountBadge(count: count)
                }
            }
            .foregroundStyle(selected ? Theme.onInverse : Theme.text)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(selected ? Theme.inverse : Theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.detail)
    }
}

/// カード(1 つ)/ 一覧(まとまり)
private struct PresentationSwitch: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        HStack(spacing: 0) {
            segment(.card, "カード", symbol: "rectangle")
            Rectangle().fill(Theme.rule).frame(width: Theme.line, height: 32)
            segment(.list, "一覧", symbol: "list.bullet")
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
    }

    private func segment(_ value: EnglishCoordinator.Presentation, _ title: String,
                         symbol: String) -> some View {
        let selected = english.presentation == value
        return Button {
            english.presentation = value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? Theme.onInverse : Theme.text)
                .frame(width: 34, height: 32)
                .background(selected ? Theme.inverse : Theme.surface)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 今日の問題数(目標つき)と連続日数
private struct GoalMeter: View {
    let count: Int
    let goal: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(count)/\(goal)")
                .font(Theme.font(Theme.Size.caption, .heavy).monospacedDigit())
            ZStack(alignment: .leading) {
                Theme.surface
                Theme.lime
                    .frame(width: 60 * CGFloat(min(1, Double(count) / Double(max(goal, 1)))))
            }
            .frame(width: 60, height: 8)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
            if streak > 0 {
                Text("\(streak)日連続")
                    .font(Theme.font(Theme.Size.caption, .heavy))
            }
        }
        .foregroundStyle(Theme.text)
        .fixedSize()
        .help("1 日 \(goal) 問が目標。連続 \(streak) 日")
    }
}

// MARK: - カードの共通部品

/// カードの右上にすみれのインク(文字とは重ねない)
private struct CardInk: View {
    var seed: UInt64 = 5

    var body: some View {
        InkSplat(seed: seed, lobes: 9, drops: 2, drip: false, depth: 0.32)
            .fill(Theme.violet)
            .frame(width: 170, height: 150)
            .offset(x: 56, y: -52)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 直前の答え(結果の一言)と「元に戻す ⌘Z」
private struct UndoLine: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        // 語料は次の語を打っているあいだは出さない(⌘Z を入力欄の取り消しに譲る)
        if let action = english.lastAction, action.mode == english.mode,
           english.mode != .spell || english.spellResult != nil {
            HStack(spacing: 8) {
                Text(action.message)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    english.undoLast()
                } label: {
                    HStack(spacing: 6) {
                        Text("元に戻す")
                        KeyHint("⌘Z")
                    }
                }
                .buttonStyle(.sharp(.plain, height: 24))
                .keyboardShortcut("z", modifiers: .command)
            }
            .font(Theme.font(Theme.Size.caption, .bold))
            .foregroundStyle(Theme.textSoft)
            .padding(.top, 14)
        }
    }
}

// MARK: - 単語

private struct VocabCardBlock: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let card = english.vocabCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    WovenTag(text: card.level)
                    if card.isNew { WovenTag(text: "New", style: .violet) }
                    if card.known { WovenTag(text: "Known", style: .lime) }
                }
                Text(card.word)
                    .font(Theme.font(Theme.Size.word, .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .textSelection(.enabled)
                    .padding(.top, 10)
                    .padding(.trailing, 110)
                HStack(spacing: 10) {
                    Text([card.phonetic, card.pos].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.font(Theme.Size.headline, .medium))
                        .foregroundStyle(Theme.textSoft)
                    Button {
                        english.speakWord()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.sharpSquare(size: 28))
                    .help("発音を聞く")
                }
                if english.revealed || card.known {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                        .padding(.vertical, 12)
                    Text(card.meaning)
                        .font(Theme.font(22, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let example = card.example {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(example)
                                .font(Theme.font(Theme.Size.body, .medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            Button {
                                english.speakExample()
                            } label: {
                                Image(systemName: "speaker.wave.2")
                            }
                            .buttonStyle(.plain)
                            .help("例文を聞く")
                        }
                        .padding(.top, 6)
                    }
                }
                actions(card)
                    .padding(.top, 16)
                UndoLine(english: english)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) { CardInk() }
            .clipped()
            .block()
        } else {
            DoneBlock(english: english, message: "今日の単語はここまで")
        }
    }

    @ViewBuilder
    private func actions(_ card: EnglishCoordinator.VocabCard) -> some View {
        if card.known {
            HStack(spacing: 10) {
                Text("「知ってる」にしたので出題していません")
                    .font(Theme.font(Theme.Size.caption, .bold))
                    .foregroundStyle(Theme.textSoft)
                Spacer()
                Button("出題に戻す") { english.restoreCurrent() }
                    .buttonStyle(.sharp(.primary))
            }
        } else if english.revealed {
            HStack(spacing: 8) {
                rateButton("もう一回", key: "1", rating: .again, kind: .plain)
                rateButton("あいまい", key: "2", rating: .hard, kind: .plain)
                rateButton("覚えた", key: "3", rating: .good, kind: .primary)
                rateButton("簡単", key: "4", rating: .easy, kind: .accent)
            }
        } else {
            HStack(spacing: 8) {
                Button {
                    english.reveal()
                } label: {
                    HStack(spacing: 8) {
                        Text("意味を見る")
                        KeyHint("space")
                    }
                }
                .buttonStyle(.sharp(.primary, height: 42, wide: true))
                .keyboardShortcut(.space, modifiers: [])
                Button("知ってる") { english.markKnown() }
                    .buttonStyle(.sharp(.plain, height: 42))
                    .help("もう出さない(一覧の「知ってる」から戻せる)")
            }
        }
    }

    private func rateButton(_ title: String, key: KeyEquivalent, rating: SRSRating,
                            kind: SharpButtonStyle.Kind) -> some View {
        Button {
            english.rate(rating)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                KeyHint(String(key.character))
            }
        }
        .buttonStyle(.sharp(kind, height: 42, wide: true))
        .keyboardShortcut(key, modifiers: [])
    }
}

// MARK: - 考点词

private struct ParaphraseCardBlock: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let q = english.question {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    WovenTag(text: q.entry.skill == "listening" ? "Listening" : "Reading")
                    Text("真題での言い換えはどれ?")
                        .font(Theme.font(Theme.Size.caption, .bold))
                        .foregroundStyle(Theme.textSoft)
                }
                Text(q.entry.w)
                    .font(Theme.font(Theme.Size.word, .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.top, 10)
                    .padding(.trailing, 110)
                Text([q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(Theme.Size.headline, .medium))
                    .foregroundStyle(Theme.textSoft)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { index, choice in
                        choiceButton(index, choice, question: q)
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 3)
                if let picked = english.picked {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(picked == q.answerIndex ? "正解" : "ざんねん。今日もう一度出ます")
                                .font(Theme.font(Theme.Size.headline, .heavy))
                            Text("言い換え:" + q.entry.syn.joined(separator: " · "))
                                .font(Theme.font(Theme.Size.body, .medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            english.nextParaphrase()
                        } label: {
                            HStack(spacing: 8) {
                                Text("次へ")
                                KeyHint("⏎")
                            }
                        }
                        .buttonStyle(.sharp(.primary))
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 14)
                }
                UndoLine(english: english)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) { CardInk(seed: 9) }
            .clipped()
            .block()
        } else {
            DoneBlock(english: english, message: "今日の考点词はここまで")
        }
    }

    private func choiceButton(_ index: Int, _ choice: String, question q: ParaphraseQuestion) -> some View {
        let picked = english.picked
        let kind: SharpButtonStyle.Kind
        if picked != nil && index == q.answerIndex {
            kind = .accent
        } else if picked == index {
            kind = .primary
        } else {
            kind = .plain
        }
        return Button {
            english.choose(index)
        } label: {
            HStack(spacing: 10) {
                KeyHint("\(index + 1)")
                Text(choice)
                    .font(Theme.font(17, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if picked != nil && index == q.answerIndex {
                    Image(systemName: "checkmark")
                } else if picked == index {
                    Image(systemName: "xmark")
                }
            }
        }
        .buttonStyle(.sharp(kind, height: 48, wide: true))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .opacity(picked != nil && index != q.answerIndex && index != picked ? 0.5 : 1)
    }
}

// MARK: - 語料(聴写)

private struct SpellCardBlock: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    WovenTag(text: "Wang Lu")
                    Text(item.word.set)
                        .font(Theme.font(Theme.Size.caption, .bold))
                        .foregroundStyle(Theme.textSoft)
                    if item.isNew { WovenTag(text: "New", style: .violet) }
                }
                HStack(spacing: 8) {
                    Button {
                        english.play()
                        focused = true
                    } label: {
                        HStack(spacing: 8) {
                            Label("聞く", systemImage: "play.fill")
                            KeyHint("⌘R")
                        }
                    }
                    .buttonStyle(.sharp(.primary, height: 40))
                    .keyboardShortcut("r", modifiers: .command)
                    Button {
                        english.play(slow: true)
                        focused = true
                    } label: {
                        Label("ゆっくり", systemImage: "tortoise.fill")
                    }
                    .buttonStyle(.sharp(.plain, height: 40))
                    Spacer()
                    Text("英国英語の読み上げ・イヤホン推奨")
                        .font(Theme.font(Theme.Size.caption, .bold))
                        .foregroundStyle(Theme.textSoft)
                }
                .padding(.top, 14)
                // 白い枠の中はダークでも明るい配色で描く
                TextField("", text: $english.spellInput,
                          prompt: Text("聞こえた語を入力して Enter").foregroundStyle(Theme.inkSoft))
                    .textFieldStyle(.plain)
                    .environment(\.colorScheme, .light)
                    .font(Theme.font(26, .heavy))
                    .foregroundStyle(Theme.black)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 14)
                    .frame(height: 54)
                    .background(Theme.white)
                    .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 2))
                    .focused($focused)
                    .onSubmit {
                        english.submitSpelling()
                        focused = true
                    }
                    .padding(.top, 12)
                if let result = english.spellResult {
                    resultBox(result, item.word)
                        .padding(.top, 12)
                }
                HStack(spacing: 10) {
                    if english.spellResult == nil {
                        Button("わからない") { english.giveUpSpelling() }
                            .buttonStyle(.sharp(.plain))
                        Spacer()
                        Button {
                            english.submitSpelling()
                        } label: {
                            HStack(spacing: 8) {
                                Text("答え合わせ")
                                KeyHint("⏎")
                            }
                        }
                        .buttonStyle(.sharp(.primary))
                    } else {
                        Spacer()
                        Button {
                            english.submitSpelling()
                            focused = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("次へ")
                                KeyHint("⏎")
                            }
                        }
                        .buttonStyle(.sharp(.primary))
                    }
                }
                .padding(.top, 14)
                UndoLine(english: english)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .block()
            .onAppear { focused = true }
        } else {
            DoneBlock(english: english, message: "今日の語料はここまで")
        }
    }

    /// 採点:正解は黄緑、おしい・まちがいは墨(文字は常に読める組み合わせ)
    private func resultBox(_ result: SpellResult, _ word: DictationWord) -> some View {
        let (title, fill, textColor): (String, Color, Color) = {
            switch result {
            case .correct: return ("正解", Theme.lime, Theme.black)
            case .almost: return ("おしい(1 文字ちがい)· 明日もう一度", Theme.inverse, Theme.onInverse)
            case .wrong: return ("正解はこちら · 今日もう一度", Theme.inverse, Theme.onInverse)
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(Theme.Size.caption, .heavy))
            Text(word.w)
                .font(Theme.font(28, .black))
                .textSelection(.enabled)
            Text([word.ipa.map { "/\($0)/" }, word.zh].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.font(Theme.Size.body, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(textColor)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
    }
}

// MARK: - 辞書

private struct DictionaryBlock: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $english.dictQuery,
                      prompt: Text("英単語を入力(例:sustainable)").foregroundStyle(Theme.inkSoft))
                .textFieldStyle(.plain)
                .environment(\.colorScheme, .light)
                .font(Theme.font(22, .heavy))
                .foregroundStyle(Theme.black)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Theme.white)
                .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 2))
                .focused($focused)
            if english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("仕事中に出てきた単語をその場で。引いた語は単語カードに足して、あとで復習できます")
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hit = english.dictHit {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(hit.word)
                            .font(Theme.font(36, .black))
                            .textSelection(.enabled)
                        Text("/\(hit.ipa)/")
                            .font(Theme.font(Theme.Size.headline, .medium))
                            .foregroundStyle(Theme.textSoft)
                        Button {
                            Speaker.shared.say(hit.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.sharpSquare(size: 28))
                        .help("発音を聞く")
                        Spacer()
                    }
                    Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                        .font(Theme.font(17, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        if english.isInDeck(hit) {
                            Text("単語カードに追加済み")
                                .font(Theme.font(Theme.Size.caption, .heavy))
                                .foregroundStyle(Theme.textSoft)
                        } else {
                            Button {
                                english.addToDeck(hit)
                            } label: {
                                Label("単語カードに追加", systemImage: "plus")
                            }
                            .buttonStyle(.sharp(.primary))
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("「\(english.dictQuery)」は見つかりませんでした")
                    .font(Theme.font(Theme.Size.body, .bold))
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .padding(16)
        .block()
        .onAppear { focused = true }
    }
}

// MARK: - 一覧(まとまり)

/// 出たことのあるものの一覧。行を押すとカードで開く(期限前の復習・「知ってる」を戻すのもカードから)
private struct CollectionBlock: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        let rows = english.listRows()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(EnglishCoordinator.ListFilter.allCases) { filter in
                    if filter != .known || english.mode == .vocab {
                        filterButton(filter)
                    }
                }
                Spacer()
            }
            .padding(10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.rule).frame(height: Theme.line)
            }
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(14)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    CollectionRow(row: row) { english.focus(row.id) }
                }
                if rows.count >= 200 {
                    Text("先頭の 200 件を表示")
                        .font(Theme.font(Theme.Size.caption, .bold))
                        .foregroundStyle(Theme.textSoft)
                        .padding(12)
                }
            }
        }
        .block()
    }

    private var emptyMessage: String {
        switch english.listFilter {
        case .today: return "今日の復習はありません"
        case .learning: return "まだ出たものはありません。カードから始めましょう"
        case .known: return "「知ってる」にしたものはありません"
        }
    }

    private func filterButton(_ filter: EnglishCoordinator.ListFilter) -> some View {
        let selected = english.listFilter == filter
        return Button {
            english.listFilter = filter
        } label: {
            HStack(spacing: 6) {
                Text(filter.title)
                Text("\(english.listCount(filter))")
                    .monospacedDigit()
            }
            .font(Theme.font(12, .heavy))
            .foregroundStyle(selected ? Theme.onInverse : Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(selected ? Theme.inverse : Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(Theme.font(Theme.Size.body, .heavy))
                    .lineLimit(1)
                    .frame(width: 180, alignment: .leading)
                Text(row.gloss)
                    .font(Theme.font(Theme.Size.caption, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.dueLabel)
                    .font(Theme.font(12, .heavy))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSoft)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(hovering ? Theme.hairline : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("カードで開く")
    }
}

// MARK: - 今日のぶんが終わった・素材が無い

private struct DoneBlock: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WovenTag(text: "Done", style: .lime)
            Text(message)
                .font(Theme.font(Theme.Size.title, .heavy))
            Text("復習の続きは明日また出ます。まだやるなら、新しいものを 10 問足せます")
                .font(Theme.font(Theme.Size.body, .medium))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("新しいのをもう 10 問") { english.addMoreNew() }
                    .buttonStyle(.sharp(.primary))
                Button("一覧を見る") { english.presentation = .list }
                    .buttonStyle(.sharp(.plain))
            }
            UndoLine(english: english)
        }
        .padding(16)
        .block()
    }
}

private struct MissingDataBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WovenTag(text: "No data", style: .violet)
            Text("IELTS アプリの素材を取り込むと使えます")
                .font(Theme.font(Theme.Size.title, .heavy))
            Text("ターミナルで IELTS アプリのフォルダを指定してビルドし直してください")
                .font(Theme.font(Theme.Size.body, .medium))
                .foregroundStyle(Theme.textSoft)
            Text("IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.black)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.white)
                .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
        }
        .padding(16)
        .block()
    }
}
