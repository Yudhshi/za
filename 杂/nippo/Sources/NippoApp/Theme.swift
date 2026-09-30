import AppKit
import SwiftUI

/// デザイントークン(2026-09 v11「Ink & Paper」:ペルソナ5 の切り紙 × スプラトゥーンの墨。iOS 27 からは透明感だけ)。
/// 形はペルソナ5:文字を載せる面はすべて「切り紙の札」(黒紙に白、白紙に墨、青/橙の紙に墨)。辺は斜め、右上をひと口かじる。
/// 一覧はメニュー:行が 1 枚ずつ札で、選んだ行は関卡色になって ▶ が付く。英語の喊声は斜体・横広・大文字、小さな札は 3〜4° 傾く。中文は直立。
/// 材質:窓は机が透ける半透明の黒(ぼかし + 墨 72%)で、角は札と同じくひと口かじる。ガラスの胶囊・大きな角丸は使わない。
/// スプラトゥーン:NICE! は墨の塊、黒い札には半調の網点、白い札の後ろに関卡色の版ずれ。
/// 色は青と橙の二色だけ:色面が青なら墨迹(大数字・章)は橙、色面が橙(緊急・立て・座れ)なら墨迹は青。色面の上の文字はつねに黒。
/// 重ねない:章は指令列の上の自分の枠に出る、数字は自分の格に居る。文字は減らして図で語る(小窓の図・下の帯の絵文字)。
/// 文字サイズは 12/13/15/22 + 大数字/見出し語/喊声。日付は英語の曜日(TUESDAY)だけ。月日はどこにも出さない
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
    /// 切り紙:黒い札(行・指令・里布)と白い札(ラベル・選んだモード)
    static let plate = rgb(0x111114)
    static let paper = rgb(0xF4F2EC)

    // 青橙の二色墨。一画面に一色の色面 + もう一色の墨迹。色面の上の文字はつねに黒(白文字は使わない:橙に白は 2.6:1)
    static let teal = rgb(0x1FD1C4)        // 青:今日 NEXT / 英语 / STANDING。黒文字 11.0:1
    static let orange = rgb(0xFF7A1A)      // 橙:緊急(NOW / 開始 5 分以内)/ STAND UP / SIT DOWN / CLEAR!。黒文字 8.0:1
    /// 夜(19:00–07:00)は少し落とす(黒文字はなお 8.2:1 / 6.7:1)
    static let tealNight = rgb(0x19B5AA)
    static let orangeNight = rgb(0xEA6D12)

    static func isNight(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour < 7 || hour >= 19
    }

    /// 札のひと口(右上の斜め切り)
    static let chamfer: CGFloat = 22
    /// 札の辺の傾き(横に何 pt ずれるか)
    static let skew: CGFloat = 9
    /// 入力欄・小さな面の角(ほぼ直角)
    static let blockRadius: CGFloat = 3

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

/// 関卡色と、その色面の上に置ける文字・主ボタンの色、もう一方の色(墨迹)。画面ごとに 1 つを環境値で流す
struct Level: Equatable {
    let color: Color
    /// 色面の上の文字
    let ink: Color
    /// 色面の上の主ボタン(塗り・文字)
    let primaryFill: Color
    let primaryText: Color
    /// 里布・舞台の上の主ボタンの塗り(文字は墨)
    let liningPrimary: Color
    /// 墨迹(主役の数字の塊・章)の色 = 色面と反対の色
    let splat: Color

    static let teal = Level(color: Theme.teal, ink: Theme.ink, primaryFill: Theme.ink,
                            primaryText: Theme.white, liningPrimary: Theme.teal, splat: Theme.orange)
    static let tealNight = Level(color: Theme.tealNight, ink: Theme.ink, primaryFill: Theme.ink,
                                 primaryText: Theme.white, liningPrimary: Theme.tealNight, splat: Theme.orangeNight)
    static let orange = Level(color: Theme.orange, ink: Theme.ink, primaryFill: Theme.ink,
                              primaryText: Theme.white, liningPrimary: Theme.orange, splat: Theme.teal)
    static let orangeNight = Level(color: Theme.orangeNight, ink: Theme.ink, primaryFill: Theme.ink,
                                   primaryText: Theme.white, liningPrimary: Theme.orangeNight, splat: Theme.tealNight)
    /// 主役が終わった/いない(灰いカード。文字は淡く)
    static let done = Level(color: Theme.card, ink: Theme.textFaint, primaryFill: Theme.fill,
                            primaryText: Theme.white, liningPrimary: Theme.fill, splat: Theme.fill)

    /// 今日・英语の関卡は青(夜は少し落とす)。緊急(NOW / 5 分以内 / 立て / 座れ)は橙
    static func today(night: Bool) -> Level { night ? .tealNight : .teal }
    static func english(night: Bool) -> Level { night ? .tealNight : .teal }
    static func urgent(night: Bool) -> Level { night ? .orangeNight : .orange }
    /// CLEAR!(橙)
    static let clear = Level.orange
}

private struct LevelKey: EnvironmentKey {
    static let defaultValue = Level.teal
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

/// 角をひと口かじった長方形(関卡カード・小窓の札)。corner でどの角か
struct BiteShape: Shape {
    enum Corner { case topRight, bottomLeft }
    var corner: Corner = .topRight
    var size: CGFloat = Theme.chamfer

    func path(in r: CGRect) -> Path {
        let s = min(size, min(r.width, r.height) / 2)
        var p = Path()
        switch corner {
        case .topRight:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + s))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case .bottomLeft:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - s))
        }
        p.closeSubpath()
        return p
    }
}

/// 関卡カードの外形(右上ひと口)
typealias HeroShape = BiteShape

/// 切り紙の札(ペルソナ5):平行四辺形。bite > 0 なら右上もかじる
struct PhantomPlate: Shape {
    var skew: CGFloat = Theme.skew
    var bite: CGFloat = 0

    func path(in r: CGRect) -> Path {
        let skew = min(self.skew, r.width / 3)
        let bite = min(self.bite, min(r.width, r.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + skew, y: r.minY))
        if bite > 0 {
            p.addLine(to: CGPoint(x: r.maxX - bite, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + bite))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        p.addLine(to: CGPoint(x: r.maxX - skew, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// 章の爆ぜた形(ペルソナ5 の「ヒット」)。山と谷が交互に並ぶ 22 の角。文字を載せるので谷は浅め
struct Burst: Shape {
    func path(in r: CGRect) -> Path {
        let radii: [CGFloat] = [1, 0.78, 0.96, 0.72, 1, 0.8, 0.94, 0.74, 0.98, 0.76, 1,
                                0.8, 0.95, 0.73, 0.99, 0.78, 0.96, 0.74, 1, 0.79, 0.97, 0.75]
        let c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        for (i, k) in radii.enumerated() {
            let a = Double(i) / Double(radii.count) * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r.width / 2 * k, y: c.y + CGFloat(sin(a)) * r.height / 2 * k)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// 色布(見る)の札:関卡カードの左に載る切り紙。右の辺はギザギザ(ペルソナ5)。
/// SeamLayout はこの 2 つの定数で左右の幅を決める(左の文字は bottom より左、右の指令列は top より右)
struct SeamShape: Shape {
    static let top: CGFloat = 0.60
    static let bottom: CGFloat = 0.54

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * Self.top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * Self.top - 26, y: r.minY + h * 0.30))
        p.addLine(to: CGPoint(x: r.minX + w * Self.top - 6, y: r.minY + h * 0.44))
        p.addLine(to: CGPoint(x: r.minX + w * Self.bottom, y: r.maxY))
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
                        Theme.plate
                        Halftone()   // 黒い札の網点(スプラトゥーン)。色布の下は隠れる
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
                        in: RoundedRectangle(cornerRadius: Theme.blockRadius, style: .continuous))
            // フォーカスは下辺の 2pt の線(墨 / 関卡色)。.plain の入力欄は自分で描かないと分からない
            .overlay(alignment: .bottom) {
                if focused {
                    Rectangle()
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

    /// 脇役の札(黒い切り紙)。会議条・空の主役・素材なしなど
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.white)
            .background(Theme.plate, in: BiteShape())
    }

    /// 下の帯:上に薄い線を引くだけ(ガラスは使わない)。文字は 13pt 以上の太字か絵文字だけ
    func footerBar() -> some View {
        self.padding(.horizontal, 4)
            .frame(height: 40)
            .overlay(alignment: .top) { Color.white.opacity(0.14).frame(height: 1) }
    }

    /// 窓の地:机が透ける半透明の黒(ぼかし)を、ひと口かじった札の形に切り、白い縁を引く
    func inkStage() -> some View {
        self.background {
                ZStack {
                    BlurBehindWindow()
                    Theme.stage.opacity(0.72)
                }
            }
            .clipShape(PanelShape())
            .overlay(PanelShape().stroke(Theme.paper.opacity(0.85), lineWidth: 2))
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
        .clipShape(PhantomPlate(skew: 4))
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

/// 面を切り替える札(今日 / 英语)。選んだものは関卡色の札に墨(滑って移る)、ほかは黒い札に白
struct PillTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var color: Color = Theme.teal
    var size: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 6) {
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
            .foregroundStyle(selected ? Theme.ink : Theme.white)
            .padding(.horizontal, 12)
            .frame(height: size + 13)
            .background {
                if selected {
                    PhantomPlate()
                        .fill(color)
                        .matchedGeometryEffect(id: "pill", in: pill)
                } else {
                    PhantomPlate().fill(Theme.plate)
                }
            }
            .contentShape(PhantomPlate())
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

/// 同じ面の中で「もの」を切り替える札(单词 / 考点词…)。選んだものは白い札に墨、ほかは黒い札に白
struct UnderlineTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    var size: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
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
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.title)
                    .font(Theme.font(size, selected ? .bold : .semibold))
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(Theme.font(12, .bold).monospacedDigit())
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(PhantomPlate().fill(selected ? Theme.paper : Theme.plate))
            .contentShape(PhantomPlate())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 切り紙の小さな札に載せた英語の喊声(NEXT / STAND UP / NEW)。色面の上では黒札に白、舞台では白札に墨(dark で黒札に固定)
struct PlateLabel: View {
    let text: String
    var tint: Color?
    var dark: Bool?
    var tilt: Double = -4
    @Environment(\.onLevel) private var onLevel

    var body: some View {
        let onDark = dark ?? onLevel
        Text(text)
            .font(Theme.shout(12))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(tint ?? (onDark ? Theme.white : Theme.ink))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(PhantomPlate().fill(onDark ? Theme.plate : Theme.paper))
            .rotationEffect(.degrees(tilt))
            .fixedSize()
    }
}

/// 小さなラベル行。先頭の英語(NEXT / NOW / STAND UP)は傾いた札、続く文字は細く薄く、trail(NEW)は黒札に関卡色
struct Eyebrow: View {
    var lead: String?
    var text: String = ""
    var trail: String?
    @Environment(\.level) private var level

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let lead {
                PlateLabel(text: lead)
            }
            if !text.isEmpty {
                Text(text)
                    .font(Theme.font(12, .semibold).monospacedDigit())
                    // 青・橙とも黒 72% でなお 5:1 以上
                    .opacity(0.72)
            }
            if let trail {
                PlateLabel(text: trail, tint: level.color, dark: true)
            }
        }
        .lineLimit(1)
    }
}

/// 小見出し:白い札に絵文字 + 英語の喊声(SCHEDULE / TASKS)。右に添え物
struct SectionHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.level) private var level

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(Theme.shout(12))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(PhantomPlate().fill(Theme.paper))
            .background(PhantomPlate().fill(level.color).offset(x: 3, y: 3))   // 版ずれ
            .rotationEffect(.degrees(-2))
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil) {
        self.init(title: title, symbol: symbol) { EmptyView() }
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

/// 切り紙の札のボタン(ペルソナ5 の指令)。押すと横に伸びて縦に潰れ、弾んで戻る。
/// primary:舞台の上では関卡色の札 + 墨の文字、色面の上では黒い札 + 白の文字(裏返し)。
/// secondary:2pt の描線(舞台では白、色面では墨)。quiet:文字だけ
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
            .contentShape(shape)
            .scaleEffect(x: pressed ? 1.04 : 1, y: pressed ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.18, bounce: 0.5),
                       value: pressed)
            .onHover { hovering = $0 }
    }

    private var shape: PhantomPlate { PhantomPlate() }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            shape.fill((onLevel ? level.primaryFill : level.liningPrimary).opacity(hovering ? 0.88 : 1))
        case .secondary:
            if onLevel {
                shape.fill(level.ink.opacity(hovering ? 0.12 : 0))
                    .overlay(shape.stroke(level.ink, lineWidth: 2))
            } else {
                shape.fill(Color.white.opacity(hovering ? 0.12 : 0))
                    .overlay(shape.stroke(Theme.paper, lineWidth: 2))
            }
        case .quiet:
            if onLevel {
                shape.fill(level.ink.opacity(hovering ? 0.12 : 0))
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

/// 主役の数字を墨の塊に載せる(v1/v3/v5/v6 の墨迹の数字)。数字は縦長の極太の斜体、単位は直立。
/// 塊の色は関卡色と反対の色(青の面なら橙)。文字は墨
struct SplatNumber<Number: View>: View {
    let unit: String
    var size: CGFloat = 60
    /// nil = level.splat
    var color: Color?
    @ViewBuilder var number: () -> Number
    @Environment(\.level) private var level

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            number()
                .font(Theme.numeral(size).italic())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(InkSplat(seed: 21, lobes: 11, depth: 0.14).fill(color ?? level.splat))
        .accessibilityElement(children: .combine)
    }
}

/// 答えたときの章:NICE! は橙の墨の塊(スプラトゥーン)、MISS は白い紙の爆ぜた形(ペルソナ5)。指令列の上の枠(StampSlot)に出る
struct Stamp: View {
    let good: Bool

    var body: some View {
        Text(good ? "NICE!" : "MISS")
            .font(Theme.shout(20))
            .tracking(1)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 26)
            .frame(height: 48)
            .background {
                if good {
                    InkSplat(seed: 33, lobes: 9, depth: 0.2).fill(Theme.orange)
                } else {
                    Burst().fill(Theme.paper)
                }
            }
            .rotationEffect(.degrees(-6))
            .allowsHitTesting(false)
            .accessibilityLabel(good ? "答对了" : "答错了")
    }
}

// MARK: - 窓を掴む所

/// ここを掴むと窓ごと動く(面板の曜日の行・小窓の上段)。ボタンの無い所にだけ敷く
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - 窓の形・網点・ぼかし・絵

/// 窓の外形:右上と左下をひと口かじった長方形(札と同じ言葉)
struct PanelShape: Shape {
    var topRight: CGFloat = 36
    var bottomLeft: CGFloat = 24

    func path(in r: CGRect) -> Path {
        let a = min(topRight, min(r.width, r.height) / 3)
        let b = min(bottomLeft, min(r.width, r.height) / 3)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - a, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + a))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - b))
        p.closeSubpath()
        return p
    }
}

/// 半調の網点(黒い札の質感)。9pt の格子に白 7% の点
struct Halftone: View {
    var pitch: CGFloat = 9
    var radius: CGFloat = 1.6
    var opacity: Double = 0.07

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = pitch / 2
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? pitch / 2 : pitch
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(Color.white.opacity(opacity)))
                    x += pitch
                }
                y += pitch * 0.87
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 窓の後ろをぼかす(机が透ける)。色味は上に重ねる墨で決める
struct BlurBehindWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 説明の絵(Resources/Stretches/<name>@2x.png、scripts/make-illustrations.py で描く)。無ければ SF Symbols で代用
struct Illustration: View {
    let name: String
    var size: CGFloat = 96
    var fallback: String = "figure.stand"

    var body: some View {
        if let image = Self.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * 0.55, weight: .regular))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Stretches/\(name)@2x.png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}
