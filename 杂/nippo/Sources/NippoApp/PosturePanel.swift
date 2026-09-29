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
        panel.hasShadow = false            // 影は SwiftUI 側で固い影を描く
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

/// デスクトップの上に浮く、透けるガラスのカード。目覚まし時計くん(マスコット)が尋ねる
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
        .padding(20)   // カードの下の影が窓の中に収まるように
        .environment(\.locale, Theme.locale)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    /// マスコット + 大きな問いかけ + 補足
    private func question(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Mascot(size: 64)
                .padding(.leading, -6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(28, .black))
                Text(detail)
                    .font(Theme.font(Theme.Size.body, .bold))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var askStand: some View {
        VStack(alignment: .leading, spacing: 12) {
            question("立ちましたか?", "座って \(sittingMinutes) 分。デスクを肘 90° の高さに")
            VStack(alignment: .leading, spacing: 6) {
                Label("このあと「\(coordinator.promptStretch.name)」", systemImage: "figure.cooldown")
                Label("立つついでに水を一杯", systemImage: "drop.fill")
            }
            .font(Theme.font(Theme.Size.body, .bold))
            HStack(spacing: 10) {
                Button {
                    coordinator.confirmStood()
                } label: {
                    Text("立った!").frame(maxWidth: .infinity)
                }
                .buttonStyle(.rubber(Theme.mustard, height: 44))
                Button("15分後") { coordinator.snoozePosture(minutes: 15) }
                    .buttonStyle(.rubber(Theme.cream, height: 44))
            }
        }
        .card()
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return VStack(alignment: .leading, spacing: 12) {
            question("座りましたか?", "立って \(standing) 分。おつかれさまでした。深く座って足裏を床に")
            HStack(spacing: 10) {
                Button {
                    coordinator.confirmSat()
                } label: {
                    Text("座った").frame(maxWidth: .infinity)
                }
                .buttonStyle(.rubber(Theme.teal, height: 44))
                Button("あと5分") { coordinator.snoozePosture(minutes: 5) }
                    .buttonStyle(.rubber(Theme.cream, height: 44))
            }
        }
        .card()
    }
}

/// 立ち作業中:残り時間のカウントダウン + ストレッチを 1 手順ずつ
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = TimeInterval(coordinator.settings.standMinutes * 60)
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Mascot(size: 52)
                        .padding(.leading, -6)
                    VStack(alignment: .leading, spacing: 0) {
                        Tag(text: "立ち作業 のこり", symbol: "figure.stand", color: Theme.teal)
                        BigNumber(value: Self.clock(remaining), unit: "", size: 44)
                    }
                    Spacer()
                    Button("閉じる") { coordinator.closePosturePrompt() }
                        .buttonStyle(.rubber(Theme.cream, height: 30))
                        .help("閉じてもカウントは続きます。時間になったらまた知らせます")
                }
                RubberProgress(progress: total > 0 ? 1 - remaining / total : 1)
                stretch
            }
            .card()
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(s.name, systemImage: "figure.cooldown")
                    .font(Theme.font(Theme.Size.headline, .heavy))
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(Theme.font(Theme.Size.body, .black).monospacedDigit())
                }
            }
            if done {
                Text("おつかれさま!あとは立ったまま作業を。")
                    .font(Theme.font(Theme.Size.title, .heavy))
                Label("水を一杯", systemImage: "drop.fill")
                    .font(Theme.font(Theme.Size.body, .bold))
            } else {
                Text(s.steps[step])
                    .font(Theme.font(Theme.Size.title, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                Text("※しびれ・痛みが出たら中止")
                    .font(Theme.font(Theme.Size.caption, .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 10) {
                if step > 0 && !done {
                    Button("戻る") { coordinator.moveStretchStep(by: -1) }
                        .buttonStyle(.rubber(Theme.cream, height: 38))
                }
                Spacer()
                if !done {
                    Button(step == s.steps.count - 1 ? "できた!" : "次へ") {
                        coordinator.moveStretchStep(by: 1)
                    }
                    .buttonStyle(.rubber(Theme.mustard, height: 38))
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.ink, lineWidth: 2))
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// ゴムのチューブに赤が満ちていく進捗バー(太い輪郭 + 上のつや)
private struct RubberProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Theme.cream)
                Capsule(style: .continuous).fill(Theme.red)
                    .frame(width: max(18, min(1, progress) * geo.size.width))
                Capsule(style: .continuous).fill(Theme.white.opacity(0.45))
                    .frame(height: 4)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 3)
            }
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink, lineWidth: 2.5))
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}
