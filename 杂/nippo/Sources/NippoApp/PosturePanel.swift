import AppKit
import SwiftUI
import NippoCore

/// 画面上部中央に出す、座り/立ちの小窓。
/// フォーカスを奪わない(打鍵中のアプリはそのまま)・全スペースとフルスクリーンの上にも出る
@MainActor
final class PosturePanelController {
    private var panel: NSPanel?
    private unowned let coordinator: AppCoordinator

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
        DispatchQueue.main.async {
            // マウスのある画面に出す(外部ディスプレイで作業中に内蔵画面へ出さない)。無ければ主画面
            let mouse = NSEvent.mouseLocation
            let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            guard let host = panel.contentView,
                  let screen = target?.visibleFrame else { return }
            let size = host.fittingSize
            panel.setFrame(NSRect(x: screen.midX - size.width / 2,
                                  y: screen.maxY - size.height - 12,
                                  width: size.width, height: size.height),
                           display: true)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true             // 紙が机から少し浮く程度のシステムの影
        panel.hidesOnDeactivate = false    // 常駐アプリは普段非アクティブなので必須
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PosturePromptView(coordinator: coordinator))
        return panel
    }
}

/// ボタンを押せるように key にはなれるが、アプリはアクティブにしない
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 小窓の中身

/// デスクトップの上に浮く小窓(v8):Liquid Glass の外枠の中に、不透明な関卡カード 1 枚。
/// 三つの状態は三つの色:STAND UP 朱红(黒字)・STANDING 翠绿(黒字)・SIT DOWN 钴蓝(白字)。文字はガラスの上に置かない
struct PosturePromptView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var level: Level {
        switch coordinator.posturePrompt {
        case .askStand: return .vermilion
        case .standing: return .viridian
        case .askSit: return .cobalt
        case nil: return .chrome
        }
    }

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: 26, style: .continuous)
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
        .padding(12)
        .background(Color.black.opacity(0.45), in: frame)
        .glassEffect(.regular, in: frame)
        .padding(12)   // 影の分
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    private var askStand: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(lead: "STAND UP")
            Text("站起来了吗？")
                .font(Theme.font(22, .semibold))
                .padding(.top, 8)
            Text("已经坐了 \(sittingMinutes) 分钟。把桌子升到手肘 90° 的高度")
                .font(Theme.font(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text("接下来做「\(coordinator.promptStretch.name)」，顺便去喝杯水")
                .font(Theme.font(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Button("站好了") { coordinator.confirmStood() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
                Button("15 分钟后") { coordinator.snoozePosture(minutes: 15) }
                    .buttonStyle(.command(.secondary, height: 40))
            }
            .padding(.top, 18)
        }
        .padding(20)
        .hero(seam: false, bleed: false)
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(lead: "SIT DOWN")
            Text("坐下了吗？")
                .font(Theme.font(22, .semibold))
                .padding(.top, 8)
            Text("已经站了 \(standing) 分钟，辛苦了。坐深一点，双脚踩实地面")
                .font(Theme.font(13, .medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 8) {
                Button("坐好了") { coordinator.confirmSat() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
                Button("再站 5 分钟") { coordinator.snoozePosture(minutes: 5) }
                    .buttonStyle(.command(.secondary, height: 40))
            }
            .padding(.top, 18)
        }
        .padding(20)
        .hero(seam: false, bleed: false)
    }
}

/// 站立中:剩余时间(墨の大数字)+ 褶皺の計量条(15 褶 = 15 分)+ 拉伸,一次一步
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.level) private var level

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, coordinator.settings.standMinutes)
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            let elapsedMinutes = max(0, min(total, Int((Double(total) * 60 - remaining) / 60)))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(lead: "STANDING")
                        Text("放松肩膀，手肘 90°")
                            .font(Theme.font(13, .medium))
                            .opacity(0.8)
                            .padding(.top, 6)
                    }
                    Spacer()
                    BigNumber(value: Self.clock(remaining), unit: "剩余", size: 48,
                              color: level.ink, unitColor: level.ink.opacity(0.7))
                }
                PleatGauge(states: (0..<total).map { $0 < elapsedMinutes ? .meeting : .empty })
                    .padding(.top, 12)
                stretch
                    .padding(.top, 14)
                HStack {
                    Spacer()
                    Button("关闭") { coordinator.closePosturePrompt() }
                        .buttonStyle(.command(.quiet, height: 22))
                        .help("关掉后也会继续计时，到点了再提醒你")
                }
                .padding(.top, 10)
            }
            .padding(20)
            .hero(seam: false, bleed: false)
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
                    .opacity(0.75)
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(Theme.font(12, .semibold).monospacedDigit())
                        .opacity(0.75)
                }
            }
            if done {
                Text("完成！接下来站着工作吧")
                    .font(Theme.font(15, .semibold))
                    .padding(.top, 8)
                Text("喝杯水")
                    .font(Theme.font(13, .medium))
                    .opacity(0.8)
                    .padding(.top, 2)
            } else {
                Text(s.steps[step])
                    .font(Theme.font(15, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .padding(.top, 8)
                Text("※ 如有麻木或疼痛请停止")
                    .font(Theme.font(12, .medium))
                    .opacity(0.7)
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
        .background(level.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
