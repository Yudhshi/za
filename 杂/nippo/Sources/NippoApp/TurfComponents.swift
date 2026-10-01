import SwiftUI

// MARK: - 面と台紙

/// 今日 / 英語の面板:平铺の混凝土を 20pt の角丸で切り、上に縁の九宮格(対拉孔・欠け・接地影)を重ねる。
/// 影は panel-frame の bleed に焼いてあるので、窓のシステム影は使わない
struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                MaterialTile(id: "concrete-night")
                    .clipShape(RoundedRectangle(cornerRadius: Turf.panelRadius, style: .continuous))
            }
            .overlay { MaterialSlice(id: "panel-frame-night") }
    }
}

/// 文字の下だけ混凝土を ±3% に静める(texture zone の上に文字を置くとき)
struct QuietConcrete: View {
    var body: some View {
        MaterialTile(id: "concrete-quiet-night", fallback: Palette.surface)
    }
}

/// 坐站の小窓:牛皮纸の台紙(九宮格)。神兽の残影は彩蛋としてうっすら
struct KraftSurface: ViewModifier {
    var ghost: String?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack(alignment: .bottomTrailing) {
                    MaterialSlice(id: "kraft-sheet-night", fallback: Palette.kraft)
                    if let ghost, Material.has(ghost) {
                        MaterialSprite(id: ghost)
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                    }
                }
            }
    }
}

extension View {
    func panelSurface() -> some View { modifier(PanelSurface()) }
    func kraftSurface(ghost: String? = nil) -> some View { modifier(KraftSurface(ghost: ghost)) }
}

// MARK: - ボタン

/// 主ボタン = 焼いた喷漆块(橙 / 坐站の小窓は青 / 青い主角卡の上は黒い輪付きの橙)+ 黒い中文。
/// 押すと 2pt 下がる。ホバーは素材の上に薄い白(素材の色は変えない)
struct SprayButtonStyle: ButtonStyle {
    enum Kind {
        case orange, teal, orangeRinged

        var asset: String {
            switch self {
            case .orange: return "button-orange-night"
            case .teal: return "button-teal-night"
            case .orangeRinged: return "button-orange-ringed-night"
            }
        }

        var fallback: Color {
            switch self {
            case .orange, .orangeRinged: return Palette.orange
            case .teal: return Palette.teal
            }
        }
    }

    var kind: Kind = .orange
    var height: CGFloat = Turf.primaryButton
    var wide = false

    func makeBody(configuration: Configuration) -> some View {
        SprayButtonBody(configuration: configuration, kind: kind, height: height, wide: wide)
    }
}

private struct SprayButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SprayButtonStyle.Kind
    let height: CGFloat
    let wide: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(TypeRole.button)
            .tracking(17 * 0.04)
            .foregroundStyle(Palette.black)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: height, maxHeight: height)
            .background {
                MaterialSlice(id: kind.asset, fallback: kind.fallback)
                    .overlay(Palette.white.opacity(hovering && !pressed ? 0.08 : 0).blendMode(.screen))
            }
            .contentShape(Rectangle())
            .offset(y: pressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}

/// 次ボタン = 焼いた 2pt の白漆の遮喷枠 + 白い文字(CSS の枠線ではない)
struct FrameButtonStyle: ButtonStyle {
    var height: CGFloat = Turf.primaryButton
    var wide = false
    /// 牛皮纸の上(枠は白漆のまま、文字は黒)
    var onKraft = false

    func makeBody(configuration: Configuration) -> some View {
        FrameButtonBody(configuration: configuration, height: height, wide: wide, onKraft: onKraft)
    }
}

private struct FrameButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let height: CGFloat
    let wide: Bool
    let onKraft: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(TypeRole.button)
            .tracking(17 * 0.04)
            .foregroundStyle(onKraft ? Palette.kraftText : Palette.text)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: height, maxHeight: height)
            .background {
                ZStack {
                    if hovering && !pressed {
                        Rectangle().fill(onKraft ? Palette.kraftRule : Palette.rowHover)
                    }
                    // 牛皮纸の上でも枠は白漆(文字だけ黒)
                    if Material.has("frame-white-night") {
                        MaterialSlice(id: "frame-white-night")
                    } else {
                        Rectangle().strokeBorder(Palette.white, lineWidth: 2)
                    }
                }
            }
            .contentShape(Rectangle())
            .offset(y: pressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}

/// 文字だけのボタン(底栏・取り消し・小さな操作)。ホバーで混凝土が少し明るくなる
struct BareButtonStyle: ButtonStyle {
    var color: Color = Palette.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        BareButtonBody(configuration: configuration, color: color)
    }
}

private struct BareButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering ? Palette.text : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Rectangle().fill(hovering ? Palette.rowHover : .clear))
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 1 : 0)
            .onHover { hovering = $0 }
    }
}

/// 評分・選択肢 = 焼いた灰漆の遮喷块 + 本物の文字。選んだ / 正解 = 青、誤って選んだ = 灰 + 删除线 + ✕
struct BlockButtonStyle: ButtonStyle {
    enum Look { case idle, selected, wrong, disabled }

    var state: Look = .idle
    var height: CGFloat = Turf.ratingButton
    var wide = true

    func makeBody(configuration: Configuration) -> some View {
        BlockButtonBody(configuration: configuration, state: state, height: height, wide: wide)
    }
}

private struct BlockButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let state: BlockButtonStyle.Look
    let height: CGFloat
    let wide: Bool
    @State private var hovering = false

    private var asset: String {
        switch state {
        case .idle, .disabled: return "block-slate-night"
        case .selected: return "block-teal-night"
        case .wrong: return "block-grey-night"
        }
    }

    private var fallback: Color {
        switch state {
        case .idle: return Palette.disabledFill
        case .disabled: return Palette.disabledFill
        case .selected: return Palette.teal
        case .wrong: return Palette.meetingGrey
        }
    }

    private var foreground: Color {
        switch state {
        case .idle: return Palette.text
        case .disabled: return Palette.disabledText
        case .selected, .wrong: return Palette.black
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(foreground)
            .strikethrough(state == .wrong, color: Palette.black)
            .padding(.horizontal, 12)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: height, maxHeight: height)
            .background {
                MaterialSlice(id: asset, fallback: fallback)
                    .overlay(Palette.white.opacity(hovering && state == .idle && !pressed ? 0.06 : 0))
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
            .onHover { hovering = $0 }
    }
}

// MARK: - 標籤(今日 / 英語、单词 / 考点词 / 语料 / 词典)

/// 未選 = 文字だけ(14 / 700、次要色、枠なし)。選んだもの = 焼いた白漆の遮喷小块 + 黒い字
struct StencilTabs<Value: Hashable>: View {
    let items: [TabItem<Value>]
    @Binding var selection: Value

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
            selection = item.value
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.title)
                    .font(TypeRole.tab)
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(TypeRole.count)
                }
            }
            .foregroundStyle(selected ? Palette.black : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: Turf.tabHeight)
            .background {
                if selected {
                    MaterialSlice(id: "tab-chip-night", fallback: Palette.white)
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

// MARK: - 小さな部品

/// 手で切った四角の枠(2px の白漆の遮喷、角は不揃い)。勾选 = 青で喷き、模板の ✓
struct HandCheckbox: View {
    let checked: Bool
    var size: CGFloat = Turf.checkbox

    var body: some View {
        let id = checked ? "checkbox-checked-night" : "checkbox-night"
        Group {
            if Material.has(id) {
                MaterialSprite(id: id)
            } else if checked {
                Rectangle().fill(Palette.teal)
                    .overlay(StencilIconView(icon: .check, size: size * 0.75).foregroundStyle(Palette.black))
            } else {
                Rectangle().strokeBorder(Palette.white, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 遮喷の小さな札(橙の「到点了」など)。文字は本物
struct PaintTag: View {
    let text: String
    var asset = "tag-orange-night"
    var fallback: Color = Palette.orange
    var foreground: Color = Palette.black

    var body: some View {
        Text(text)
            .font(Typeface.cjk(12, weight: .black))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background { MaterialSlice(id: asset, fallback: fallback) }
    }
}

/// 盤面・時長の格(10.5 × 20pt)。素材がなければ単色で代える
struct TurfCell: View {
    enum Kind: String {
        case empty, past, meeting, meetingPast = "meeting-past", teal, tealDots = "teal-dots", black, blackDots = "black-dots"
    }

    let kind: Kind
    var width: CGFloat = 10.5
    var height: CGFloat = 20

    var body: some View {
        let id = "cell-\(kind.rawValue)-night"
        Group {
            if Material.has(id) {
                MaterialSprite(id: id)
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
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
        }
    }
}

/// 評分の格(漆の満ち具合で語る):easy = 満 + 星、good = 満、fuzzy = まばらな点、forgot = 灰 + ✕、current = 橙の破線
struct RatingCell: View {
    enum Kind: String { case easy, good, fuzzy, forgot, empty, current }

    let kind: Kind
    /// 24(本轮の 4×5)/ 18(复习记录)/ 14(凡例)
    var size: CGFloat = 24

    var body: some View {
        let id = "rate-\(Int(size))-\(kind.rawValue)"
        Group {
            if Material.has(id) {
                MaterialSprite(id: id)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

/// 動の主角卡の下縁から垂れる漆(卡 1 枚に 3 本まで。静では出さない)。
/// xs は卡の幅に対する割合、seed で素材を選ぶ
struct Drips: View {
    enum Paint: String { case teal, black, orange }

    let paint: Paint
    var xs: [CGFloat] = [0.24, 0.81]
    var seed: Int = 0

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(xs.prefix(3).enumerated()), id: \.offset) { index, x in
                let id = "drip-\(paint.rawValue)-\((seed + index * 2) % 6 + 1)"
                if let asset = Material.asset(id) {
                    // 素材の anchor(画像の座標)を卡の下縁の x に合わせる。position は配置の枠(bleed を除く)の中心
                    let anchor = asset.anchor ?? [asset.width / 2, 0]
                    let bleed = asset.bleedInsets
                    MaterialSprite(id: id)
                        .fixedSize()
                        .position(x: geo.size.width * x - anchor[0] + bleed.leading + asset.layoutSize.width / 2,
                                  y: geo.size.height - anchor[1] + bleed.top + asset.layoutSize.height / 2 - 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// NICE! / ⊘ MISS の章(焼いた完成品。回転も焼いてある)。素材がなければ本物の文字の札
struct TurfStamp: View {
    enum Kind { case nice, miss }

    let kind: Kind

    var body: some View {
        let id = kind == .nice ? "stamp-nice-night" : "stamp-miss-night"
        if Material.has(id) {
            MaterialSprite(id: id)
                .accessibilityLabel(kind == .nice ? "NICE!" : "MISS")
        } else {
            Text(kind == .nice ? "NICE!" : "⊘ MISS")
                .font(Typeface.archivo(32, weight: 900, width: 125))
                .foregroundStyle(Palette.black)
                .frame(width: 150, height: 60)
                .background(kind == .nice ? Palette.orange : Palette.meetingGrey)
                .rotationEffect(.degrees(kind == .nice ? -7 : 5))
        }
    }
}
