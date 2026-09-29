import AppKit
import SwiftUI

/// デザイントークン(2026-09 v7:静かなゲーム画面)。
/// 1 列・左端を 1 本にそろえ、面は「黒いステージ + 少し明るいカード」の 2 段だけ。
/// 黄緑は主役(次の会議の残り時間・単語の意味)と、いちばん押すボタンと、選んだものの印にだけ使う。
/// 形は角丸の面だけ(斜め・枠線・インクの主役はやめた)。ゲームらしさは大きな数字と、答えたときのスタンプ(NICE! / MISS)で。
/// 文字の大きさは 12(ラベル)・13(補足)・15(本文)・22(見出し)と、大きな数字・見出し語だけ。
/// 画面の文字は中国語(簡体字。字形も中国語のものにする)。短い掛け声やラベルは英語(NEXT・NEW・NICE!)
enum Theme {
    static let panelWidth: CGFloat = 520
    static let padding: CGFloat = 20

    /// 日付・時刻は中国語で(9月29日 周二・14:00)
    static let locale = Locale(identifier: "zh_CN")
    /// 漢字の字形を中国語(簡体字)にそろえる
    static let language = Locale.Language(identifier: "zh-Hans")

    static let lime = rgb(0xC8FF1A)      // 黒文字 16.8:1。ステージ上の黄緑文字も 16.8:1
    static let black = rgb(0x0A0A0A)
    static let white = rgb(0xFFFFFF)
    static let stage = rgb(0x0A0A0A)
    /// カード(主役を載せる面)
    static let card = rgb(0x151515)
    /// ふつうのボタン・入力欄・選んだタブ
    static let fill = rgb(0x262626)
    /// 本文(例文など。やや控えめな白。16:1)
    static let body = rgb(0xD4D4D4)
    /// 補足(7:1 以上)
    static let textSoft = rgb(0xA3A3A3)
    /// ラベル・終わった予定(5.7:1)
    static let textFaint = rgb(0x8A8A8A)
    static let hairline = Color.white.opacity(0.08)

    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 9

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// 本文・見出し(SF Pro。漢字は PingFang SC)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// 大きな数字(縦長の極太・等幅)
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed).monospacedDigit()
    }

    /// スタンプ・完成の掛け声(横に広い極太の斜体)
    static func shout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded).italic()
    }
}

// MARK: - 面

extension View {
    /// 主役を載せるカード
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// 入力欄の見た目(塗りだけ。フォーカスは下の黄緑の線で)
    func inputField(height: CGFloat) -> some View {
        self.textFieldStyle(.plain)
            .foregroundStyle(Theme.white)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
    }
}

// MARK: - インク(スタンプだけに使う)

/// 決まった種から毎回同じ形を作る乱数(SplitMix64)
struct SeededRandom {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next(_ range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// インクの塊(スプラトゥーン)。種が同じなら毎回同じ形。文字を載せるので谷は浅く
struct InkSplat: Shape {
    var seed: UInt64
    var lobes = 11
    var depth = 0.14

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2 * 0.94, ry = rect.height / 2 * 0.94
        let n = lobes * 2
        var points: [CGPoint] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + rng.next(-0.1...0.1)
            let r = i.isMultiple(of: 2) ? rng.next(1.0...1.08)
                                        : rng.next((1 - depth)...(1 - depth * 0.45))
            points.append(CGPoint(x: c.x + cos(a) * rx * r, y: c.y + sin(a) * ry * r))
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path()
        path.move(to: mid(points[n - 1], points[0]))
        for i in 0..<n {
            path.addQuadCurve(to: mid(points[i], points[(i + 1) % n]), control: points[i])
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 部品

/// タブ 1 つ
struct TabItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var badge: Int?
    /// ⌘ と組み合わせるキー
    var shortcut: KeyEquivalent?

    var id: Value { value }
}

/// 面を切り替えるタブ(今日 / 英语)。暗い溝の中で、選んだものだけ少し明るい
struct PillTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var size: CGFloat = 13
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                tab(item)
            }
        }
        .padding(3)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .fixedSize()
    }

    @ViewBuilder
    private func tab(_ item: TabItem<Value>) -> some View {
        let selected = selection == item.value
        let button = Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.2)) { selection = item.value }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.title)
                    .font(Theme.font(size, .semibold))
                    .foregroundStyle(selected ? Theme.white : Theme.textSoft)
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(Theme.font(size - 1, .bold).monospacedDigit())
                        .foregroundStyle(Theme.lime)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: size + 13)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.fill)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if let key = item.shortcut {
            button
                .keyboardShortcut(key, modifiers: .command)
                .help("\(item.title)（⌘\(key.character)）")
        } else {
            button
        }
    }
}

/// 同じ面の中で「もの」を切り替えるタブ(单词 / 考点词…)。選んだものの下に黄緑の細い線
struct UnderlineTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var size: CGFloat = 14
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 18) {
            ForEach(items) { item in
                tab(item)
            }
        }
        .fixedSize()
    }

    private func tab(_ item: TabItem<Value>) -> some View {
        let selected = selection == item.value
        return Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.2)) { selection = item.value }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.title)
                    .font(Theme.font(size, .semibold))
                    .foregroundStyle(selected ? Theme.white : Theme.textSoft)
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(Theme.font(12, .medium).monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(Theme.lime)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 小さなラベル(灰色)。先頭の一語だけ黄緑にできる(「NEXT 14:00 – 15:00」「B1 · 名词 · NEW」)
struct Eyebrow: View {
    var lead: String?
    var text: String = ""
    var trail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let lead {
                Text(lead)
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.lime)
            }
            if !text.isEmpty {
                Text(text)
                    .font(Theme.font(12, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textFaint)
            }
            if let trail {
                Text(trail)
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.lime)
            }
        }
        .lineLimit(1)
    }
}

/// 小見出し(ラベルと同じ灰色)+ 右に添え物
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.textFaint)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// ボタンの中のキーの手がかり(控えめ)
struct KeyHint: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(Theme.font(12, .bold))
            .opacity(0.55)
            .accessibilityHidden(true)
    }
}

/// 角丸の塗りボタン。primary は黄緑(その画面でいちばん押すもの)、secondary は灰色の塗り、quiet は文字だけ
struct CommandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }

    var kind: Kind = .primary
    var height: CGFloat = 38
    var wide = false
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        CommandButtonBody(configuration: configuration, kind: kind, height: height, wide: wide, square: square)
    }
}

/// ボタンの見た目(ホバーの状態を持つので View に分ける)
struct CommandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CommandButtonStyle.Kind
    let height: CGFloat
    let wide: Bool
    let square: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        let small = height < 32
        let shape = RoundedRectangle(cornerRadius: small ? 7 : Theme.buttonRadius, style: .continuous)
        configuration.label
            .font(Theme.font(kind == .quiet || small ? 12 : 14, .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : (kind == .quiet ? 2 : (small ? 10 : 18)))
            .frame(minWidth: square ? height : nil, maxWidth: wide ? .infinity : nil, minHeight: height)
            .background {
                switch kind {
                case .primary: shape.fill(Theme.lime.opacity(hovering ? 0.88 : 1))
                case .secondary: shape.fill(hovering ? Theme.rgb(0x303030) : Theme.fill)
                case .quiet: EmptyView()
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.spring(duration: 0.18, bounce: 0.3), value: pressed)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.black
        case .secondary: return Theme.white
        case .quiet: return hovering ? Theme.white : Theme.textSoft
        }
    }
}

extension ButtonStyle where Self == CommandButtonStyle {
    static var command: CommandButtonStyle { .init() }

    static func command(_ kind: CommandButtonStyle.Kind, height: CGFloat = 38,
                        wide: Bool = false) -> CommandButtonStyle {
        .init(kind: kind, height: height, wide: wide)
    }

    static func commandSquare(_ kind: CommandButtonStyle.Kind = .quiet, size: CGFloat = 28) -> CommandButtonStyle {
        .init(kind: kind, height: size, square: true)
    }
}

/// 主役の数字:黄緑の縦長の極太 + 下に小さな単位(右寄せ)
struct BigNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = 72
    var color: Color = Theme.lime

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(value)
                .font(Theme.numeral(size))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.textSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 答えたときのスタンプ(NICE! / MISS)。インクはここだけ
struct Stamp: View {
    let good: Bool

    var body: some View {
        Text(good ? "NICE!" : "MISS")
            .font(Theme.shout(26))
            .foregroundStyle(good ? Theme.black : Theme.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(InkSplat(seed: good ? 33 : 37, lobes: 10, depth: 0.22)
                .fill(good ? Theme.lime : Theme.fill))
            .rotationEffect(.degrees(-8))
            .allowsHitTesting(false)
    }
}
