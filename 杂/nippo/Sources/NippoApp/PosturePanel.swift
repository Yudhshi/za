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

/// デスクトップの上に浮くガラスのカード。角からネオンのインクがはみ出す
struct PosturePromptView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var accent: Color {
        switch coordinator.posturePrompt {
        case .askStand: return Theme.lime
        case .standing: return Theme.cyan
        default: return Theme.pink
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
        .frame(width: 380)
        .background(alignment: .topLeading) {
            InkSplat(seed: 51, lobes: 9, drops: 5, drip: false)
                .fill(accent)
                .frame(width: 120, height: 120)
                .offset(x: -34, y: -34)
        }
        .background(alignment: .bottomTrailing) {
            InkSplat(seed: 57, lobes: 8, drops: 4, drip: true)
                .fill(Theme.purple)
                .frame(width: 100, height: 100)
                .offset(x: 30, y: 34)
        }
        .padding(36)   // はみ出したインクが窓の中に収まるように
        .environment(\.locale, Theme.locale)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    private var askStand: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "figure.stand", color: Theme.lime,
                       title: "立ち作業へ:デスクを肘 90° の高さに",
                       subtitle: "座って \(sittingMinutes) 分", seed: 61)
            Text("立ちましたか?")
                .font(.system(size: 30, weight: .black))
            VStack(alignment: .leading, spacing: 6) {
                Label("このあと「\(coordinator.promptStretch.name)」", systemImage: "figure.cooldown")
                Label("立つついでに水を一杯", systemImage: "drop.fill")
            }
            .font(.system(size: Theme.Size.subhead, weight: .bold))
            HStack(spacing: 10) {
                Button {
                    coordinator.confirmStood()
                } label: {
                    Text("立った!").frame(maxWidth: .infinity)
                }
                .buttonStyle(.splat(Theme.lime, minHeight: 46))
                Button("15分後") { coordinator.snoozePosture(minutes: 15) }
                    .buttonStyle(.splat(Theme.white, minHeight: 46))
            }
        }
        .glassCard()
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "chair.fill", color: Theme.pink,
                       title: "座り作業へ:深く座って足裏を床に",
                       subtitle: "立って \(standing) 分。おつかれさまでした", seed: 67)
            Text("座りましたか?")
                .font(.system(size: 30, weight: .black))
            HStack(spacing: 10) {
                Button {
                    coordinator.confirmSat()
                } label: {
                    Text("座った").frame(maxWidth: .infinity)
                }
                .buttonStyle(.splat(Theme.pink, minHeight: 46))
                Button("あと5分") { coordinator.snoozePosture(minutes: 5) }
                    .buttonStyle(.splat(Theme.white, minHeight: 46))
            }
        }
        .glassCard()
    }
}

/// 立ち作業中:残り時間のカウントダウン + ストレッチを 1 手順ずつ
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = TimeInterval(coordinator.settings.standMinutes * 60)
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    SplatBadge(text: "立ち作業 のこり", color: Theme.cyan, seed: 71, angle: -4)
                    Spacer()
                    Button("閉じる") { coordinator.closePosturePrompt() }
                        .buttonStyle(.splat(Theme.white, minHeight: 32))
                        .help("閉じてもカウントは続きます。時間になったらまた知らせます")
                }
                SplatNumber(value: Self.clock(remaining), unit: "", color: Theme.yellow,
                            size: 54, seed: 73)
                    .padding(.leading, 6)
                InkProgress(progress: total > 0 ? 1 - remaining / total : 1)
                stretch
            }
            .glassCard()
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(s.name, systemImage: "figure.cooldown")
                    .font(.system(size: Theme.Size.headline, weight: .heavy))
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(.system(size: Theme.Size.subhead, weight: .black).monospacedDigit())
                }
            }
            if done {
                Text("おつかれさま!あとは立ったまま作業を。")
                    .font(.system(size: Theme.Size.title, weight: .heavy))
                Label("水を一杯", systemImage: "drop.fill")
                    .font(.system(size: Theme.Size.subhead, weight: .bold))
            } else {
                Text(s.steps[step])
                    .font(.system(size: Theme.Size.title, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                Text("※しびれ・痛みが出たら中止")
                    .font(.system(size: Theme.Size.subhead, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 10) {
                if step > 0 && !done {
                    Button("戻る") { coordinator.moveStretchStep(by: -1) }
                        .buttonStyle(.splat(Theme.white, minHeight: 40))
                }
                Spacer()
                if !done {
                    Button(step == s.steps.count - 1 ? "できた!" : "次へ") {
                        coordinator.moveStretchStep(by: 1)
                    }
                    .buttonStyle(.splat(Theme.lime, minHeight: 40))
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(Theme.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.ink, lineWidth: 2.5))
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// インクが満ちていく進捗バー(太い輪郭)
private struct InkProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .circular).fill(Theme.white)
                Capsule(style: .circular).fill(Theme.pink)
                    .frame(width: max(18, min(1, progress) * geo.size.width))
            }
            .overlay(Capsule(style: .circular).strokeBorder(Theme.ink, lineWidth: 2.5))
        }
        .frame(height: 18)
    }
}
