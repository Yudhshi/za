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
            guard let host = panel.contentView,
                  let screen = NSScreen.main?.visibleFrame else { return }
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

/// デスクトップの上に浮く小窓(v6):黒い札に大きな問いかけ(中国語)と、押すだけのボタン
struct PosturePromptView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            switch coordinator.posturePrompt {
            case .askStand: askStand
            case .standing: StandingGuide(coordinator: coordinator)
            case .askSit: askSit
            case nil: EmptyView()
            }
        }
        .frame(width: 380)
        .padding(12)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    /// 黄緑の小見出し + 大きな問いかけ + 補足
    private func question(_ kicker: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(Theme.font(13, .bold))
                .foregroundStyle(Theme.lime)
            Text(title)
                .font(Theme.font(28, .heavy))
                .foregroundStyle(Theme.white)
            Text(detail)
                .font(Theme.font(14, .medium))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stage)
            .clipShape(CutRect(topTrailing: 18, bottomLeading: 12))
    }

    private var askStand: some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                question("该站起来了", "站起来了吗？", "已经坐了 \(sittingMinutes) 分钟。把桌子升到手肘 90° 的高度")
                VStack(alignment: .leading, spacing: 4) {
                    Text("接下来做「\(coordinator.promptStretch.name)」")
                    Text("顺便去喝杯水")
                }
                .font(Theme.font(14, .medium))
                .foregroundStyle(Theme.body)
                HStack(spacing: 10) {
                    Button("站好了") { coordinator.confirmStood() }
                        .buttonStyle(.command(.primary, height: 44, wide: true))
                    Button("15 分钟后") { coordinator.snoozePosture(minutes: 15) }
                        .buttonStyle(.command(.ghost, height: 44))
                }
            }
        }
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return panel {
            VStack(alignment: .leading, spacing: 16) {
                question("可以坐下了", "坐下了吗？", "已经站了 \(standing) 分钟，辛苦了。坐深一点，双脚踩实地面")
                HStack(spacing: 10) {
                    Button("坐好了") { coordinator.confirmSat() }
                        .buttonStyle(.command(.primary, height: 44, wide: true))
                    Button("再站 5 分钟") { coordinator.snoozePosture(minutes: 5) }
                        .buttonStyle(.command(.ghost, height: 44))
                }
            }
        }
    }
}

/// 站立中:剩余时间 + 拉伸,一次一步
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("站立中")
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.lime)
                        Text("放松肩膀，手肘 90°")
                            .font(Theme.font(14, .medium))
                            .foregroundStyle(Theme.textSoft)
                    }
                    Spacer()
                    SplatNumeral(value: Self.clock(remaining), unit: "剩余", size: 52)
                }
                stretch
                HStack {
                    Spacer()
                    Button("关闭") { coordinator.closePosturePrompt() }
                        .buttonStyle(.command(.quiet, height: 22))
                        .help("关掉后也会继续计时，到点了再提醒你")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stage)
            .clipShape(CutRect(topTrailing: 18, bottomLeading: 12))
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name)
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.white)
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(Theme.numeral(22))
                        .foregroundStyle(Theme.lime)
                }
            }
            if done {
                Text("完成！接下来站着工作吧")
                    .font(Theme.font(20, .bold))
                    .foregroundStyle(Theme.lime)
                Text("喝杯水")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.body)
            } else {
                Text(s.steps[step])
                    .font(Theme.font(20, .bold))
                    .foregroundStyle(Theme.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                Text("※ 如有麻木或疼痛请停止")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textSoft)
            }
            HStack(spacing: 10) {
                if step > 0 && !done {
                    Button("上一步") { coordinator.moveStretchStep(by: -1) }
                        .buttonStyle(.command(.ghost, height: 36))
                }
                Spacer()
                if !done {
                    Button(step == s.steps.count - 1 ? "做完了" : "下一步") {
                        coordinator.moveStretchStep(by: 1)
                    }
                    .buttonStyle(.command(.primary, height: 36))
                }
            }
        }
        .padding(14)
        .background(Theme.tile)
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
