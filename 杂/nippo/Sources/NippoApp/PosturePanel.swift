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

/// デスクトップの上に浮く小窓(v7):角丸の黒いカードに問いかけ(中国語)と、押すだけのボタン
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
        .frame(width: 360)
        .padding(12)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    /// ラベル + 問いかけ + 補足
    private func question(_ kicker: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(lead: kicker)
            Text(title)
                .font(Theme.font(22, .semibold))
                .foregroundStyle(Theme.white)
                .padding(.top, 6)
            Text(detail)
                .font(Theme.font(13, .regular))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var askStand: some View {
        VStack(alignment: .leading, spacing: 0) {
            question("STAND UP", "站起来了吗？", "已经坐了 \(sittingMinutes) 分钟。把桌子升到手肘 90° 的高度")
            Text("接下来做「\(coordinator.promptStretch.name)」，顺便去喝杯水")
                .font(Theme.font(13, .regular))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            HStack(spacing: 8) {
                Button("站好了") { coordinator.confirmStood() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
                Button("15 分钟后") { coordinator.snoozePosture(minutes: 15) }
                    .buttonStyle(.command(.secondary, height: 40))
            }
            .padding(.top, 18)
        }
        .promptCard()
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return VStack(alignment: .leading, spacing: 0) {
            question("SIT DOWN", "坐下了吗？", "已经站了 \(standing) 分钟，辛苦了。坐深一点，双脚踩实地面")
            HStack(spacing: 8) {
                Button("坐好了") { coordinator.confirmSat() }
                    .buttonStyle(.command(.primary, height: 40, wide: true))
                Button("再站 5 分钟") { coordinator.snoozePosture(minutes: 5) }
                    .buttonStyle(.command(.secondary, height: 40))
            }
            .padding(.top, 18)
        }
        .promptCard()
    }
}

private extension View {
    /// 小窓の面(黒・角丸・細い縁で壁紙から離す)
    func promptCard() -> some View {
        self.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stage, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// 站立中:剩余时间 + 拉伸,一次一步
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(lead: "STANDING")
                        Text("放松肩膀，手肘 90°")
                            .font(Theme.font(13, .regular))
                            .foregroundStyle(Theme.textSoft)
                            .padding(.top, 6)
                    }
                    Spacer()
                    BigNumber(value: Self.clock(remaining), unit: "剩余", size: 48)
                }
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
            .promptCard()
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
                    .foregroundStyle(Theme.textFaint)
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
                    .foregroundStyle(Theme.lime)
                    .padding(.top, 8)
                Text("喝杯水")
                    .font(Theme.font(13, .regular))
                    .foregroundStyle(Theme.body)
                    .padding(.top, 2)
            } else {
                Text(s.steps[step])
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .padding(.top, 8)
                Text("※ 如有麻木或疼痛请停止")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textFaint)
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
