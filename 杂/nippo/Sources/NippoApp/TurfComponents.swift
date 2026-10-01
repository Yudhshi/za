import NippoCore
import SwiftUI

// MARK: - 墙(面板)と牛皮纸

/// 今日 / 英語の面板 = 浇筑した混凝土の墙:安静な平铺(±3%)を 20pt の角丸で切り、左右の縁に纹理、
/// いちばん上に縁の九宮格(対拉孔・欠け・接地影は bleed に焼いてある)。
/// 開くとき:その日の最初の 1 回は遮盖纸を揭がして(520ms、漆はあとから淡く出る)、ほかは漆が 120ms で淡く出るだけ
struct PanelSurface: ViewModifier {
    @State private var opening = PanelOpening.current()

    func body(content: Content) -> some View {
        MotionPlayer(trigger: 0, durationMs: opening.durationMs, playOnAppear: true) { progress in
            content
                .opacity(opening.paintOpacity(progress))
                .background {
                    ZStack {
                        BakedTile(id: "concrete-night")
                        if Baked.has("concrete-edge-night") {
                            // 両端の帯だけ焼いてあり中央は透明。面板いっぱいに敷き、縦は 512pt で繰り返す
                            BakedSlice(id: "concrete-edge-night", fallback: .clear, tile: true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Turf.panelRadius, style: .continuous))
                }
                .overlay { BakedSlice(id: "panel-frame-night") }
                .overlay {
                    if opening == .cover && progress < 1 {
                        PanelCoverSheet(progress: progress)
                    }
                }
        }
    }
}

/// 面板の開き方(その日の最初の 1 回だけ遮盖纸。決めた日は覚えておく)
enum PanelOpening: Equatable {
    case fade, cover

    static func current() -> PanelOpening {
        let today = DayKey.key(for: Date())
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "panelCoverDay") != today else { return .fade }
        defaults.set(today, forKey: "panelCoverDay")
        return .cover
    }

    var durationMs: Double { self == .cover ? 520 : 120 }

    /// 漆(中身)の不透明度:遮盖纸のときは紙が飛んだあと 320–520ms で、ふだんは 0–120ms で出る
    func paintOpacity(_ progress: Double) -> Double {
        switch self {
        case .fade: return progress
        case .cover: return motionPhase(progress, totalMs: 520, from: 320, to: 520)
        }
    }
}

/// 遮盖纸:右上の角が掀起(100–160ms で掀起した絵へ溶けながら 0.96 → 1)、左下を軸に甩って(160–320ms)、
/// 窓の外へ出る前に消える(180–260ms)
private struct PanelCoverSheet: View {
    let progress: Double

    var body: some View {
        let total: Double = 520
        let peel = motionPhase(progress, totalMs: total, from: 100, to: 160)
        let fling = motionPhase(progress, totalMs: total, from: 160, to: 320)
        let fade = motionPhase(progress, totalMs: total, from: 180, to: 260)
        ZStack {
            BakedSlice(id: "cover-sheet-night", fallback: .clear, tile: true)
                .opacity(1 - peel)
            if Baked.has("cover-sheet-corner-night") {
                BakedSlice(id: "cover-sheet-corner-night", fallback: .clear, tile: true)
                    .scaleEffect(0.96 + 0.04 * peel)
                    .opacity(peel)
            }
        }
        .rotationEffect(.degrees(6 * fling), anchor: .bottomLeading)
        .offset(x: 60 * fling, y: -90 * fling)
        .opacity(1 - fade)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 区画のあいだの模板の継ぎ目(面板の端から端まで。字や卡を横切らない、隙間にだけ置く)
struct ConcreteSeam: View {
    var body: some View {
        let height = Baked.asset("concrete-seam-night")?.layoutSize.height ?? 0
        if height > 0 && Baked.has("concrete-seam-night") {
            Color.clear
                .frame(height: height)
                .overlay { BakedSprite(id: "concrete-seam-night") }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// 坐站の小窓:牛皮纸の台紙(九宮格、角 10pt は焼いてある)。神兽の残影は小窓の側で台紙の上に置く
struct KraftSurface: ViewModifier {
    /// 站立中に壁画带まで並ぶ縦長の台紙(360×500 に焼いた紙。纤维を縦に伸ばさない)
    var tall = false

    func body(content: Content) -> some View {
        let id = tall ? (Baked.first(["kraft-sheet-tall-night", "kraft-sheet-night"]) ?? "kraft-sheet-night")
                      : "kraft-sheet-night"
        content
            .background {
                if Baked.has(id) {
                    BakedSlice(id: id)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.kraft)
                }
            }
    }
}

extension View {
    func panelSurface() -> some View { modifier(PanelSurface()) }
    func kraftSurface(tall: Bool = false) -> some View { modifier(KraftSurface(tall: tall)) }

    /// 盤面の後ろの纹理の帯(気孔・骨材。両端は混凝土に溶ける)。配置には影響しない
    func boardBand() -> some View {
        background {
            Color.clear.overlay { BakedSprite(id: "concrete-band-night") }
                .allowsHitTesting(false)
        }
    }
}

// MARK: - ボタン

/// 主ボタン = 焼いた喷漆块 + 黒い中文(00 の黒い块だけ白字)。押すと 2pt 下がる。ホバーは素材の上に薄い白
struct SprayButtonStyle: ButtonStyle {
    enum Kind {
        /// 橙(面板)/ 小さな橙(高さ 34)/ 青(坐站の小窓)/ 黒い輪付きの橙(青い主角卡の上)/ 黒(到点の橙の上)
        case orange, orangeSmall, teal, orangeRinged, blackOnOrange

        @MainActor var asset: String {
            switch self {
            case .orange: return "button-orange-night"
            case .orangeSmall: return Baked.has("button-orange-small-night") ? "button-orange-small-night" : "button-orange-night"
            case .teal: return "button-teal-night"
            case .orangeRinged: return "button-orange-ringed-night"
            case .blackOnOrange: return Baked.has("button-black-zero") ? "button-black-zero" : "plate-black-night"
            }
        }

        var fallback: Color {
            switch self {
            case .orange, .orangeSmall, .orangeRinged: return Palette.orange
            case .teal: return Palette.teal
            case .blackOnOrange: return Palette.black
            }
        }

        var foreground: Color { self == .blackOnOrange ? Palette.white : Palette.black }
    }

    var kind: Kind = .orange
    var height: CGFloat = Turf.primaryButton
    var wide = false
    /// 決まった幅(主角卡の 120pt など)
    var width: CGFloat?
    var padding: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        SprayButtonBody(configuration: configuration, kind: kind, height: height, wide: wide, width: width,
                        padding: padding)
    }
}

private struct SprayButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SprayButtonStyle.Kind
    let height: CGFloat
    let wide: Bool
    let width: CGFloat?
    let padding: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        // 短い文字でも焼いた块を 0.8 倍より細くしない(喷粒が横に潰れる)
        let minWidth = width == nil ? (Baked.asset(kind.asset)?.layoutSize.width ?? 0) * 0.8 : nil
        configuration.label
            .font(height < 40 ? Typeface.mixed(14, weight: 900) : TypeRole.button)
            .tracking(height < 40 ? 0.4 : 0.68)
            .foregroundStyle(kind.foreground)
            .lineLimit(1)
            .padding(.horizontal, width == nil ? padding : 0)
            .frame(width: width, height: height)
            .frame(minWidth: minWidth, maxWidth: wide ? .infinity : nil)
            .background {
                BakedSlice(id: kind.asset, fallback: kind.fallback)
                    // 閉包にして View の blendMode に決める(ShapeStyle 版と取り合わない)
                    .overlay { Palette.white.opacity(hovering && !pressed ? 0.08 : 0).blendMode(.screen) }
            }
            .contentShape(Rectangle())
            .offset(y: pressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}

/// 次ボタン = 焼いた 2pt の白漆の遮喷枠 + 文字(混凝土の上は白、牛皮纸の上は黒)。ホバーは枠の中に遮喷の薄い块
struct FrameButtonStyle: ButtonStyle {
    var height: CGFloat = Turf.primaryButton
    var wide = false
    var width: CGFloat?
    /// 牛皮纸の上(枠は白漆のまま、文字は黒)
    var onKraft = false

    func makeBody(configuration: Configuration) -> some View {
        FrameButtonBody(configuration: configuration, height: height, wide: wide, width: width, onKraft: onKraft)
    }
}

private struct FrameButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    let wide: Bool
    let width: CGFloat?
    let onKraft: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        // 牛皮纸の上は牛皮纸に焼いた白漆の枠(地面の違う素材を流用しない)
        let frame = onKraft && Baked.has("frame-white-kraft") ? "frame-white-kraft" : "frame-white-night"
        let minWidth = width == nil ? (Baked.asset(frame)?.layoutSize.width ?? 0) * 0.8 : nil
        configuration.label
            .font(height < 40 ? Typeface.mixed(14, weight: 900) : TypeRole.button)
            .tracking(height < 40 ? 0.4 : 0.68)
            .foregroundStyle(onKraft ? Palette.kraftText : Palette.text)
            .lineLimit(1)
            .padding(.horizontal, width == nil ? 18 : 0)
            .frame(width: width, height: height)
            .frame(minWidth: minWidth, maxWidth: wide ? .infinity : nil)
            .background {
                // 悬停は枠の白漆が少し明るくなるだけ(枠の中に矩形を敷かない)
                Group {
                    if Baked.has(frame) {
                        BakedSlice(id: frame)
                    } else {
                        Rectangle().strokeBorder(Palette.white, lineWidth: 2)
                    }
                }
                .brightness(hovering && !pressed && isEnabled ? 0.08 : 0)
            }
            .contentShape(Rectangle())
            .offset(y: pressed ? 2 : 0)
            .opacity(isEnabled ? (onKraft && hovering ? 0.85 : 1) : 0.4)
            .onHover { hovering = $0 }
    }
}

/// 文字だけのボタン(底栏・取り消し・小さな操作)。ホバーで下に遮喷の薄い块、押せないときは暗く
struct BareButtonStyle: ButtonStyle {
    var color: Color = Palette.textSecondary
    /// 悬停の文字色(牛皮纸の上は Palette.kraftText)
    var hoverColor: Color = Palette.text

    func makeBody(configuration: Configuration) -> some View {
        BareButtonBody(configuration: configuration, color: color, hoverColor: hoverColor)
    }
}

private struct BareButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let hoverColor: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        // 文字だけのボタンは悬停で文字が明るくなるだけ(下に块を敷くと、焼いた块が細く潰れる)
        configuration.label
            .foregroundStyle(hovering && isEnabled ? hoverColor : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }
}

/// 評分・選択肢 = 焼いた灰漆の遮喷块 + 本物の文字。選んだ / 正解 = 青、誤って選んだ = 灰 + 删除线 + ✕。
/// size で焼いた大きさの違う块を選ぶ(option 233×56 / rate 112×52 / generic)
struct BlockButtonStyle: ButtonStyle {
    enum Look { case idle, selected, wrong }
    enum Size { case option, rate, generic }

    var state: Look = .idle
    var size: Size = .generic
    var height: CGFloat = Turf.ratingButton
    var wide = true
    /// 删除线(誤って選んだときの文字)。番号や「你的选择」に線を引きたくないときは false にして自分で引く
    var strikeLabel = true

    func makeBody(configuration: Configuration) -> some View {
        BlockButtonBody(configuration: configuration, state: state, size: size, height: height, wide: wide,
                        strikeLabel: strikeLabel)
    }
}

private struct BlockButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let state: BlockButtonStyle.Look
    let size: BlockButtonStyle.Size
    let height: CGFloat
    let wide: Bool
    let strikeLabel: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var asset: String {
        let paint: String
        switch state {
        case .idle: paint = "slate"
        case .selected: paint = "teal"
        case .wrong: paint = "grey"
        }
        let suffix: String
        switch size {
        case .option: suffix = "-option"
        case .rate: suffix = "-rate"
        case .generic: suffix = ""
        }
        let sized = "block-\(paint)\(suffix)-night"
        return Baked.has(sized) ? sized : "block-\(paint)-night"
    }

    private var fallback: Color {
        switch state {
        case .idle: return Palette.disabledFill
        case .selected: return Palette.teal
        case .wrong: return Palette.meetingGrey
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.disabledText }
        switch state {
        case .idle: return Palette.text
        case .selected, .wrong: return Palette.black
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(foreground)
            .strikethrough(strikeLabel && state == .wrong, color: Palette.black)
            .padding(.horizontal, 12)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: height, maxHeight: height)
            .background {
                BakedSlice(id: asset, fallback: fallback)
                    .overlay { Palette.white.opacity(hovering && state == .idle && !pressed && isEnabled ? 0.06 : 0) }
            }
            .overlay(alignment: .trailing) {
                if state == .wrong {
                    StencilIconView(icon: .cross, size: 14)
                        .foregroundStyle(Palette.black)
                        .padding(.trailing, 12)
                }
            }
            .contentShape(Rectangle())
            .offset(y: pressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.6)
            .onHover { hovering = $0 }
    }
}

/// 悬停:遮喷の薄い块がふっと出る(混凝土の上の行・文字ボタン)。素材が無ければ何も出さない(単色の矩形は使わない)。
/// 行の幅と高さに合わせて焼いた块を選ぶ:title = 面板幅で高さ 24(「任务 N」の行)、small = 120×24、ふだん = 472×40
struct HoverPlate: View {
    let active: Bool
    var small = false
    var title = false

    var body: some View {
        let id = title ? Baked.first(["row-hover-title-night", "row-hover-night"])
            : (small ? Baked.first(["row-hover-small-night", "row-hover-night"]) : "row-hover-night")
        BakedSlice(id: id ?? "row-hover-night")
            .opacity(active ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: active)
            .allowsHitTesting(false)
    }
}

// MARK: - 標籤(今日 / 英語、单词 / 考点词 / 语料 / 词典)

/// 未選 = 文字だけ(14 / 700、次要色、枠なし)。選んだもの = 焼いた白漆の遮喷小块 + 黒い字(滑って移る)。
/// 今日の分が終わった標籤は数の代わりに模板の ✓
struct StencilTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var chip

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
        // 読み上げの値は先に String にしておく(閉包 + 三項 + 多重定義を 1 つの式で推論させない)
        let spokenValue: String = item.done ? "已完成" : (item.badge.map { String($0) } ?? "")
        let button = Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2)) {
                selection = item.value
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.title)
                    .font(TypeRole.tab)
                if item.done {
                    StencilIconView(icon: .check, size: 11)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                } else if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(TypeRole.count)
                }
            }
            .foregroundStyle(selected ? Palette.black : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: Turf.tabHeight)
            .background {
                if selected {
                    // 「学习中 120」のような長い札は幅広に焼いた块
                    let long = item.title.count + (item.badge.map { String($0).count + 1 } ?? 0) >= 5
                    BakedSlice(id: long ? (Baked.first(["tab-chip-wide-night", "tab-chip-night"]) ?? "tab-chip-night")
                                        : "tab-chip-night",
                               fallback: Palette.white)
                        .matchedGeometryEffect(id: "chip", in: chip)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(spokenValue)
        if let key = item.shortcut {
            button
                .keyboardShortcut(key, modifiers: .command)
                .help("\(item.title)（⌘\(String(key.character))）")
        } else {
            button
        }
    }
}

// MARK: - 小さな部品

/// 手で切った四角の枠(2px の白漆の遮喷、角は不揃い)。勾选 = 青で喷き、その上に模板の ✓(黒)
struct HandCheckbox: View {
    let checked: Bool
    var size: CGFloat = Turf.checkbox

    var body: some View {
        let id = checked ? "checkbox-checked-night" : "checkbox-night"
        Group {
            if Baked.has(id) {
                BakedSprite(id: id)
            } else if checked {
                Rectangle().fill(Palette.teal)
            } else {
                Rectangle().strokeBorder(Palette.white, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if checked {
                StencilIconView(icon: .check, size: size * 0.75)
                    .foregroundStyle(Palette.black)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 遮喷の小さな札(橙の「到点了」、青の CLEAR など)。文字は本物:欧文だけなら Archivo 900 幅広、中文は直立
struct PaintTag: View {
    let text: String
    var asset = "tag-orange-night"
    var fallback: Color = Palette.orange
    var foreground: Color = Palette.black
    var height: CGFloat = 24

    var body: some View {
        let latin = text.unicodeScalars.allSatisfy { $0.isASCII }
        let minWidth = (Baked.asset(asset)?.layoutSize.width ?? 0) * 0.8
        Text(text)
            .font(latin ? TypeRole.tagLatin : Typeface.mixed(12.5, weight: 900))
            .tracking(latin ? 0.8 : 0.2)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background { BakedSlice(id: asset, fallback: fallback) }
    }
}

/// 盤面・時長の格(既定 10.5 × 20pt。幅は盤面の格数で少し変わる)。素材がなければ単色で代える
struct TurfCell: View {
    enum Kind: String {
        case empty, past, meeting, meetingPast = "meeting-past", teal, tealDots = "teal-dots", black,
             blackDots = "black-dots", outline
    }

    let kind: Kind
    var width: CGFloat = 10.5
    var height: CGFloat = 20

    var body: some View {
        // 30 分の盤面の太い格(約 18pt)は、それ用に焼いた格
        let narrow = "cell-\(kind.rawValue)-night"
        let id = width > 14 ? (Baked.first(["cell-\(kind.rawValue)-wide-night", narrow]) ?? narrow) : narrow
        Group {
            if Baked.has(id) {
                BakedSlice(id: id)
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        switch kind {
        case .empty: Rectangle().strokeBorder(Palette.cellEmptyStroke, lineWidth: 1.5)
        case .past: Rectangle().fill(Palette.cellPastFill)
        case .meeting: Rectangle().fill(Palette.meetingGrey)
        case .meetingPast: Rectangle().fill(Palette.meetingCellPast)
        case .teal: Rectangle().fill(Palette.teal)
        case .tealDots: Rectangle().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 1.5)
        case .black: Rectangle().fill(Palette.black)
        case .blackDots: Rectangle().strokeBorder(Palette.black.opacity(0.6), lineWidth: 1.5)
        case .outline: Rectangle().strokeBorder(Palette.white.opacity(0.7), lineWidth: 1.5)
        }
    }
}

/// 評分の格(漆の満ち具合で語る):easy = 满 + 星、good = 满、fuzzy = まばらな点、forgot = 灰 + ✕、current = 橙の破線。
/// 空き / いまの 1 問から塗られたときは雾点 → 满 → 星 / ✕ が落ちる(200ms)
struct RatingCell: View {
    typealias Kind = RoundMark

    let kind: Kind
    /// 30(本轮の 4×5)/ 20(复习记录)/ 14(凡例)
    var size: CGFloat = 30
    /// 塗られたときに喷く動き(本轮の地盘だけ。复习记录・凡例・見本は動かさない)
    var animated = false
    /// 黒い小さな台の上の 14pt(評分ボタンの見本)。黒い台に焼いた格を使う
    var dark = false

    var body: some View {
        Group {
            if animated {
                MotionPlayer(trigger: kind, durationMs: 200) { progress in
                    cell(progress)
                }
            } else {
                cell(1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(_ progress: Double) -> some View {
        let painted = kind != .empty && kind != .current
        let mistID = "rate-\(Int(size))-\(kind.rawValue)-mist"
        if painted && progress < 0.3 && Baked.has(mistID) {
            BakedSprite(id: mistID)
        } else {
            let land = motionPhase(progress, totalMs: 200, from: 160, to: 200)
            let marked = kind == .easy || kind == .forgot
            finalCell
                .scaleEffect(marked && painted && progress < 1 ? 1.15 - 0.15 * land : 1)
        }
    }

    @ViewBuilder
    private var finalCell: some View {
        let plain = "rate-\(Int(size))-\(kind.rawValue)"
        let id = dark ? (Baked.first(["\(plain)-dark", plain]) ?? plain) : plain
        if Baked.has(id) {
            BakedSprite(id: id)
        } else {
            fallback
        }
    }

    @ViewBuilder
    private var fallback: some View {
        switch kind {
        case .easy:
            Rectangle().fill(Palette.teal)
                .overlay(StencilIconView(icon: .star, size: size * 0.55).foregroundStyle(Palette.black))
        case .good: Rectangle().fill(Palette.teal)
        case .fuzzy: Rectangle().strokeBorder(Palette.teal, lineWidth: 1.5)
        case .forgot:
            Rectangle().fill(Palette.meetingGrey)
                .overlay(StencilIconView(icon: .cross, size: size * 0.55).foregroundStyle(Palette.black))
        case .empty: Rectangle().strokeBorder(Palette.cellEmptyStroke, lineWidth: 1.5)
        case .current: Rectangle().strokeBorder(Palette.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 2.6]))
        }
    }
}

/// 喷块の下縁から垂れる漆(動の主角卡・答えた直後の白卡。卡 1 枚に 3 本まで。静では出さない)。
/// xs は卡の幅に対する割合、seed で素材を選ぶ。maxLength より長い垂れは選ばない(下の格・ボタンに届かない)。
/// grow = 垂れが伸びる途中(0…1、焼いた drip-grow の遮罩)
struct Drips: View {
    enum Paint: String { case teal, black, orange, white }

    let paint: Paint
    var xs: [CGFloat] = [0.24, 0.81]
    var seed: Int = 0
    var maxLength: CGFloat = 40
    var grow: Double = 1

    var body: some View {
        GeometryReader { geo in
            let ids = Self.choose(paint: paint, count: min(3, xs.count), seed: seed, maxLength: maxLength)
            ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                if let asset = Baked.asset(id) {
                    // 素材の anchor(画像の座標)を卡の下縁の x に合わせる。position は配置の枠(bleed を除く)の中心
                    let anchor = (asset.anchor?.count ?? 0) >= 2 ? (asset.anchor ?? []) : [asset.width / 2, 0]
                    let bleed = asset.bleedInsets
                    BakedSprite(id: id)
                        .fixedSize()
                        .mask(alignment: .top) { growMask(asset) }
                        .position(x: geo.size.width * xs[index] - anchor[0] + bleed.leading + asset.layoutSize.width / 2,
                                  y: geo.size.height - anchor[1] + bleed.top + asset.layoutSize.height / 2 - 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func growMask(_ asset: BakedManifest.Asset) -> some View {
        if grow >= 1 {
            Rectangle()
        } else if Baked.hasFrames("drip-grow-", count: 4) {
            BakedFrame(prefix: "drip-grow-", count: 4, progress: grow)
                .frame(width: asset.width, height: asset.height)
        } else {
            Rectangle().frame(height: asset.height * grow)
        }
    }

    /// 長さが maxLength 以下の素材から、seed で決まった順に count 本(足りなければ短いものを繰り返す)
    static func choose(paint: Paint, count: Int, seed: Int, maxLength: CGFloat) -> [String] {
        let all = (1...6).map { "drip-\(paint.rawValue)-\($0)" }
        let fitting = all.filter { (Baked.asset($0)?.layoutSize.height ?? .infinity) <= maxLength }
        let pool = fitting.isEmpty ? Array(all.prefix(1)) : fitting
        guard count > 0, !pool.isEmpty else { return [] }
        return (0..<count).map { pool[(seed + $0 * 2) % pool.count] }
    }
}

/// NICE! / ⊘ MISS の章。出たときに 1 回:模板纸を置く → 喷く(焼いた遮罩)→ 纸を揭がす → (NICE だけ)垂れが伸びる。
/// 減らす動きでは完成した章だけ。素材がなければ本物の文字の札
struct TurfStamp: View {
    enum Kind { case nice, miss }

    let kind: Kind

    private var total: Double { kind == .nice ? 600 : 420 }

    var body: some View {
        let id = kind == .nice ? "stamp-nice-night" : "stamp-miss-night"
        Group {
            if Baked.has(id) {
                MotionPlayer(trigger: kind == .nice, durationMs: total, playOnAppear: true) { progress in
                    stamp(id: id, progress: progress)
                }
            } else {
                Text(kind == .nice ? "NICE!" : "⊘ MISS")
                    .font(Typeface.archivo(32, weight: 900, width: 125))
                    .foregroundStyle(Palette.black)
                    .frame(width: 150, height: 60)
                    .background(kind == .nice ? Palette.orange : Palette.meetingGrey)
                    .rotationEffect(.degrees(kind == .nice ? -7 : 5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .nice ? "答对了" : "答错了")
    }

    @ViewBuilder
    private func stamp(id: String, progress: Double) -> some View {
        let nice = kind == .nice
        let place = motionPhase(progress, totalMs: total, from: 0, to: nice ? 90 : 110)
        let spray = motionPhase(progress, totalMs: total, from: nice ? 90 : 110, to: nice ? 220 : 270)
        let lift = motionPhase(progress, totalMs: total, from: nice ? 220 : 270, to: nice ? 320 : 420)
        let sheet = nice ? "stamp-nice-sheet" : "stamp-miss-sheet"
        let grow = motionPhase(progress, totalMs: total, from: 320, to: 600)
        ZStack {
            // 章の垂れは章の素材に焼いてある:喷く間は遮罩で隠し、纸を揭がしてから dripBox の中で伸ばす
            BakedSprite(id: id)
                .mask { stampMask(nice: nice, progress: progress, spray: spray, grow: grow) }
            if progress < 1 && lift < 1 && Baked.has(sheet) {
                BakedSprite(id: sheet)
                    .offset(x: 18 * lift, y: -8 * (1 - place) - 26 * lift)
                    .opacity(place * (1 - lift))
            }
        }
    }
}

extension TurfStamp {
    @ViewBuilder
    @MainActor fileprivate func stampMask(nice: Bool, progress: Double, spray: Double, grow: Double) -> some View {
        if progress >= 1 || !Baked.hasFrames("stamp-mask-", count: 4) {
            Rectangle().opacity(progress >= 1 ? 1 : spray).padding(-40)
        } else if spray < 1 {
            BakedFrame(prefix: "stamp-mask-", count: 4, progress: spray)
        } else if !nice {
            Rectangle().padding(-40)
        } else {
            ZStack(alignment: .topLeading) {
                BakedFrame(prefix: "stamp-mask-", count: 4, progress: 1)
                if let box = Baked.asset("stamp-mask-0")?.dripBox, box.count == 4 {
                    BakedFrame(prefix: "drip-grow-", count: 4, progress: grow)
                        .frame(width: box[2], height: box[3])
                        .offset(x: box[0], y: box[1])
                }
            }
        }
    }
}

/// 章の槽(148 × 86)。空のときは墙に残った胶带の浅い印(焼いた stamp-slot)、虚線の枠は描かない
struct StampSlotMark: View {
    var body: some View {
        Color.clear
            .frame(width: 148, height: 86)
            .overlay {
                if Baked.has("stamp-slot-night") {
                    BakedSprite(id: "stamp-slot-night")
                }
            }
            .accessibilityHidden(true)
    }
}

/// 坐站小窗の手順の点:做完 = 黒、いま = 青 + 黒い輪(16pt)、これから = 模板の浅い印(10pt)。牛皮纸の上、間 6pt
struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                let state = i < index ? "done" : (i == index ? "current" : "future")
                let size: CGFloat = i == index ? 16 : 10
                Group {
                    if Baked.has("dot-\(state)-kraft") {
                        BakedSprite(id: "dot-\(state)-kraft")
                    } else {
                        Circle()
                            .fill(i < index ? Palette.kraftText : (i == index ? Palette.teal : Color.clear))
                            .overlay { Circle().strokeBorder(Palette.kraftText.opacity(i > index ? 0.35 : 1), lineWidth: 1.5) }
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 白卡の四隅の橙の对位角标(模板を合わせる印。通关の卡だけ)。
/// 素材は左上の角で、anchor = L の外側の頂点。頂点を卡の角から外へ 6pt に置き、ほかの三隅は頂点を軸に 90 / 180 / 270° 回す
struct RegMarks: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            if let asset = Baked.asset("regmark-orange-night"), Baked.has("regmark-orange-night") {
                let anchor = (asset.anchor?.count ?? 0) >= 2 ? (asset.anchor ?? []) : [0, 0]
                let bleed = asset.bleedInsets
                GeometryReader { geo in
                    let corners: [(CGPoint, Double)] = [
                        (CGPoint(x: -6, y: -6), 0), (CGPoint(x: geo.size.width + 6, y: -6), 90),
                        (CGPoint(x: geo.size.width + 6, y: geo.size.height + 6), 180),
                        (CGPoint(x: -6, y: geo.size.height + 6), 270),
                    ]
                    ForEach(0..<corners.count, id: \.self) { i in
                        // 頂点を 0×0 の枠の原点に合わせ、その原点を軸に回して角へ置く
                        BakedSprite(id: "regmark-orange-night")
                            .fixedSize()
                            .offset(x: -(anchor[0] - bleed.leading), y: -(anchor[1] - bleed.top))
                            .frame(width: 0, height: 0, alignment: .topLeading)
                            .rotationEffect(.degrees(corners[i].1), anchor: .topLeading)
                            .position(corners[i].0)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func regMarks() -> some View { modifier(RegMarks()) }
}
