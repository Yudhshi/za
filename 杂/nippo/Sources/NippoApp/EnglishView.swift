import SwiftUI
import NippoCore

/// 英語タブ:モード(単語・同替・聴写・辞書)+ 今日の進み具合 + 1 問のカード。
/// すきま時間向けに 1 問 10 秒前後で終わり、キーボードだけで回せる(単語:Space → 1〜4、同替:1〜4 → Enter、聴写:入力 → Enter)
struct EnglishView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            HStack(spacing: 8) {
                ForEach(EnglishCoordinator.Mode.allCases) { mode in
                    modeButton(mode)
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
                .card(padding: 16)
            } else if !english.hasData {
                MissingDataCard()
            } else {
                switch english.mode {
                case .vocab: VocabCardView(english: english)
                case .para: ParaphraseCardView(english: english)
                case .spell: SpellCardView(english: english)
                case .dict: DictionaryCardView(english: english)
                }
            }
        }
    }

    private func modeButton(_ mode: EnglishCoordinator.Mode) -> some View {
        let selected = english.mode == mode
        return Button {
            english.mode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 12, weight: .heavy))
                Text(mode.title)
                    .font(Theme.font(14, .heavy))
                if let count = english.remaining[mode], count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .black).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .background(Theme.yellow, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
                }
            }
            .foregroundStyle(selected ? Theme.card : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? Theme.text : Theme.card, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.outline, lineWidth: 2))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(Self.tooltip(for: mode))
    }

    static func tooltip(for mode: EnglishCoordinator.Mode) -> String {
        switch mode {
        case .vocab: return "単語カード(IELTS 分層詞池・B1 から)。間隔反復で復習日を決める"
        case .para: return "同義替換(刘洪波 考点词真经)。真題での言い換えを 4 択で"
        case .spell: return "聴写(王陆 语料库)。読み上げを聞いて書き取る"
        case .dict: return "辞書(ECDICT)。引いた語は単語カードに足せる"
        }
    }
}

/// 今日の問題数(目標つき)と連続日数
private struct GoalMeter: View {
    let count: Int
    let goal: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("今日 \(count)/\(goal)")
                .font(Theme.font(Theme.Size.caption, .heavy).monospacedDigit())
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Theme.card)
                Capsule(style: .continuous).fill(Theme.green)
                    .frame(width: 70 * CGFloat(min(1, Double(count) / Double(max(goal, 1)))))
            }
            .frame(width: 70, height: 12)
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.outline, lineWidth: 2))
            if streak > 0 {
                Label("\(streak)日", systemImage: "flame.fill")
                    .font(Theme.font(Theme.Size.caption, .heavy))
            }
        }
        .foregroundStyle(Theme.text)
        .fixedSize()
        .help("1 日 \(goal) 問が目標。連続 \(streak) 日")
    }
}

// MARK: - 単語

private struct VocabCardView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let card = english.vocabCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Tag(text: card.level, color: Theme.cyan)
                    if card.isNew { Tag(text: "NEW", color: Theme.yellow) }
                    Spacer()
                    Button {
                        english.speakWord()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.popRound())
                    .help("発音を聞く")
                }
                Text(card.word)
                    .font(Theme.font(Theme.Size.word, .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                    .padding(.top, 6)
                Text([card.phonetic, card.pos].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(Theme.Size.headline, .semibold))
                    .foregroundStyle(Theme.textSoft)
                if english.revealed {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 2)
                        .padding(.vertical, 12)
                    Text(card.meaning)
                        .font(Theme.font(22, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let example = card.example {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(example)
                                .font(Theme.font(Theme.Size.body, .semibold))
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
                    HStack(spacing: 10) {
                        rateButton("もう一回", key: "1", rating: .again, color: Theme.pink)
                        rateButton("あいまい", key: "2", rating: .hard, color: Theme.white)
                        rateButton("覚えた", key: "3", rating: .good, color: Theme.green)
                        rateButton("簡単", key: "4", rating: .easy, color: Theme.cyan)
                    }
                    .padding(.top, 16)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            english.reveal()
                        } label: {
                            HStack(spacing: 8) {
                                Text("意味を見る")
                                KeyHint("space")
                            }
                        }
                        .buttonStyle(.pop(Theme.green, height: 44, wide: true))
                        .keyboardShortcut(.space, modifiers: [])
                        Button("知ってる") { english.markKnown() }
                            .buttonStyle(.pop(Theme.white, height: 44))
                            .help("もう出さない")
                    }
                    .padding(.top, 16)
                }
            }
            .card(padding: 16)
        } else {
            DoneCard(english: english, message: "今日の単語はここまで")
        }
    }

    private func rateButton(_ title: String, key: KeyEquivalent, rating: SRSRating,
                            color: Color) -> some View {
        Button {
            english.rate(rating)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                KeyHint(String(key.character))
            }
        }
        .buttonStyle(.pop(color, height: 42, wide: true))
        .keyboardShortcut(key, modifiers: [])
    }
}

// MARK: - 同替

private struct ParaphraseCardView: View {
    @ObservedObject var english: EnglishCoordinator

    var body: some View {
        if let q = english.question {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Tag(text: q.entry.skill == "listening" ? "聴力 考点词" : "阅读 考点词", color: Theme.cyan)
                    Spacer()
                    Text("真題での言い換えはどれ?")
                        .font(Theme.font(Theme.Size.caption, .bold))
                        .foregroundStyle(Theme.textSoft)
                }
                Text(q.entry.w)
                    .font(Theme.font(Theme.Size.word, .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 6)
                Text([q.entry.pos, q.entry.zh].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(Theme.Size.headline, .semibold))
                    .foregroundStyle(Theme.textSoft)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { index, choice in
                        choiceButton(index, choice, question: q)
                    }
                }
                .padding(.top, 14)
                .padding(.trailing, 3)
                if let picked = english.picked {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(picked == q.answerIndex ? "正解!" : "ざんねん。今日もう一度出ます")
                                .font(Theme.font(Theme.Size.headline, .heavy))
                            Text("言い換え:" + q.entry.syn.joined(separator: " · "))
                                .font(Theme.font(Theme.Size.body, .semibold))
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
                        .buttonStyle(.pop(Theme.yellow, height: 40))
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 14)
                }
            }
            .card(padding: 16)
        } else {
            DoneCard(english: english, message: "今日の同替はここまで")
        }
    }

    private func choiceButton(_ index: Int, _ choice: String, question q: ParaphraseQuestion) -> some View {
        let picked = english.picked
        let fill: Color
        if picked == nil {
            fill = Theme.white
        } else if index == q.answerIndex {
            fill = Theme.green
        } else if index == picked {
            fill = Theme.pink
        } else {
            fill = Theme.white
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
        .buttonStyle(.pop(fill, height: 48, wide: true))
        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        .opacity(picked != nil && index != q.answerIndex && index != picked ? 0.55 : 1)
    }
}

// MARK: - 聴写

private struct SpellCardView: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        if let item = english.spellItem {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Tag(text: "王陆 · \(item.word.set)", color: Theme.cyan)
                    if item.isNew { Tag(text: "NEW", color: Theme.yellow) }
                    Spacer()
                    Button {
                        english.play()
                        focused = true
                    } label: {
                        Label("聞く", systemImage: "play.fill")
                    }
                    .buttonStyle(.pop(Theme.green, height: 38))
                    .keyboardShortcut("r", modifiers: .command)
                    .help("読み上げる(⌘R)")
                    Button {
                        english.play(slow: true)
                        focused = true
                    } label: {
                        Image(systemName: "tortoise.fill")
                    }
                    .buttonStyle(.popRound(size: 38))
                    .help("ゆっくり")
                }
                Text("聞こえた語を書き取る(英国英語の読み上げ・イヤホン推奨)")
                    .font(Theme.font(Theme.Size.caption, .bold))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, 12)
                // 白い枠の中はダークでも明るい配色で描く
                TextField("", text: $english.spellInput,
                          prompt: Text("ここに入力して Enter").foregroundStyle(Theme.inkSoft))
                    .textFieldStyle(.plain)
                    .environment(\.colorScheme, .light)
                    .font(Theme.font(24, .heavy))
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Theme.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: 2.5))
                    .focused($focused)
                    .onSubmit {
                        english.submitSpelling()
                        focused = true
                    }
                    .padding(.top, 8)
                if let result = english.spellResult {
                    resultBox(result, item.word)
                        .padding(.top, 12)
                }
                HStack(spacing: 10) {
                    if english.spellResult == nil {
                        Button("わからない") { english.giveUpSpelling() }
                            .buttonStyle(.pop(Theme.white, height: 40))
                        Spacer()
                        Button {
                            english.submitSpelling()
                        } label: {
                            HStack(spacing: 8) {
                                Text("答え合わせ")
                                KeyHint("⏎")
                            }
                        }
                        .buttonStyle(.pop(Theme.green, height: 40))
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
                        .buttonStyle(.pop(Theme.yellow, height: 40))
                    }
                }
                .padding(.top, 14)
            }
            .card(padding: 16)
            .onAppear { focused = true }
        } else {
            DoneCard(english: english, message: "今日の聴写はここまで")
        }
    }

    private func resultBox(_ result: SpellResult, _ word: DictationWord) -> some View {
        let (symbol, title, color): (String, String, Color) = {
            switch result {
            case .correct: return ("checkmark.circle.fill", "正解!", Theme.green)
            case .almost: return ("exclamationmark.circle.fill", "おしい(1 文字ちがい)。明日もう一度", Theme.yellow)
            case .wrong: return ("xmark.circle.fill", "正解はこちら。今日もう一度", Theme.pink)
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(Theme.Size.body, .heavy))
                Text(word.w)
                    .font(Theme.font(26, .black))
                    .textSelection(.enabled)
                Text([word.ipa.map { "/\($0)/" }, word.zh].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.font(Theme.Size.body, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
    }
}

// MARK: - 辞書

private struct DictionaryCardView: View {
    @ObservedObject var english: EnglishCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $english.dictQuery,
                      prompt: Text("英単語を入力(例:sustainable)").foregroundStyle(Theme.inkSoft))
                .textFieldStyle(.plain)
                .environment(\.colorScheme, .light)
                .font(Theme.font(22, .heavy))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Theme.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: 2.5))
                .focused($focused)
            if english.dictQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("仕事中に出てきた単語をその場で。引いた語は単語カードに足して、あとで復習できます")
                    .font(Theme.font(Theme.Size.body, .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hit = english.dictHit {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(hit.word)
                            .font(Theme.font(34, .black))
                            .textSelection(.enabled)
                        Text("/\(hit.ipa)/")
                            .font(Theme.font(Theme.Size.headline, .semibold))
                            .foregroundStyle(Theme.textSoft)
                        Spacer()
                        Button {
                            Speaker.shared.say(hit.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.popRound())
                        .help("発音を聞く")
                    }
                    Text(hit.zh.replacingOccurrences(of: ";", with: "\n"))
                        .font(Theme.font(17, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack {
                        Spacer()
                        if english.isInDeck(hit) {
                            Label("単語カードに追加済み", systemImage: "checkmark")
                                .font(Theme.font(Theme.Size.caption, .heavy))
                                .foregroundStyle(Theme.textSoft)
                        } else {
                            Button {
                                english.addToDeck(hit)
                            } label: {
                                Label("単語カードに追加", systemImage: "plus")
                            }
                            .buttonStyle(.pop(Theme.green))
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
        .card(padding: 16)
        .onAppear { focused = true }
    }
}

// MARK: - 今日のぶんが終わった・素材が無い

private struct DoneCard: View {
    @ObservedObject var english: EnglishCoordinator
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Tag(text: "今日のぶん おわり", symbol: "checkmark.seal.fill", color: Theme.green)
            Text(message)
                .font(Theme.font(Theme.Size.title, .heavy))
            Text("復習の続きは明日また出ます。まだやるなら、新しいものを 10 問足せます")
                .font(Theme.font(Theme.Size.body, .medium))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("新しいのをもう 10 問") { english.addMoreNew() }
                .buttonStyle(.pop(Theme.yellow))
        }
        .card(padding: 16)
    }
}

private struct MissingDataCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Tag(text: "英語の素材がありません", symbol: "tray", color: Theme.pink)
            Text("IELTS アプリの素材を取り込むと使えます")
                .font(Theme.font(Theme.Size.title, .heavy))
            Text("ターミナルで IELTS アプリのフォルダを指定してビルドし直してください")
                .font(Theme.font(Theme.Size.body, .medium))
                .foregroundStyle(Theme.textSoft)
            Text("IELTS_DIR=~/Downloads/ielts-dist-v71 ./build-app.sh")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
        }
        .card(padding: 16)
    }
}
