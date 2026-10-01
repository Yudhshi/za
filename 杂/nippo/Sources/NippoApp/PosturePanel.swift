import AppKit
import SwiftUI
import NippoCore

/// 画面上部中央に出す、座り/立ちの小窓(混凝土に貼った牛皮纸 + 縁を留める胶带)。胶带を掴んで動かせる(動かした位置は次からも使う)。
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
        // 牛皮纸の接地影は素材の bleed に焼いてある(窓はその分広げてある)。素材が無いときだけシステムの影
        panel.hasShadow = !Self.shadowIsBaked
        panel.hidesOnDeactivate = false    // 常駐アプリは普段非アクティブなので必須
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 胶带を掴んで動かせる。動かした位置を覚える
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

    /// 牛皮纸の素材に bleed(焼いた影・飛沫)があれば、システムの影は重ねない
    private static var shadowIsBaked: Bool {
        guard let b = Material.asset("kraft-sheet-night")?.bleedInsets else { return false }
        return b.top > 0 || b.leading > 0 || b.bottom > 0 || b.trailing > 0
    }
}

/// ボタンを押せるように key にはなれるが、アプリはアクティブにしない
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 小窓の中身

/// 小窓の寸法(pt)。tokens の size.popup* / illustration.sizes と posture-v3 の実寸から
private enum PostureMetrics {
    /// 胶带(tape-handle-night の配置の枠は 26pt)と、紙の上端からはみ出す分
    static let tapeHeight: CGFloat = 26
    static let tapeOverhang: CGFloat = 12
    /// 問いの姿勢(09 / 10 / 11)と、09 の拉伸の小さな姿勢(240pt の母版を縮める)
    static let questionPose: CGFloat = 132
    static let stepPose: CGFloat = 96
    /// 数字の札
    static let chip: CGFloat = 32
    /// 次ボタン(15 分钟后 / 再站 5 分钟 / 结束拉伸)の幅。主ボタンは残り(169)
    static let secondaryWidth: CGFloat = 135
    /// 段の区切り(kraft-score は 8pt の帯)とその上下
    static let ruleHeight: CGFloat = 8
    static let ruleGap: CGFloat = 11
    static let buttonGap: CGFloat = Turf.xxl
    /// 壁画带の札の高さ・幅
    static let friezeLabelHeight: CGFloat = 34
    static let friezeLabelWidth: CGFloat = 104
    /// 牛皮纸の角(素材に焼いてある)と、神兽の残影の位置(紙の上から)
    static let sheetRadius: CGFloat = 10
    static let ghostTop: CGFloat = 84
}

/// デスクトップの上に浮く小窓(v12「Stencil Turf」夜):牛皮纸の台紙 1 枚を混凝土に貼り、上端を胶带で留める。
/// 胶带に STAND UP / STRETCH / SIT DOWN、紙には黒漆の剪影 + 本物の黒い文字 + 青の主ボタン(坐站は青)+ 白漆枠の次ボタン。
/// 09 / 11 は今日の神兽がうっすら残る(彩蛋。名前は出さない)。坐站の通知は「動」の強さ
struct PosturePromptView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            if let prompt = coordinator.posturePrompt {
                sheet(prompt)
            }
        }
        .environment(\.intensity, .event)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    /// 牛皮纸(幅 360)+ 上端の胶带。焼いた影と胶带のはみ出しが窓で切れないように外側を広げる。
    /// 神兽の残影は紙の上・文字の下。素材の指定どおり(台紙の (0, 84)、台紙で切る)にここで置く
    private func sheet(_ prompt: BreakReminder.Prompt) -> some View {
        ZStack(alignment: .top) {
            content(prompt)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Turf.popupPadding)
                .frame(width: Turf.popupWidth)
                .background {
                    if prompt != .standing {
                        PostureGhost(id: Myth.ghostCreature(for: Date()))
                    }
                }
                .kraftSurface()
                .padding(.top, PostureMetrics.tapeOverhang)
            PostureTape(title: Self.tapeTitle(prompt))
        }
        .padding(outerInsets)
    }

    @ViewBuilder
    private func content(_ prompt: BreakReminder.Prompt) -> some View {
        switch prompt {
        case .askStand: askStand
        case .standing: PostureStandingGuide(coordinator: coordinator)
        case .askSit: askSit
        }
    }

    private static func tapeTitle(_ prompt: BreakReminder.Prompt) -> String {
        switch prompt {
        case .askStand: return "STAND UP"
        case .standing: return "STRETCH"
        case .askSit: return "SIT DOWN"
        }
    }

    /// 窓の余白 = 牛皮纸の bleed(焼いた影)。上は胶带のはみ出しと胶带自身の bleed も見る
    private var outerInsets: EdgeInsets {
        let sheet = Material.asset("kraft-sheet-night")?.bleedInsets ?? EdgeInsets()
        let tape = Material.asset("tape-handle-night")?.bleedInsets ?? EdgeInsets()
        return EdgeInsets(top: max(0, sheet.top - PostureMetrics.tapeOverhang, tape.top),
                          leading: sheet.leading, bottom: sheet.bottom, trailing: sheet.trailing)
    }

    private static func minutes(since start: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(start) / 60))
    }

    // MARK: 09 站起来了吗？

    /// 上:立つ人の剪影 + 問い + 座った分。破線の下:今回の拉伸(小さな剪影・名前・90° と分の札)。指令 2 つ
    @ViewBuilder
    private var askStand: some View {
        let stretch = coordinator.promptStretch
        // 分の数字は 30 秒ごとに読み直す
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let sitting = Self.minutes(since: coordinator.postureSince, now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                PostureQuestion(pose: "stand-up", symbol: "figure.stand",
                                title: "站起来\n了吗？", spoken: "站起来了吗？") {
                    PostureMinutesLine(prefix: "已经坐了", minutes: sitting)
                }
                PostureRule()
                    .padding(.vertical, PostureMetrics.ruleGap)
                HStack(alignment: .center, spacing: 20) {
                    PosturePose(name: BreakReminder.illustration(for: stretch),
                                height: PostureMetrics.stepPose, symbol: "figure.cooldown")
                    VStack(alignment: .leading, spacing: 10) {
                        Text(PostureCopy.displayName(stretch.name))
                            .font(Typeface.cjk(18, weight: .black))
                            .foregroundStyle(Palette.kraftText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            PostureChip(asset: "plate-black-night", fallback: Palette.black) {
                                Text("90°")
                                    .font(Typeface.archivo(17, weight: 900, width: 108))
                                    .foregroundStyle(Palette.white)
                            }
                            .help("把桌子升到手肘 90° 的高度")
                            PostureChip(asset: "tag-orange-night", fallback: Palette.orange) {
                                PostureCount(number: sitting, unit: "分钟", color: Palette.black)
                            }
                            .help("已经坐了 \(sitting) 分钟")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button {
                        coordinator.confirmStood()
                    } label: {
                        Text("站起来了")
                    }
                    .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, wide: true))
                    Button {
                        coordinator.snoozePosture(minutes: 15)
                    } label: {
                        Text("15 分钟后")
                    }
                    .buttonStyle(FrameButtonStyle(height: Turf.popupButton, wide: true, onKraft: true))
                    .frame(width: PostureMetrics.secondaryWidth)
                    .help("15 分钟后再提醒")
                }
                .padding(.top, PostureMetrics.buttonGap)
            }
        }
    }

    // MARK: 11 坐下了吗？

    /// 上:座る人の剪影 + 問い + 立った分。破線の下:已站(黒漆)と目標(橙)の札。指令 2 つ
    @ViewBuilder
    private var askSit: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = Self.minutes(since: coordinator.postureSince, now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                PostureQuestion(pose: "sit-down", symbol: "figure.seated.side",
                                title: "坐下了\n吗？", spoken: "坐下了吗？") {
                    PostureMinutesLine(prefix: "已经站了", minutes: standing)
                }
                PostureRule()
                    .padding(.vertical, PostureMetrics.ruleGap)
                HStack(spacing: 10) {
                    PostureChip(asset: "plate-black-night", fallback: Palette.black) {
                        PostureCount(prefix: "已站", number: standing, unit: "分钟", color: Palette.white)
                    }
                    PostureChip(asset: "tag-orange-night", fallback: Palette.orange) {
                        PostureCount(prefix: "目标", number: coordinator.settings.standMinutes, unit: "分钟",
                                     color: Palette.black)
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        coordinator.confirmSat()
                    } label: {
                        Text("坐下了")
                    }
                    .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, wide: true))
                    Button {
                        coordinator.snoozePosture(minutes: 5)
                    } label: {
                        Text("再站 5 分钟")
                    }
                    .buttonStyle(FrameButtonStyle(height: Turf.popupButton, wide: true, onKraft: true))
                    .frame(width: PostureMetrics.secondaryWidth)
                    .help("再站 5 分钟")
                }
                .padding(.top, PostureMetrics.buttonGap)
            }
        }
    }
}

// MARK: - 10 站立中(拉伸の手順)

/// 站立中:上に「站立中」+ 模板字の残り時間 + 手順の点、姿勢の大きな剪影と今の手順。
/// 手順がどれも壁画带の素材のある姿勢(夹肩胛骨・转肩・收下巴)なら、破線の下に古埃及の壁画带(同じ地平線に 2〜3 人)。
/// それ以外は大きな剪影だけ。指令:下一步(青)/ 结束拉伸(白漆枠)
private struct PostureStandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let stretch = coordinator.promptStretch
        let count = stretch.steps.count
        let step = min(max(0, coordinator.stretchStep), count)
        let done = step >= count
        let steps = PostureCopy.steps(of: stretch)
        let distinct = Set(steps.map(\.pose)).count > 1
        // 同じ人が並ぶだけになるので、手順ごとに姿勢が全部違うときだけ壁画带にする
        let showsFrieze = (2...3).contains(steps.count)
            && Set(steps.map(\.pose)).count == steps.count
            && steps.allSatisfy { PostureCopy.friezeNames[$0.pose] != nil && Material.has("frieze-\($0.pose)-current") }
        VStack(alignment: .leading, spacing: 0) {
            header(count: count, step: step)
            HStack(alignment: .center, spacing: 14) {
                PosturePose(name: done ? "walk" : steps[step].pose,
                            height: PostureMetrics.questionPose, symbol: "figure.cooldown")
                Group {
                    if done {
                        finished
                    } else {
                        instruction(title: heading(of: stretch, pose: steps[step].pose, distinct: distinct),
                                    line: stretch.steps[step], step: step, count: count)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 6)
            if showsFrieze {
                PostureRule()
                    .padding(.top, PostureMetrics.ruleGap)
                    .padding(.bottom, 8)
                PostureFrieze(steps: steps, current: step)
            }
            buttons(step: step, count: count, done: done)
                .padding(.top, PostureMetrics.buttonGap)
        }
    }

    /// 站立中 + 残り時間(timer-black の模板字。秒を刻むのはこの行だけ)+ 手順の点
    private func header(count: Int, step: Int) -> some View {
        let due = coordinator.postureDueAt
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("站立中")
                        .font(Typeface.cjk(15, weight: .black))
                        .foregroundStyle(Palette.kraftText)
                    StencilText(text: PostureCopy.clock(until: due, now: context.date), set: "timer-black",
                                fallbackSize: 40, fallbackColor: Palette.kraftText)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                PostureStepDots(count: count, index: step)
            }
        }
    }

    /// 今の手順の見出し:姿勢が混ざる組み立てなら姿勢の名前(转肩)、それ以外はストレッチの名前(括弧の前)
    private func heading(of stretch: BreakReminder.Stretch, pose: String, distinct: Bool) -> String {
        if distinct, let name = PostureCopy.friezeNames[pose] { return name }
        return PostureCopy.split(stretch.name).title
    }

    /// 第 2 步 / 共 3 步・名前・手順の一行・注意
    private func instruction(title: String, line: String, step: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("第")
                Text("\(step + 1)")
                    .font(Typeface.mono(13, weight: 700))
                    .foregroundStyle(Palette.kraftText)
                Text("步 / 共")
                Text("\(count)")
                    .font(Typeface.mono(13, weight: 700))
                    .foregroundStyle(Palette.kraftText)
                Text("步")
            }
            .font(Typeface.cjk(12.5, weight: .bold))
            .foregroundStyle(Palette.kraftTextSecondary)
            .accessibilityElement(children: .combine)
            if !title.isEmpty {
                Text(title)
                    .font(TypeRole.titleZh)
                    .tracking(30 * 0.02)
                    .foregroundStyle(Palette.kraftText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Text(line)
                .font(Typeface.cjk(14, weight: .bold))
                .foregroundStyle(Palette.kraftText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(BreakReminder.caution)
                .font(Typeface.cjk(12, weight: .medium))
                .foregroundStyle(Palette.kraftTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    /// 手順を全部終えた
    private var finished: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("完成！接下来站着工作吧")
                .font(Typeface.cjk(18, weight: .black))
                .foregroundStyle(Palette.kraftText)
                .fixedSize(horizontal: false, vertical: true)
            Text("喝杯水")
                .font(Typeface.cjk(13, weight: .semibold))
                .foregroundStyle(Palette.kraftTextSecondary)
        }
    }

    /// 上一步(2 歩目から)・下一步 / 做完了・结束拉伸。終えたら「关闭」だけ
    private func buttons(step: Int, count: Int, done: Bool) -> some View {
        HStack(spacing: 12) {
            if done {
                Spacer(minLength: 0)
                closeButton("关闭")
            } else {
                if step > 0 {
                    Button {
                        coordinator.moveStretchStep(by: -1)
                    } label: {
                        StencilIconView(icon: .next, size: 16)
                            .scaleEffect(x: -1, y: 1)
                    }
                    .buttonStyle(FrameButtonStyle(height: Turf.popupButton, onKraft: true))
                    .help("上一步")
                    .accessibilityLabel("上一步")
                }
                Button {
                    coordinator.moveStretchStep(by: 1)
                } label: {
                    Text(step == count - 1 ? "做完了" : "下一步")
                }
                .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, wide: true))
                closeButton("结束拉伸")
            }
        }
    }

    /// 閉じても立ち作業の計時は続く
    private func closeButton(_ title: String) -> some View {
        Button {
            coordinator.closePosturePrompt()
        } label: {
            Text(title)
        }
        .buttonStyle(FrameButtonStyle(height: Turf.popupButton, wide: true, onKraft: true))
        .frame(width: PostureMetrics.secondaryWidth)
        .help("关掉后也会继续计时，到点了再提醒你")
    }
}

/// 手順の点:済み = 黒、今 = 青(黒い縁)、まだ = 黒の輪
private struct PostureStepDots: View {
    let count: Int
    /// count と同じなら全部済み
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                dot(i)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        index < count ? "第 \(index + 1) 步，共 \(count) 步" : "\(count) 步都做完了"
    }

    @ViewBuilder
    private func dot(_ i: Int) -> some View {
        if i < index {
            Circle()
                .fill(Palette.kraftText)
                .frame(width: 12, height: 12)
        } else if i == index {
            Circle()
                .fill(Palette.teal)
                .overlay { Circle().strokeBorder(Palette.kraftText, lineWidth: 1.5) }
                .frame(width: 16, height: 16)
        } else {
            Circle()
                .strokeBorder(Palette.kraftText, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
    }
}

/// 古埃及の壁画带:同じ地平線に手順の人が並ぶ(済み = 淡く + ✓、今 = 漆満ち、まだ = ごく淡い)。下に本物の文字の札。
/// 帯は frieze-ground の配置の枠(316 × 113)で、どの人の精灵も同じ高さ・同じ地平線に焼いてある
private struct PostureFrieze: View {
    let steps: [PostureStepInfo]
    let current: Int

    /// 3 人のときの各人の中心 x(焼いた frieze-* の origin + 幅の半分。316pt の帯で)
    private static let canon: [CGFloat] = [48.25, 159, 273]

    var body: some View {
        let band = Material.asset("frieze-ground")?.layoutSize ?? CGSize(width: 316, height: 113)
        let xs = Self.centres(count: steps.count, width: band.width)
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                ground
                ForEach(steps.indices, id: \.self) { i in
                    MaterialSprite(id: "frieze-\(steps[i].pose)-\(state(i))")
                        .position(x: xs[i], y: band.height / 2)
                }
            }
            .frame(width: band.width, height: band.height)
            ZStack(alignment: .topLeading) {
                ForEach(steps.indices, id: \.self) { i in
                    label(i)
                        .frame(width: PostureMetrics.friezeLabelWidth, height: PostureMetrics.friezeLabelHeight,
                               alignment: .top)
                        .position(x: xs[i], y: PostureMetrics.friezeLabelHeight / 2)
                }
            }
            .frame(width: band.width, height: PostureMetrics.friezeLabelHeight)
        }
        .frame(maxWidth: .infinity)
    }

    /// 3 人は焼いた格子の位置、それ以外は等分
    private static func centres(count: Int, width: CGFloat) -> [CGFloat] {
        if count == canon.count {
            return canon.map { $0 * width / 316 }
        }
        let n = CGFloat(max(count, 1))
        return (0..<count).map { (CGFloat($0) + 0.5) * width / n }
    }

    private func state(_ i: Int) -> String {
        i < current ? "done" : (i == current ? "current" : "future")
    }

    /// 地平線(素材が無ければ帯の下端に黒い細線)
    @ViewBuilder
    private var ground: some View {
        if Material.has("frieze-ground") {
            MaterialSprite(id: "frieze-ground")
        } else {
            Rectangle()
                .fill(Palette.kraftText)
                .frame(height: 1.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)
        }
    }

    /// 名前(今のは太く)+ 回数・秒。札の文字は淡くしない(≥ 4.5:1)
    private func label(_ i: Int) -> some View {
        let step = steps[i]
        let isCurrent = i == current
        let progress: String = i < current ? "完成" : (isCurrent ? "进行中" : "")
        return VStack(spacing: 2) {
            HStack(spacing: 3) {
                if i < current {
                    StencilIconView(icon: .check, size: 12)
                }
                Text(step.name)
                    .font(Typeface.cjk(13, weight: isCurrent ? .black : .bold))
            }
            if let meta = step.meta {
                Text(meta)
                    .font(Typeface.cjk(12, weight: .semibold))
            }
        }
        .lineLimit(1)
        .foregroundStyle(isCurrent ? Palette.kraftText : Palette.kraftTextSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress)
    }
}

// MARK: - 部品

/// 上端の胶带(掴むと窓が動く)。英字は TypeRole.tape、大文字、字間 0.18em、少し傾ける
private struct PostureTape: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(TypeRole.tape)
            .tracking(12 * 0.18)
            .foregroundStyle(Palette.kraftText)
            .lineLimit(1)
            .fixedSize()
            // 字間は最後の字の後ろにも付くので、左にも同じだけ足して真ん中に
            .padding(.leading, 12 * 0.18)
            .rotationEffect(.degrees(-1.2))
            .padding(.horizontal, 20)
            .frame(height: PostureMetrics.tapeHeight)
            .background(WindowDragArea())   // 胶带を掴むと窓が動く
            .background { MaterialSlice(id: "tape-handle-night", fallback: Palette.tape) }
            .accessibilityAddTraits(.isHeader)
    }
}

/// 問いの段:左に姿勢の剪影(132pt)、右に問い(2 行)と一行の補足
private struct PostureQuestion<Detail: View>: View {
    let pose: String
    let symbol: String
    /// 改行入りの問い(読み上げは spoken)
    let title: String
    let spoken: String
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PosturePose(name: pose, height: PostureMetrics.questionPose, symbol: symbol)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(TypeRole.titleZh)
                    .tracking(30 * 0.02)
                    .foregroundStyle(Palette.kraftText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(spoken)
                    .accessibilityAddTraits(.isHeader)
                detail()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 姿勢の剪影(焼いた pose-<name>、240pt の母版を縮める)。素材が無ければ旧い絵(Resources/Stretches)
private struct PosturePose: View {
    let name: String
    let height: CGFloat
    var symbol = "figure.stand"

    var body: some View {
        let id = "pose-\(name)"
        if Material.has(id) {
            MaterialSprite.height(id, height)
        } else {
            Illustration(name: name, size: height, fallback: symbol)
                .foregroundStyle(Palette.kraftText)
        }
    }
}

/// 「已经坐了 47 分钟」:文字は次要色、数字だけ黒の等幅
private struct PostureMinutesLine: View {
    let prefix: String
    let minutes: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(prefix)
            Text("\(minutes)")
                .font(Typeface.mono(14, weight: 700))
                .foregroundStyle(Palette.kraftText)
            Text("分钟")
        }
        .font(Typeface.cjk(13, weight: .semibold))
        .foregroundStyle(Palette.kraftTextSecondary)
        .accessibilityElement(children: .combine)
    }
}

/// 札の中の「已站 32 分钟」(数字は等幅)
private struct PostureCount: View {
    var prefix: String? = nil
    let number: Int
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let prefix {
                Text(prefix)
            }
            Text("\(number)")
                .font(Typeface.mono(16, weight: 700))
            Text(unit)
        }
        .font(Typeface.cjk(13, weight: .bold))
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

/// 遮喷の札(黒漆 plate-black / 橙 tag-orange)。高さ 32
private struct PostureChip<Content: View>: View {
    let asset: String
    let fallback: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: PostureMetrics.chip)
            .background { MaterialSlice(id: asset, fallback: fallback) }
            .fixedSize()
    }
}

/// 段の区切り:牛皮纸の折り目の破線(焼いた kraft-score。無ければ細い破線を描く)
private struct PostureRule: View {
    var body: some View {
        Group {
            if Material.has("kraft-score") {
                MaterialSlice(id: "kraft-score")
            } else {
                PostureRuleLine()
                    .stroke(Palette.kraftRule, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .frame(height: PostureMetrics.ruleHeight)
        .accessibilityHidden(true)
    }
}

/// 神兽の残影(彩蛋):配置の枠 360 × 300 を紙の (0, 84) に置き、紙の形で切る。名前は出さない
private struct PostureGhost: View {
    let id: String

    var body: some View {
        if Material.has(id) {
            Color.clear
                .overlay(alignment: .topLeading) {
                    MaterialSprite(id: id)
                        .offset(y: PostureMetrics.ghostTop)
                }
                .clipShape(RoundedRectangle(cornerRadius: PostureMetrics.sheetRadius, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct PostureRuleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - 文言と手順の読み方

/// 手順 1 つ:姿勢(pose-<name> / frieze-<name>-*)と、壁画带の札の名前・回数
private struct PostureStepInfo {
    let pose: String
    let name: String
    let meta: String?
}

private enum PostureCopy {
    /// 壁画带の素材がある姿勢と、その短い名前
    static let friezeNames: [String: String] = [
        "shoulder-blades": "夹肩胛骨",
        "shoulder-rolls": "转肩",
        "chin-tuck": "收下巴",
    ]

    /// 「夹肩胛骨（约 1 分钟）」→(夹肩胛骨, 1 分钟)。括弧が無ければそのまま
    static func split(_ name: String) -> (title: String, note: String?) {
        guard let open = name.firstIndex(where: { $0 == "（" || $0 == "(" }) else {
            return (name.trimmingCharacters(in: .whitespaces), nil)
        }
        let title = name[..<open].trimmingCharacters(in: .whitespaces)
        var inside = name[name.index(after: open)...]
        if let close = inside.lastIndex(where: { $0 == "）" || $0 == ")" }) {
            inside = inside[..<close]
        }
        var note = inside.trimmingCharacters(in: .whitespaces)
        if note.hasPrefix("约") {
            note = String(note.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return (title.isEmpty ? name : title, note.isEmpty ? nil : note)
    }

    /// 「夹肩胛骨 · 1 分钟」
    static func displayName(_ name: String) -> String {
        let parts = split(name)
        guard let note = parts.note else { return parts.title }
        return "\(parts.title) · \(note)"
    }

    /// 手順ごとの姿勢。基本はストレッチ全体の絵で、手順の文が壁画带の姿勢を名指ししているときだけそれに替える
    /// (「夹肩胛骨 1 分钟 / 转肩 10 次 / 收下巴 10 次」のような 3 歩の組み立てを、1 歩 1 人で並べるため)。
    /// 札の名前は姿勢が混ざるときは姿勢の名前、全部同じなら「第 N 步」
    static func steps(of stretch: BreakReminder.Stretch) -> [PostureStepInfo] {
        let base = BreakReminder.illustration(for: stretch)
        let poses = stretch.steps.map { line -> String in
            let own = BreakReminder.illustration(for: BreakReminder.Stretch(name: line, steps: []))
            return friezeNames[own] != nil ? own : base
        }
        let distinct = Set(poses).count > 1
        var result: [PostureStepInfo] = []
        for (i, line) in stretch.steps.enumerated() {
            let pose = poses[i]
            let named: String? = distinct ? friezeNames[pose] : nil
            result.append(PostureStepInfo(pose: pose, name: named ?? "第 \(i + 1) 步", meta: metaText(line)))
        }
        return result
    }

    /// 手順の文の中の数を札の一行に(5 秒 · 10 次 / 10 次 / 1 分钟)
    static func metaText(_ line: String) -> String? {
        let meta = BreakReminder.StepMeta.parse(line)
        if let s = meta.seconds, let r = meta.reps { return "\(s) 秒 · \(r) 次" }
        if let s = meta.seconds { return "\(s) 秒" }
        if let r = meta.reps { return "\(r) 次" }
        if let m = meta.minutes { return "\(m) 分钟" }
        return nil
    }

    /// 残り時間「12:30」(分は桁を詰める)
    static func clock(until due: Date, now: Date) -> String {
        let seconds = max(0, Int(due.timeIntervalSince(now).rounded(.up)))
        return String(format: "%ld:%02ld", seconds / 60, seconds % 60)
    }
}
