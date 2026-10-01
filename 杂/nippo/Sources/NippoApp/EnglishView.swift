import AppKit
import NippoCore
import SwiftUI

/// 英語タブ(v12.1「Stencil Turf」夜版)。混凝土の墙に白漆の単語卡 1 枚(308pt)、右の列(148pt)に章の槽と本轮の地盘(4×5、30pt)。
/// 卡の上は濃い墨の本物の文字、色面はすべて焼いた素材(喷块・遮块・格・折痕)。答えたら章の槽に NICE! / MISS が喷かれ、
/// その間だけ卡の下縁から白い漆が垂れる(下の操作の列には届かない長さ)。卡と操作の列のあいだに模板の継ぎ目。
/// 子標籤の行の右には、どの画面でも今日の進み具合(连续 N 天 · 12/20、達成で青 + ✓)。
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
                EngProgress(english: english)
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
                    EngMissingData()
                } else if english.presentation == .list && english.mode != .dict {
                    EngWordList(english: english)
                } else {
                    switch english.mode {
                    case .vocab: EngVocab(english: english)
                    case .para: EngParaphrase(english: english)
                    case .spell: EngSpell(english: english)
                    case .dict: EngDictionary(english: english)
                    }
                }
            }
            .padding(.top, Turf.xxl)
        }
    }

    /// 单词 8 / 考点词 4 / 语料 / 词典(今日の分が終わった種類は数の代わりに模板の ✓)
    private var modeTabs: [TabItem<EnglishCoordinator.Mode>] {
        EnglishCoordinator.Mode.allCases.map { mode -> TabItem<EnglishCoordinator.Mode> in
            let left = english.remaining[mode]
            let done = english.loaded && english.hasData && left == 0
            return TabItem(value: mode, title: mode.title, badge: done ? nil : left, done: done)
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
                .font(Typeface.mixed(13, weight: 700))
        }
        .buttonStyle(BareButtonStyle())
        .keyboardShortcut("l", modifiers: .command)
        .help(showingList ? "回到卡片（⌘L）" : "查看列表（⌘L）")
        .accessibilityLabel(showingList ? "回到卡片" : "查看列表")
    }
}

// MARK: - 寸法(D1:渲染稿どおり)

private enum EngMetrics {
    /// 右の列(章の槽と本轮の地盘)。面板の右端にそろえる
    static let column: CGFloat = 148
    /// 卡と右の列のあいだ(472 − 308 − 148 = 16、english.png のとおり)
    static let columnGap: CGFloat = 16
    /// 単語卡(card-white-night は 308×380 で焼いてある)
    static let cardWidth: CGFloat = 308
    /// 単語卡の左右の余白。中の幅 272 = 复习记录の帯・入力枠・折痕を焼いた幅
    static let cardPadding: CGFloat = 18
    static let cardInner: CGFloat = cardWidth - 2 * cardPadding
    /// 章の槽
    static let slotHeight: CGFloat = 86
    /// 本轮の地盘(4 × 5、30pt、間 6pt = 138 × 174)
    static let boardColumns = 4
    static let boardCell: CGFloat = 30
    static let boardGap: CGFloat = 6
    static var boardWidth: CGFloat { CGFloat(boardColumns) * boardCell + CGFloat(boardColumns - 1) * boardGap }
    /// 复习记录(10 マス、20pt、間 4pt。黒い帯 272×32 の内側 4pt)
    static let historySlots = 10
    static let historyCell: CGFloat = 20
    static let historyGap: CGFloat = 4
    static let historyPadding: CGFloat = 4
    static let historyBand: CGFloat = 32
    /// 卡(と右の列)と操作の列のあいだ。垂れはこれより 6pt 短いものだけ
    static let stageGap: CGFloat = 40
    /// 聴写の字の格(20 × 32)と、入力枠の内側の余白
    static let letterWidth: CGFloat = 20
    static let letterHeight: CGFloat = 32
    static let letterInset: CGFloat = 10
    /// 字の格を並べられる幅(卡の中 − 入力枠の内側の余白)
    static let letterRow: CGFloat = cardInner - 2 * letterInset
    /// 入力枠(input-frame-night 244×52)
    static let inputHeight: CGFloat = 52
}

// MARK: - 共通

/// 焼けている最初の素材(新しい素材がまだ無いときは前からある素材で代える)
@MainActor
private func engFirstBaked(_ ids: [String]) -> String? {
    Baked.first(ids)
}

/// 白漆の卡の種類:単語卡(280×380 焼き)/ 広い卡(472×340:通关・词典の結果)/ 短い卡(472×160:词典の空・素材なし)
private enum EngCardKind {
    case word, wide, short

    var assets: [String] {
        switch self {
        case .word: return ["card-white-night"]
        case .wide: return ["card-white-wide-night", "card-white-night"]
        case .short: return ["card-white-short-night", "card-white-night"]
        }
    }

    var width: CGFloat? { self == .word ? EngMetrics.cardWidth : nil }

    /// 単語卡は左右 18pt(中の幅 244)、広い / 短い卡は主角卡と同じ 20pt
    var padding: EdgeInsets {
        self == .word
            ? EdgeInsets(top: Turf.heroPadding.top, leading: EngMetrics.cardPadding,
                         bottom: Turf.heroPadding.bottom, trailing: EngMetrics.cardPadding)
            : Turf.heroPadding
    }

    /// 焼いた高さの 0.8 倍より低くしない(九宮格を −20% より潰さない)。専用の素材があるときだけ
    @MainActor var minHeight: CGFloat? {
        guard let id = assets.first, Baked.has(id), let asset = Baked.asset(id) else { return nil }
        return asset.layoutSize.height * 0.8
    }
}

@MainActor
private extension View {
    /// 白漆の卡(焼いた喷块)。中の文字は濃い墨。入力欄のカーソル・選択の色が白く消えないよう、卡の中は明るい外観で描く
    func engCardSurface(_ kind: EngCardKind) -> some View {
        self
            .padding(kind.padding)
            .frame(minWidth: kind.width, maxWidth: kind.width ?? .infinity, minHeight: kind.minHeight,
                   alignment: .topLeading)
            .foregroundStyle(Palette.cardText)
            .environment(\.colorScheme, .light)
            .background {
                BakedSlice(id: engFirstBaked(kind.assets) ?? kind.assets[0], fallback: Palette.white)
            }
    }
}

/// 卡(280)+ 右の列(148、面板の右端。章の槽 148×86 と本轮の地盘)。章は卡にもボタンにも重ならない
private struct EngStage<Card: View>: View {
    @ObservedObject var english: EnglishCoordinator
    /// いま出ている問題にまだ答えていない(地盘の次のマスを橙の破線にする)
    let pending: Bool
    @ViewBuilder var content: () -> Card

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            content()
                .engCardSurface(.word)
                .overlay { EngCardDrips(english: english) }
            Spacer(minLength: EngMetrics.columnGap)
            VStack(alignment: .leading, spacing: 0) {
                EngStampSlot(english: english)
                EngRoundBoard(english: english, pending: pending, width: EngMetrics.column)
                    .padding(.top, 16)
            }
            .frame(width: EngMetrics.column)
        }
        // 垂れが下の継ぎ目の上に来るように
        .zIndex(1)
    }
}

/// 卡と操作の列のあいだ(40pt)。真ん中に混凝土の模板の継ぎ目(面板の端から端まで、卡にも字にもかからない)
private struct EngGap: View {
    var body: some View {
        Color.clear
            .frame(height: EngMetrics.stageGap)
            .overlay { ConcreteSeam() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 章の槽(148×86)。空のときは墙に残った胶带の浅い印、答えた直後は NICE! / MISS(章が自分で喷かれる)
private struct EngStampSlot: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let flash = english.flash {
                // 無障碍の「答对了 / 答错了」は TurfStamp が付ける
                TurfStamp(kind: flash.good ? .nice : .miss)
                    .id(flash.id)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            } else {
                StampSlotMark()
                    .transition(.opacity)
            }
        }
        .frame(width: EngMetrics.column, height: EngMetrics.slotHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: english.flash)
        .accessibilityHidden(english.flash == nil)
    }
}

/// 答えた直後(章が出ている間)だけ、卡の下縁から白い漆が垂れる。長さは操作の列まで 6pt 残す
private struct EngCardDrips: View {
    @ObservedObject var english: EnglishCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let flash = english.flash {
                MotionPlayer(trigger: flash.id, durationMs: 280, playOnAppear: true) { progress in
                    Drips(paint: .white, xs: [0.06, 0.64], seed: flash.good ? 0 : 3,
                          maxLength: EngMetrics.stageGap - 6, grow: progress)
                }
                .id(flash.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: english.flash)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 本轮:今日の 20 問を 4×5 の格で(漆の満ち具合 = 評分、いまの 1 問 = 橙の破線)。混凝土の上(卡片)か黒い台の上(通关)
private struct EngRoundBoard: View {
    @ObservedObject var english: EnglishCoordinator
    let pending: Bool
    /// 見出しの行の幅(格は真ん中)
    var width: CGFloat = EngMetrics.boardWidth

    var body: some View {
        let goal = EnglishCoordinator.dailyGoal
        let count = min(english.todayCount, goal)
        let marks = EnglishRound.board(results: english.todayResults, answered: english.todayCount, goal: goal,
                                       pending: pending)
        let columns = EngMetrics.boardColumns
        let rows = (marks.count + columns - 1) / columns
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("本轮")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 8)
                Text("\(count)/\(goal)")
                    .font(Typeface.mono(15, weight: 700))
                    .foregroundStyle(Palette.text)
            }
            VStack(spacing: EngMetrics.boardGap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: EngMetrics.boardGap) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            RatingCell(kind: index < marks.count ? marks[index] : .empty, size: EngMetrics.boardCell,
                                       animated: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width)
        .help("今天答了 \(english.todayCount) 题，目标 \(goal) 题")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("本轮 \(count)/\(goal)")
    }
}

/// 子標籤の行の右:🔥 连续 N 天 · 12/20(目標に届いたら 20/20 が青 + 模板の ✓)。どの画面でも出す
private struct EngProgress: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        let goal = EnglishCoordinator.dailyGoal
        ViewThatFits(in: .horizontal) {
            line(full: true)
            line(full: false)
        }
        .help("今天答了 \(english.todayCount) 题，目标 \(goal) 题，连续 \(english.streak) 天")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(english.streak > 0
            ? "连续 \(english.streak) 天，今天 \(english.todayCount)/\(goal)"
            : "今天 \(english.todayCount)/\(goal)")
    }

    /// full = 「连续 N 天 ·」まで、そうでなければ炎と数だけ(標籤が長くて入らないとき)
    private func line(full: Bool) -> some View {
        let goal = EnglishCoordinator.dailyGoal
        let reached = english.todayCount >= goal
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if english.streak > 0 {
                StencilIconView(icon: .flame, size: 15)
                    .foregroundStyle(Palette.orange)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                if full {
                    Text("连续 \(english.streak) 天")
                        .font(Typeface.mixed(14, weight: 700))
                        .foregroundStyle(Palette.text)
                    Text("·")
                        .font(Typeface.mixed(14, weight: 700))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else if full {
                Text("今天")
                    .font(Typeface.mixed(14, weight: 700))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text("\(english.todayCount)/\(goal)")
                .font(Typeface.mono(13, weight: 700))
                .foregroundStyle(reached ? Palette.teal : Palette.text)
            if reached {
                StencilIconView(icon: .check, size: 12)
                    .foregroundStyle(Palette.teal)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            }
        }
        .fixedSize()
    }
}

/// 卡の中の复习记录:黒い遮喷の帯に 10 マス(20pt)+ 回数。いま答える 1 問は橙の破線
private struct EngReviewBand: View {
    /// 初めて出たカード(0 回なのが確か)
    let isNew: Bool
    /// いまの 1 問に答え終わった
    let answered: Bool
    /// そのカードの評分(古い順。EnglishCoordinator.history(for:)、控えから)
    let past: [SRSRating]

    var body: some View {
        let marks = Self.cells(past, answered: answered)
        // 同期より前の記録しかないカードは回数が分からないので出さない
        let known = isNew || !past.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("复习记录")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.cardText)
                Spacer(minLength: 8)
                if known {
                    Text("\(past.count) 次")
                        .font(Typeface.mono(13, weight: 700))
                        .foregroundStyle(Palette.cardText)
                }
            }
            HStack(spacing: EngMetrics.historyGap) {
                ForEach(0..<marks.count, id: \.self) { index in
                    RatingCell(kind: marks[index], size: EngMetrics.historyCell)
                }
            }
            .padding(.horizontal, EngMetrics.historyPadding)
            .frame(maxWidth: .infinity, minHeight: EngMetrics.historyBand, maxHeight: EngMetrics.historyBand,
                   alignment: .leading)
            .background { BakedSlice(id: "band-black-night", fallback: Palette.black) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(known ? "复习记录 \(past.count) 次" : "复习记录")
    }

    /// 最近の 10 回(答える前なら最後の 1 マスはいまの 1 問)、足りない分は空き
    private static func cells(_ past: [SRSRating], answered: Bool) -> [RoundMark] {
        var marks = EnglishRound.history(past, answered: answered, slots: EngMetrics.historySlots)
        while marks.count < EngMetrics.historySlots { marks.append(.empty) }
        return marks
    }
}

/// 見出し語(大きく・まっすぐ・墨)
private struct EngHeadWord: View {
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

/// 卡の上の小さな札:黒い遮块に白字(B1 / 考点词 / 听写 / 词典 / 本轮)/ 橙の札に黒字(NEW)/ 黒い遮喷の枠に黒字(名词 / 听力)。
/// 欧文は Archivo 900 の幅広、中文は直立のまま
private struct EngTag: View {
    enum Style { case black, orange, frame, longFrame }

    let text: String
    var style: Style = .black

    var body: some View {
        let latin = text.unicodeScalars.allSatisfy { $0.isASCII }
        Text(text)
            .font(latin ? TypeRole.tagLatin : Typeface.mixed(12.5, weight: 900))
            .tracking(latin ? 0.8 : 0.2)
            .foregroundStyle(style == .black ? Palette.white : Palette.black)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minWidth: 40)
            .frame(height: 24)
            .background { paint }
    }

    @ViewBuilder
    private var paint: some View {
        switch style {
        case .black:
            BakedSlice(id: engFirstBaked(["tag-black-card", "band-black-night"]) ?? "tag-black-card",
                       fallback: Palette.black)
        case .orange:
            BakedSlice(id: "tag-orange-night", fallback: Palette.orange)
        case .frame:
            EngFrame(ids: ["frame-black-night"])
        case .longFrame:
            EngFrame(ids: ["frame-black-long-night", "frame-black-night"])
        }
    }
}

/// 白い卡の上の黒い遮喷の枠(素材がなければ墨の線)
private struct EngFrame: View {
    let ids: [String]

    var body: some View {
        if let id = engFirstBaked(ids) {
            BakedSlice(id: id)
        } else {
            Rectangle().strokeBorder(Palette.black, lineWidth: 1.8)
        }
    }
}

/// キーの説明(Space / Enter / ⌘Z)。枠なしの等幅(⌘⏎⌫ があるので系统の等幅)、次要色
private struct EngKeycap: View {
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

/// 卡の上の折痕(焼いた card-rule。素材がなければ墨の破線)
private struct EngFoldRule: View {
    var body: some View {
        Group {
            if Baked.has("card-rule") {
                BakedSlice(id: "card-rule")
                    .frame(height: 2)
            } else {
                EngRuleLine()
                    .stroke(Palette.cardText.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(height: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct EngRuleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// 白い卡の上の小さな操作(発音・再生)。墨の色のまま、乗せると少し薄く
private struct EngInkButtonStyle: ButtonStyle {
    var square: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        EngInkButtonBody(configuration: configuration, square: square)
    }
}

private struct EngInkButtonBody: View {
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

/// 入力欄:焼いた黒い遮喷の枠(白い卡の上)。フォーカスがないときは枠を少し薄く(線は描き足さない)
private struct EngInputBox<Content: View>: View {
    /// 枠を濃く見せる(フォーカス中・採点の印を見せている間)
    let active: Bool
    /// 词典の幅広い入力欄(input-frame-wide-night 432 幅)
    var wide = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, EngMetrics.letterInset)
            .padding(.vertical, (EngMetrics.inputHeight - EngMetrics.letterHeight) / 2)
            .frame(maxWidth: .infinity, minHeight: EngMetrics.inputHeight, alignment: .leading)
            .background { EngInputFrame(active: active, wide: wide) }
    }
}

private struct EngInputFrame: View {
    let active: Bool
    var wide = false

    var body: some View {
        Group {
            if let id = engFirstBaked(wide ? ["input-frame-wide-night", "input-frame-night"] : ["input-frame-night"]) {
                BakedSlice(id: id)
            } else {
                Rectangle().strokeBorder(Palette.cardText, lineWidth: 2)
            }
        }
        .opacity(active ? 1 : 0.6)
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// 直前の答え(結果の一言)と「↶ 撤销 ⌘Z」
private struct EngUndoLine: View {
    @ObservedObject var english: EnglishCoordinator
    /// 考点词:撤销を左に寄せる(右に「下一题」が来る)
    var compact = false

    var body: some View {
        if let action = engVisibleUndo(english) {
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
                    .font(Typeface.mixed(13, weight: 700))
                EngKeycap(text: "⌘Z")
            }
        }
        .buttonStyle(BareButtonStyle())
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityLabel("撤销")
    }
}

/// 撤销の行に出す直前の答え。语料は次の語を打っているあいだは出さない(⌘Z を入力欄の取り消しに譲る)
@MainActor
private func engVisibleUndo(_ english: EnglishCoordinator) -> EnglishCoordinator.LastAction? {
    guard let action = english.lastAction, action.mode == english.mode,
          english.mode != .spell || english.spellResult != nil || english.spellInput.isEmpty else { return nil }
    return action
}

/// 評分ボタンの見本の格:黒い遮块の小さな台(白卡用の素材)に 14pt の格。台の素材がなければ格だけ(黒の平塗りは使わない)
private struct EngSwatch: View {
    let kind: RoundMark

    var body: some View {
        RatingCell(kind: kind, size: 14)
            .padding(3)
            .background {
                if let id = engFirstBaked(["swatch-black-card", "tag-black-card"]) {
                    BakedSlice(id: id)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 单词

private struct EngVocab: View {
    @ObservedObject var english: EnglishCoordinator
    /// いま押した評分(少しのあいだ青く光らせてから記録する)
    @State private var pressed: SRSRating?

    var body: some View {
        if let card = english.vocabCard {
            VStack(alignment: .leading, spacing: 0) {
                EngStage(english: english, pending: !card.known) {
                    content(card)
                }
                EngGap()
                actions(card)
                if engVisibleUndo(english) != nil {
                    EngUndoLine(english: english)
                        .padding(.top, 12)
                }
            }
        } else {
            EngStageClear(english: english, message: "今天的单词做完了")
        }
    }

    private func content(_ card: EnglishCoordinator.VocabCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EngTag(text: card.level)
                if card.isNew && !card.known {
                    EngTag(text: "NEW", style: .orange)
                }
                if let pos = card.pos, !pos.isEmpty {
                    EngTag(text: pos, style: .frame)
                }
            }
            EngHeadWord(text: card.word)
                .padding(.top, 8)
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
                .buttonStyle(EngInkButtonStyle(square: 26))
                .keyboardShortcut("r", modifiers: .command)
                .help("听发音（⌘R）")
                .accessibilityLabel("听发音")
            }
            .padding(.top, 2)
            EngReviewBand(isNew: card.isNew, answered: card.known, past: english.history(for: card.id))
                .padding(.top, 14)
            EngFoldRule()
                .padding(.top, 16)
            meaning(card)
                .padding(.top, 12)
            if card.known {
                Text("你标记了「已经会了」，现在不会出题")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.cardTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    /// 释义:めくる前は黒い遮喷の帯 2 本(長さ違い・少し傾く)、めくったら 楼层 + 例文(見出し語に青の遮块)
    @ViewBuilder
    private func meaning(_ card: EnglishCoordinator.VocabCard) -> some View {
        if english.revealed || card.known {
            let short = card.meaning.count <= 10
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("释义")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.cardTextSecondary)
                    Text(card.meaning)
                        .font(short ? TypeRole.definition : Typeface.mixed(20, weight: 900))
                        .tracking(short ? 32 * 0.06 : 0)
                        .foregroundStyle(Palette.cardText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let example = card.example {
                    HStack(alignment: .top, spacing: 6) {
                        EngExample(example: example, word: card.word)
                        Button {
                            english.speakExample()
                        } label: {
                            StencilIconView(icon: .speaker, size: 14)
                        }
                        .buttonStyle(EngInkButtonStyle(square: 22))
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
                    .padding(.top, 10)
                EngRedaction()
            }
        }
    }

    /// 卡の下の 1 列:めくる前 = 已经会了(文字だけ)/ Space 显示释义、めくった後 = 評分 1〜4、「已经会了」の卡 = 恢复出题
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
                // Space も「记住了」:見本の横に「3 ␣」と書いて分かるようにする
                rateButton("记住了", key: "3", rating: .good, keyLabel: "3 ␣")
                rateButton("太简单", key: "4", rating: .easy)
            }
            .help("按 1–4 评分；Space = 记住了")
            // 空格 = 记住了(1 問 1 キー:空格で見て、空格で次へ)
            .background {
                Button("") { press(.good) }
                    .keyboardShortcut(.space, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    english.markKnown()
                } label: {
                    Text("已经会了")
                        .font(Typeface.mixed(14, weight: 700))
                }
                .buttonStyle(BareButtonStyle())
                .help("以后不再出这个词（可以在列表的「已掌握」里恢复）")
                Spacer(minLength: 8)
                EngKeycap(text: "Space")
                Button("显示释义") { english.reveal() }
                    .buttonStyle(SprayButtonStyle(height: 50))
                    .keyboardShortcut(.space, modifiers: [])
            }
        }
    }

    /// 評分:平時は 4 つとも灰の遮块。押したものだけ少しのあいだ青(見本の格 + キー + 文字)
    private func rateButton(_ title: String, key: KeyEquivalent, rating: SRSRating, keyLabel: String? = nil) -> some View {
        let lit = pressed == rating
        return Button {
            press(rating)
        } label: {
            HStack(spacing: 5) {
                EngSwatch(kind: EnglishRound.mark(rating: rating))
                Text(keyLabel ?? String(key.character))
                    .font(TypeRole.keycap)
                    .foregroundStyle(lit ? Palette.cardTextSecondary : Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typeface.mixed(16, weight: 900))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(BlockButtonStyle(state: lit ? .selected : .idle, size: .rate))
        .keyboardShortcut(key, modifiers: [])
    }

    /// 押した評分を 140ms 青く見せてから記録する(続けて押した分は無視)
    private func press(_ rating: SRSRating) {
        guard pressed == nil else { return }
        pressed = rating
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            english.rate(rating)
            pressed = nil
        }
    }
}

/// めくる前の释义:黒い遮喷の帯 2 本(134×35 は −1.6°、226×15 は +0.8°。傾きは素材に焼いてあるので回さない)。
/// 2 本目は「释义」の横に収まるよう少しだけ縮める(0.85 倍まで)
private struct EngRedaction: View {
    /// 帯を置ける幅(卡の中 244 − 「释义」と間 12)
    private static let room: CGFloat = EngMetrics.cardInner - 38

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar("redact-black-1-night", width: 134, height: 35, angle: -1.6)
            bar("redact-black-2-night", width: 226, height: 15, angle: 0.8)
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bar(_ id: String, width: CGFloat, height: CGFloat, angle: Double) -> some View {
        let scale = max(0.85, min(1, Self.room / width))
        if Baked.has(id) {
            BakedSprite(id: id, scale: scale)
        } else {
            // 前の素材(傾いていない)で代えるときだけ、ここで傾ける
            BakedSlice(id: "redact-black-night", fallback: Palette.black)
                .frame(width: width * scale, height: height * scale)
                .rotationEffect(.degrees(angle))
        }
    }
}

/// 例文(欧文の斜体)。語ごとに折り返し、見出し語は青の遮块(mark-teal-card)の上に。素材がなければ青の下線(平塗りはしない)
private struct EngExample: View {
    let example: String
    let word: String

    private struct Piece {
        /// 普通の語(mark が空)か、見出し語の前にくっついた字
        let lead: String
        /// 見出し語(青の遮块の上)
        let mark: String
        /// 見出し語の後ろにくっついた字(storeys の s、句読点)
        let tail: String
    }

    var body: some View {
        let pieces = Self.pieces(example, word: word)
        // Layout を値として呼ぶ(callAsFunction。初期化子の後ろ閉包と取り違えないように)
        let flow = EngWordFlow(spacing: 4.5, lineSpacing: 4)
        flow {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                pieceView(piece)
            }
        }
        .font(TypeRole.example)
        .foregroundStyle(Palette.cardText)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(example)
    }

    @ViewBuilder
    private func pieceView(_ piece: Piece) -> some View {
        if piece.mark.isEmpty {
            Text(piece.lead)
        } else {
            HStack(spacing: 0) {
                if !piece.lead.isEmpty {
                    Text(piece.lead)
                }
                marked(piece.mark)
                if !piece.tail.isEmpty {
                    Text(piece.tail)
                }
            }
        }
    }

    @ViewBuilder
    private func marked(_ text: String) -> some View {
        if Baked.has("mark-teal-card") {
            Text(text)
                .padding(.horizontal, 3)
                .background { BakedSlice(id: "mark-teal-card") }
                .padding(.horizontal, 1)
        } else {
            Text(text)
                .underline(true, color: Palette.teal)
        }
    }

    /// 空白で語に分け、見出し語(大文字小文字は問わない)を前後にくっついた字ごと 1 つにする
    private static func pieces(_ example: String, word: String) -> [Piece] {
        func plain(_ text: Substring) -> [Piece] {
            text.split(separator: Character(" ")).map { Piece(lead: String($0), mark: "", tail: "") }
        }
        guard !word.isEmpty, let range = example.range(of: word, options: .caseInsensitive) else {
            return plain(example[...])
        }
        var before = example[..<range.lowerBound].split(separator: Character(" "), omittingEmptySubsequences: false)
        var after = example[range.upperBound...].split(separator: Character(" "), omittingEmptySubsequences: false)
        let lead = before.popLast().map { String($0) } ?? ""
        let tail = after.isEmpty ? "" : String(after.removeFirst())
        var result = before.filter { !$0.isEmpty }.map { Piece(lead: String($0), mark: "", tail: "") }
        result.append(Piece(lead: lead, mark: String(example[range]), tail: tail))
        result += after.filter { !$0.isEmpty }.map { Piece(lead: String($0), mark: "", tail: "") }
        return result
    }
}

/// 語を左から詰めて、入らなければ次の行へ(例文の折り返し)
private struct EngWordFlow: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for index in subviews.indices where index < layout.origins.count {
            let origin = layout.origins[index]
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (origins, CGSize(width: widest, height: y + lineHeight))
    }
}

// MARK: - 考点词

private struct EngParaphrase: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let q = english.question {
            VStack(alignment: .leading, spacing: 0) {
                EngStage(english: english, pending: english.picked == nil) {
                    content(q)
                }
                EngGap()
                options(q)
                if engVisibleUndo(english) != nil || english.picked != nil {
                    HStack(spacing: 12) {
                        EngUndoLine(english: english, compact: true)
                        Spacer(minLength: 8)
                        if english.picked != nil {
                            nextButton
                        }
                    }
                    .padding(.top, 12)
                }
            }
        } else {
            EngStageClear(english: english, message: "今天的考点词做完了")
        }
    }

    private func content(_ q: ParaphraseQuestion) -> some View {
        let skill = q.entry.skill == "listening" ? "听力" : "阅读"
        let gloss = [q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · ")
        let id = engParaID(q)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EngTag(text: "考点词")
                EngTag(text: skill, style: .frame)
            }
            EngHeadWord(text: q.entry.w, quiz: true)
                .padding(.top, 10)
            // 設計稿の文言のまま。読み上げは意味の分かる文に
            Text("（\(skill)）常被换成？")
                .font(Typeface.mixed(20, weight: 800))
                .foregroundStyle(Palette.cardText)
                .accessibilityLabel("真题里它会被换成哪个词？")
                .padding(.top, 2)
            EngReviewBand(isNew: false, answered: english.picked != nil, past: english.history(for: id))
                .padding(.top, 16)
            EngFoldRule()
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 4) {
                if !gloss.isEmpty {
                    Text(gloss)
                        .font(Typeface.mixed(13.5, weight: 500))
                        .foregroundStyle(Palette.cardText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let picked = english.picked {
                    Text(picked == q.answerIndex ? "正确" : "错了，今天还会再出")
                        .font(Typeface.mixed(15, weight: 700))
                        .foregroundStyle(Palette.cardText)
                        .padding(.top, 6)
                    Text("可替换为：" + q.entry.syn.joined(separator: " · "))
                        .font(Typeface.mixed(13, weight: 500))
                        .foregroundStyle(Palette.cardTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 12)
        }
    }

    /// 選択肢 2×2(灰の遮块。正解 = 青 + ✓、誤って選んだ = 灰 + 語だけに删除线 + ✕)
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
            english.choose(index)
        } label: {
            // 删除线は語だけ(番号・「你的选择」には引かない)
            Text(q.choices[index])
                .font(Typeface.archivo(22, weight: 700))
                .strikethrough(isWrongPick, color: Palette.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, 20)
                // 右の「正确答案 ✓」「你的选择 ✕」の分を空ける
                .padding(.trailing, isAnswer || isWrongPick ? 96 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BlockButtonStyle(state: look, size: .option, height: Turf.optionButton, strikeLabel: false))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .accessibilityValue(status)
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
                        .font(Typeface.mixed(13, weight: 700))
                    StencilIconView(icon: .check, size: 14)
                }
                .foregroundStyle(Palette.black)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else if isWrongPick {
                // 模板の ✕ は BlockButtonStyle が右端に置く
                Text("你的选择")
                    .font(Typeface.mixed(13, weight: 700))
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
                    .font(Typeface.mixed(14, weight: 700))
                EngKeycap(text: "Enter")
            }
        }
        .buttonStyle(BareButtonStyle(color: Palette.text))
        .keyboardShortcut(.defaultAction)
    }
}

/// 考点词のカード id(EnglishCoordinator の出題と同じ形)
private func engParaID(_ q: ParaphraseQuestion) -> String {
    "para:\(q.entry.skill):\(q.entry.w)"
}

// MARK: - 语料(听写)

private struct EngSpell: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            VStack(alignment: .leading, spacing: 0) {
                EngStage(english: english, pending: english.spellResult == nil) {
                    content(item)
                }
                EngGap()
                actions
                if engVisibleUndo(english) != nil {
                    EngUndoLine(english: english)
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
            EngStageClear(english: english, message: "今天的语料做完了")
        }
    }

    private func content(_ item: EnglishCoordinator.SpellItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                EngTag(text: "听写")
                EngTag(text: item.word.set, style: .frame)
                if item.isNew {
                    EngTag(text: "NEW", style: .orange)
                }
            }
            .help("王陆语料 · \(item.word.set)")
            playButton
                .padding(.top, 14)
            EngReviewBand(isNew: item.isNew, answered: english.spellResult != nil,
                          past: english.history(for: item.id))
                .padding(.top, 16)
            Text("你的拼写")
                .font(TypeRole.caption)
                .foregroundStyle(Palette.cardText)
                .padding(.top, 16)
            EngInputBox(active: focused || english.spellResult != nil) {
                ZStack(alignment: .leading) {
                    // 採点後も入力欄は残す(回车で次へ・焦点を保つ)。見た目は採点した綴りの字の格に置き換える
                    TextField("", text: $english.spellInput,
                              prompt: Text("输入听到的单词，按回车").foregroundStyle(Palette.cardTextSecondary.opacity(0.6)))
                        .textFieldStyle(.plain)
                        .font(TypeRole.input)
                        .foregroundStyle(Palette.cardText)
                        .autocorrectionDisabled(true)
                        .focused($focused)
                        .onSubmit {
                            english.submitSpelling()
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
                    EngPlayDisc()
                    StencilIconView(icon: .play, size: 20)
                        .foregroundStyle(Palette.black)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("播放")
                            .font(TypeRole.cardTitle)
                        EngKeycap(text: "⌘R", color: Palette.cardTextSecondary)
                    }
                    Text("英式发音 · 建议戴耳机")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.cardTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EngInkButtonStyle())
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
                    english.giveUpSpelling()
                } label: {
                    HStack(spacing: 8) {
                        Text("不知道")
                        EngKeycap(text: "⌘⌫")
                    }
                }
                .buttonStyle(FrameButtonStyle(height: 50))
                .keyboardShortcut(.delete, modifiers: .command)
            }
            Spacer(minLength: 8)
            EngKeycap(text: "Enter")
            if english.spellResult == nil {
                Button("检查") { english.submitSpelling() }
                    .buttonStyle(SprayButtonStyle(height: 50))
            } else {
                Button("下一个") {
                    english.submitSpelling()
                    focused = true
                }
                .buttonStyle(SprayButtonStyle(height: 50))
            }
        }
    }

    /// 採点した綴り(gradedInput の控え):余計な字・違う字に橙の遮块
    @ViewBuilder
    private func typed(_ word: DictationWord) -> some View {
        let graded = english.gradedInput ?? english.spellInput
        if graded.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("—")
                .font(TypeRole.input)
                .foregroundStyle(Palette.cardTextSecondary)
                .allowsHitTesting(false)
        } else {
            let marks = Self.marks(graded, word)
            EngLetterRow(letters: marks.typed, marked: marks.typedMarks, paint: .orange, width: EngMetrics.letterRow)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("你的拼写：\(graded)")
        }
    }

    /// 判定の一言 + 正しい綴り(足りない字・違う字に青の遮块)+ 発音と意味
    private func answer(_ result: SpellResult, _ word: DictationWord) -> some View {
        let marks = Self.marks(english.gradedInput ?? english.spellInput, word)
        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.title(result))
                .font(TypeRole.caption)
                .foregroundStyle(Palette.cardText)
            EngLetterRow(letters: marks.answer, marked: marks.answerMarks, paint: .teal, width: EngMetrics.letterRow)
                .padding(.leading, EngMetrics.letterInset)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("正确拼写：\(word.w)")
                .contextMenu {
                    Button("拷贝单词") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(word.w, forType: .string)
                    }
                }
            if word.ipa != nil || word.zh != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let ipa = word.ipa {
                        // Archivo に IPA が無いので系统字体
                        Text("/\(ipa)/")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.cardText)
                            .fixedSize()
                    }
                    if word.ipa != nil && word.zh != nil {
                        Text("·")
                            .font(Typeface.mixed(13, weight: 600))
                            .foregroundStyle(Palette.cardTextSecondary)
                    }
                    if let zh = word.zh {
                        Text(zh)
                            .font(Typeface.mixed(13, weight: 600))
                            .foregroundStyle(Palette.cardText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
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

    /// 採点した綴りと正解の食い違い(入力の字 = 橙、正解の字 = 青)
    private static func marks(_ graded: String, _ word: DictationWord)
        -> (typed: [Character], typedMarks: [Bool], answer: [Character], answerMarks: [Bool]) {
        let typed = Array(SpellCheck.normalize(graded))
        let answer = Array(word.w)
        let marks = engSpellingMarks(typed, answer)
        return (typed, marks.input, answer, marks.answer)
    }
}

/// 聴写の字の格(20 × 32、Archivo 26pt)の列。印の字は焼いた橙 / 青の遮块(素材がなければ下線)。
/// 長い語は 0.6 倍まで縮め、それでも入らなければ次の行へ
private struct EngLetterRow: View {
    enum Paint { case orange, teal }

    let letters: [Character]
    let marked: [Bool]
    let paint: Paint
    /// 並べられる幅
    let width: CGFloat

    var body: some View {
        let count = max(letters.count, 1)
        let scale = max(0.6, min(1, width / (CGFloat(count) * EngMetrics.letterWidth)))
        // 割り算の誤差で最後の 1 字だけ次の行に落ちないよう、少しだけ余裕を見る
        let perRow = max(1, Int((width / (EngMetrics.letterWidth * scale) + 0.001).rounded(.down)))
        let rows = stride(from: 0, to: letters.count, by: perRow).map { start in
            Array(start..<min(start + perRow, letters.count))
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(rows[row], id: \.self) { index in
                        cell(index, scale: scale)
                    }
                }
            }
        }
    }

    private var asset: String { paint == .orange ? "letter-orange-card" : "letter-teal-card" }
    private var markColor: Color { paint == .orange ? Palette.orange : Palette.teal }

    private func cell(_ index: Int, scale: CGFloat) -> some View {
        let isMarked = index < marked.count && marked[index]
        let baked = isMarked && Baked.has(asset)
        return Text(String(letters[index]))
            .font(scale < 1 ? Typeface.archivo(26 * scale, weight: 600) : TypeRole.letter)
            .underline(isMarked && !baked, color: markColor)
            .foregroundStyle(Palette.cardText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: EngMetrics.letterWidth * scale, height: EngMetrics.letterHeight * scale)
            .background {
                if baked {
                    BakedSlice(id: asset)
                }
            }
    }
}

/// 再生ボタンの橙の円(白い卡の上に喷いた素材。なければ単色の円)
private struct EngPlayDisc: View {
    var body: some View {
        if Baked.has("button-play-orange-night") {
            BakedSprite(id: "button-play-orange-night")
        } else {
            Circle().fill(Palette.orange)
        }
    }
}

/// 綴りの食い違い:編集距離の道筋をたどって、入力の余計・誤った字と、正解の足りない・違う字に印を付ける
private func engSpellingMarks(_ input: [Character], _ answer: [Character]) -> (input: [Bool], answer: [Bool]) {
    let n = input.count, m = answer.count
    var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in 0...n { cost[i][0] = i }
    for j in 0...m { cost[0][j] = j }
    if n > 0 && m > 0 {
        for i in 1...n {
            for j in 1...m {
                let step = engSameLetter(input[i - 1], answer[j - 1]) ? 0 : 1
                cost[i][j] = min(cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + step)
            }
        }
    }
    var inputMarks = Array(repeating: false, count: n)
    var answerMarks = Array(repeating: false, count: m)
    var i = n, j = m
    while i > 0 || j > 0 {
        if i > 0, j > 0 {
            let same = engSameLetter(input[i - 1], answer[j - 1])
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

private func engSameLetter(_ a: Character, _ b: Character) -> Bool {
    String(a).lowercased() == String(b).lowercased()
}

// MARK: - 词典

/// 白い卡に入力欄と引けた語(引けたら広い卡、まだ・見つからないときは短い卡)。単語卡へ足す操作は卡の下
private struct EngDictionary: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        let empty = english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let hit: DictHit? = empty ? nil : english.dictHit
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                EngTag(text: "词典")
                EngInputBox(active: focused, wide: true) {
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
            .engCardSurface(hit == nil ? .short : .wide)
            .zIndex(1)
            if let hit {
                EngGap()
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    if english.isInDeck(hit) {
                        Text("已在单词卡里")
                            .font(TypeRole.caption)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        EngKeycap(text: "⌘⏎")
                        Button("加入单词卡") { english.addToDeck(hit) }
                            .buttonStyle(SprayButtonStyle(height: 50))
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("加入单词卡（⌘⏎）")
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
    }

    private func entry(_ hit: DictHit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                EngHeadWord(text: hit.word, quiz: true)
                Text("/\(hit.ipa)/")
                    .font(TypeRole.ipa)
                    .foregroundStyle(Palette.cardTextSecondary)
                Button {
                    Speaker.shared.say(hit.word)
                } label: {
                    StencilIconView(icon: .speaker, size: 16)
                }
                .buttonStyle(EngInkButtonStyle(square: 26))
                .help("听发音")
                .accessibilityLabel("听发音")
                Spacer(minLength: 0)
            }
            Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                .font(Typeface.mixed(15, weight: 600))
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
private struct EngWordList: View {
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
                        EngWordRow(row: row) { english.focus(row.id) }
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

/// 一覧の 1 行:混凝土の上の本物の文字。乗せると焼いた悬停块(区切りの線は引かない)
private struct EngWordRow: View {
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
                    .font(Typeface.mixed(13, weight: 500))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.dueLabel)
                    .font(Typeface.mixed(12, weight: 700))
                    .foregroundStyle(row.dueLabel == "今天" ? Palette.text : Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: Turf.scheduleRow)
            .background { hover }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("用卡片打开")
    }

    /// 行の悬停块(row-hover-night)。まだ焼けていなければ選択肢の灰の遮块で代える
    @ViewBuilder
    private var hover: some View {
        if Baked.has("row-hover-night") {
            HoverPlate(active: hovering)
        } else {
            BakedSlice(id: engFirstBaked(["block-slate-option-night", "block-slate-night"]) ?? "block-slate-night")
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

// MARK: - 做完了・没有素材

/// 今日の分が終わった:広い白卡(四隅に橙の对位角标)。左 = 黒い台に本轮の地盘・连续 N 天・明日の一言、
/// 右 = 本轮 + CLEAR、模板の 20/20、凡例、20 問そろったら奖章(神兽、説明なし)
private struct EngStageClear: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String
    /// 「回到今日」:面板のタブ(MenuContentView と同じ保存先)
    @AppStorage(PanelTab.storageKey) private var panelTab: PanelTab = .today

    var body: some View {
        let goal = EnglishCoordinator.dailyGoal
        let count = min(english.todayCount, goal)
        let full = english.todayCount >= goal
        let marks = EnglishRound.board(results: english.todayResults, answered: english.todayCount, goal: goal,
                                       pending: false)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    EngRoundBoard(english: english, pending: false)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background { BakedSlice(id: "plate-black-night", fallback: Palette.black) }
                    if english.streak > 0 {
                        EngStreakChip(streak: english.streak)
                    }
                    EngTag(text: "要复习的明天会再出现", style: .longFrame)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        EngTag(text: "本轮")
                        PaintTag(text: "CLEAR", asset: "tag-teal-night", fallback: Palette.teal)
                    }
                    StencilText(text: "\(count)/\(goal)", set: "count-black", fallbackSize: 44,
                                fallbackColor: Palette.cardText)
                        .padding(.top, 20)
                    Text(message)
                        .font(Typeface.mixed(15, weight: 700))
                        .foregroundStyle(Palette.cardText)
                        .padding(.top, 14)
                    if full {
                        Text("全部完成，地盘喷满了")
                            .font(TypeRole.caption)
                            .foregroundStyle(Palette.cardTextSecondary)
                            .padding(.top, 4)
                    }
                    EngLegend(marks: Array(marks.prefix(count)))
                        .padding(.top, 16)
                    if full {
                        EngClearBadge()
                            .padding(.top, 22)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .engCardSurface(.wide)
            .regMarks()
            .zIndex(1)

            EngGap()
            HStack(spacing: 6) {
                Button {
                    english.addMoreNew()
                } label: {
                    HStack(spacing: 8) {
                        Text("再来 10 个新的")
                            .font(Typeface.mixed(14, weight: 700))
                        EngKeycap(text: "⌘N")
                    }
                }
                .buttonStyle(BareButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
                .help("还想继续的话，可以再加 10 个新的")
                Button {
                    english.presentation = .list
                } label: {
                    Text("查看列表")
                        .font(Typeface.mixed(14, weight: 700))
                }
                .buttonStyle(BareButtonStyle())
                Spacer(minLength: 8)
                Button("回到今日") { panelTab = .today }
                    .buttonStyle(SprayButtonStyle(kind: .orange, height: 50))
            }
            if engVisibleUndo(english) != nil {
                EngUndoLine(english: english)
                    .padding(.top, 12)
            }
        }
    }
}

/// 凡例:记住了 / 太简单 / 模糊 / 忘了 と本轮の数(14pt の格)
private struct EngLegend: View {
    let marks: [RoundMark]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
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

    private func entry(_ kind: RoundMark, _ title: String) -> some View {
        let number = marks.filter { $0 == kind }.count
        return HStack(spacing: 8) {
            RatingCell(kind: kind, size: 14)
            Text(title)
                .font(Typeface.mixed(13.5, weight: 800))
                .foregroundStyle(Palette.cardText)
            Spacer(minLength: 6)
            Text("\(number)")
                .font(Typeface.mono(14, weight: 700))
                .foregroundStyle(Palette.cardText)
        }
        .frame(width: 104)
        .accessibilityElement(children: .combine)
    }
}

/// 黒い遮块(白卡用の小牌)に 橙の炎 + 连续 N 天
private struct EngStreakChip: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            StencilIconView(icon: .flame, size: 14)
                .foregroundStyle(Palette.orange)
            Text("连续 \(streak) 天")
                .font(Typeface.mixed(13, weight: 700))
                .foregroundStyle(Palette.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background {
            BakedSlice(id: engFirstBaked(["chip-black-card", "plate-black-night"]) ?? "chip-black-card",
                       fallback: Palette.black)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 20/20 の奖章:切り角の黒い底板 + 曜日の神兽(青漆)。どちらも −2° で焼いてあるので回さない。文字は付けない。
/// 出たときに 1 回(⑤ 650ms):底板が喷かれ(badge-mask の 4 枚)→ 神兽がふっと出る。減らす動きでは最後の絵
private struct EngClearBadge: View {
    private static let total: Double = 650
    /// 奖章を喷いた日(通关したその日の最初の 1 回だけ動かす。面板を開き直すたびには喷かない)
    @AppStorage("englishBadgeDay") private var playedDay = ""
    @State private var playNow = false

    var body: some View {
        MotionPlayer(trigger: playNow, durationMs: Self.total) { progress in
            badge(progress)
        }
        .frame(width: 142, height: 105)
        .accessibilityHidden(true)
        .onAppear {
            let today = DayKey.key(for: Date())
            guard playedDay != today else { return }
            playedDay = today
            playNow = true
        }
    }

    @ViewBuilder
    private func badge(_ progress: Double) -> some View {
        let spray = motionPhase(progress, totalMs: Self.total, from: 0, to: 420)
        let reveal = motionPhase(progress, totalMs: Self.total, from: 420, to: Self.total)
        ZStack {
            plate
                .mask { plateMask(spray) }
            BakedSprite(id: Myth.badgeCreature(for: Date()))
                .opacity(reveal)
        }
    }

    @ViewBuilder
    private var plate: some View {
        if Baked.has("badge-plate-night") {
            BakedSlice(id: "badge-plate-night")
        } else {
            EngChamferedPlate()
                .fill(Palette.black)
                .rotationEffect(.degrees(-2))
        }
    }

    @ViewBuilder
    private func plateMask(_ spray: Double) -> some View {
        if spray < 1 && Baked.hasFrames("badge-mask-", count: 4) {
            BakedFrame(prefix: "badge-mask-", count: 4, progress: spray)
        } else {
            Rectangle()
                .opacity(spray)
                .padding(-30)
        }
    }
}

/// 模板の底板の形(四隅を切り落とす)。素材がないときだけ使う
private struct EngChamferedPlate: Shape {
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

/// 素材が無い(IELTS app から取り込む前):短い白卡に手順
private struct EngMissingData: View {
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
                .background {
                    BakedSlice(id: engFirstBaked(["band-black-wide-night", "band-black-night"]) ?? "band-black-night",
                               fallback: Palette.black)
                }
                .padding(.top, 4)
        }
        .engCardSurface(.short)
    }
}
