import SwiftUI
import NippoCore

/// 英語タブ(v12「Stencil Turf」夜版)。混凝土の上に白漆の単語卡 1 枚、右に章の置き場と本轮の盤面(4×5)。
/// 卡の上は濃い墨の本物の文字、色面はすべて焼いた素材(喷块・遮块・格)。答えたら卡の右上の枠に NICE! / MISS、
/// 章が出ている間(動)だけ卡の下縁から漆が垂れる。操作は卡の下の 1 列、撤销はその下の 1 行。
/// OOUI:もの(单词・考点词・语料・词典)を選ぶ → カード(1 つ)か列表(まとまり)→ カードに付いた操作。
/// 1 問 10 秒前後、キーボードだけで回せる(单词:空格 → 1〜4、考点词:1〜4 → 回车、语料:输入 → 回车、⌘Z 撤销)
struct EnglishView: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                StencilTabs(items: modeTabs, selection: $english.mode)
                Spacer(minLength: 8)
                streak
                if english.mode != .dict {
                    listToggle
                }
            }
            Group {
                if !english.loaded {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("加载中…")
                            .font(TypeRole.caption)
                            .foregroundStyle(Palette.textSecondary)
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
            .padding(.top, Turf.xxl)
        }
    }

    /// 单词 8 / 考点词 4 / 语料 / 词典(今日の分が終わった種類は ✓)
    private var modeTabs: [TabItem<EnglishCoordinator.Mode>] {
        EnglishCoordinator.Mode.allCases.map { mode -> TabItem<EnglishCoordinator.Mode> in
            let left = english.remaining[mode]
            let done = english.loaded && english.hasData && left == 0
            return TabItem(value: mode, title: done ? "\(mode.title) ✓" : mode.title, badge: left)
        }
    }

    /// 橙の炎 + 连续 4 天(今日の数と目標は help に)
    @ViewBuilder
    private var streak: some View {
        if english.streak > 0 {
            HStack(spacing: 5) {
                StencilIconView(icon: .flame, size: 15)
                    .foregroundStyle(Palette.orange)
                Text("连续 \(english.streak) 天")
                    .font(Typeface.cjk(14, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
            .fixedSize()
            .help("今天答了 \(english.todayCount) 题，目标 \(EnglishCoordinator.dailyGoal) 题，连续 \(english.streak) 天")
        }
    }

    /// カード ⇄ 列表(⌘L)。文字だけの小さな操作
    private var listToggle: some View {
        let showingList = english.presentation == .list
        return Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2)) {
                english.presentation = showingList ? .card : .list
            }
        } label: {
            Text(showingList ? "卡片" : "列表")
                .font(Typeface.cjk(13, weight: .bold))
        }
        .buttonStyle(BareButtonStyle())
        .keyboardShortcut("l", modifiers: .command)
        .help(showingList ? "回到卡片（⌘L）" : "查看列表（⌘L）")
        .accessibilityLabel(showingList ? "回到卡片" : "查看列表")
    }
}

// MARK: - 共通

/// 卡 + 右の列(章の置き場 176×100 と本轮の盤面)。章は卡にもボタンにも重ならない
private struct CardStage<Card: View>: View {
    @ObservedObject var english: EnglishCoordinator
    /// いま出ている問題にまだ答えていない(盤面の次のマスを橙の破線にする)
    let pending: Bool
    @ViewBuilder var card: () -> Card

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            card()
                .wordCardSurface()
                .overlay(alignment: .bottom) { CardDrips(english: english) }
            VStack(spacing: 12) {
                StampSlot(english: english)
                RoundBoard(english: english, pending: pending)
            }
            .frame(width: 176)
        }
    }
}

/// 章の置き場(卡の右上、176×100)。空のときは薄い破線の枠だけ
private struct StampSlot: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let flash = english.flash {
                TurfStamp(kind: flash.good ? .nice : .miss)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(flash.good ? "NICE!" : "MISS")
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .id(flash.id)
            } else {
                Rectangle()
                    .strokeBorder(Palette.cellEmptyStroke.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: 136, height: 58)
                    .rotationEffect(.degrees(-4))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 176, height: 100)
        // 弾むのは章だけ(カード全体には animation を掛けない)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.5), value: english.flash)
        .accessibilityHidden(english.flash == nil)
    }
}

/// 章が出ている間(動)だけ、卡の下縁から漆が垂れる(NICE! = 青、MISS = 黒、2 本)。静では出さない
private struct CardDrips: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let flash = english.flash {
                Drips(paint: flash.good ? .teal : .black, xs: [0.18, 0.7], seed: flash.good ? 0 : 3)
                    .transition(.opacity)
                    .id(flash.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: english.flash)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 本轮:今日の 20 問を 4×5 の格で(漆の満ち具合 = 評分、いまの 1 問 = 橙の破線)
private struct RoundBoard: View {
    @ObservedObject var english: EnglishCoordinator
    let pending: Bool

    private static let columns = 4
    private static let cell: CGFloat = 24
    /// 橙の破線と青の格のあいだは 8pt 空ける
    private static let gap: CGFloat = 8

    var body: some View {
        let goal = EnglishCoordinator.dailyGoal
        let count = min(english.todayCount, goal)
        let kinds = roundCells(english.todayResults, answered: english.todayCount, goal: goal, pending: pending)
        let rows = (kinds.count + Self.columns - 1) / Self.columns
        let label = "本轮 \(count)/\(goal)"
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("本轮")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 8)
                Text("\(count)/\(goal)")
                    .font(TypeRole.count)
                    .foregroundStyle(Palette.text)
            }
            VStack(spacing: Self.gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<Self.columns, id: \.self) { column in
                            let index = row * Self.columns + column
                            RatingCell(kind: index < kinds.count ? kinds[index] : .empty, size: Self.cell)
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(Self.columns) * Self.cell + CGFloat(Self.columns - 1) * Self.gap)
        .help("今天答了 \(english.todayCount) 题，目标 \(goal) 题")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// 卡の中の复习记录:黒い帯に 10 マス(18pt)+ 回数。いま答える 1 問は橙の破線
private struct ReviewBand: View {
    let id: String
    /// 初めて出たカード(0 回なのが確か)
    let isNew: Bool
    /// いまの 1 問に答え終わった
    let answered: Bool
    /// そのカードの評分(古い順。EnglishCoordinator.history)
    let past: [RatingCell.Kind]

    private static let slots = 10

    var body: some View {
        let cells = Self.cells(past, answered: answered, slots: Self.slots)
        // 同期より前の記録しかないカードは回数が分からないので出さない
        let known = isNew || !past.isEmpty
        let label = known ? "复习记录 \(past.count) 次" : "复习记录"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("复习记录")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.cardText)
                Spacer(minLength: 8)
                if known {
                    Text("\(past.count) 次")
                        .font(TypeRole.count)
                        .foregroundStyle(Palette.cardText)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<Self.slots, id: \.self) { index in
                    RatingCell(kind: index < cells.count ? cells[index] : .empty, size: 18)
                }
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            .material("band-black-night", fallback: Palette.black)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private static func cells(_ past: [RatingCell.Kind], answered: Bool, slots: Int) -> [RatingCell.Kind] {
        var cells = Array(past.suffix(answered ? slots : slots - 1))
        if !answered { cells.append(.current) }
        return cells
    }
}

/// 見出し語(大きく・まっすぐ・墨)
private struct HeadWord: View {
    let text: String
    /// 考点词・词典は一回り小さく
    var quiz = false

    var body: some View {
        Text(text)
            .font(quiz ? TypeRole.quizWord : TypeRole.word)
            .tracking(quiz ? -0.56 : -0.68)
            .foregroundStyle(Palette.cardText)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .textSelection(.enabled)
    }
}

/// 卡の上の小さな札:黒い遮块に白字 / 橙の札に黒字 / 黒い遮喷の枠に黒字。欧文は Archivo の幅広、中文は直立のまま
private struct CardTag: View {
    enum Style { case solid, orange, frame }

    let text: String
    var style: Style = .solid

    var body: some View {
        let latin = text.allSatisfy(\.isASCII)
        Text(text)
            .font(latin ? Typeface.archivo(12, weight: 900, width: 112) : Typeface.cjk(12, weight: .black))
            .tracking(latin ? 0.8 : 0)
            .foregroundStyle(style == .solid ? Palette.white : Palette.black)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background { paint }
    }

    @ViewBuilder
    private var paint: some View {
        switch style {
        case .solid:
            MaterialSlice(id: "band-black-night", fallback: Palette.black)
        case .orange:
            MaterialSlice(id: "tag-orange-night", fallback: Palette.orange)
        case .frame:
            if Material.has("frame-black-night") {
                MaterialSlice(id: "frame-black-night")
            } else {
                Rectangle().strokeBorder(Palette.black, lineWidth: 1.8)
            }
        }
    }
}

/// キーの説明(Space / Enter / ⌘Z)。枠なしの等幅、次要色
private struct Keycap: View {
    let text: String
    var color: Color = Palette.textSecondary

    var body: some View {
        Text(text)
            .font(TypeRole.keycap)
            .tracking(12 * 0.02)
            .foregroundStyle(color)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// 卡の上の区切り(墨の破線)
private struct DashedRule: View {
    var body: some View {
        RuleLine()
            .stroke(Palette.cardText.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 1.5)
            .accessibilityHidden(true)
    }
}

private struct RuleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// 白い卡の上の小さな操作(発音・再生)。墨の色のまま、乗せると少し薄く
private struct InkButtonStyle: ButtonStyle {
    var square: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        InkButtonBody(configuration: configuration, square: square)
    }
}

private struct InkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let square: CGFloat?
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(Palette.cardText)
            .frame(width: square, height: square)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : (hovering ? 0.75 : 1))
            .offset(y: configuration.isPressed ? 1 : 0)
            .onHover { hovering = $0 }
    }
}

/// 入力欄:焼いた黒い遮喷の枠(白い卡の上)。フォーカスは下辺の内側の 2pt の線
private struct InputBox<Content: View>: View {
    let focused: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Turf.input, maxHeight: Turf.input, alignment: .leading)
            .background { InputFrame() }
            .overlay(alignment: .bottom) {
                // .plain の入力欄は自分で描かないとフォーカスが分からない
                if focused {
                    Rectangle()
                        .fill(Palette.cardText)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
    }
}

private struct InputFrame: View {
    var body: some View {
        if Material.has("input-frame-night") {
            MaterialSlice(id: "input-frame-night")
        } else {
            Rectangle().strokeBorder(Palette.cardText, lineWidth: 2)
        }
    }
}

/// 直前の答え(結果の一言)と「↶ 撤销 ⌘Z」
private struct UndoLine: View {
    @ObservedObject var english: EnglishCoordinator
    /// 考点词:撤销を左に寄せる(右に「下一题」が来る)
    var compact = false

    var body: some View {
        if let action = visibleUndo(english) {
            HStack(spacing: 8) {
                if compact {
                    undoButton
                    message(action)
                } else {
                    message(action)
                    Spacer(minLength: 6)
                    undoButton
                }
            }
        }
    }

    private func message(_ action: EnglishCoordinator.LastAction) -> some View {
        Text(action.message)
            .font(TypeRole.caption)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
    }

    private var undoButton: some View {
        Button {
            english.undoLast()
        } label: {
            HStack(spacing: 6) {
                StencilIconView(icon: .undo, size: 14)
                Text("撤销")
                    .font(Typeface.cjk(13, weight: .bold))
                Keycap(text: "⌘Z")
            }
        }
        .buttonStyle(BareButtonStyle())
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityLabel("撤销")
    }
}

/// 撤销の行に出す直前の答え。语料は次の語を打っているあいだは出さない(⌘Z を入力欄の取り消しに譲る)
@MainActor
private func visibleUndo(_ english: EnglishCoordinator) -> EnglishCoordinator.LastAction? {
    guard let action = english.lastAction, action.mode == english.mode,
          english.mode != .spell || english.spellResult != nil || english.spellInput.isEmpty else { return nil }
    return action
}

private extension View {
    /// 白漆の単語卡(焼いた喷块)。中の文字は濃い墨。入力欄のカーソル・選択の色が白く消えないよう、卡の中は明るい外観で描く
    func wordCardSurface() -> some View {
        self
            .padding(Turf.heroPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .foregroundStyle(Palette.cardText)
            .environment(\.colorScheme, .light)
            .material("card-white-night", fallback: Palette.white)
    }
}

// MARK: - 单词

private struct VocabView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let card = english.vocabCard {
            VStack(alignment: .leading, spacing: 0) {
                CardStage(english: english, pending: !card.known) {
                    content(card)
                }
                actions(card)
                    .padding(.top, 36)
                if visibleUndo(english) != nil {
                    UndoLine(english: english)
                        .padding(.top, 12)
                }
            }
        } else {
            StageClear(english: english, message: "今天的单词做完了")
        }
    }

    private func content(_ card: EnglishCoordinator.VocabCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CardTag(text: card.level)
                if card.isNew && !card.known {
                    CardTag(text: "NEW", style: .orange)
                }
                if let pos = card.pos, !pos.isEmpty {
                    CardTag(text: pos, style: .frame)
                }
            }
            HeadWord(text: card.word)
                .padding(.top, 12)
            HStack(spacing: 8) {
                if let phonetic = card.phonetic {
                    Text(phonetic)
                        .font(TypeRole.ipa)
                        .foregroundStyle(Palette.cardTextSecondary)
                        .textSelection(.enabled)
                }
                Button {
                    english.speakWord()
                } label: {
                    StencilIconView(icon: .speaker, size: 16)
                }
                .buttonStyle(InkButtonStyle(square: 26))
                .keyboardShortcut("r", modifiers: .command)
                .help("听发音（⌘R）")
                .accessibilityLabel("听发音")
            }
            .padding(.top, 4)
            ReviewBand(id: card.id, isNew: card.isNew, answered: card.known,
                       past: english.history(for: card.id).map { kindOf($0) })
                .padding(.top, 16)
            DashedRule()
                .padding(.top, 14)
            meaning(card)
                .padding(.top, 14)
            if card.known {
                Text("你标记了「已经会了」，现在不会出题")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.cardTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    /// 释义:めくる前は黒い遮喷の帯 2 本(長さ違い)、めくったら 楼层 + 例文(見出し語に青の遮块)
    @ViewBuilder
    private func meaning(_ card: EnglishCoordinator.VocabCard) -> some View {
        if english.revealed || card.known {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("释义")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.cardTextSecondary)
                    Text(card.meaning)
                        .font(card.meaning.count <= 10 ? TypeRole.definition : Typeface.cjk(20, weight: .black))
                        .tracking(card.meaning.count <= 10 ? 32 * 0.06 : 0)
                        .foregroundStyle(Palette.cardText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let example = card.example {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        ExampleLine(example: example, word: card.word)
                        Button {
                            english.speakExample()
                        } label: {
                            StencilIconView(icon: .speaker, size: 14)
                        }
                        .buttonStyle(InkButtonStyle(square: 22))
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                        .help("听例句（⇧⌘R）")
                        .accessibilityLabel("听例句")
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Text("释义")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.cardTextSecondary)
                    .padding(.top, 8)
                Redaction()
            }
        }
    }

    /// 卡の下の 1 列:めくる前 = 已经会了 / Space 显示释义、めくった後 = 評分 1〜4、「已经会了」の卡 = 恢复出题
    @ViewBuilder
    private func actions(_ card: EnglishCoordinator.VocabCard) -> some View {
        if card.known {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("恢复出题") { english.restoreCurrent() }
                    .buttonStyle(SprayButtonStyle(height: 50))
            }
        } else if english.revealed {
            HStack(spacing: 8) {
                rateButton("忘了", key: "1", rating: .again)
                rateButton("模糊", key: "2", rating: .hard)
                rateButton("记住了", key: "3", rating: .good)
                rateButton("太简单", key: "4", rating: .easy)
            }
            // 空格 = 记住了(1 問 1 キー:空格で見て、空格で次へ)
            .background {
                Button("") { rate(.good) }
                    .keyboardShortcut(.space, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        } else {
            HStack(spacing: 12) {
                Button("已经会了") { markKnown() }
                    .buttonStyle(FrameButtonStyle(height: 50))
                    .help("以后不再出这个词（可以在列表的「已掌握」里恢复）")
                Spacer(minLength: 8)
                Keycap(text: "Space")
                Button("显示释义") { english.reveal() }
                    .buttonStyle(SprayButtonStyle(height: 50))
                    .keyboardShortcut(.space, modifiers: [])
            }
        }
    }

    /// 評分:灰の遮块(记住了 = 空格の既定なので青)+ 評分の格 + キー + 文字
    private func rateButton(_ title: String, key: KeyEquivalent, rating: SRSRating) -> some View {
        let look: BlockButtonStyle.Look = rating == .good ? .selected : .idle
        return Button {
            rate(rating)
        } label: {
            HStack(spacing: 5) {
                // 格の下に黒い縁(青の遮块の上でも格が読める)
                RatingCell(kind: kindOf(rating), size: 14)
                    .padding(3)
                    .background(Palette.black)
                Text(String(key.character))
                    .font(TypeRole.keycap)
                    .foregroundStyle(look == .selected ? Palette.cardTextSecondary : Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typeface.cjk(16, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(BlockButtonStyle(state: look, height: Turf.ratingButton))
        .keyboardShortcut(key, modifiers: [])
    }

    private func rate(_ rating: SRSRating) {
        english.rate(rating)
    }

    private func markKnown() {
        english.markKnown()
    }
}

/// めくる前の释义:黒い遮喷の帯 2 本(長さ違い)
private struct Redaction: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .material("redact-black-night", fallback: Palette.black)
                .padding(.trailing, 38)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 14)
                .material("redact-black-night", fallback: Palette.black)
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }
}

/// 例文(欧文の斜体)。見出し語は青の遮块の上に。1 行に収まらないときは折り返し(見出し語は青の地色)
private struct ExampleLine: View {
    let example: String
    let word: String

    var body: some View {
        if let range = example.range(of: word, options: .caseInsensitive) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(example[..<range.lowerBound])
                    Text(example[range])
                        .padding(.horizontal, 3)
                        .background { MaterialSlice(id: "block-teal-night", fallback: Palette.teal) }
                        .padding(.horizontal, 2)
                    Text(example[range.upperBound...])
                }
                .font(TypeRole.example)
                .foregroundStyle(Palette.cardText)
                .lineLimit(1)
                .fixedSize()
                Text(highlighted)
                    .font(TypeRole.example)
                    .foregroundStyle(Palette.cardText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .textSelection(.enabled)
        } else {
            Text(example)
                .font(TypeRole.example)
                .foregroundStyle(Palette.cardText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var highlighted: AttributedString {
        var text = AttributedString(example)
        if let range = text.range(of: word, options: .caseInsensitive) {
            let teal: Color = Palette.teal
            text[range].backgroundColor = teal
        }
        return text
    }
}

// MARK: - 考点词

private struct ParaphraseCard: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let q = english.question {
            VStack(alignment: .leading, spacing: 0) {
                CardStage(english: english, pending: english.picked == nil) {
                    content(q)
                }
                options(q)
                    .padding(.top, 36)
                if visibleUndo(english) != nil || english.picked != nil {
                    HStack(spacing: 12) {
                        UndoLine(english: english, compact: true)
                        Spacer(minLength: 8)
                        if english.picked != nil {
                            nextButton
                        }
                    }
                    .padding(.top, 12)
                }
            }
        } else {
            StageClear(english: english, message: "今天的考点词做完了")
        }
    }

    private func content(_ q: ParaphraseQuestion) -> some View {
        let skill = q.entry.skill == "listening" ? "听力" : "阅读"
        let gloss = [q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CardTag(text: "考点词")
                CardTag(text: skill, style: .frame)
            }
            HeadWord(text: q.entry.w, quiz: true)
                .padding(.top, 12)
            Text("（\(skill)）常被换成？")
                .font(Typeface.cjk(20, weight: .bold))
                .foregroundStyle(Palette.cardText)
                .padding(.top, 2)
            ReviewBand(id: paraID(q), isNew: false, answered: english.picked != nil,
                       past: english.history(for: paraID(q)).map { kindOf($0) })
                .padding(.top, 16)
            DashedRule()
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 4) {
                if !gloss.isEmpty {
                    Text(gloss)
                        .font(Typeface.cjk(13.5, weight: .medium))
                        .foregroundStyle(Palette.cardText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let picked = english.picked {
                    Text(picked == q.answerIndex ? "正确" : "错了，今天还会再出")
                        .font(Typeface.cjk(15, weight: .bold))
                        .foregroundStyle(Palette.cardText)
                        .padding(.top, 6)
                    Text("可替换为：" + q.entry.syn.joined(separator: " · "))
                        .font(Typeface.cjk(13, weight: .medium))
                        .foregroundStyle(Palette.cardTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 12)
        }
    }

    /// 選択肢 2×2(灰の遮块。正解 = 青 + ✓、誤って選んだ = 灰 + 删除线 + ✕)
    private func options(_ q: ParaphraseQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: q.choices.count, by: 2)), id: \.self) { start in
                HStack(spacing: 10) {
                    option(start, question: q)
                    if start + 1 < q.choices.count {
                        option(start + 1, question: q)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private func option(_ index: Int, question q: ParaphraseQuestion) -> some View {
        let picked = english.picked
        let isAnswer = picked != nil && index == q.answerIndex
        let isWrongPick = picked == index && !isAnswer
        let look: BlockButtonStyle.Look = isAnswer ? .selected : (isWrongPick ? .wrong : .idle)
        let status: String
        if isAnswer {
            status = picked == index ? "你的选择，正确" : "正确答案"
        } else {
            status = isWrongPick ? "你的选择，错误" : ""
        }
        return Button {
            choose(index, question: q)
        } label: {
            Text(q.choices[index])
                .font(Typeface.archivo(22, weight: 700))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, 20)
                // 右の「正确答案 ✓」「你的选择 ✕」の分を空ける
                .padding(.trailing, isAnswer || isWrongPick ? 96 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BlockButtonStyle(state: look, height: Turf.optionButton))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .accessibilityValue(status)
        // 番号と状態は削除線の外(選択肢の語だけに線を引く)
        .overlay(alignment: .leading) {
            Text("\(index + 1)")
                .font(TypeRole.keycap)
                .foregroundStyle(look == .idle ? Palette.textSecondary : Palette.cardTextSecondary)
                .padding(.leading, 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) {
            if isAnswer {
                HStack(spacing: 8) {
                    Text(picked == index ? "你的选择" : "正确答案")
                        .font(Typeface.cjk(13, weight: .bold))
                    StencilIconView(icon: .check, size: 14)
                }
                .foregroundStyle(Palette.black)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else if isWrongPick {
                // ✕ は BlockButtonStyle が右端に置く
                Text("你的选择")
                    .font(Typeface.cjk(13, weight: .bold))
                    .foregroundStyle(Palette.black)
                    .padding(.trailing, 12 + 14 + 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var nextButton: some View {
        Button {
            english.nextParaphrase()
        } label: {
            HStack(spacing: 8) {
                Text("下一题")
                    .font(Typeface.cjk(14, weight: .bold))
                Keycap(text: "Enter")
            }
        }
        .buttonStyle(BareButtonStyle(color: Palette.text))
        .keyboardShortcut(.defaultAction)
    }

    private func choose(_ index: Int, question q: ParaphraseQuestion) {
        english.choose(index)
    }
}

/// 考点词のカード id(EnglishCoordinator の出題と同じ形)
private func paraID(_ q: ParaphraseQuestion) -> String {
    "para:\(q.entry.skill):\(q.entry.w)"
}

// MARK: - 语料(听写)

private struct SpellCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            VStack(alignment: .leading, spacing: 0) {
                CardStage(english: english, pending: english.spellResult == nil) {
                    content(item)
                }
                actions
                    .padding(.top, 36)
                if visibleUndo(english) != nil {
                    UndoLine(english: english)
                        .padding(.top, 12)
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

    private func content(_ item: EnglishCoordinator.SpellItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CardTag(text: "听写")
                CardTag(text: item.word.set, style: .frame)
                if item.isNew {
                    CardTag(text: "NEW", style: .orange)
                }
            }
            .help("王陆语料 · \(item.word.set)")
            playButton
                .padding(.top, 14)
            ReviewBand(id: item.id, isNew: item.isNew, answered: english.spellResult != nil,
                       past: english.history(for: item.id).map { kindOf($0) })
                .padding(.top, 16)
            Text("你的拼写")
                .font(TypeRole.caption)
                .foregroundStyle(Palette.cardText)
                .padding(.top, 16)
            InputBox(focused: focused && english.spellResult == nil) {
                ZStack(alignment: .leading) {
                    // 採点後も入力欄は残す(回车で次へ・焦点を保つ)。見た目は印を付けた綴りに置き換える
                    TextField("", text: $english.spellInput,
                              prompt: Text("输入听到的单词，按回车").foregroundStyle(Palette.cardTextSecondary.opacity(0.6)))
                        .textFieldStyle(.plain)
                        .font(TypeRole.input)
                        .foregroundStyle(Palette.cardText)
                        .autocorrectionDisabled(true)
                        .focused($focused)
                        .onSubmit {
                            submit()
                            focused = true
                        }
                        .opacity(english.spellResult == nil ? 1 : 0)
                    if english.spellResult != nil {
                        typed(item.word)
                    }
                }
            }
            .padding(.top, 8)
            if let result = english.spellResult {
                answer(result, item.word)
                    .padding(.top, 12)
            }
        }
    }

    /// 橙の円(喷漆)+ 模板の再生アイコン。⌘R で何度でも
    private var playButton: some View {
        Button {
            english.play()
            focused = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    PlayDisc()
                    StencilIconView(icon: .play, size: 20)
                        .foregroundStyle(Palette.black)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("播放")
                            .font(TypeRole.cardTitle)
                        Keycap(text: "⌘R", color: Palette.cardTextSecondary)
                    }
                    Text("英式发音 · 建议戴耳机")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.cardTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(InkButtonStyle())
        .keyboardShortcut("r", modifiers: .command)
        .help("播放（⌘R）")
    }

    /// 卡の下の 1 列:慢速 / 不知道 ⌘⌫ … Enter 检查 → 下一个
    private var actions: some View {
        HStack(spacing: 10) {
            Button("慢速") {
                english.play(slow: true)
                focused = true
            }
            .buttonStyle(FrameButtonStyle(height: 50))
            if english.spellResult == nil {
                Button {
                    giveUp()
                } label: {
                    HStack(spacing: 8) {
                        Text("不知道")
                        Keycap(text: "⌘⌫")
                    }
                }
                .buttonStyle(FrameButtonStyle(height: 50))
                .keyboardShortcut(.delete, modifiers: .command)
            }
            Spacer(minLength: 8)
            Keycap(text: "Enter")
            if english.spellResult == nil {
                Button("检查") { submit() }
                    .buttonStyle(SprayButtonStyle(height: 50))
            } else {
                Button("下一个") {
                    submit()
                    focused = true
                }
                .buttonStyle(SprayButtonStyle(height: 50))
            }
        }
    }

    /// 自分の綴り:余計な字・違う字に橙の地
    @ViewBuilder
    private func typed(_ word: DictationWord) -> some View {
        if english.spellInput.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("—")
                .font(TypeRole.input)
                .foregroundStyle(Palette.cardTextSecondary)
                .allowsHitTesting(false)
        } else {
            Text(marks(word).typed)
                .font(TypeRole.input)
                .tracking(3)
                .foregroundStyle(Palette.cardText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsHitTesting(false)
        }
    }

    /// 判定の一言 + 正しい綴り(足りない字・違う字に青の地)+ 発音と意味
    private func answer(_ result: SpellResult, _ word: DictationWord) -> some View {
        let gloss = [word.ipa.map { "/\($0)/" }, word.zh].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.title(result))
                .font(TypeRole.caption)
                .foregroundStyle(Palette.cardText)
            Text(marks(word).answer)
                .font(TypeRole.input)
                .tracking(3)
                .foregroundStyle(Palette.cardText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !gloss.isEmpty {
                Text(gloss)
                    .font(Typeface.cjk(13, weight: .semibold))
                    .foregroundStyle(Palette.cardText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func title(_ result: SpellResult) -> String {
        switch result {
        case .correct: return "正确"
        case .almost: return "差一点（错了 1 个字母）"
        case .wrong: return "正确答案 · 今天再来一次"
        }
    }

    /// 入力と正解の食い違い(入力の字 = 橙、正解の字 = 青)
    private func marks(_ word: DictationWord) -> (typed: AttributedString, answer: AttributedString) {
        let typed = Array(SpellCheck.normalize(english.spellInput))
        let answer = Array(word.w)
        let marks = spellingMarks(typed, answer)
        return (markedText(typed, marks.input, color: Palette.orange),
                markedText(answer, marks.answer, color: Palette.teal))
    }

    /// 回车・检查・下一个:未採点なら採点、採点済みなら次へ
    private func submit() {
        english.submitSpelling()
    }

    private func giveUp() {
        english.giveUpSpelling()
    }
}

/// 再生ボタンの橙の円(白い卡の上に喷いた素材。なければ単色の円)
private struct PlayDisc: View {
    var body: some View {
        if Material.has("button-play-orange-night") {
            MaterialSprite(id: "button-play-orange-night")
        } else {
            Circle().fill(Palette.orange)
        }
    }
}

/// 綴りの食い違い:編集距離の道筋をたどって、入力の余計・誤った字と、正解の足りない・違う字に印を付ける
private func spellingMarks(_ input: [Character], _ answer: [Character]) -> (input: [Bool], answer: [Bool]) {
    let n = input.count, m = answer.count
    var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in 0...n { cost[i][0] = i }
    for j in 0...m { cost[0][j] = j }
    if n > 0 && m > 0 {
        for i in 1...n {
            for j in 1...m {
                let step = sameLetter(input[i - 1], answer[j - 1]) ? 0 : 1
                cost[i][j] = min(cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + step)
            }
        }
    }
    var inputMarks = Array(repeating: false, count: n)
    var answerMarks = Array(repeating: false, count: m)
    var i = n, j = m
    while i > 0 || j > 0 {
        if i > 0, j > 0 {
            let same = sameLetter(input[i - 1], answer[j - 1])
            if cost[i][j] == cost[i - 1][j - 1] + (same ? 0 : 1) {
                if !same {
                    inputMarks[i - 1] = true
                    answerMarks[j - 1] = true
                }
                i -= 1
                j -= 1
                continue
            }
        }
        if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
            inputMarks[i - 1] = true
            i -= 1
        } else if j > 0 {
            answerMarks[j - 1] = true
            j -= 1
        } else {
            // ここには来ない(念のため)
            i -= 1
        }
    }
    return (inputMarks, answerMarks)
}

private func sameLetter(_ a: Character, _ b: Character) -> Bool {
    String(a).lowercased() == String(b).lowercased()
}

/// 印の付いた字に地色を敷いた文字列
private func markedText(_ characters: [Character], _ marks: [Bool], color: Color) -> AttributedString {
    var text = AttributedString()
    for (index, character) in characters.enumerated() {
        var run = AttributedString(String(character))
        if index < marks.count, marks[index] {
            run.backgroundColor = color
        }
        text.append(run)
    }
    return text
}

// MARK: - 词典

/// 白い卡に入力欄と引けた語。単語卡へ足す操作は卡の下
private struct DictionaryCard: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        let empty = english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let hit: DictHit? = empty ? nil : english.dictHit
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CardTag(text: "词典")
                InputBox(focused: focused) {
                    TextField("", text: $english.dictQuery,
                              prompt: Text("输入英文单词（例：sustainable）").foregroundStyle(Palette.cardTextSecondary.opacity(0.6)))
                        .textFieldStyle(.plain)
                        .font(TypeRole.input)
                        .foregroundStyle(Palette.cardText)
                        .autocorrectionDisabled(true)
                        .focused($focused)
                }
                .padding(.top, 14)
                if empty {
                    Text("工作中遇到的生词，随手查。查到的词可以加进单词卡，之后复习")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.cardTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                } else if let hit {
                    entry(hit)
                        .padding(.top, 18)
                } else {
                    Text("没有找到「\(english.dictQuery)」")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.cardTextSecondary)
                        .padding(.top, 12)
                }
            }
            .wordCardSurface()
            if let hit {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    if english.isInDeck(hit) {
                        Text("已在单词卡里")
                            .font(TypeRole.caption)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        Keycap(text: "⌘⏎")
                        Button("加入单词卡") { english.addToDeck(hit) }
                            .buttonStyle(SprayButtonStyle(height: 50))
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("加入单词卡（⌘⏎）")
                    }
                }
                .padding(.top, 24)
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

    private func entry(_ hit: DictHit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HeadWord(text: hit.word, quiz: true)
                Text("/\(hit.ipa)/")
                    .font(TypeRole.ipa)
                    .foregroundStyle(Palette.cardTextSecondary)
                Button {
                    Speaker.shared.say(hit.word)
                } label: {
                    StencilIconView(icon: .speaker, size: 16)
                }
                .buttonStyle(InkButtonStyle(square: 26))
                .help("听发音")
                .accessibilityLabel("听发音")
                Spacer(minLength: 0)
            }
            Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                .font(Typeface.cjk(15, weight: .semibold))
                .foregroundStyle(Palette.cardText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 10)
        }
    }
}

// MARK: - 列表

/// 出现过的单词/考点词/语料。点一行就用卡片打开(提前复习、恢复「已掌握」都在卡片上)
private struct WordList: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        let rows = english.listRows()
        VStack(alignment: .leading, spacing: 12) {
            StencilTabs(items: EnglishCoordinator.ListFilter.allCases
                .filter { $0 != .known || english.mode == .vocab }
                .map { TabItem(value: $0, title: $0.title, badge: english.listCount($0)) },
                        selection: $english.listFilter)
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(TypeRole.body)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        WordRow(row: row) { english.focus(row.id) }
                    }
                }
                if rows.count >= 200 {
                    Text("只显示前 200 条")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.textSecondary)
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

/// 一覧の 1 行:混凝土の上の本物の文字。乗せると灰の遮块
private struct WordRow: View {
    let row: EnglishCoordinator.ListRow
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Text(row.title)
                    .font(Typeface.archivo(16, weight: 700))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(row.gloss)
                    .font(Typeface.cjk(13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.dueLabel)
                    .font(Typeface.cjk(12, weight: .bold))
                    .foregroundStyle(row.dueLabel == "今天" ? Palette.text : Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: Turf.scheduleRow)
            .background {
                if hovering {
                    MaterialSlice(id: "block-slate-night", fallback: Palette.rowHover)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.rule.opacity(0.4))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
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

/// 今日の分が終わった:白い卡に本轮の盤面(黒い台)、模板の 20/20、CLEAR、凡例。20 問そろったら奖章(神兽、説明なし)
private struct StageClear: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String
    /// 「回到今日」:面板のタブ(MenuContentView と同じ保存先)
    @AppStorage("panelTab") private var panelTab = "today"

    var body: some View {
        let goal = EnglishCoordinator.dailyGoal
        let count = min(english.todayCount, goal)
        let full = english.todayCount >= goal
        let cells = roundCells(english.todayResults, answered: english.todayCount, goal: goal, pending: false)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    RoundBoard(english: english, pending: false)
                        .padding(14)
                        .material("plate-black-night", fallback: Palette.black)
                    if english.streak > 0 {
                        StreakPlate(streak: english.streak)
                    }
                    CardTag(text: "要复习的明天会再出现", style: .frame)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        CardTag(text: "本轮")
                        PaintTag(text: "CLEAR", asset: "tag-teal-night", fallback: Palette.teal)
                    }
                    StencilText(text: "\(count)/\(goal)", set: "big-black", scale: 0.45, fallbackColor: Palette.cardText)
                        .padding(.top, 14)
                    Text(message)
                        .font(Typeface.cjk(15, weight: .bold))
                        .foregroundStyle(Palette.cardText)
                        .padding(.top, 10)
                    if full {
                        Text("全部完成，地盘喷满了")
                            .font(TypeRole.caption)
                            .foregroundStyle(Palette.cardTextSecondary)
                            .padding(.top, 4)
                    }
                    RoundLegend(cells: Array(cells.prefix(count)))
                        .padding(.top, 14)
                    if full {
                        ClearBadge()
                            .padding(.top, 18)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .wordCardSurface()

            HStack(spacing: 10) {
                Button {
                    english.addMoreNew()
                } label: {
                    HStack(spacing: 8) {
                        Text("再来 10 个新的")
                        Keycap(text: "⌘N")
                    }
                }
                .buttonStyle(FrameButtonStyle(height: 50))
                .keyboardShortcut("n", modifiers: .command)
                .help("还想继续的话，可以再加 10 个新的")
                Button("查看列表") { english.presentation = .list }
                    .buttonStyle(FrameButtonStyle(height: 50))
                Spacer(minLength: 8)
                Button("回到今日") { panelTab = "today" }
                    .buttonStyle(SprayButtonStyle(height: 50))
            }
            .padding(.top, 28)
            if visibleUndo(english) != nil {
                UndoLine(english: english)
                    .padding(.top, 12)
            }
        }
    }
}

/// 凡例:记住了 / 太简单 / 模糊 / 忘了 と本轮の数
private struct RoundLegend: View {
    let cells: [RatingCell.Kind]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
            GridRow {
                entry(.good, "记住了")
                entry(.easy, "太简单")
            }
            GridRow {
                entry(.fuzzy, "模糊")
                entry(.forgot, "忘了")
            }
        }
    }

    private func entry(_ kind: RatingCell.Kind, _ title: String) -> some View {
        let number = cells.filter { $0 == kind }.count
        return HStack(spacing: 8) {
            RatingCell(kind: kind, size: 14)
            Text(title)
                .font(Typeface.cjk(13, weight: .bold))
                .foregroundStyle(Palette.cardText)
            Spacer(minLength: 8)
            Text("\(number)")
                .font(TypeRole.count)
                .foregroundStyle(Palette.cardText)
        }
        .frame(width: 112)
        .accessibilityElement(children: .combine)
    }
}

/// 黒い遮块に 橙の炎 + 连续 N 天
private struct StreakPlate: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            StencilIconView(icon: .flame, size: 14)
                .foregroundStyle(Palette.orange)
            Text("连续 \(streak) 天")
                .font(Typeface.cjk(13, weight: .bold))
                .foregroundStyle(Palette.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .material("plate-black-night", fallback: Palette.black)
    }
}

/// 20/20 の奖章:切り角の黒い底板(−2° は素材に焼き込み済み)+ 曜日の神兽(青漆)。文字は付けない
private struct ClearBadge: View {
    var body: some View {
        ZStack {
            if Material.has("badge-plate-night") {
                MaterialSlice(id: "badge-plate-night")
            } else {
                ChamferedPlate()
                    .fill(Palette.black)
                    .rotationEffect(.degrees(-2))
            }
            MaterialSprite.height(Myth.badgeCreature(for: Date()), 89)
                .frame(width: 119, height: 89)
                .rotationEffect(.degrees(-2))
        }
        .frame(width: 142, height: 105)
        .accessibilityHidden(true)
    }
}

/// 模板の底板の形(四隅を切り落とす)。素材がないときだけ使う
private struct ChamferedPlate: Shape {
    var cut: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

private struct MissingData: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有英语素材")
                .font(TypeRole.cardTitle)
                .foregroundStyle(Palette.cardText)
            Text("导入 IELTS app 的素材后就能用。在终端里指定 IELTS app 的文件夹重新构建：")
                .font(TypeRole.caption)
                .foregroundStyle(Palette.cardTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh")
                .font(TypeRole.keycap)
                .foregroundStyle(Palette.teal)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .material("band-black-night", fallback: Palette.black)
                .padding(.top, 4)
        }
        .wordCardSurface()
    }
}

// MARK: - 本轮の漆

/// 本轮の盤面:今日答えた順に goal マス + いまの 1 問(橙の破線)+ 空き。結果は english_log(同期した分も入る)
private func roundCells(_ results: [String], answered: Int, goal: Int, pending: Bool) -> [RatingCell.Kind] {
    (0..<max(goal, 0)).map { index -> RatingCell.Kind in
        if index < answered {
            return results.indices.contains(index) ? kindOf(result: results[index]) : .good
        }
        return index == answered && pending ? .current : .empty
    }
}

/// english_log の結果 → 格の漆(「知ってる」は太简单と同じ満 + 星)
private func kindOf(result: String) -> RatingCell.Kind {
    if result == "known" { return .easy }
    return SRSRating(rawValue: result).map { kindOf($0) } ?? .good
}

/// 評分 → 格の漆(忘了 = 灰 ✕、模糊 = まばら、记住了 = 満、太简单 = 満 + 星)
private func kindOf(_ rating: SRSRating) -> RatingCell.Kind {
    switch rating {
    case .again: return .forgot
    case .hard: return .fuzzy
    case .good: return .good
    case .easy: return .easy
    }
}

/// 聴写の判定 → 格の漆(差一点 = 模糊)
private func kindOf(_ result: SpellResult) -> RatingCell.Kind {
    switch result {
    case .correct: return .good
    case .almost: return .fuzzy
    case .wrong: return .forgot
    }
}
