import AppKit
import SwiftUI
import NippoCore

/// 画面上部中央に出す、座り/立ちの小窓。掴んで動かせる(動かした位置は次からも使う)。
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

/// デスクトップの上に浮く小窓(v9):ガラスは使わない。上段は関卡色(問いと大数字)、下段は黒い里布(説明とボタン)。
/// STAND UP と SIT DOWN は橙(いま動け)、STANDING は青(順調)。文字はつねに黒。上段を掴んで動かせる
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
        .frame(width: 360)
        .environment(\.level, level)
        .padding(12)   // 影の分
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    private var askStand: some View {
        HemLayout {
            Eyebrow(lead: "STAND UP", text: "已坐 \(sittingMinutes) 分钟")
            Text("站起来了吗？")
                .font(Theme.font(22, .semibold))
                .padding(.top, 8)
        } bottom: {
            Text("把桌子升到手肘 90° 的高度。接下来做「\(coordinator.promptStretch.name)」，顺便去喝杯水")
                .font(Theme.font(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("站起来了") { coordinator.confirmStood() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
                Button("15 分钟后") { coordinator.snoozePosture(minutes: 15) }
                    .buttonStyle(.command(.secondary, height: 40))
            }
            .padding(.top, 14)
        }
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return HemLayout {
            Eyebrow(lead: "SIT DOWN", text: "已站 \(standing) 分钟")
            Text("坐下了吗？")
                .font(Theme.font(22, .semibold))
                .padding(.top, 8)
        } bottom: {
            Text("辛苦了。坐深一点，双脚踩实地面")
                .font(Theme.font(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("坐下了") { coordinator.confirmSat() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
                Button("再站 5 分钟") { coordinator.snoozePosture(minutes: 5) }
                    .buttonStyle(.command(.secondary, height: 40))
            }
            .padding(.top, 14)
        }
    }
}

/// 上下二段の裾:上段は関卡色(看)、下段は里布(做)。まとめて関卡の形に裁つ
private struct HemLayout<Top: View, Bottom: View>: View {
    @Environment(\.level) private var level
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) { top() }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(level.ink)
                .background(WindowDragArea())   // 上段を掴むと窓が動く
                .background(level.color)
                .environment(\.onLevel, true)
            VStack(alignment: .leading, spacing: 0) { bottom() }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Theme.white)
                .background(Theme.lining)
                .environment(\.onLevel, false)
        }
        .clipShape(HeroShape())
    }
}

/// 站立中:上段に剩余时间(墨の大数字)+ 褶皺の計量条(1 褶 = 1 分)、下段に拉伸,一次一步
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(lead: "STANDING")
                        Text("放松肩膀，手肘 90°")
                            .font(Theme.font(13, .medium))
                            .opacity(0.8)
                            .padding(.top, 6)
                    }
                    Spacer()
                    SplatNumber(unit: "剩余", size: 40) {
                        Text(timerInterval: min(context.date, due)...due, countsDown: true, showsHours: false)
                    }
                }
                PleatGauge(states: (0..<total).map { $0 < elapsedMinutes ? .meeting : .empty })
                    .padding(.top, 12)
            } bottom: {
                stretch
                HStack {
                    Spacer()
                    Button("关闭") { coordinator.closePosturePrompt() }
                        .buttonStyle(.command(.quiet, height: 22))
                        .help("关掉后也会继续计时，到点了再提醒你")
                }
                .padding(.top, 8)
            }
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.textSoft)
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(Theme.font(12, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSoft)
                }
            }
            if done {
                Text("完成！接下来站着工作吧")
                    .font(Theme.font(15, .semibold))
                    .padding(.top, 8)
                Text("喝杯水")
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.body)
                    .padding(.top, 2)
            } else {
                Text(s.steps[step])
                    .font(Theme.font(15, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .padding(.top, 8)
                Text(BreakReminder.caution)
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textSoft)
            }
            HStack(spacing: 8) {
                if step > 0 && !done {
                    Button("上一步") { coordinator.moveStretchStep(by: -1) }
                        .buttonStyle(.command(.secondary, height: 32))
                }
                Spacer()
                if !done {
                    Button(step == s.steps.count - 1 ? "做完了" : "下一步") {
                        coordinator.moveStretchStep(by: 1)
                    }
                    .buttonStyle(.command(.primary, height: 32))
                }
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
