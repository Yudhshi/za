import AppKit
import SwiftUI
import NippoCore

/// 画面上部中央に出す、座り/立ちの小窓(ガラスの枠 + 切り紙の札)。掴んで動かせる(動かした位置は次からも使う)。
/// フォーカスを奪わない(打鍵中のアプリはそのまま)・全スペースとフルスクリーンの上にも出る
@MainActor
final class PosturePanelController {
    private var panel: NSPanel?
    private unowned let coordinator: AppCoordinator
    /// 自分で動かした位置(左上)。nil なら画面上部の中央
    private var movedTopLeft: CGPoint?
    private var programmaticMove = false
    private var moveObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// posturePrompt に合わせて出し入れ。内容が変わったら高さを合わせる(上端は固定)
    func update() {
        guard coordinator.posturePrompt != nil else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // SwiftUI の再レイアウト後に測る
        DispatchQueue.main.async { [weak self] in
            // 出すと決めたあとに閉じられていたら、空の窓を出し直さない
            guard let self, self.coordinator.posturePrompt != nil else { return }
            guard let host = panel.contentView else { return }
            let size = host.fittingSize
            let frame: NSRect
            if let topLeft = self.movedTopLeft,
               let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(topLeft) })?.visibleFrame {
                // 動かした所に。画面からはみ出さないように寄せる
                let x = max(screen.minX, min(topLeft.x, screen.maxX - size.width))
                let y = max(screen.minY, min(topLeft.y - size.height, screen.maxY - size.height))
                frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            } else {
                // マウスのある画面の上部中央(外部ディスプレイで作業中に内蔵画面へ出さない)。無ければ主画面
                let mouse = NSEvent.mouseLocation
                let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
                guard let screen = target?.visibleFrame else { return }
                frame = NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 12,
                               width: size.width, height: size.height)
            }
            self.programmaticMove = true
            panel.setFrame(frame, display: true)
            self.programmaticMove = false
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // 押したのがボタンなら key にならない(打鍵中のアプリからキーボードを奪わない)
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true             // 紙が机から少し浮く程度のシステムの影
        panel.hidesOnDeactivate = false    // 常駐アプリは普段非アクティブなので必須
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 上段(色面)を掴んで動かせる。動かした位置を覚える
        panel.isMovableByWindowBackground = true
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                                              object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.programmaticMove, let frame = self.panel?.frame else { return }
                self.movedTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
            }
        }
        panel.contentView = NSHostingView(rootView: PosturePromptView(coordinator: coordinator))
        return panel
    }
}

/// ボタンを押せるように key にはなれるが、アプリはアクティブにしない
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 小窓の中身

/// デスクトップの上に浮く小窓(v10):ガラスの枠の中に切り紙の札が 2 枚。
/// 上の札は関卡色:人の図 + 英語の喊声 + 一句の問い(STAND UP / SIT DOWN は橙、STANDING は青)。
/// 下の札は黒:ストレッチの姿勢の図 + 秒・回の数字の札 + 一行の動作 + 手順の点 + 指令。文字は減らして図で語る。上の札を掴んで動かせる
struct PosturePromptView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var level: Level {
        switch coordinator.posturePrompt {
        case .askStand: return Level.urgent(night: Theme.isNight())
        case .standing: return Level.today(night: Theme.isNight())
        case .askSit: return Level.urgent(night: Theme.isNight())
        case nil: return .teal
        }
    }

    var body: some View {
        Group {
            switch coordinator.posturePrompt {
            case .askStand: askStand
            case .standing: StandingGuide(coordinator: coordinator)
            case .askSit: askSit
            case nil: EmptyView()
            }
        }
        .frame(width: 348)
        .environment(\.level, level)
        .padding(12)
        // iOS 27:枠だけガラス。文字はガラスの上に置かない
        .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(12)   // 影の分
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    private var askStand: some View {
        let stretch = coordinator.promptStretch
        return HemLayout {
            Pictogram("figure.stand", size: 56)
            VStack(alignment: .leading, spacing: 8) {
                PlateLabel(text: "STAND UP", dark: true)
                Text("站起来了吗？")
                    .font(Theme.font(22, .semibold))
            }
        } bottom: {
            StepPanel(symbol: BreakReminder.symbol(for: stretch)) {
                HStack(spacing: 6) {
                    MetaPlate(symbol: "table.furniture", text: "90°")
                        .help("把桌子升到手肘 90° 的高度")
                    MetaPlate(symbol: "clock", text: "\(sittingMinutes) 分钟")
                        .help("已经坐了 \(sittingMinutes) 分钟")
                }
                Text(stretch.name)
                    .font(Theme.font(15, .semibold))
                    .lineLimit(2)
                    .padding(.top, 8)
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("顺便喝杯水")
                        .font(Theme.font(13, .semibold))
                }
                .foregroundStyle(Theme.textSoft)
                .padding(.top, 8)
            }
            HStack(spacing: 8) {
                Button {
                    coordinator.confirmStood()
                } label: {
                    Label("站起来了", systemImage: "checkmark")
                }
                .buttonStyle(.command(.primary, height: 40, wide: true))
                Button {
                    coordinator.snoozePosture(minutes: 15)
                } label: {
                    Label("15", systemImage: "clock")
                }
                .buttonStyle(.command(.secondary, height: 40))
                .help("15 分钟后再提醒")
            }
            .padding(.top, 14)
        }
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return HemLayout {
            Pictogram("figure.seated.side", size: 56)
            VStack(alignment: .leading, spacing: 8) {
                PlateLabel(text: "SIT DOWN", dark: true)
                Text("坐下了吗？")
                    .font(Theme.font(22, .semibold))
            }
        } bottom: {
            StepPanel(symbol: "figure.seated.side") {
                MetaPlate(symbol: "clock", text: "站了 \(standing) 分钟")
                Text("坐深，双脚踩实")
                    .font(Theme.font(15, .semibold))
                    .padding(.top, 8)
            }
            HStack(spacing: 8) {
                Button {
                    coordinator.confirmSat()
                } label: {
                    Label("坐下了", systemImage: "checkmark")
                }
                .buttonStyle(.command(.primary, height: 40, wide: true))
                Button {
                    coordinator.snoozePosture(minutes: 5)
                } label: {
                    Label("5", systemImage: "clock")
                }
                .buttonStyle(.command(.secondary, height: 40))
                .help("再站 5 分钟")
            }
            .padding(.top, 14)
        }
    }
}

/// 上下 2 枚の札:上は関卡色(図 + 問い)、下は黒(やり方)。上は右上、下は左下をひと口かじる
private struct HemLayout<Top: View, Bottom: View>: View {
    @Environment(\.level) private var level
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 14) { top() }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(level.ink)
                .background(WindowDragArea())   // 上の札を掴むと窓が動く
                .background(BiteShape(corner: .topRight).fill(level.color))
                .environment(\.onLevel, true)
            VStack(alignment: .leading, spacing: 0) { bottom() }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Theme.white)
                .background(BiteShape(corner: .bottomLeft, size: 18).fill(Theme.plate))
                .environment(\.onLevel, false)
        }
    }
}

/// 人の図(SF Symbols)。文字の代わり
private struct Pictogram: View {
    let symbol: String
    var size: CGFloat = 56

    init(_ symbol: String, size: CGFloat = 56) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .frame(width: size + 8, height: size + 8)
            .accessibilityHidden(true)
    }
}

/// やり方の段:左に姿勢の図(96 の札)、右に数字の札と一行
private struct StepPanel<Content: View>: View {
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(Theme.paper)
                .frame(width: 92, height: 92)
                .background(PhantomPlate(skew: 6).fill(Color.white.opacity(0.07)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 数字の札(白い紙に絵文字 + 「5 秒」「× 10」「90°」)
private struct MetaPlate: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(Theme.font(13, .bold).monospacedDigit())
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(PhantomPlate().fill(Theme.paper))
        .fixedSize()
    }
}

/// 手順の点(何番目か)。傾いた短い棒
private struct StepDots: View {
    let count: Int
    let index: Int
    @Environment(\.level) private var level

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                PhantomPlate(skew: 3)
                    .fill(i <= index ? level.color : Color.white.opacity(0.18))
                    .frame(width: 14, height: 6)
            }
        }
        .accessibilityLabel("第 \(index + 1) 步，共 \(count) 步")
    }
}

/// 站立中:上の札に人の図・STANDING・墨迹の残り時間・褶皺の計量条(1 褶 = 1 分)、下の札に拉伸,一次一步(図で)
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.level) private var level

    var body: some View {
        // 秒の数字はシステムの Text(timerInterval:) に任せる(毎秒 body を評価しない)。褶と分は 30 秒ごと
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let total = max(1, coordinator.settings.standMinutes)
            let due = coordinator.postureDueAt
            let remaining = max(0, due.timeIntervalSince(context.date))
            let elapsedMinutes = max(0, min(total, Int((Double(total) * 60 - remaining) / 60)))
            HemLayout {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        Pictogram("figure.stand", size: 44)
                        PlateLabel(text: "STANDING", dark: true)
                        Spacer(minLength: 8)
                        SplatNumber(unit: "剩余", size: 34) {
                            Text(timerInterval: min(context.date, due)...due, countsDown: true, showsHours: false)
                        }
                    }
                    PleatGauge(states: (0..<total).map { $0 < elapsedMinutes ? .meeting : .empty })
                }
            } bottom: {
                stretch
                HStack(spacing: 8) {
                    Spacer()
                    Button("关闭") { coordinator.closePosturePrompt() }
                        .buttonStyle(.command(.quiet, height: 22))
                        .help("关掉后也会继续计时，到点了再提醒你")
                }
                .padding(.top, 6)
            }
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        let meta = done ? BreakReminder.StepMeta() : BreakReminder.StepMeta.parse(s.steps[step])
        return VStack(alignment: .leading, spacing: 0) {
            StepPanel(symbol: done ? "checkmark" : BreakReminder.symbol(for: s)) {
                if done {
                    Text("完成！接下来站着工作吧")
                        .font(Theme.font(15, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("喝杯水")
                            .font(Theme.font(13, .semibold))
                    }
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, 8)
                } else {
                    HStack(spacing: 6) {
                        if let seconds = meta.seconds {
                            MetaPlate(symbol: "clock", text: "\(seconds) 秒")
                        }
                        if let reps = meta.reps {
                            MetaPlate(symbol: "repeat", text: "× \(reps)")
                        }
                        if meta.seconds == nil, meta.reps == nil, let minutes = meta.minutes {
                            MetaPlate(symbol: "clock", text: "\(minutes) 分钟")
                        }
                        PlateLabel(text: "\(step + 1) / \(s.steps.count)", dark: true, tilt: 0)
                    }
                    Text(s.steps[step])
                        .font(Theme.font(15, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                        .padding(.top, 8)
                    StepDots(count: s.steps.count, index: step)
                        .padding(.top, 8)
                }
            }
            if !done {
                Text(BreakReminder.caution)
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, 10)
            }
            HStack(spacing: 8) {
                if step > 0 && !done {
                    Button {
                        coordinator.moveStretchStep(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.commandSquare(.secondary, size: 36))
                    .help("上一步")
                    .accessibilityLabel("上一步")
                }
                if !done {
                    Button {
                        coordinator.moveStretchStep(by: 1)
                    } label: {
                        Label(step == s.steps.count - 1 ? "做完了" : "下一步",
                              systemImage: step == s.steps.count - 1 ? "checkmark" : "chevron.right")
                    }
                    .buttonStyle(.command(.primary, height: 36, wide: true))
                }
            }
            .padding(.top, 12)
        }
    }
}
