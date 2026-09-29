import AppKit
import SwiftUI

/// メニューパネルのデザイントークン(2026-09 v3:レトロポップ × ネオブルータリズム × ちょっとスプラトゥーン)。
/// 参考:佐久間宣行事務所オフィシャルサイトの「レトロポップ」(グレーの地・緑の差し色・テレビのカラーバー)。
/// 地:明るいグレー(わずかにガラスが透ける)+ 上端にテレビのカラーバー。
/// カード:不透明の白 + 太い墨の輪郭 + 右下の固い影(文字の下に柄や透けを置かない)。
/// 差し色:緑 = 押すもの、黄 = 数字のインク、ピンク・シアン = 見出しの札。
/// 読みやすさ最優先:本文 18:1・補足 8:1 以上(補足も不透明色)。最小 13pt。文字は傾けない
enum Theme {
    static let panelWidth: CGFloat = 660
    static let leftColumnWidth: CGFloat = 340
    static let panelPadding: CGFloat = 16
    static let gap: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 16
    static let border: CGFloat = 2.5
    /// カードの右下の固い影
    static let shadow: CGFloat = 4

    /// 日付・時刻の表記はシステム言語に関係なく日本語(UI 文言と揃える)
    static let locale = Locale(identifier: "ja_JP")

    // 差し色(ライト/ダーク共通)。カッコ内は墨文字とのコントラスト
    static let green = rgb(0x2BD66B)     // 9.8:1 押すもの・開催中
    static let yellow = rgb(0xFFD60A)    // 13:1 数字のインク
    static let pink = rgb(0xFF4FA3)      // 6.2:1
    static let cyan = rgb(0x2BD4F0)      // 10.6:1
    static let red = rgb(0xFF5A45)       // 6.1:1
    static let blue = rgb(0x3D5CFF)      // 飾りのみ(墨文字が読めない)
    static let white = rgb(0xFFFFFF)

    /// 色の上の文字・ボタンの輪郭(常に墨)
    static let ink = rgb(0x111111)
    static let inkSoft = rgb(0x4B4B47)

    /// パネルの地(システムのガラスの上に 94%。ほんの少し透ける)
    static let base = dynamic(light: 0xECECE8, dark: 0x1A1A19, lightAlpha: 0.94, darkAlpha: 0.94)
    /// カード・チップの地(不透明)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x242423)
    static let text = dynamic(light: 0x111111, dark: 0xF4F4EF)
    static let textSoft = dynamic(light: 0x4B4B47, dark: 0xC4C4BC)
    /// カードの輪郭と固い影(ダークでは生成りの線にして見えるように)
    static let outline = dynamic(light: 0x111111, dark: 0xF4F4EF)
    static let hairline = dynamic(light: 0x111111, dark: 0xF4F4EF, lightAlpha: 0.14, darkAlpha: 0.16)

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

    /// SF Pro(日本語はヒラギノ角ゴ)。丸ゴシックより字の形がはっきりする
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    enum Size {
        static let hero: CGFloat = 44
        static let word: CGFloat = 46
        static let date: CGFloat = 26
        static let title: CGFloat = 19
        static let headline: CGFloat = 16
        static let body: CGFloat = 15
        static let caption: CGFloat = 13
    }

    /// テレビのカラーバー(パネルの上端)
    static let colorBars: [Color] = [rgb(0xEDEDE8), yellow, cyan, green, pink, red, blue]
}

// MARK: - インクの形(スプラトゥーン)

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

/// インクの塊(ぎざぎざの輪郭)。種が同じなら毎回同じ形。数字の下地に使うので谷は浅め
struct InkSplat: Shape {
    var seed: UInt64
    var lobes = 11
    /// ぎざぎざの深さ(谷がどこまで内側に入るか)
    var depth = 0.12

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2 * 0.94, ry = rect.height / 2 * 0.94
        let n = lobes * 2
        var points: [CGPoint] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + rng.next(-0.1...0.1)
            let r = i.isMultiple(of: 2) ? rng.next(1.0...1.07)
                                        : rng.next((1 - depth)...(1 - depth * 0.5))
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

// MARK: - カード・チップ・ボタン

extension View {
    /// 不透明の白いカード + 太い輪郭 + 右下の固い影
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return self
            .foregroundStyle(Theme.text)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: Theme.border))
            .background(shape.fill(Theme.outline).offset(x: Theme.shadow, y: Theme.shadow))
    }

    /// ヘッダー・フッターの小さな情報チップ
    func chip(fill: Color = Theme.card, text: Color = Theme.text, height: CGFloat = 32) -> some View {
        let shape = Capsule(style: .continuous)
        return self
            .font(Theme.font(Theme.Size.caption, .bold))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 2))
    }
}

/// 見出しの札(平らな色のカプセル。傾けない)
struct Tag: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.yellow

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .black))
            }
            Text(text)
                .font(Theme.font(Theme.Size.caption, .heavy))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(color, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
        .fixedSize()
    }
}

/// キーボードの手がかり(「1」「⏎」など)
struct KeyHint: View {
    let key: String

    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .heavy).monospacedDigit())
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(lineWidth: 1.5))
            .opacity(0.8)
            .accessibilityHidden(true)
    }
}

/// ポップな塗りボタン:太い輪郭 + 右下の固い影。押すと影の位置まで沈む
struct PopButtonStyle: ButtonStyle {
    var fill: Color = Theme.white
    var text: Color = Theme.ink
    var height: CGFloat = 38
    /// アイコンだけの丸ボタン(幅 = 高さ)
    var isRound = false
    /// 横いっぱいに広げる
    var wide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let offset: CGFloat = 3
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.font(isRound ? Theme.Size.headline : Theme.Size.body, .heavy))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, isRound ? 0 : 15)
            .frame(minWidth: isRound ? height : nil, maxWidth: wide ? .infinity : nil, minHeight: height)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 2.5))
            .contentShape(shape)
            .offset(x: pressed ? offset : 0, y: pressed ? offset : 0)
            .background(shape.fill(Theme.outline).offset(x: offset, y: offset))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.15), value: pressed)
    }
}

extension ButtonStyle where Self == PopButtonStyle {
    static var pop: PopButtonStyle { .init() }

    static func pop(_ fill: Color, text: Color = Theme.ink, height: CGFloat = 38,
                    wide: Bool = false) -> PopButtonStyle {
        .init(fill: fill, text: text, height: height, wide: wide)
    }

    /// アイコンだけの丸ボタン
    static func popRound(_ fill: Color = Theme.white, size: CGFloat = 36) -> PopButtonStyle {
        .init(fill: fill, height: size, isRound: true)
    }
}

// MARK: - マスコット・数字・カラーバー

/// アプリアイコンの目覚まし時計くん(バンドル外で動かしたときは汎用アイコン)
struct Mascot: View {
    var size: CGFloat = 44

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 大きな数字を黄色いインクの上に(墨の輪郭つき)+ 単位
struct SplatNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = Theme.Size.hero
    var color: Color = Theme.yellow
    var seed: UInt64 = 21

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            let splat = InkSplat(seed: seed)
            Text(value)
                .font(Theme.font(size, .black).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .background(splat.fill(color))
                .overlay(splat.stroke(Theme.ink, lineWidth: 2.5))
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(Theme.Size.headline, .heavy))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// テレビのカラーバー(パネル上端の帯)+ 墨の線
struct ColorBars: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(Theme.colorBars.enumerated()), id: \.offset) { _, color in
                    color
                }
            }
            .frame(height: 8)
            Theme.ink.frame(height: 2)
        }
        .accessibilityHidden(true)
    }
}
