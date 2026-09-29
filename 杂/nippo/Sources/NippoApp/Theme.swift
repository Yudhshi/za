import AppKit
import SwiftUI

/// デザイントークン(2026-09 v4:スプラトゥーン × 日本のアヴァンギャルド)。
/// 地:生成りの紙と墨(山本耀司・川久保玲の白と黒)。角は立てる(丸いカプセルやキャラクターは使わない)。
/// インク:黄緑とすみれ(スプラトゥーンのナワバリの 2 色)を、日付・残り時間・カードの角にだけ大きく飛ばす。
/// 構造:ブロックは継ぎ合わせ(sacai)。上端はプリーツの細い縦線(三宅一生)。
/// 文字:英字の見出しは横に広い大文字、数字は縦長の極太、本文は SF Pro(日本語はヒラギノ角ゴ)。
/// 読みやすさ最優先:文字は紙・白・墨・黄緑の上にだけ置く(すみれの上は白文字)。本文 16:1・補足 6.6:1 以上、最小 13pt
enum Theme {
    static let panelWidth: CGFloat = 660
    static let leftColumnWidth: CGFloat = 340
    static let panelPadding: CGFloat = 16
    static let gap: CGFloat = 14
    /// ブロック・ボタンの線
    static let line: CGFloat = 1.5

    /// 日付・時刻の表記はシステム言語に関係なく日本語(UI 文言と揃える)
    static let locale = Locale(identifier: "ja_JP")

    // インク(ライト/ダーク共通)
    static let lime = rgb(0xC8FF1A)      // 墨文字 16.8:1
    static let violet = rgb(0x5A2DFF)    // 白文字 6.5:1
    static let black = rgb(0x0A0A0A)
    static let paper = rgb(0xF2F0EB)
    static let white = rgb(0xFFFFFF)
    /// 白い入力欄など、常に明るい面の上の補足
    static let inkSoft = rgb(0x57544E)

    /// パネルの地(ごくわずかに下が透ける)
    static let background = dynamic(light: 0xF2F0EB, dark: 0x0B0B0B, lightAlpha: 0.97, darkAlpha: 0.97)
    /// ブロックの面
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x151515)
    static let text = dynamic(light: 0x0A0A0A, dark: 0xF2F0EB)
    static let textSoft = dynamic(light: 0x57544E, dark: 0xA9A59C)
    /// 線(ダークでは生成り)
    static let rule = dynamic(light: 0x0A0A0A, dark: 0xF2F0EB)
    static let hairline = dynamic(light: 0x0A0A0A, dark: 0xF2F0EB, lightAlpha: 0.14, darkAlpha: 0.16)
    /// 反転(選択中の行・主ボタン)
    static let inverse = dynamic(light: 0x0A0A0A, dark: 0xF2F0EB)
    static let onInverse = dynamic(light: 0xF2F0EB, dark: 0x0A0A0A)

    static func rgb(_ hex: UInt32) -> Color {
        Color(nsColor: nsColor(hex))
    }

    static func dynamic(light: UInt32, dark: UInt32,
                        lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? nsColor(dark, alpha: darkAlpha) : nsColor(light, alpha: lightAlpha)
        })
    }

    private static func nsColor(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// 本文・見出し(SF Pro。日本語はヒラギノ角ゴ)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    /// 英字の見出しラベル(横に広い大文字。.tracking と合わせて使う)
    static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    /// 大きな数字(縦長の極太・等幅)
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed).monospacedDigit()
    }

    enum Size {
        static let numeral: CGFloat = 60
        static let word: CGFloat = 52
        static let date: CGFloat = 30
        static let title: CGFloat = 19
        static let headline: CGFloat = 16
        static let body: CGFloat = 15
        static let caption: CGFloat = 13
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

/// プリーツ(細い縦線の帯)。パネルの上端に
struct Pleats: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                             with: .color(Theme.rule.opacity(0.85)))
                x += 3
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

// MARK: - ブロック・ラベル・ボタン

extension View {
    /// ブロック:面 + 細い線(角は立てる)
    func block() -> some View {
        self
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
    }

    /// 情報チップ(四角・細い線)
    func chip(fill: Color = Theme.surface, text: Color = Theme.text, height: CGFloat = 32) -> some View {
        self
            .font(Theme.font(Theme.Size.caption, .bold))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(fill)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
    }
}

/// ブロックの見出し:英字ラベル + 日本語 + 右に添え物。下に線
struct BlockHeader<Trailing: View>: View {
    let en: String
    let ja: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(en.uppercased())
                .font(Theme.label())
                .tracking(1.4)
            Text(ja)
                .font(Theme.font(Theme.Size.caption, .heavy))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: Theme.line)
        }
        .accessibilityElement(children: .combine)
    }
}

extension BlockHeader where Trailing == EmptyView {
    init(en: String, ja: String) {
        self.init(en: en, ja: ja) { EmptyView() }
    }
}

/// 織りネームのような小さな札(四角・横に広い大文字)
struct WovenTag: View {
    enum Style { case ink, violet, lime }

    let text: String
    var style: Style = .ink

    var body: some View {
        let (fill, textColor): (Color, Color) = {
            switch style {
            case .ink: return (Theme.inverse, Theme.onInverse)
            case .violet: return (Theme.violet, Theme.white)
            case .lime: return (Theme.lime, Theme.black)
            }
        }()
        Text(text.uppercased())
            .font(Theme.label(10.5))
            .tracking(1.2)
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(fill)
            .fixedSize()
    }
}

/// キーボードの手がかり(「1」「⏎」など)
struct KeyHint: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .heavy).monospacedDigit())
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .overlay(Rectangle().strokeBorder(lineWidth: 1))
            .opacity(0.75)
            .accessibilityHidden(true)
    }
}

/// 角の立ったボタン。主ボタンは墨(ダークでは生成り)の後ろに黄緑を少しずらして刷る(版ずれ)
struct SharpButtonStyle: ButtonStyle {
    enum Kind { case primary, accent, plain }

    var kind: Kind = .plain
    var height: CGFloat = 36
    /// 横いっぱいに広げる
    var wide = false
    /// アイコンだけの正方形
    var square = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let (fill, textColor, border): (Color, Color, Color) = {
            switch kind {
            case .primary: return (Theme.inverse, Theme.onInverse, Theme.inverse)
            case .accent: return (Theme.lime, Theme.black, Theme.black)
            case .plain: return (Theme.surface, Theme.text, Theme.rule)
            }
        }()
        configuration.label
            .font(Theme.font(square ? Theme.Size.headline : 14, .heavy))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : 14)
            .frame(minWidth: square ? height : nil, maxWidth: wide ? .infinity : nil, minHeight: height)
            .background(fill)
            .overlay(Rectangle().strokeBorder(border, lineWidth: Theme.line))
            .contentShape(Rectangle())
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .background(alignment: .topLeading) {
                if kind == .primary {
                    Theme.lime.offset(x: 3, y: 3)
                }
            }
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension ButtonStyle where Self == SharpButtonStyle {
    static var sharp: SharpButtonStyle { .init() }

    static func sharp(_ kind: SharpButtonStyle.Kind, height: CGFloat = 36,
                      wide: Bool = false) -> SharpButtonStyle {
        .init(kind: kind, height: height, wide: wide)
    }

    /// アイコンだけの正方形ボタン
    static func sharpSquare(_ kind: SharpButtonStyle.Kind = .plain, size: CGFloat = 32) -> SharpButtonStyle {
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
                .foregroundStyle(Theme.black)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(InkSplat(seed: seed, lobes: 11, depth: 0.14).fill(Theme.lime))
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(Theme.Size.caption, .heavy))
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
