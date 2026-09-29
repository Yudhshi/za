import AppKit
import SwiftUI

/// デザイントークン(2026-09 v6:ゲームの UI、ただし主役は 1 つ)。
/// 黒いステージに、黄緑は「主役」(次の会議の残り時間・単語カード)と押すもの・選んだものにだけ使う。
/// ほかは白と灰色で静かに。ゲームらしさは斜めのボタンと下線、インクの上の数字、答えたときのスタンプで。
/// 画面の文字は中国語(簡体字。字形も中国語のものにする)。
/// 読みやすさ:本文 17:1、補足 6.7:1 以上、最小 12pt。日本語・中国語の本文は斜めにしない
enum Theme {
    static let panelWidth: CGFloat = 660
    static let padding: CGFloat = 20

    /// 日付・時刻は中国語で(9月29日 周二・14:00)
    static let locale = Locale(identifier: "zh_CN")
    /// 漢字の字形を中国語(簡体字)にそろえる
    static let language = Locale.Language(identifier: "zh-Hans")

    static let lime = rgb(0xC8FF1A)      // 黒文字 16.8:1。ステージ上の黄緑文字も 16.8:1
    static let black = rgb(0x0A0A0A)
    static let white = rgb(0xFFFFFF)
    static let stage = rgb(0x0A0A0A)
    /// 入力欄・ホバー
    static let tile = rgb(0x1C1C1C)
    /// 本文(やや控えめな白。16:1)
    static let body = rgb(0xD4D4D4)
    /// 補足(7:1 以上)
    static let textSoft = rgb(0xA3A3A3)
    /// 終わった予定など(5.7:1)
    static let textFaint = rgb(0x8A8A8A)
    static let hairline = Color.white.opacity(0.12)

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// 本文・見出し(SF Pro。漢字は PingFang SC)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// 大きな数字(縦長の極太・斜体・等幅)
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed).italic().monospacedDigit()
    }

    /// キー表示など(横に広い斜体)
    static func key(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .black).width(.expanded).italic()
    }
}

// MARK: - 形

/// 平行四辺形(ボタン・下線)
struct Slant: Shape {
    var skew: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 角を斜めに落とした四角(小窓)
struct CutRect: Shape {
    var topTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topTrailing))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeading))
        path.closeSubpath()
        return path
    }
}

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

/// 下線のタブ(選んだものの下に黄緑の斜めの線がすべって来る)
struct TabItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var badge: Int?
    /// ⌘ と組み合わせるキー
    var shortcut: KeyEquivalent?

    var id: Value { value }
}

struct UnderlineTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var size: CGFloat = 15
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 18) {
            ForEach(items) { item in
                tab(item)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func tab(_ item: TabItem<Value>) -> some View {
        let selected = selection == item.value
        let button = Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { selection = item.value }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.title)
                    .font(Theme.font(size, .bold))
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(selected ? Theme.white : Theme.textSoft)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                if selected {
                    Slant(skew: 3)
                        .fill(Theme.lime)
                        .frame(height: 4)
                        .padding(.horizontal, -2)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if let key = item.shortcut {
            button
                .keyboardShortcut(key, modifiers: .command)
                .help("\(item.title)(⌘\(key.character))")
        } else {
            button
        }
    }
}

/// 小見出し(静かな灰色)+ 右に添え物
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.textSoft)
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

/// キーの手がかり(ゲームのボタン表示のような斜体)
struct KeyHint: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(Theme.key(13))
            .opacity(0.8)
            .accessibilityHidden(true)
    }
}

/// 斜めのボタン。primary は黄緑(主役の操作)、ghost は細い白線、quiet は文字だけ
struct CommandButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, quiet }

    var kind: Kind = .primary
    var height: CGFloat = 40
    var wide = false
    var square = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.font(kind == .quiet ? 13 : 15, .bold))
            .foregroundStyle(kind == .primary ? Theme.black : (kind == .ghost ? Theme.white : Theme.textSoft))
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : (kind == .quiet ? 4 : 20))
            .frame(minWidth: square ? height + 4 : nil, maxWidth: wide ? .infinity : nil, minHeight: height)
            .background {
                switch kind {
                case .primary: Slant().fill(Theme.lime)
                case .ghost: Slant().stroke(Theme.white.opacity(0.55), lineWidth: 1.5)
                case .quiet: EmptyView()
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: pressed)
    }
}

extension ButtonStyle where Self == CommandButtonStyle {
    static var command: CommandButtonStyle { .init() }

    static func command(_ kind: CommandButtonStyle.Kind, height: CGFloat = 40,
                        wide: Bool = false) -> CommandButtonStyle {
        .init(kind: kind, height: height, wide: wide)
    }

    static func commandSquare(_ kind: CommandButtonStyle.Kind = .ghost, size: CGFloat = 28) -> CommandButtonStyle {
        .init(kind: kind, height: size, square: true)
    }
}

/// 主役の数字:黄緑のインクの上に縦長の極太(墨文字)+ 単位
struct SplatNumeral: View {
    let value: String
    let unit: String
    var size: CGFloat = 92
    var seed: UInt64 = 21

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.numeral(size))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(14, .bold))
            }
        }
        .foregroundStyle(Theme.black)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(InkSplat(seed: seed).fill(Theme.lime))
        .accessibilityElement(children: .combine)
    }
}

/// 答えたときのスタンプ(「漂亮！」「失误」)
struct Stamp: View {
    let good: Bool

    var body: some View {
        Text(good ? "漂亮！" : "失误")
            .font(Theme.font(32, .heavy))
            .foregroundStyle(good ? Theme.black : Theme.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(InkSplat(seed: good ? 33 : 37, lobes: 10, depth: 0.22)
                .fill(good ? Theme.lime : Theme.tile))
            .rotationEffect(.degrees(-8))
            .allowsHitTesting(false)
    }
}
