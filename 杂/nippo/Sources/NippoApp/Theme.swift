import AppKit
import SwiftUI

/// デザイントークン(2026-09 v8「Fauve Stage」:野獣派の関卡カード)。
/// 黒い舞台の上に、一画面に一枚だけ「関卡カード」= 高彩度の平塗り色面 + 黒い文字。色は地、文字は図。
/// - カード(HeroShape):3 つの角丸 + 右上ひとつの斜め切り。右端は面板の外へ出血する(山本の非対称・スプラトゥーンの関卡カード)。
/// - 拼縫(sacai):カードは一本の斜めの縫い目で「色布 = 見る」と「黒い里布 = する(数字・ボタン)」に分かれる。
/// - 褶皺(三宅):文字を載せない計量条(PleatGauge)を一画面に一本だけ。
/// - 橡皮管:ボタンは胶囊。押すと潰れて戻る。章(NICE!/MISS)は墨迹のまま。
/// - iOS 27:小窓の外枠だけ Liquid Glass。文字はガラスの上に置かない。
/// 文字サイズは 12/13/15/22 + 大数字/見出し語/喊声。中文は直立の PingFang、幅の変形(expanded/compressed)は英語と数字だけ。
/// 日付は英語の曜日(TUESDAY)だけ。月日はどこにも出さない
enum Theme {
    static let panelWidth: CGFloat = 520
    static let padding: CGFloat = 20

    /// 時刻(14:00)は中国語の 24 時間制。曜日だけ英語
    static let locale = Locale(identifier: "zh_CN")
    static let weekdayLocale = Locale(identifier: "en_US")
    /// 漢字の字形を中国語(簡体字)にそろえる
    static let language = Locale.Language(identifier: "zh-Hans")

    // 舞台と灰(固定。システムの外観には追従しない=ゲーム画面)
    static let stage = rgb(0x0C0C0E)
    /// 関卡カードの黒い半分(里布)
    static let lining = rgb(0x141417)
    /// 脇役の面(会議条・「今天没有会议」・素材なし)
    static let card = rgb(0x1A1A1E)
    /// 舞台上の次ボタン・入力欄
    static let fill = rgb(0x2A2A30)
    static let white = rgb(0xFFFFFF)
    /// 本文(例文など)13.5:1
    static let body = rgb(0xD6D6DA)
    /// 補足 8.1:1
    static let textSoft = rgb(0xA6A6AD)
    /// ラベル・終わった予定 5.9:1(12pt semibold 以上でだけ使う)
    static let textFaint = rgb(0x8C8C94)
    /// 色面の上の文字(墨)
    static let ink = rgb(0x0C0C0E)
    static let hairline = Color.white.opacity(0.08)

    // 野獣派の関卡色。一画面に一色、色面の上の文字は黒(钴蓝だけ白)
    static let chrome = rgb(0xFFC72C)      // 今日 NEXT。黒文字 12.5:1
    static let vermilion = rgb(0xF24A2C)   // 緊急:NOW / 開始 5 分以内 / STAND UP。黒文字 5.4:1(灰文字・13pt 未満は禁止)
    static let viridian = rgb(0x22D37E)    // 英语 / STANDING。黒文字 9.9:1
    static let cobalt = rgb(0x1E44C4)      // SIT DOWN。唯一の白文字の面 7.8:1
    static let rose = rgb(0xFF9CC7)        // CLEAR!。黒文字 10.1:1
    /// 夜(19:00–07:00)は主役色を少し落とす(黒文字はなお 10.8:1 / 7.8:1)
    static let chromeNight = rgb(0xF2B71E)
    static let viridianNight = rgb(0x1FBB71)

    static func isNight(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour < 7 || hour >= 19
    }

    static let cardRadius: CGFloat = 22
    static let chamfer: CGFloat = 28

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

    /// 英語の短いラベル(TUESDAY / NEXT / STAND UP)。横に広い極太の大文字。中文には使わない
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .black).width(.expanded)
    }

    /// 章・喊声(NICE! / MISS / CLEAR!)。横に広い極太の斜体
    static func shout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded).italic()
    }
}

// MARK: - 関卡(いま画面を支配する一色)

/// 関卡色と、その色面の上に置ける文字・主ボタンの色。画面ごとに 1 つを環境値で流す
struct Level: Equatable {
    let color: Color
    /// 色面の上の文字
    let ink: Color
    /// 色面の上の主ボタン(塗り・文字)
    let primaryFill: Color
    let primaryText: Color
    /// 里布・舞台の上の主ボタンの塗り(文字は墨)。钴蓝だけ白(钴蓝に墨は 2.7:1 で読めない)
    let liningPrimary: Color

    static let chrome = Level(color: Theme.chrome, ink: Theme.ink, primaryFill: Theme.ink,
                              primaryText: Theme.white, liningPrimary: Theme.chrome)
    static let chromeNight = Level(color: Theme.chromeNight, ink: Theme.ink, primaryFill: Theme.ink,
                                   primaryText: Theme.white, liningPrimary: Theme.chromeNight)
    static let vermilion = Level(color: Theme.vermilion, ink: Theme.ink, primaryFill: Theme.ink,
                                 primaryText: Theme.white, liningPrimary: Theme.vermilion)
    static let viridian = Level(color: Theme.viridian, ink: Theme.ink, primaryFill: Theme.ink,
                                primaryText: Theme.white, liningPrimary: Theme.viridian)
    static let viridianNight = Level(color: Theme.viridianNight, ink: Theme.ink, primaryFill: Theme.ink,
                                     primaryText: Theme.white, liningPrimary: Theme.viridianNight)
    static let rose = Level(color: Theme.rose, ink: Theme.ink, primaryFill: Theme.ink,
                            primaryText: Theme.white, liningPrimary: Theme.rose)
    static let cobalt = Level(color: Theme.cobalt, ink: Theme.white, primaryFill: Theme.white,
                              primaryText: Theme.ink, liningPrimary: Theme.white)
    /// 主役が終わった/いない(灰いカード。文字は淡く)
    static let done = Level(color: Theme.card, ink: Theme.textFaint, primaryFill: Theme.fill,
                            primaryText: Theme.white, liningPrimary: Theme.fill)

    /// 今日の関卡(夜は少し落とした铬黄)/ 英语の関卡(夜は少し落とした翠绿)
    static func today(night: Bool) -> Level { night ? .chromeNight : .chrome }
    static func english(night: Bool) -> Level { night ? .viridianNight : .viridian }
}

private struct LevelKey: EnvironmentKey {
    static let defaultValue = Level.chrome
}

/// いま色面(関卡カード)の上にいるか。ボタン・入力欄・計量条が色を切り替える
private struct OnLevelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var level: Level {
        get { self[LevelKey.self] }
        set { self[LevelKey.self] = newValue }
    }

    var onLevel: Bool {
        get { self[OnLevelKey.self] }
        set { self[OnLevelKey.self] = newValue }
    }
}

// MARK: - 形

/// 関卡カード:3 つの角丸 + 右上ひとつの斜め切り。この app で唯一の斜線
struct HeroShape: Shape {
    var radius: CGFloat = Theme.cardRadius
    var chamfer: CGFloat = Theme.chamfer

    func path(in r: CGRect) -> Path {
        let radius = min(self.radius, min(r.width, r.height) / 2)
        let chamfer = min(self.chamfer, min(r.width, r.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - chamfer, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + chamfer))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        // 角丸は接線円弧で(quadCurve より真円に近い)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - radius, y: r.maxY),
                 radius: radius)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - radius),
                 radius: radius)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + radius, y: r.minY),
                 radius: radius)
        p.closeSubpath()
        return p
    }
}

/// 拼縫の左側(色布)。縫い目は上端 62%・下端 56% の斜線。すべてのカードで同じ傾き。
/// 里布はカード全面に敷き、その上に色布を重ねる(2 枚を突き合わせると縫い目に隙間が見える)。
/// SeamLayout はこの 2 つの定数で左右の幅を決める(左の文字は縫い目の下端より左、右の指令列は上端より右)
struct SeamShape: Shape {
    static let top: CGFloat = 0.62
    static let bottom: CGFloat = 0.56
    var top: CGFloat = SeamShape.top
    var bottom: CGFloat = SeamShape.bottom

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * bottom, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 関卡カードの面:色布(+ 里布)を HeroShape で切り、右端を面板の外へ出血させる。
/// 中の文字は既定で墨。里布側は SeamLayout が白に戻す
private struct HeroSurface: ViewModifier {
    @Environment(\.level) private var level
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var seam: Bool
    var bleed: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(level.ink)
            .environment(\.onLevel, true)
            .background {
                ZStack {
                    if seam {
                        Theme.lining
                        SeamShape().fill(level.color)
                    } else {
                        level.color
                    }
                }
                // 関卡色が変わるとき(NEXT → NOW、昼 → 夜)は交差で溶ける。形は動かない
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: level)
            }
            .clipShape(HeroShape())
            .padding(.trailing, bleed ? -Theme.padding : 0)
    }
}

/// 入力欄の見た目。舞台では灰の塗り + 白文字、色面の上では墨 12% の塗り + 墨の文字
private struct InputSurface: ViewModifier {
    @Environment(\.level) private var level
    @Environment(\.onLevel) private var onLevel
    var height: CGFloat
    var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(onLevel ? level.ink : Theme.white)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(onLevel ? level.ink.opacity(0.12) : Theme.fill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // フォーカスは下辺の 2pt の線(墨 / 関卡色)。.plain の入力欄は自分で描かないと分からない
            .overlay(alignment: .bottom) {
                if focused {
                    Capsule()
                        .fill(onLevel ? level.ink : level.color)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 1)
                }
            }
    }
}

extension View {
    /// 関卡カード(主役の面)。seam = 右側に黒い里布、bleed = 右端を面板の外へ
    func hero(seam: Bool = true, bleed: Bool = true) -> some View {
        modifier(HeroSurface(seam: seam, bleed: bleed))
    }

    /// 脇役の面(灰)。会議条・空の主役・素材なしなど
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.white)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func inputField(height: CGFloat, focused: Bool = false) -> some View {
        modifier(InputSurface(height: height, focused: focused))
    }
}

/// 関卡カードの中身:左 = 色布(見る:題・件名)、右 = 里布(する:数字・指令列)。
/// 左の列は縫い目の下端(56%)より左に収め、右の列は縫い目の上端(62%)より右から始める。
/// カード幅 = 面板幅 − 左余白(右端は出血)。右は下寄せ・右寄せで、出血分 + 内側の余白を右に空ける
struct SeamLayout<Left: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        let width = Theme.panelWidth - Theme.padding
        let leftWidth = width * SeamShape.bottom
        let rightInset = width * (SeamShape.top - SeamShape.bottom)
        HStack(alignment: .top, spacing: 0) {
            left()
                .padding(.vertical, 20)
                .padding(.leading, 22)
                .padding(.trailing, 10)
                .frame(width: leftWidth, alignment: .topLeading)
            right()
                .padding(.vertical, 20)
                .padding(.leading, rightInset)
                .padding(.trailing, Theme.padding + 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .foregroundStyle(Theme.white)
                .environment(\.onLevel, false)
        }
    }
}

// MARK: - 褶皺の計量条(文字を載せない。一画面に一本)

enum PleatState {
    case empty, past, meeting, pastMeeting, selected
}

/// 高さ 10 の褶。亮面と暗面が交互に並び、会議のコマは灰、選んだコマは関卡色。色面の上では墨で描く
struct PleatGauge: View {
    let states: [PleatState]
    @Environment(\.level) private var level
    @Environment(\.onLevel) private var onLevel

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(states.enumerated()), id: \.offset) { index, state in
                Rectangle().fill(color(state, odd: index % 2 == 1))
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func color(_ state: PleatState, odd: Bool) -> Color {
        if onLevel {
            switch state {
            case .empty, .past: return level.ink.opacity(odd ? 0.18 : 0.12)
            case .meeting, .pastMeeting, .selected: return level.ink
            }
        }
        switch state {
        case .empty: return odd ? Theme.rgb(0x2A2A30) : Theme.rgb(0x1E1E23)
        case .past: return (odd ? Theme.rgb(0x2A2A30) : Theme.rgb(0x1E1E23)).opacity(0.7)
        case .meeting: return Theme.textSoft
        case .pastMeeting: return Theme.textSoft.opacity(0.55)
        case .selected: return level.color
        }
    }
}

// MARK: - インク(章だけに使う)

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

/// 面を切り替える瓦片(今日 / 英语)。選んだものだけ関卡色の瓦片、ほかは灰の文字だけ(溝は無い)
struct PillTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var color: Color = Theme.chrome
    var size: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
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
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2)) { selection = item.value }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.title)
                    .font(Theme.font(size, .semibold))
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(Theme.font(size - 1, .bold).monospacedDigit())
                        .opacity(0.85)
                }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.textSoft)
            .padding(.horizontal, 12)
            .frame(height: size + 13)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color)
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

/// 同じ面の中で「もの」を切り替えるタブ(单词 / 考点词…)。選んだものの下に白い細い線(色は関卡カードに譲る)
struct UnderlineTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2)) { selection = item.value }
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
                        .fill(Theme.white)
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

/// 小さなラベル行。先頭の英語(NEXT / NOW / STAND UP)は横に広い極太、続く文字は細く薄く。色は周りの文字色を継ぐ
struct Eyebrow: View {
    var lead: String?
    var text: String = ""
    var trail: String?
    @Environment(\.level) private var level

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let lead {
                Text(lead)
                    .font(Theme.label())
                    .tracking(1.5)
                    .textCase(.uppercase)
            }
            if !text.isEmpty {
                Text(text)
                    .font(Theme.font(12, .semibold).monospacedDigit())
                    // 朱红の上では薄くしない(黒 5.4:1 しかないので、灰にすると 4.5:1 を割る)
                    .opacity(level == .vermilion ? 1 : 0.72)
            }
            if let trail {
                Text(trail)
                    .font(Theme.label())
                    .tracking(1.5)
                    .textCase(.uppercase)
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
            .opacity(0.7)
            .accessibilityHidden(true)
    }
}

/// 胶囊のボタン(橡皮管)。押すと横に伸びて縦に潰れ、弾んで戻る。
/// primary:舞台の上では関卡色の塗り + 墨の文字、色面の上では墨の塗り + 白の文字(裏返し)。
/// secondary:舞台の上では灰の塗り、色面の上では 2pt の描線。quiet:文字だけ
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

/// ボタンの見た目(ホバーの状態と環境値を持つので View に分ける)
struct CommandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CommandButtonStyle.Kind
    let height: CGFloat
    let wide: Bool
    let square: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.level) private var level
    @Environment(\.onLevel) private var onLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        let small = height < 32
        configuration.label
            .font(Theme.font(kind == .quiet || small ? 12 : 14, .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : (kind == .quiet ? 2 : (small ? 12 : 18)))
            .frame(minWidth: square ? height : nil, maxWidth: wide ? .infinity : nil, minHeight: height)
            .background { background }
            .contentShape(Capsule())
            .scaleEffect(x: pressed ? 1.04 : 1, y: pressed ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.18, bounce: 0.5),
                       value: pressed)
            .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            Capsule().fill((onLevel ? level.primaryFill : level.liningPrimary).opacity(hovering ? 0.88 : 1))
        case .secondary:
            if onLevel {
                Capsule().fill(level.ink.opacity(hovering ? 0.12 : 0))
                    .overlay(Capsule().strokeBorder(level.ink, lineWidth: 2))
            } else {
                Capsule().fill(hovering ? Theme.rgb(0x333339) : Theme.fill)
            }
        case .quiet:
            if onLevel {
                Capsule().fill(level.ink.opacity(hovering ? 0.12 : 0))
            } else {
                EmptyView()
            }
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return onLevel ? level.primaryText : Theme.ink
        case .secondary: return onLevel ? level.ink : Theme.white
        case .quiet: return onLevel ? level.ink : (hovering ? Theme.white : Theme.textSoft)
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

/// 主役の数字:縦長の極太 + 下に小さな単位(右寄せ)。色は呼び出し側(里布の上では関卡色、色面の上では墨)
struct BigNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = 72
    var color: Color = Theme.white
    var unitColor: Color = Theme.textSoft

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
                    .foregroundStyle(unitColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 答えたときの章(NICE! / MISS)。インクはここだけ。NICE! は铬黄に墨、MISS は白に墨
struct Stamp: View {
    let good: Bool

    var body: some View {
        let splat = InkSplat(seed: good ? 33 : 37, lobes: 10, depth: 0.22)
        Text(good ? "NICE!" : "MISS")
            .font(Theme.shout(26))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(splat.fill(good ? Theme.chrome : Theme.white))
            // 墨の縁取り(黄が緑の上に落ちても輪郭が残る)
            .overlay(splat.stroke(Theme.ink, lineWidth: 2))
            .rotationEffect(.degrees(-8))
            .allowsHitTesting(false)
            .accessibilityLabel(good ? "答对了" : "答错了")
    }
}
