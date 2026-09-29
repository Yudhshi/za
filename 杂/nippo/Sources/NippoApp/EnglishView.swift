import SwiftUI
import NippoCore

/// 英語タブ(v5 ゲームの UI)。OOUI:もの(単語・考点词・語料・辞書)を選ぶ → カード(1 つ)か一覧(まとまり)→
/// カードに付いた操作。1 問 10 秒前後、キーボードだけで回せる
/// (単語:Space → 1〜4、考点词:1〜4 → Enter、語料:入力 → Enter、⌘Z で直前の答えを取り消し)。
/// 正解で「NICE!」、まちがいで「MISS」のスタンプ。今日の数は TURF ゲージ、連続日数は COMBO
struct EnglishView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(alignment: .center, spacing: 10) {
                ModeMenu(english: english)
                if english.mode != .dict {
                    Button {
                        withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                            english.presentation = english.presentation == .card ? .list : .card
                        }
                    } label: {
                        Image(systemName: english.presentation == .card ? "list.bullet" : "rectangle.portrait")
                    }
                    .buttonStyle(.commandSquare(english.presentation == .list ? .primary : .ghost, size: 30))
                    .help(english.presentation == .card ? "一覧を見る" : "カードに戻る")
                }
                Spacer(minLength: 8)
                HUDStat(label: "Turf", value: "\(english.todayCount)/\(EnglishCoordinator.dailyGoal)",
                        detail: english.streak > 0 ? "COMBO ×\(english.streak)" : nil,
                        segments: 10,
                        filled: Double(english.todayCount) / Double(EnglishCoordinator.dailyGoal) * 10,
                        alignment: .trailing)
                    .help("1 日 \(EnglishCoordinator.dailyGoal) 問が目標。COMBO は連続日数")
            }
            if !english.loaded {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("LOADING…")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.white)
                }
                .padding(16)
            } else if !english.hasData {
                MissingDataCard()
            } else if english.presentation == .list && english.mode != .dict {
                CollectionCard(english: english)
            } else {
                switch english.mode {
                case .vocab: VocabBattle(english: english)
                case .para: ParaphraseCard(english: english)
                case .spell: SpellCard(english: english)
                case .dict: DictionaryCard(english: english)
                }
            }
        }
    }
}

/// もの(オブジェクト)の切り替え。選んだタイルに黄緑の札がすべって来る。各々に今日の残り
private struct ModeMenu: View {
    @ObservedObject var english: EnglishCoordinator
    @Namespace private var plate

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EnglishCoordinator.Mode.allCases) { mode in
                tile(mode)
            }
        }
        .fixedSize()
    }

    private func tile(_ mode: EnglishCoordinator.Mode) -> some View {
        let selected = english.mode == mode
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.35)) { english.mode = mode }
        } label: {
            HStack(spacing: 6) {
                Text(mode.title)
                    .font(Theme.font(Theme.Size.body, .black))
                if let count = english.remaining[mode], count > 0 {
                    Plate(text: "\(count)", fill: Theme.violet, textColor: Theme.white)
                }
            }
            .foregroundStyle(selected ? Theme.black : Theme.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background {
                if selected {
                    Slant().fill(Theme.lime).matchedGeometryEffect(id: "mode", in: plate)
                } else {
                    Slant().fill(Theme.tile)
                }
            }
            .contentShape(Slant())
        }
        .buttonStyle(.plain)
        .help(mode.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - カードの共通部品

/// バトルカード:濃い灰の面、右上を斜めに落とし、すみれのインクを角に。正解・まちがいのスタンプを上に重ねる
private struct BattleCard<Content: View>: View {
    @ObservedObject var english: EnglishCoordinator
    var ink: UInt64 = 5
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                InkSplat(seed: ink, lobes: 9, drops: 2, drip: false, depth: 0.34)
                    .fill(Theme.violet)
                    .frame(width: 190, height: 170)
                    .offset(x: 64, y: -60)
                    .allowsHitTesting(false)
            }
            .background(Theme.surface)
            .clipShape(CutRect(topTrailing: 22))
            .overlay(alignment: .topTrailing) {
                if let flash = english.flash {
                    Stamp(text: flash.good ? "NICE!" : "MISS", good: flash.good)
                        .offset(x: -30, y: 44)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .id(flash.id)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.55), value: english.flash)
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
                        Text("⌘Z").font(Theme.label(10))
                    }
                }
                .buttonStyle(.command(.ghost, height: 24))
                .keyboardShortcut("z", modifiers: .command)
            }
            .font(Theme.font(Theme.Size.caption, .bold))
            .foregroundStyle(Theme.textSoft)
            .padding(.top, 14)
        }
    }
}

/// 大きな見出し語(学ぶ綴りなのでまっすぐ・標準幅。インクと重ならないよう右をあける)
private struct HeadWord: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.font(Theme.Size.word, .black))
            .foregroundStyle(Theme.white)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .textSelection(.enabled)
            .padding(.top, 12)
            .padding(.trailing, 120)
    }
}

// MARK: - 単語

private struct VocabBattle: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let card = english.vocabCard {
            BattleCard(english: english) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Plate(text: card.level)
                        if card.isNew { Plate(text: "New", fill: Theme.violet, textColor: Theme.white) }
                        if card.known { Plate(text: "Known", fill: Theme.lime) }
                    }
                    HeadWord(text: card.word)
                    HStack(spacing: 10) {
                        Text([card.phonetic, card.pos].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.font(Theme.Size.headline, .medium))
                            .foregroundStyle(Theme.textSoft)
                        Button {
                            english.speakWord()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.commandSquare(.ghost, size: 26))
                        .help("発音を聞く")
                    }
                    if english.revealed || card.known {
                        Text(card.meaning)
                            .font(Theme.font(24, .black))
                            .foregroundStyle(Theme.lime)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, 16)
                        if let example = card.example {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(example)
                                    .font(Theme.font(Theme.Size.body, .medium))
                                    .foregroundStyle(Theme.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                Button {
                                    english.speakExample()
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .foregroundStyle(Theme.textSoft)
                                }
                                .buttonStyle(.plain)
                                .help("例文を聞く")
                            }
                            .padding(.top, 6)
                        }
                    }
                    actions(card)
                        .padding(.top, 18)
                    UndoLine(english: english)
                }
            }
        } else {
            StageClear(english: english, message: "今日の単語はここまで")
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
                    .buttonStyle(.command(.primary))
            }
        } else if english.revealed {
            HStack(spacing: 10) {
                rateButton("もう一回", key: "1", rating: .again, kind: .ghost)
                rateButton("あいまい", key: "2", rating: .hard, kind: .ghost)
                rateButton("覚えた", key: "3", rating: .good, kind: .primary)
                rateButton("簡単", key: "4", rating: .easy, kind: .light)
            }
        } else {
            HStack(spacing: 10) {
                Button {
                    english.reveal()
                } label: {
                    HStack(spacing: 10) {
                        KeyHint("SPACE")
                        Text("意味を見る")
                    }
                }
                .buttonStyle(.command(.primary, height: 44, wide: true))
                .keyboardShortcut(.space, modifiers: [])
                Button("知ってる") { english.markKnown() }
                    .buttonStyle(.command(.ghost, height: 44))
                    .help("もう出さない(一覧の「知ってる」から戻せる)")
            }
        }
    }

    private func rateButton(_ title: String, key: KeyEquivalent, rating: SRSRating,
                            kind: CommandButtonStyle.Kind) -> some View {
        Button {
            english.rate(rating)
        } label: {
            HStack(spacing: 8) {
                KeyHint(String(key.character))
                Text(title)
            }
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
            BattleCard(english: english, ink: 9) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Plate(text: q.entry.skill == "listening" ? "Listening" : "Reading")
                        Text("真題での言い換えはどれ?")
                            .font(Theme.font(Theme.Size.caption, .bold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    HeadWord(text: q.entry.w)
                    Text([q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.font(Theme.Size.headline, .medium))
                        .foregroundStyle(Theme.textSoft)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 10) {
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { index, choice in
                            choiceButton(index, choice, question: q)
                        }
                    }
                    .padding(.top, 18)
                    if let picked = english.picked {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(picked == q.answerIndex ? "正解" : "ざんねん。今日もう一度出ます")
                                    .font(Theme.font(Theme.Size.headline, .black))
                                    .foregroundStyle(picked == q.answerIndex ? Theme.lime : Theme.white)
                                Text("言い換え:" + q.entry.syn.joined(separator: " · "))
                                    .font(Theme.font(Theme.Size.body, .medium))
                                    .foregroundStyle(Theme.white.opacity(0.9))
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
                            .buttonStyle(.command(.primary))
                            .keyboardShortcut(.defaultAction)
                        }
                        .padding(.top, 16)
                    }
                    UndoLine(english: english)
                }
            }
        } else {
            StageClear(english: english, message: "今日の考点词はここまで")
        }
    }

    private func choiceButton(_ index: Int, _ choice: String, question q: ParaphraseQuestion) -> some View {
        let picked = english.picked
        let kind: CommandButtonStyle.Kind
        if picked != nil && index == q.answerIndex {
            kind = .primary
        } else if picked == index {
            kind = .violet
        } else {
            kind = .ghost
        }
        return Button {
            english.choose(index)
        } label: {
            HStack(spacing: 10) {
                KeyHint("\(index + 1)")
                Text(choice)
                    .font(Theme.font(17, .black))
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
        .buttonStyle(.command(kind, height: 48, wide: true))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .opacity(picked != nil && index != q.answerIndex && index != picked ? 0.45 : 1)
    }
}

// MARK: - 語料(聴写)

private struct SpellCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            BattleCard(english: english, ink: 13) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Plate(text: "Wang Lu")
                        Text(item.word.set)
                            .font(Theme.font(Theme.Size.caption, .bold))
                            .foregroundStyle(Theme.textSoft)
                        if item.isNew { Plate(text: "New", fill: Theme.violet, textColor: Theme.white) }
                    }
                    Text("LISTEN & TYPE")
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.white)
                        .padding(.top, 12)
                    HStack(spacing: 10) {
                        Button {
                            english.play()
                            focused = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("聞く")
                                Text("⌘R").font(Theme.label(10))
                            }
                        }
                        .buttonStyle(.command(.primary, height: 40))
                        .keyboardShortcut("r", modifiers: .command)
                        Button {
                            english.play(slow: true)
                            focused = true
                        } label: {
                            Label("ゆっくり", systemImage: "tortoise.fill")
                        }
                        .buttonStyle(.command(.ghost, height: 40))
                        Spacer()
                        Text("英国英語の読み上げ・イヤホン推奨")
                            .font(Theme.font(Theme.Size.caption, .bold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    .padding(.top, 12)
                    TextField("", text: $english.spellInput,
                              prompt: Text("聞こえた語を入力して Enter").foregroundStyle(Theme.textSoft))
                        .textFieldStyle(.plain)
                        .font(Theme.font(26, .black))
                        .foregroundStyle(Theme.white)
                        .autocorrectionDisabled(true)
                        .padding(.horizontal, 14)
                        .frame(height: 54)
                        .background(Theme.black)
                        .overlay(Rectangle().stroke(Theme.lime, lineWidth: 2))
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
                            Button("わからない") { english.giveUpSpelling() }
                                .buttonStyle(.command(.ghost))
                            Spacer()
                            Button {
                                english.submitSpelling()
                            } label: {
                                HStack(spacing: 8) {
                                    Text("答え合わせ")
                                    KeyHint("⏎")
                                }
                            }
                            .buttonStyle(.command(.primary))
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
                            .buttonStyle(.command(.primary))
                        }
                    }
                    .padding(.top, 14)
                    UndoLine(english: english)
                }
            }
            .onAppear { focused = true }
        } else {
            StageClear(english: english, message: "今日の語料はここまで")
        }
    }

    /// 採点:正解は黄緑に墨、おしい・まちがいはすみれに白
    private func resultBox(_ result: SpellResult, _ word: DictationWord) -> some View {
        let (title, fill, textColor): (String, Color, Color) = {
            switch result {
            case .correct: return ("正解", Theme.lime, Theme.black)
            case .almost: return ("おしい(1 文字ちがい)· 明日もう一度", Theme.violet, Theme.white)
            case .wrong: return ("正解はこちら · 今日もう一度", Theme.violet, Theme.white)
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(Theme.Size.caption, .black))
            Text(word.w)
                .font(Theme.font(30, .black))
                .textSelection(.enabled)
            Text([word.ipa.map { "/\($0)/" }, word.zh].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.font(Theme.Size.body, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutRect(topTrailing: 12).fill(fill))
    }
}

// MARK: - 辞書

private struct DictionaryCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        BattleCard(english: english, ink: 17) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("", text: $english.dictQuery,
                          prompt: Text("英単語を入力(例:sustainable)").foregroundStyle(Theme.textSoft))
                    .textFieldStyle(.plain)
                    .font(Theme.font(22, .black))
                    .foregroundStyle(Theme.white)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Theme.black)
                    .overlay(Rectangle().stroke(Theme.lime, lineWidth: 2))
                    .focused($focused)
                    .padding(.trailing, 110)
                if english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("仕事中に出てきた単語をその場で。引いた語は単語カードに足して、あとで復習できます")
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let hit = english.dictHit {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(hit.word)
                                .font(Theme.font(38, .black))
                                .foregroundStyle(Theme.white)
                                .textSelection(.enabled)
                            Text("/\(hit.ipa)/")
                                .font(Theme.font(Theme.Size.headline, .medium))
                                .foregroundStyle(Theme.textSoft)
                            Button {
                                Speaker.shared.say(hit.word)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.commandSquare(.ghost, size: 26))
                            .help("発音を聞く")
                            Spacer()
                        }
                        Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                            .font(Theme.font(18, .black))
                            .foregroundStyle(Theme.lime)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        HStack {
                            Spacer()
                            if english.isInDeck(hit) {
                                Plate(text: "In deck", fill: Theme.tile, textColor: Theme.textSoft)
                            } else {
                                Button {
                                    english.addToDeck(hit)
                                } label: {
                                    Label("単語カードに追加", systemImage: "plus")
                                }
                                .buttonStyle(.command(.primary))
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
        }
        .onAppear { focused = true }
    }
}

// MARK: - 一覧(まとまり)

/// 出たことのあるものの一覧。行を押すとカードで開く(期限前の復習・「知ってる」を戻すのもカードから)
private struct CollectionCard: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        let rows = english.listRows()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(EnglishCoordinator.ListFilter.allCases) { filter in
                    if filter != .known || english.mode == .vocab {
                        filterButton(filter)
                    }
                }
                Spacer()
            }
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        CollectionRow(row: row) { english.focus(row.id) }
                    }
                }
                if rows.count >= 200 {
                    Text("先頭の 200 件を表示")
                        .font(Theme.font(Theme.Size.caption, .bold))
                        .foregroundStyle(Theme.textSoft)
                }
            }
        }
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
            .font(Theme.font(Theme.Size.caption, .black))
            .foregroundStyle(selected ? Theme.black : Theme.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Slant(skew: 6).fill(selected ? Theme.lime : Theme.tile))
            .contentShape(Slant(skew: 6))
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
                Text("▶")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(hovering ? Theme.lime : Color.clear)
                Text(row.title)
                    .font(Theme.font(Theme.Size.body, .black))
                    .foregroundStyle(Theme.white)
                    .lineLimit(1)
                    .frame(width: 170, alignment: .leading)
                Text(row.gloss)
                    .font(Theme.font(Theme.Size.caption, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.dueLabel)
                    .font(Theme.font(12, .black))
                    .foregroundStyle(row.dueLabel == "今日" ? Theme.lime : Theme.white)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background { if hovering { Slant().fill(Theme.tile) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("カードで開く")
    }
}

// MARK: - 今日のぶんが終わった・素材が無い

private struct StageClear: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String

    var body: some View {
        BattleCard(english: english, ink: 21) {
            VStack(alignment: .leading, spacing: 10) {
                Text("STAGE CLEAR!")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.lime)
                Text(message)
                    .font(Theme.font(Theme.Size.title, .black))
                    .foregroundStyle(Theme.white)
                Text("復習の続きは明日また出ます。まだやるなら、新しいものを 10 問足せます")
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("新しいのをもう 10 問") { english.addMoreNew() }
                        .buttonStyle(.command(.primary))
                    Button("一覧を見る") { english.presentation = .list }
                        .buttonStyle(.command(.ghost))
                }
                .padding(.top, 4)
                UndoLine(english: english)
            }
        }
    }
}

private struct MissingDataCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NO DATA")
                .font(Theme.display(34))
                .foregroundStyle(Theme.violet)
            Text("IELTS アプリの素材を取り込むと使えます")
                .font(Theme.font(Theme.Size.title, .black))
                .foregroundStyle(Theme.white)
            Text("ターミナルで IELTS アプリのフォルダを指定してビルドし直してください")
                .font(Theme.font(Theme.Size.body, .medium))
                .foregroundStyle(Theme.textSoft)
            Text("IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.lime)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.black)
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(CutRect(topTrailing: 22))
    }
}
