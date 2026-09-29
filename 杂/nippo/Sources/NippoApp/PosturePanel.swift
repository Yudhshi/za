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

/// デスクトップの上に浮く小窓(v4:紙と墨・黄緑のインク)。大きな問いかけと、押すだけの操作
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
        .padding(16)   // 主ボタンの版ずれが窓の中に収まるように
        .environment(\.locale, Theme.locale)
    }

    private var sittingMinutes: Int {
        max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
    }

    /// 英字ラベル + 大きな問いかけ + 補足。右上に黄緑のインク(文字とは重ねない)
    private func question(_ label: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.label())
                .tracking(1.4)
            Text(title)
                .font(Theme.font(32, .black))
                .padding(.trailing, 90)
            Text(detail)
                .font(Theme.font(Theme.Size.body, .semibold))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                InkSplat(seed: 31, lobes: 9, drops: 2, drip: true, depth: 0.3)
                    .fill(Theme.lime)
                    .frame(width: 130, height: 120)
                    .offset(x: 40, y: -40)
                    .allowsHitTesting(false)
            }
            .clipped()
            .block()
    }

    private var askStand: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                question("Stand up", "立ちましたか?", "座って \(sittingMinutes) 分。デスクを肘 90° の高さに")
                VStack(alignment: .leading, spacing: 4) {
                    Text("このあと「\(coordinator.promptStretch.name)」")
                    Text("立つついでに水を一杯")
                }
                .font(Theme.font(Theme.Size.body, .bold))
                HStack(spacing: 8) {
                    Button("立った") { coordinator.confirmStood() }
                        .buttonStyle(.sharp(.primary, height: 44, wide: true))
                    Button("15分後") { coordinator.snoozePosture(minutes: 15) }
                        .buttonStyle(.sharp(.plain, height: 44))
                }
            }
        }
    }

    private var askSit: some View {
        let standing = max(0, Int(Date().timeIntervalSince(coordinator.postureSince) / 60))
        return card {
            VStack(alignment: .leading, spacing: 14) {
                question("Sit down", "座りましたか?", "立って \(standing) 分。おつかれさまでした。深く座って足裏を床に")
                HStack(spacing: 8) {
                    Button("座った") { coordinator.confirmSat() }
                        .buttonStyle(.sharp(.primary, height: 44, wide: true))
                    Button("あと5分") { coordinator.snoozePosture(minutes: 5) }
                        .buttonStyle(.sharp(.plain, height: 44))
                }
            }
        }
    }
}

/// 立ち作業中:残り時間のカウントダウン + ストレッチを 1 手順ずつ
private struct StandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = TimeInterval(coordinator.settings.standMinutes * 60)
            let remaining = max(0, coordinator.postureDueAt.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 0) {
                BlockHeader(en: "Standing", ja: "立ち作業 のこり") {
                    Button("閉じる") { coordinator.closePosturePrompt() }
                        .buttonStyle(.sharp(.plain, height: 24))
                        .help("閉じてもカウントは続きます。時間になったらまた知らせます")
                }
                HStack(spacing: 0) {
                    SplatNumeral(value: Self.clock(remaining), unit: "", size: 56)
                        .padding(.vertical, 14)
                        .frame(width: 150)
                        .frame(maxHeight: .infinity)
                        .background(Theme.black)
                    VStack(alignment: .leading, spacing: 10) {
                        StandProgress(progress: total > 0 ? 1 - remaining / total : 1)
                        Text("肩の力を抜き、肘は 90°")
                            .font(Theme.font(Theme.Size.caption, .bold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.rule).frame(width: Theme.line)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.rule).frame(height: Theme.line)
                }
                stretch
                    .padding(14)
            }
            .block()
        }
    }

    private var stretch: some View {
        let s = coordinator.promptStretch
        let step = coordinator.stretchStep
        let done = step >= s.steps.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s.name)
                    .font(Theme.font(Theme.Size.headline, .heavy))
                Spacer()
                if !s.steps.isEmpty && !done {
                    Text("\(step + 1) / \(s.steps.count)")
                        .font(Theme.numeral(20))
                }
            }
            if done {
                Text("おつかれさま!あとは立ったまま作業を。")
                    .font(Theme.font(Theme.Size.title, .heavy))
                Text("水を一杯")
                    .font(Theme.font(Theme.Size.body, .bold))
            } else {
                Text(s.steps[step])
                    .font(Theme.font(Theme.Size.title, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                Text("※しびれ・痛みが出たら中止")
                    .font(Theme.font(Theme.Size.caption, .bold))
                    .foregroundStyle(Theme.textSoft)
            }
            HStack(spacing: 8) {
                if step > 0 && !done {
                    Button("戻る") { coordinator.moveStretchStep(by: -1) }
                        .buttonStyle(.sharp(.plain, height: 38))
                }
                Spacer()
                if !done {
                    Button(step == s.steps.count - 1 ? "できた" : "次へ") {
                        coordinator.moveStretchStep(by: 1)
                    }
                    .buttonStyle(.sharp(.primary, height: 38))
                }
            }
        }
    }

    /// 「12:34」
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 黄緑が満ちていく進捗バー(細い線の四角)
private struct StandProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.surface
                Theme.lime
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
