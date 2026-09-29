import AppKit
import SwiftUI

/// メニューパネルのデザイントークン(2026-09 スプラトゥーン × ネオブルータリズム × Liquid Glass)。
/// 奥:ネオンのインクの飛び散り(不規則な形・しずく・垂れ)。
/// 中:透けるガラスのカード(下にインクがにじんで見える)+ 太い輪郭。
/// 手前:ネオンの塗りボタンとインク形のステッカー(固い影つき)。
/// 読みやすさ:ガラスの上に 76% の下地を敷き、インクが最も派手な所でも文字 8:1 以上・補足 4.5:1 以上。
/// 青・紫のインクは墨文字が 3.5:1 しか出ないので飾りにだけ使う
enum Theme {
    static let panelWidth: CGFloat = 400
    static let panelPadding: CGFloat = 18
    static let gap: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 22
    static let border: CGFloat = 3
    static let shadowOffset: CGFloat = 4

    /// 日付・時刻の表記はシステム言語に関係なく日本語(UI 文言と揃える)
    static let locale = Locale(identifier: "ja_JP")

    // ネオンのインク(ライト/ダーク共通)。上に文字を載せてよいのは pink/lime/orange/yellow/cyan
    static let pink = rgb(0xFF3E9A)
    static let lime = rgb(0xC6F31C)
    static let orange = rgb(0xFF7A00)
    static let yellow = rgb(0xFFE11A)
    static let cyan = rgb(0x19D9E0)
    static let blue = rgb(0x3D5CFF)      // 飾りのみ
    static let purple = rgb(0x7B3CFF)    // 飾りのみ
    static let white = rgb(0xFFFFFF)

    /// インクの上の文字・輪郭(常に墨色)
    static let ink = rgb(0x141414)
    static let inkSoft = ink.opacity(0.72)

    /// 紙と、ガラスのカードの上の文字(ダークでは生成り)
    static let paper = dynamic(light: 0xFFF4E2, dark: 0x121016)
    static let text = dynamic(light: 0x141414, dark: 0xF6F0E4)
    static let textSoft = text.opacity(0.75)
    /// カードの輪郭・紙の上の固い影(ダークでは生成りにして見えるように)
    static let outline = dynamic(light: 0x141414, dark: 0xF6F0E4)
    /// ガラスの上に敷く下地(76%)。これより薄くするとインクの上で文字が読めなくなる
    static let glassTint = dynamic(light: 0xFFFFFF, dark: 0x141217, alpha: 0.76)

    static func rgb(_ hex: UInt32) -> Color {
        Color(nsColor: nsColor(hex))
    }

    static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light,
                    alpha: alpha)
        })
    }

    private static func nsColor(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    enum Size {
        static let display: CGFloat = 48
        static let largeTitle: CGFloat = 36
        static let title: CGFloat = 19
        static let headline: CGFloat = 16
        static let body: CGFloat = 15
        static let subhead: CGFloat = 13
    }
}

// MARK: - インクの形

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

extension SeededRandom {
    /// 文字列から毎回同じ種を作る(String.hashValue は起動ごとに変わるので使わない)
    static func seed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(1469598103934665603) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }
}

/// スプラトゥーンのインクの飛び散り:ぎざぎざの塊 + 周りのしずく + 下への垂れ。
/// 種が同じなら毎回同じ形(開くたびに形が変わらない)。重なりは union で 1 つの輪郭にまとめる
struct InkSplat: Shape {
    var seed: UInt64
    var lobes = 9
    var drops = 5
    var drip = true
    /// ぎざぎざの深さ(谷がどこまで内側に入るか)。文字を載せるバッジは浅く
    var depth = 0.3

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // しずく・垂れの分だけ内側に小さく描く(幅と高さは別々に=横長のバッジにも使える)
        let inset = drops > 0 || drip ? 0.7 : 0.9
        let rx = rect.width / 2 * inset, ry = rect.height / 2 * inset
        let n = lobes * 2
        var points: [CGPoint] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + rng.next(-0.12...0.12)
            let r = i.isMultiple(of: 2) ? rng.next(0.96...1.14)
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
            let d = rng.next(1.12...1.34)
            let s = r * rng.next(0.07...0.15)
            extras.addEllipse(in: CGRect(x: c.x + cos(a) * rx * d - s, y: c.y + sin(a) * ry * d - s,
                                         width: s * 2, height: s * 2))
        }
        if drip {
            let x = c.x + rx * rng.next(-0.4...0.3)
            let w = r * rng.next(0.14...0.2)
            let top = c.y + ry * 0.5
            let length = ry * rng.next(0.45...0.62)
            extras.addRoundedRect(in: CGRect(x: x - w / 2, y: top, width: w, height: length),
                                  cornerSize: CGSize(width: w / 2, height: w / 2))
            extras.addEllipse(in: CGRect(x: x - w * 0.75, y: top + length - w * 0.75,
                                         width: w * 1.5, height: w * 1.5))
        }
        return blob.union(extras)
    }
}

/// インク形のステッカー(文字の下地)。少し傾けて貼る
struct SplatBadge: View {
    let text: String
    var color: Color = Theme.pink
    var seed: UInt64 = 1
    var angle: Double = -4

    var body: some View {
        // 谷を浅くして、字が形からはみ出さないようにする
        let shape = InkSplat(seed: seed, lobes: 13, drops: 0, drip: false, depth: 0.1)
        Text(text)
            .font(.system(size: Theme.Size.subhead, weight: .black))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(shape.fill(color))
            .overlay(shape.stroke(Theme.ink, lineWidth: 2.5))
            .rotationEffect(.degrees(angle))
    }
}

/// インク形のアイコン
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var seed: UInt64 = 7

    var body: some View {
        let shape = InkSplat(seed: seed, lobes: 8, drops: 0, drip: false)
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .black))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(shape.fill(color))
            .overlay(shape.stroke(Theme.ink, lineWidth: 2.5))
            .accessibilityHidden(true)
    }
}

// MARK: - カード・ボタン

extension View {
    /// 透けるガラスのカード:インクがにじんで見える + 太い輪郭。
    /// ガラスの上に 76% の下地(Theme.glassTint)を敷いて、下のインクに文字が負けないようにする
    func glassCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return self
            .foregroundStyle(Theme.text)
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.glassTint, in: shape)
            .glassPane(shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: Theme.border))
    }

    /// Liquid Glass(背景をぼかして透かす)
    func glassPane<S: Shape>(_ shape: S) -> some View {
        glassEffect(.regular, in: shape)
    }
}

/// ネオンの塗りボタン:太い輪郭 + 固い影。押すと影の位置まで沈む
struct SplatButtonStyle: ButtonStyle {
    var fill: Color = Theme.white
    var minHeight: CGFloat = 38
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .circular)
        let offset: CGFloat = 3
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: Theme.Size.subhead, weight: .black))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: minHeight)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 2.5))
            .contentShape(shape)
            .offset(x: pressed ? offset : 0, y: pressed ? offset : 0)
            .background(shape.fill(Theme.outline).offset(x: offset, y: offset))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.15), value: pressed)
    }
}

extension ButtonStyle where Self == SplatButtonStyle {
    static var splat: SplatButtonStyle { .init() }
    static func splat(_ fill: Color, minHeight: CGFloat = 38) -> SplatButtonStyle {
        .init(fill: fill, minHeight: minHeight)
    }
}

/// カードの見出し行:インク形のアイコン + 太いタイトル + 補足
struct CardHeader: View {
    let symbol: String
    let color: Color
    let title: String
    var subtitle: String?
    var seed: UInt64 = 7

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, seed: seed)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.Size.headline, weight: .heavy))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: Theme.Size.subhead, weight: .semibold))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 大きな数字をインクの飛び散りの上に(残り時間など)
struct SplatNumber: View {
    let value: String
    let unit: String
    var color: Color = Theme.yellow
    var size: CGFloat = Theme.Size.display
    var seed: UInt64 = 21

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .black).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .background(InkSplat(seed: seed, lobes: 10, drops: 4, drip: false)
                    .fill(color).padding(-10))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: Theme.Size.headline, weight: .heavy))
            }
        }
    }
}

// MARK: - パネルの地

/// 傾けたインクの曜日ステッカー + 極太の日付
struct DateHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SplatBadge(text: Date().formatted(.dateTime.weekday(.wide).locale(Theme.locale)),
                       color: Theme.pink, seed: 3, angle: -6)
            Text(Date(), format: .dateTime.month().day())
                .font(.system(size: Theme.Size.largeTitle, weight: .black))
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 紙の地にネオンのインクを大きく飛び散らせる(カードのガラス越しににじんで見える)
struct SplatBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.paper
                splat(Theme.pink, seed: 11, size: 230, at: CGPoint(x: w - 30, y: 60), angle: 20)
                splat(Theme.lime, seed: 23, size: 210, at: CGPoint(x: 10, y: h * 0.38), angle: -10)
                splat(Theme.blue, seed: 5, size: 240, at: CGPoint(x: w + 10, y: h * 0.62), angle: 40)
                splat(Theme.yellow, seed: 31, size: 150, at: CGPoint(x: w * 0.35, y: h * 0.8), angle: 0)
                splat(Theme.orange, seed: 17, size: 120, at: CGPoint(x: w * 0.62, y: 14), angle: -30)
                splat(Theme.purple, seed: 41, size: 200, at: CGPoint(x: 30, y: h - 20), angle: 12)
                Halftone(color: Theme.outline.opacity(0.18))
                    .frame(width: 120, height: 90)
                    .position(x: w - 70, y: h - 50)
            }
        }
    }

    private func splat(_ color: Color, seed: UInt64, size: CGFloat, at point: CGPoint,
                       angle: Double) -> some View {
        InkSplat(seed: seed, lobes: 9, drops: 6, drip: true)
            .fill(color)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .position(point)
    }
}

/// 網点(スプラトゥーンのポスター風)。右下に向かって点が大きくなる
struct Halftone: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 9
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let t = (x / size.width + y / size.height) / 2
                    let d = 1.5 + 4 * t
                    context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                                 with: .color(color))
                    x += step
                }
                y += step
            }
        }
    }
}

/// パネル下部:設定・終了
struct PanelFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            SettingsLink {
                Label("設定", systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: Theme.Size.headline, weight: .bold))
            }
            .buttonStyle(.splat(Theme.cyan))
            .help("設定")
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Nippo を終了", systemImage: "power")
                    .labelStyle(.iconOnly)
                    .font(.system(size: Theme.Size.headline, weight: .bold))
            }
            .buttonStyle(.splat(Theme.white))
            .help("Nippo を終了")
        }
    }
}
