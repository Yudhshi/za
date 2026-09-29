import AppKit
import SwiftUI

/// デザイントークン(2026-09 v5:ゲームの UI として作る)。
/// アプリの画面ではなく、ゲームの HUD とメニュー画面のつもりで:黒いステージに黄緑とすみれのインク(スプラトゥーンのナワバリの 2 色)、
/// 斜めに切った札とボタン、ゲージ、選択カーソル「▶」、正解で「NICE!」のスタンプ。
/// システムのライト/ダークに関係なく常に黒いステージ(ゲーム画面なので)。
/// 読みやすさ:文字は黒・濃い灰・黄緑・白・すみれの面の上だけ。本文 17:1、補足 6.7:1 以上、最小 13pt。
/// 斜めにするのは英字の大見出しと札の形だけで、日本語の本文はまっすぐ
enum Theme {
    static let panelWidth: CGFloat = 660
    static let leftColumnWidth: CGFloat = 350
    static let panelPadding: CGFloat = 16
    static let gap: CGFloat = 14
    /// 札・ボタンの斜めの量
    static let slant: CGFloat = 8

    /// 日付・時刻の表記はシステム言語に関係なく日本語(UI 文言と揃える)
    static let locale = Locale(identifier: "ja_JP")

    // インクと地(固定色)。カッコ内はその上の文字とのコントラスト
    static let lime = rgb(0xC8FF1A)      // 黒文字 16.8:1。ステージ上の黄緑文字も 16.8:1
    static let violet = rgb(0x5A2DFF)    // 白文字 6.5:1
    static let black = rgb(0x0A0A0A)
    static let white = rgb(0xFFFFFF)
    /// ステージ(パネルの地)
    static let stage = rgb(0x0A0A0A)
    /// 札・カードの面
    static let surface = rgb(0x151515)
    /// タイル(選ばれていないメニュー)・入力欄
    static let tile = rgb(0x1C1C1C)
    static let text = white
    /// 補足(7:1 以上)
    static let textSoft = rgb(0xA3A3A3)
    /// 終わった予定など(5.7:1)
    static let textFaint = rgb(0x8A8A8A)
    static let hairline = Color.white.opacity(0.14)

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// 本文・見出し(SF Pro。日本語はヒラギノ角ゴ)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    /// ゲームのタイトルのような英字(横に広い極太の斜体)
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded).italic()
    }

    /// 英字の小さなラベル(横に広い斜体。.tracking と合わせて使う)
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .heavy).width(.expanded).italic()
    }

    /// 大きな数字(縦長の極太・等幅)
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed).monospacedDigit()
    }

    enum Size {
        static let numeral: CGFloat = 72
        static let word: CGFloat = 60
        static let date: CGFloat = 40
        static let title: CGFloat = 20
        static let headline: CGFloat = 17
        static let body: CGFloat = 15
        static let caption: CGFloat = 13
    }
}

// MARK: - 形

/// 平行四辺形(ゲームの札・ボタン)
struct Slant: Shape {
    var skew: CGFloat = Theme.slant

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

/// 角を斜めに落とした四角(カード)
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

/// 左の辺だけ斜めの四角(継ぎ合わせの布)
struct SlashedPanel: Shape {
    var slash: CGFloat = 34

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + slash, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - インク(スプラトゥーン)

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

/// インクの飛び散り:ぎざぎざの塊 + 周りのしずく + 下への垂れ。種が同じなら毎回同じ形
struct InkSplat: Shape {
    var seed: UInt64
    var lobes = 10
    var drops = 0
    var drip = false
    /// ぎざぎざの深さ(谷がどこまで内側に入るか)。文字を載せるときは浅く
    var depth = 0.16

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let inset = drops > 0 || drip ? 0.78 : 0.94
        let rx = rect.width / 2 * inset, ry = rect.height / 2 * inset
        let n = lobes * 2
        var points: [CGPoint] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + rng.next(-0.1...0.1)
            let r = i.isMultiple(of: 2) ? rng.next(1.0...1.08)
                                        : rng.next((1 - depth)...(1 - depth * 0.45))
            points.append(CGPoint(x: c.x + cos(a) * rx * r, y: c.y + sin(a) * ry * r))
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var blob = Path()
        blob.move(to: mid(points[n - 1], points[0]))
        for i in 0..<n {
            blob.addQuadCurve(to: mid(points[i], points[(i + 1) % n]), control: points[i])
        }
        blob.closeSubpath()

        let r = min(rx, ry)
        var extras = Path()
        for _ in 0..<drops {
            let a = rng.next(0...(2 * .pi))
            let d = rng.next(1.12...1.3)
            let s = r * rng.next(0.06...0.12)
            extras.addEllipse(in: CGRect(x: c.x + cos(a) * rx * d - s, y: c.y + sin(a) * ry * d - s,
                                         width: s * 2, height: s * 2))
        }
        if drip {
            let x = c.x + rx * rng.next(-0.5...0.2)
            let w = r * rng.next(0.1...0.15)
            let top = c.y + ry * 0.5
            let length = ry * rng.next(0.5...0.7)
            extras.addRoundedRect(in: CGRect(x: x - w / 2, y: top, width: w, height: length),
                                  cornerSize: CGSize(width: w / 2, height: w / 2))
            extras.addEllipse(in: CGRect(x: x - w * 0.7, y: top + length - w * 0.7,
                                         width: w * 1.4, height: w * 1.4))
        }
        return blob.union(extras)
    }
}

/// 網点(丸だけ。角から離れるほど小さく)。文字の無いところの飾り
struct Halftone: View {
    var color: Color = Theme.black.opacity(0.35)
    var step: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let diagonal = hypot(size.width, size.height)
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    let t = 1 - hypot(x, y) / diagonal
                    let d = max(0, t * step * 0.75)
                    if d > 0.8 {
                        context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                                     with: .color(color))
                    }
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 札・見出し・ゲージ・ボタン

/// 斜めの札(「TUE」「B1」「NEW」「CLEAR!」など)
struct Plate: View {
    let text: String
    var fill: Color = Theme.white
    var textColor: Color = Theme.black

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(11))
            .tracking(1.2)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Slant(skew: 6).fill(fill))
            .fixedSize()
    }
}

/// セクションの見出し:大きな英字(ゲームのタイトル風)+ 日本語 + 右に添え物
struct SectionTitle<Trailing: View>: View {
    let en: String
    let ja: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(en.uppercased())
                .font(Theme.display(20))
                .foregroundStyle(Theme.white)
            Text(ja)
                .font(Theme.font(Theme.Size.caption, .heavy))
                .foregroundStyle(Theme.textSoft)
            Spacer(minLength: 8)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(en: String, ja: String) {
        self.init(en: en, ja: ja) { EmptyView() }
    }
}

/// HUD のゲージ(斜めのコマを並べる)
struct HUDGauge: View {
    let segments: Int
    let filled: Double
    var color: Color = Theme.lime

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(segments, 1), id: \.self) { index in
                Slant(skew: 4)
                    .fill(Double(index) < filled ? color : Color.white.opacity(0.18))
                    .frame(width: 14, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// HUD の数値:黄緑の英字ラベル + 値 + 補足、下にゲージ
struct HUDStat: View {
    let label: String
    let value: String
    var detail: String?
    /// ゲージのコマ数(0 ならゲージなし)
    var segments = 0
    var filled: Double = 0
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(label.uppercased())
                    .font(Theme.label(11))
                    .tracking(1.2)
                    .foregroundStyle(Theme.lime)
                Text(value)
                    .font(Theme.font(Theme.Size.headline, .black).monospacedDigit())
                    .foregroundStyle(Theme.white)
                if let detail {
                    Text(detail)
                        .font(Theme.font(Theme.Size.caption, .bold).monospacedDigit())
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .lineLimit(1)
            if segments > 0 {
                HUDGauge(segments: segments, filled: filled)
            }
        }
        .fixedSize()
    }
}

/// キーボードの手がかり(ゲームのボタン表示のような斜体の数字)
struct KeyHint: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(Theme.display(13))
            .accessibilityHidden(true)
    }
}

/// ゲームのコマンドボタン(斜めの札)。押すと少し縮む
struct CommandButtonStyle: ButtonStyle {
    enum Kind { case primary, light, ghost, violet }

    var kind: Kind = .primary
    var height: CGFloat = 38
    /// 横いっぱいに広げる
    var wide = false
    /// アイコンだけ
    var square = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let (fill, textColor): (Color, Color) = {
            switch kind {
            case .primary: return (Theme.lime, Theme.black)
            case .light: return (Theme.white, Theme.black)
            case .ghost: return (Color.clear, Theme.white)
            case .violet: return (Theme.violet, Theme.white)
            }
        }()
        configuration.label
            .font(Theme.font(square ? Theme.Size.headline : 15, .heavy))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : 18)
            .frame(minWidth: square ? height + 6 : nil, maxWidth: wide ? .infinity : nil, minHeight: height)
            .background(Slant().fill(fill))
            .overlay {
                if kind == .ghost {
                    Slant().stroke(Theme.white, lineWidth: 2)
                }
            }
            .contentShape(Slant())
            .scaleEffect(pressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: pressed)
    }
}

extension ButtonStyle where Self == CommandButtonStyle {
    static var command: CommandButtonStyle { .init() }

    static func command(_ kind: CommandButtonStyle.Kind, height: CGFloat = 38,
                        wide: Bool = false) -> CommandButtonStyle {
        .init(kind: kind, height: height, wide: wide)
    }

    /// アイコンだけのコマンド
    static func commandSquare(_ kind: CommandButtonStyle.Kind = .light, size: CGFloat = 30) -> CommandButtonStyle {
        .init(kind: kind, height: size, square: true)
    }
}

/// 大きな縦長の数字を黄緑のインクの上に(墨文字)+ 単位
struct SplatNumeral: View {
    let value: String
    let unit: String
    var size: CGFloat = Theme.Size.numeral
    var seed: UInt64 = 21

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Theme.numeral(size))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(Theme.Size.caption, .black))
            }
        }
        .foregroundStyle(Theme.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(InkSplat(seed: seed, lobes: 11, depth: 0.14).fill(Theme.lime))
        .accessibilityElement(children: .combine)
    }
}

/// スタンプ(「NICE!」「MISS」):インクの上に斜めの極太英字
struct Stamp: View {
    let text: String
    var good = true

    var body: some View {
        Text(text)
            .font(Theme.display(40))
            .foregroundStyle(good ? Theme.black : Theme.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
            .background(InkSplat(seed: good ? 33 : 37, lobes: 10, depth: 0.22)
                .fill(good ? Theme.lime : Theme.violet))
            .rotationEffect(.degrees(-10))
            .allowsHitTesting(false)
            .accessibilityLabel(good ? "正解" : "まちがい")
    }
}
