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

/// デスクトップの上に浮く小窓(v5 ゲームの UI):黒い札に大きな英字の号令と、押すだけのコマンド
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
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    /// 号令(英字の大見出し)+ 日本語の問いかけ + 補足
    private func call(_ en: String, _ ja: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(en)
                .font(Theme.display(34))
                .foregroundStyle(Theme.lime)
                .padding(.trailing, 90)
            Text(ja)
                .font(Theme.font(24, .black))
                .foregroundStyle(Theme.white)
            Text(detail)
                .font(Theme.font(Theme.Size.body, .semibold))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 黒い札:右上を斜めに落とし、すみれのインクを角に
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                InkSplat(seed: 31, lobes: 9, drops: 2, drip: true, depth: 0.3)
                    .fill(Theme.violet)
                    .frame(width: 150, height: 130)
                    .offset(x: 50, y: -46)
                    .allowsHitTesting(false)
            }
            .background(Theme.stage)
            .clipShape(CutRect(topTrailing: 20, bottomLeading: 14))
    }

    private var askStand: some View {
        panel {
            VStack(alignment: .leading, spacing: 14) {
                call("STAND UP!", "立ちましたか?", "座って \(sittingMinutes) 分。デスクを肘 90° の高さに")
                VStack(alignment: .leading, spacing: 4) {
                    Text("このあと「\(coordinator.promptStretch.name)」")
                    Text("立つついでに水を一杯")
                }
                .font(Theme.font(Theme.Size.body, .bold))
                .foregroundStyle(Theme.white)
                HStack(spacing: 10) {
                    Button("立った") { coordinator.confirmStood() }
                        .buttonStyle(.command(.primary, height: 44, wide: true))
                    Button("15分後") { coordinator.snoozePosture(minutes: 15) }
                        .buttonStyle(.command(.ghost, height: 44))
                }
            }
        }
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return panel {
            VStack(alignment: .leading, spacing: 14) {
                call("SIT DOWN!", "座りましたか?", "立って \(standing) 分。おつかれさまでした。深く座って足裏を床に")
                HStack(spacing: 10) {
                    Button("座った") { coordinator.confirmSat() }
                        .buttonStyle(.command(.primary, height: 44, wide: true))
                    Button("あと5分") { coordinator.snoozePosture(minutes: 5) }
                        .buttonStyle(.command(.ghost, height: 44))
                }
            }
        }
    }
}

/// 立ち作業中:残り時間のタイマー + ゲージ + ストレッチを 1 手順ずつ
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = TimeInterval(coordinator.settings.standMinutes * 60)
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STANDING")
                            .font(Theme.display(24))
                            .foregroundStyle(Theme.lime)
                        HUDGauge(segments: 15, filled: total > 0 ? (1 - remaining / total) * 15 : 15)
                        Text("肩の力を抜き、肘は 90°")
                            .font(Theme.font(Theme.Size.caption, .bold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    Spacer()
                    SplatNumeral(value: Self.clock(remaining), unit: "のこり", size: 50)
                }
                stretch
                HStack {
                    Spacer()
                    Button("閉じる") { coordinator.closePosturePrompt() }
                        .buttonStyle(.command(.ghost, height: 26))
                        .help("閉じてもカウントは続きます。時間になったらまた知らせます")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.stage)
            .clipShape(CutRect(topTrailing: 20, bottomLeading: 14))
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s.name)
                    .font(Theme.font(Theme.Size.headline, .black))
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(Theme.numeral(22))
                        .foregroundStyle(Theme.lime)
                }
            }
            if done {
                Text("CLEAR! あとは立ったまま作業を。")
                    .font(Theme.font(Theme.Size.title, .black))
                    .foregroundStyle(Theme.lime)
                Text("水を一杯")
                    .font(Theme.font(Theme.Size.body, .bold))
            } else {
                Text(s.steps[step])
                    .font(Theme.font(Theme.Size.title, .black))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                Text("※しびれ・痛みが出たら中止")
                    .font(Theme.font(Theme.Size.caption, .bold))
                    .foregroundStyle(Theme.textSoft)
            }
            HStack(spacing: 10) {
                if step > 0 && !done {
                    Button("戻る") { coordinator.moveStretchStep(by: -1) }
                        .buttonStyle(.command(.ghost, height: 38))
                }
                Spacer()
                if !done {
                    Button(step == s.steps.count - 1 ? "できた" : "次へ") {
                        coordinator.moveStretchStep(by: 1)
                    }
                    .buttonStyle(.command(.primary, height: 38))
                }
            }
        }
        .foregroundStyle(Theme.white)
        .padding(14)
        .background(Theme.surface)
        .clipShape(CutRect(topTrailing: 12))
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
