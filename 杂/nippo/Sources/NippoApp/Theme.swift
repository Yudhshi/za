import AppKit
import SwiftUI

/// メニューパネルのデザイントークン(2026-09 ラバーホース × ガラス)。
/// 1930 年代のアニメ(ゴムホースの腕・白い手袋・パイカットの目)の色と線を、Liquid Glass の上に載せる。
/// 奥:ガラス越しに、からし色のサンバースト(放射線)が透ける。
/// 中:クリーム色のガラスのカード + 墨の太い輪郭 + 真下の固い影(ゴムのおもちゃが床に立っている感じ)。
/// 手前:ゴムのように丸いボタン(上につや・下に厚み)と、平らな見出しタグ。
/// 読みやすさ:文字はカード・チップ・タグの上にだけ置き、柄の上には置かない。傾けない。
/// 本文 16:1・補足 8:1 以上(補足も透明度ではなく不透明の茶色で作る)。タグの墨文字は 5.5:1 以上
enum Theme {
    static let panelWidth: CGFloat = 640
    static let leftColumnWidth: CGFloat = 336
    static let panelPadding: CGFloat = 16
    static let gap: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 20
    static let border: CGFloat = 2.5
    /// カード・ボタンの真下の固い影の厚み
    static let lift: CGFloat = 4

    /// 日付・時刻の表記はシステム言語に関係なく日本語(UI 文言と揃える)
    static let locale = Locale(identifier: "ja_JP")

    // 1930 年代のアニメの色(ライト/ダーク共通)。カッコ内は上に載せる文字とのコントラスト
    static let red = rgb(0xC8321F)       // 白文字 5.3:1(参加ボタン)
    static let mustard = rgb(0xF2B233)   // 墨文字 9.7:1
    static let teal = rgb(0x2F9E97)      // 墨文字 5.6:1
    static let blush = rgb(0xF4A3A0)     // 墨文字 9.2:1
    static let cream = rgb(0xFFFBF2)     // 墨文字 17:1
    static let white = rgb(0xFFFFFF)

    /// 墨(色の上の文字・ボタンの輪郭。ライト/ダーク共通)
    static let ink = rgb(0x1C1410)
    static let inkSoft = rgb(0x5B4636)

    /// パネルの地:システムのガラスの上に薄く敷く紙の色(透けて見える)
    static let paperTint = dynamic(light: 0xF8EACC, dark: 0x221812, lightAlpha: 0.6, darkAlpha: 0.62)
    /// サンバーストの線
    static let ray = dynamic(light: 0xF2B233, dark: 0xF2B233, lightAlpha: 0.3, darkAlpha: 0.16)
    /// カードの地(ガラスの上に 90%。下のサンバーストがうっすら透ける)
    static let card = dynamic(light: 0xFFF8E8, dark: 0x2E221B, lightAlpha: 0.9, darkAlpha: 0.9)
    /// カード・チップの上の文字(ダークでは生成り)
    static let text = dynamic(light: 0x1C1410, dark: 0xFFF1DA)
    static let textSoft = dynamic(light: 0x5B4636, dark: 0xDCC6A8)
    /// カードの輪郭と真下の影(ダークでは生成りの線画にして見えるように)
    static let outline = dynamic(light: 0x1C1410, dark: 0xF3E3C3)
    /// 一覧の区切り線
    static let hairline = dynamic(light: 0x1C1410, dark: 0xF3E3C3, lightAlpha: 0.14, darkAlpha: 0.18)

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

    /// 丸ゴシック(SF Pro Rounded。日本語はヒラギノで表示される)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    enum Size {
        static let hero: CGFloat = 40
        static let date: CGFloat = 24
        static let title: CGFloat = 18
        static let headline: CGFloat = 15
        static let body: CGFloat = 14
        static let caption: CGFloat = 12
    }
}

// MARK: - 形

/// 真下の固い影:形を下にずらし、形そのものを抜いた三日月。
/// 半透明のカードの下に影が透けて濁らないよう、はみ出す部分だけを描く
struct Lip<Base: Shape>: Shape {
    var base: Base
    var offset: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = base.path(in: rect)
        return body.offsetBy(dx: 0, dy: offset).subtracting(body)
    }
}

/// サンバースト(昔のアニメのタイトルカードの放射線)。中心から rays 本のくさびを描く
struct Sunburst: Shape {
    var rays = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = hypot(rect.width, rect.height)
        let step = Double.pi / Double(rays)
        for i in 0..<rays {
            let a0 = Double(i) * 2 * step, a1 = a0 + step
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + cos(a0) * r, y: c.y + sin(a0) * r))
            path.addLine(to: CGPoint(x: c.x + cos(a1) * r, y: c.y + sin(a1) * r))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - カード・チップ・ボタン

extension View {
    /// 透けるクリーム色のガラスのカード + 太い輪郭 + 真下の固い影
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return self
            .foregroundStyle(Theme.text)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: Theme.border))
            .background(Lip(base: shape, offset: Theme.lift).fill(Theme.outline))
    }

    /// ヘッダー・フッターの小さな情報チップ(カードと同じ透けるガラス)
    func chip(fill: Color = Theme.card, text: Color = Theme.text, height: CGFloat = 32) -> some View {
        let shape = Capsule(style: .continuous)
        return self
            .font(Theme.font(Theme.Size.caption, .bold))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(fill, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 2))
    }
}

/// 見出しのタグ(平らな色の札。傾けない)
struct Tag: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.mustard

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

/// ゴムのように丸いボタン:太い輪郭 + 上のつや + 下の厚み。押すと厚みの分だけ沈む
struct RubberButtonStyle: ButtonStyle {
    var fill: Color = Theme.cream
    var text: Color = Theme.ink
    var height: CGFloat = 36
    /// アイコンだけの丸ボタン(幅 = 高さ)
    var isRound = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let lift: CGFloat = 3
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.font(isRound ? Theme.Size.headline : Theme.Size.body, .heavy))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, isRound ? 0 : 14)
            .frame(minWidth: isRound ? height : nil, minHeight: height)
            .background {
                shape.fill(fill)
                    .overlay(alignment: .top) {
                        // ゴムのつや(文字の後ろ)
                        shape.fill(Theme.white.opacity(0.5))
                            .frame(height: max(4, height * 0.2))
                            .padding(.horizontal, height * 0.32)
                            .padding(.top, 3.5)
                    }
            }
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 2.5))
            .contentShape(shape)
            .offset(y: pressed ? lift : 0)
            .background(Lip(base: shape, offset: lift).fill(Theme.ink).opacity(pressed ? 0 : 1))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.15), value: pressed)
    }
}

extension ButtonStyle where Self == RubberButtonStyle {
    static var rubber: RubberButtonStyle { .init() }

    static func rubber(_ fill: Color, text: Color = Theme.ink, height: CGFloat = 36) -> RubberButtonStyle {
        .init(fill: fill, text: text, height: height)
    }

    /// アイコンだけの丸ボタン
    static func rubberRound(_ fill: Color = Theme.cream, size: CGFloat = 34) -> RubberButtonStyle {
        .init(fill: fill, height: size, isRound: true)
    }
}

// MARK: - マスコット・数字

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

/// 大きな数字 + 単位(残り時間など)
struct BigNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = Theme.Size.hero

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(Theme.font(size, .black).monospacedDigit())
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(Theme.Size.headline, .heavy))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - パネルの地

/// 紙色を薄く敷いたガラスに、からし色のサンバーストが透ける(左上のマスコットから放射)
struct PanelBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.paperTint
                Sunburst(rays: 24)
                    .fill(Theme.ray)
                    .frame(width: 900, height: 900)
                    .position(x: 36, y: 36)
                    .mask(
                        RadialGradient(colors: [.black, .black.opacity(0.4), .clear],
                                       center: UnitPoint(x: 36 / max(geo.size.width, 1),
                                                         y: 36 / max(geo.size.height, 1)),
                                       startRadius: 40, endRadius: 520)
                    )
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
