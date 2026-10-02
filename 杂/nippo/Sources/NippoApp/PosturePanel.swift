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
        guard let prompt = coordinator.posturePrompt else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // 牛皮纸の接地影は素材の bleed に焼いてある(窓はその分広げてある)。いま敷く台紙の素材が無いときだけシステムの影
        panel.hasShadow = !Self.shadowIsBaked(
            tall: PosturePromptView.usesTallSheet(prompt, stretch: coordinator.promptStretch,
                                                  breathing: coordinator.breathStartedAt != nil))
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
        // 牛皮纸の接地影は素材の bleed に焼いてある(窓はその分広げてある)。素材が無いときだけシステムの影(update で台紙ごとに決め直す)
        panel.hasShadow = !Self.shadowIsBaked(tall: false)
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

    /// いま敷く牛皮纸の素材(縦長の台紙 / ふつうの台紙)に bleed(焼いた影・飛沫)があれば、システムの影は重ねない
    private static func shadowIsBaked(tall: Bool) -> Bool {
        let id = PostureMetrics.sheetAsset(tall: tall)
        guard Baked.has(id), let b = Baked.asset(id)?.bleedInsets else { return false }
        return b.top > 0 || b.leading > 0 || b.bottom > 0 || b.trailing > 0
    }
}

/// ボタンを押せるように key にはなれるが、アプリはアクティブにしない
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 小窓の中身

/// 小窓の寸法(pt)。tokens の size.popup* と posture-v3 の実寸から
private enum PostureMetrics {
    /// 胶带(tape-handle-night の配置の枠は 26pt)と、紙の上端からはみ出す分
    static let tapeHeight: CGFloat = 26
    static let tapeOverhang: CGFloat = 12
    /// 問いの姿勢(09 / 11、10 の今の手順。pose-<name> はこの大きさで焼く)と、09 の拉伸の小さな姿勢(pose-<name>-s)
    static let questionPose: CGFloat = 132
    static let stepPose: CGFloat = 96
    /// 数字の札(chip-black-kraft / tag-orange-kraft は 100 × 32 で焼いてある)
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

    /// 敷く台紙の素材(KraftSurface と同じ選び方):壁画带まで並ぶ站立中は 360×500 に焼いた縦長の台紙
    /// (無ければふつうの台紙)、ほかは 360×400 の台紙。窓の余白(bleed)と影はこの素材で測る
    @MainActor
    static func sheetAsset(tall: Bool) -> String {
        guard tall else { return "kraft-sheet-night" }
        return Baked.first(["kraft-sheet-tall-night", "kraft-sheet-night"]) ?? "kraft-sheet-night"
    }
}

/// デスクトップの上に浮く小窓(v12.1「Stencil Turf」夜):牛皮纸の台紙 1 枚を混凝土に貼り、上端を皱纹纸胶带で留める。
/// 胶带に STAND UP / STRETCH / SIT DOWN、紙には黒漆の剪影 + 本物の黒い文字 + 焼いた数字の札 + 青の主ボタン + 白漆枠の次ボタン。
/// 区切りは紙の折り目(kraft-score)、手順の点は模板の点(StepDots)。09 / 11 は今日の神兽がうっすら残る(彩蛋。名前は出さない)
struct PosturePromptView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            if let prompt = coordinator.posturePrompt {
                sheet(prompt)
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
    }

    /// 牛皮纸(幅 360)+ 上端の胶带。焼いた影と胶带のはみ出しが窓で切れないように外側を広げる。
    /// 壁画带まで並ぶ站立中だけ縦長の台紙(360×500。ふつうの 400pt の台紙を縦に伸ばさない)。
    /// 神兽の残影は紙の上・文字の下。素材の指定どおり(台紙の (0, 84)、台紙で切る)にここで置く(09 / 11 のふつうの台紙だけ)
    private func sheet(_ prompt: BreakReminder.Prompt) -> some View {
        let tall = Self.usesTallSheet(prompt, stretch: coordinator.promptStretch,
                                      breathing: coordinator.breathStartedAt != nil)
        return ZStack(alignment: .top) {
            content(prompt)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Turf.popupPadding)
                .frame(width: Turf.popupWidth)
                .background {
                    if prompt != .standing {
                        PostureGhost(id: Myth.ghostCreature(for: Date()))
                    }
                }
                .kraftSurface(tall: tall)
                .padding(.top, PostureMetrics.tapeOverhang)
            PostureTape(title: Self.tapeTitle(prompt))
        }
        .padding(Self.outerInsets(tall: tall))
    }

    /// 縦長の台紙にするか:站立中で、手順が壁画带になるとき(PostureStandingGuide と同じ判定)。
    /// 立ってすぐの腹式呼吸のあいだは壁画带を出さないので、ふつうの台紙
    @MainActor
    static func usesTallSheet(_ prompt: BreakReminder.Prompt, stretch: BreakReminder.Stretch,
                              breathing: Bool = false) -> Bool {
        prompt == .standing && !breathing && PostureStandingGuide.showsFrieze(StretchGuide.steps(of: stretch))
    }

    @ViewBuilder
    private func content(_ prompt: BreakReminder.Prompt) -> some View {
        switch prompt {
        case .askStand: askStand
        case .standing: PostureStandingGuide(coordinator: coordinator)
        case .askSit: askSit
        case .standForMeeting: askStandForMeeting
        }
    }

    private static func tapeTitle(_ prompt: BreakReminder.Prompt) -> String {
        switch prompt {
        case .askStand: return "STAND UP"
        case .standing: return "STRETCH"
        case .askSit: return "SIT DOWN"
        case .standForMeeting: return "MEETING"
        }
    }

    /// 窓の余白 = いま敷く牛皮纸の素材の bleed(焼いた影。縦長の台紙なら縦長の台紙の bleed)。
    /// 上は胶带のはみ出しと胶带自身の bleed も見る
    @MainActor
    private static func outerInsets(tall: Bool) -> EdgeInsets {
        let sheet = Baked.asset(PostureMetrics.sheetAsset(tall: tall))?.bleedInsets ?? EdgeInsets()
        let tape = Baked.asset("tape-handle-night")?.bleedInsets ?? EdgeInsets()
        return EdgeInsets(top: max(0, sheet.top - PostureMetrics.tapeOverhang, tape.top),
                          leading: sheet.leading, bottom: sheet.bottom, trailing: sheet.trailing)
    }

    private static func minutes(since start: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(start) / 60))
    }

    // MARK: 09 站起来了吗？

    /// 上:立つ人の剪影 + 問い + 座った分(ここ全体が持ち手)。折り目の下:今回の拉伸(小さな剪影・名前・90° と分の札・
    /// 顺便喝杯水)。指令 2 つ
    @ViewBuilder
    private var askStand: some View {
        let stretch = coordinator.promptStretch
        // 分の数字は 30 秒ごとに読み直す
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let sitting = Self.minutes(since: coordinator.postureSince, now: context.date)
            let name = StretchGuide.displayName(stretch.name)
            VStack(alignment: .leading, spacing: 0) {
                PostureQuestion(pose: "stand-up", symbol: "figure.stand",
                                title: "站起来\n了吗？", spoken: "站起来了吗？") {
                    PostureMinutesLine(prefix: coordinator.promptAfterMeeting ? "开完会，已坐" : "已经坐了",
                                       minutes: sitting)
                }
                PostureRule()
                    .padding(.vertical, PostureMetrics.ruleGap)
                HStack(alignment: .center, spacing: 20) {
                    PosturePose(name: BreakReminder.illustration(for: stretch), height: PostureMetrics.stepPose,
                                small: true, symbol: "figure.cooldown")
                    VStack(alignment: .leading, spacing: 10) {
                        Text(name)
                            .font(Typeface.mixed(18, weight: 900, japanese: Typeface.isJapanese(name)))
                            .typesetting(for: name)
                            .foregroundStyle(Palette.kraftText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            PostureChip(asset: "chip-black-kraft", fallback: Palette.black) {
                                PostureNumbers(text: "90°", color: Palette.white)
                            }
                            .help("把桌子升到手肘 90° 的高度")
                            PostureChip(asset: "tag-orange-kraft", fallback: Palette.orange) {
                                PostureNumbers(text: "\(sitting) 分钟", color: Palette.black)
                            }
                            .help("已经坐了 \(sitting) 分钟")
                        }
                        Text("顺便喝杯水")
                            .font(Typeface.cjk(13, weight: .semibold))
                            .foregroundStyle(Palette.kraftTextSecondary)
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

    // MARK: 会前 站着开会？

    /// 会議の 10 分前から(座って 10 分以上のとき):立つ人の剪影 + 「站着开会？」+ 何時から何分。
    /// 折り目の下:会議名・90° と已坐の札・水(長い会議は「倒杯水带进去」)。指令 2 つ(站着开 / 坐着开)。会議が始まれば自然に閉じる
    @ViewBuilder
    private var askStandForMeeting: some View {
        let meeting = coordinator.meetingAsk
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let sitting = Self.minutes(since: coordinator.postureSince, now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                PostureQuestion(pose: "stand-up", symbol: "figure.stand",
                                title: "站着\n开会？", spoken: "站着开会？") {
                    // 数字は等幅(ほかの小窓の分数と同じ)
                    PostureNumbers(text: meeting.map { Self.meetingLine($0) } ?? "会议马上开始",
                                   color: Palette.kraftTextSecondary,
                                   digits: Typeface.mono(14, weight: 700),
                                   words: Typeface.cjk(13, weight: .semibold))
                }
                PostureRule()
                    .padding(.vertical, PostureMetrics.ruleGap)
                VStack(alignment: .leading, spacing: 10) {
                    if let title = meeting?.title {
                        Text(title)
                            .font(Typeface.mixed(18, weight: 900, japanese: Typeface.isJapanese(title)))
                            .typesetting(for: title)
                            .foregroundStyle(Palette.kraftText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        PostureChip(asset: "chip-black-kraft", fallback: Palette.black) {
                            PostureNumbers(text: "90°", color: Palette.white)
                        }
                        .help("把桌子升到手肘 90° 的高度")
                        PostureChip(asset: "tag-orange-kraft", fallback: Palette.orange) {
                            PostureNumbers(text: "已坐 \(sitting) 分钟", color: Palette.black)
                        }
                        .help("已经坐了 \(sitting) 分钟")
                    }
                    // 45 分以上の会議は水を持って入る(会議の通知と同じ決まり)
                    Text(meeting.map { BreakReminder.isLong($0) } == true ? "会比较长，倒杯水带进去" : "顺便喝杯水")
                        .font(Typeface.cjk(13, weight: .semibold))
                        .foregroundStyle(Palette.kraftTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    Button {
                        coordinator.standForMeeting()
                    } label: {
                        Text("站着开")
                    }
                    .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, wide: true))
                    Button {
                        coordinator.sitForMeeting()
                    } label: {
                        Text("坐着开")
                    }
                    .buttonStyle(FrameButtonStyle(height: Turf.popupButton, wide: true, onKraft: true))
                    .frame(width: PostureMetrics.secondaryWidth)
                    .help("这个会坐着开，开完再提醒站起来")
                }
                .padding(.top, PostureMetrics.buttonGap)
            }
        }
    }

    /// 「10:30 开始 · 60 分钟」
    private static func meetingLine(_ meeting: MeetingEvent) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        let minutes = max(1, Int((meeting.end.timeIntervalSince(meeting.start) / 60).rounded()))
        return "\(f.string(from: meeting.start)) 开始 · \(minutes) 分钟"
    }

    // MARK: 11 坐下了吗？

    /// 上:座る人の剪影 + 問い + 立った分(ここ全体が持ち手)。折り目の下:已站(黒漆)と目標(橙)の札 + 坐深，双脚踩实。指令 2 つ
    @ViewBuilder
    private var askSit: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = Self.minutes(since: coordinator.postureSince, now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                PostureQuestion(pose: "sit-down", symbol: "figure.seated.side",
                                title: "坐下了\n吗？", spoken: "坐下了吗？") {
                    PostureMinutesLine(prefix: coordinator.promptAfterMeeting ? "开完会，已站" : "已经站了",
                                       minutes: standing)
                }
                PostureRule()
                    .padding(.vertical, PostureMetrics.ruleGap)
                HStack(spacing: 10) {
                    PostureChip(asset: "chip-black-kraft", fallback: Palette.black) {
                        PostureNumbers(text: "已站 \(standing) 分钟", color: Palette.white)
                    }
                    PostureChip(asset: "tag-orange-kraft", fallback: Palette.orange) {
                        PostureNumbers(text: "目标 \(coordinator.settings.standMinutes) 分钟", color: Palette.black)
                    }
                }
                Text("坐深，双脚踩实")
                    .font(Typeface.cjk(13, weight: .semibold))
                    .foregroundStyle(Palette.kraftTextSecondary)
                    .padding(.top, 10)
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

/// 站立中:上に「站立中」+ 模板字の残り時間 +(2 歩目から)‹ 上一步 + 手順の点、姿勢の大きな剪影と今の手順(数字の札つき)。
/// 上の 2 段は持ち手。手順がどれも壁画带の素材のある姿勢(夹肩胛骨・转肩・收下巴 = 既定の「肩颈三步」)なら、
/// 折り目の下に古埃及の壁画带(同じ地平線に 2〜3 人。台紙は縦長)。それ以外は大きな剪影だけ。
/// 指令はいつも 2 つ:下一步 / 做完了(青)・结束拉伸(白漆枠)
private struct PostureStandingGuide: View {
    @ObservedObject var coordinator: AppCoordinator

    /// 同じ人が並ぶだけになるので、手順ごとに姿勢が全部違うときだけ壁画带にする(人の絵が焼いてあれば)。
    /// 小窓の台紙(縦長にするか)もこれで決める
    @MainActor
    static func showsFrieze(_ steps: [StretchGuide.Step]) -> Bool {
        StretchGuide.showsFrieze(steps) && steps.allSatisfy { Baked.has("frieze-\($0.pose)-current") }
    }

    var body: some View {
        let stretch = coordinator.promptStretch
        let steps = StretchGuide.steps(of: stretch)
        let count = steps.count
        let step = min(max(0, coordinator.stretchStep), count)
        let done = step >= count
        let showsFrieze = Self.showsFrieze(steps)
        if let start = coordinator.breathStartedAt {
            // 立ってすぐ:拉伸の前に腹式呼吸を 3 回
            PostureBreath(coordinator: coordinator, start: start)
        } else {
            guide(stretch: stretch, steps: steps, count: count, step: step, done: done, showsFrieze: showsFrieze)
        }
    }

    private func guide(stretch: BreakReminder.Stretch, steps: [StretchGuide.Step], count: Int, step: Int,
                       done: Bool, showsFrieze: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(count: count, step: step, done: done)
            HStack(alignment: .center, spacing: 14) {
                PosturePose(name: done ? "walk" : steps[step].pose,
                            height: PostureMetrics.questionPose, symbol: "figure.cooldown")
                Group {
                    if done {
                        finished
                    } else {
                        instruction(title: StretchGuide.heading(of: stretch, steps: steps, at: step),
                                    step: steps[step], index: step, count: count)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(WindowDragArea())   // 剪影と手順の段も持ち手
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

    /// 站立中 + 残り時間(timer-black の模板字。秒を刻むのはここだけ)+(2 歩目から、終えるまで)‹ 上一步 + 手順の点。
    /// ボタン以外は持ち手(ボタンの下には持ち手を敷かない)。点は 16 / 10pt で数だけ伸びるので幅は決め打ちしない:
    /// 左の塊はつぶさず、残りを点と ‹ 上一步 が先に取る(入らなければ ‹ だけ)。あまりは左の塊の右の空き
    private func header(count: Int, step: Int, done: Bool) -> some View {
        let due = coordinator.postureDueAt
        return HStack(alignment: .center, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("站立中")
                        .font(Typeface.cjk(15, weight: .black))
                        .foregroundStyle(Palette.kraftText)
                    PostureTimer(text: StretchGuide.clock(until: due, now: context.date))
                }
                .accessibilityElement(children: .combine)
            }
            .fixedSize()
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WindowDragArea())
            if step > 0 && !done {
                backButton
                    .layoutPriority(1)
            }
            PostureStepDots(count: count, index: step)
                .background(WindowDragArea())
                .layoutPriority(1)
        }
    }

    /// ‹ 上一步:手順の点の横の小さな文字のボタン(指令の列には入れない)
    private var backButton: some View {
        Button {
            coordinator.moveStretchStep(by: -1)
        } label: {
            ViewThatFits(in: .horizontal) {
                Text("‹ 上一步")
                Text("‹")
            }
            .font(Typeface.mixed(12.5, weight: 700))
            .lineLimit(1)
        }
        .buttonStyle(BareButtonStyle(color: Palette.kraftTextSecondary, hoverColor: Palette.kraftText))
        .help("上一步")
        .accessibilityLabel("上一步")
    }

    /// 第 2 步 / 共 3 步・見出し・数字の札(秒 / 次。壁画带が無くても出す)・手順の一行・注意
    private func instruction(title: String, step: StretchGuide.Step, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("第")
                Text("\(index + 1)")
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
                    .font(Typeface.mixed(30, weight: 900, japanese: Typeface.isJapanese(title)))
                    .tracking(30 * 0.02)
                    .typesetting(for: title)
                    .foregroundStyle(Palette.kraftText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            if let meta = step.meta {
                PostureChip(asset: "chip-black-kraft", fallback: Palette.black) {
                    PostureNumbers(text: meta, color: Palette.white)
                }
                .padding(.top, 10)
            }
            Text(step.text)
                .font(Typeface.mixed(14, weight: 700, japanese: Typeface.isJapanese(step.text)))
                .typesetting(for: step.text)
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

    /// 手順を全部終えた(剪影は走一走)
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

    /// 指令は 2 つ:左 = 青(下一步、最後の手順は 做完了)169 × 50、右 = 白漆枠(结束拉伸)135 × 50。
    /// 終えたら右の「关闭」だけ。上一步 は見出しの行
    private func buttons(step: Int, count: Int, done: Bool) -> some View {
        HStack(spacing: 12) {
            if done {
                // 終えたら「关闭」だけ(前と同じ。左は空けておく)
                Spacer(minLength: 0)
            } else {
                Button {
                    coordinator.moveStretchStep(by: 1)
                } label: {
                    Text(step == count - 1 ? "做完了" : "下一步")
                }
                .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, wide: true))
            }
            closeButton(done ? "关闭" : "结束拉伸")
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

/// 立ってすぐの腹式呼吸 3 回(吸う 4 秒・吐く 6 秒、30 秒)。拉伸の前に毎回挟んで、腹式呼吸を習慣にする。
/// 吸う / 吐くの字 + 模板字の残り秒 + 回数の点。終われば数えて拉伸へ、跳过なら数えない
private struct PostureBreath: View {
    @ObservedObject var coordinator: AppCoordinator
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.25)) { context in
            let state = BreathPacer.state(elapsed: context.date.timeIntervalSince(start))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text("先做 3 次腹式呼吸")
                        .font(Typeface.cjk(15, weight: .black))
                        .foregroundStyle(Palette.kraftText)
                    Spacer(minLength: 8)
                    StepDots(count: BreathPacer.breaths, index: state.breath)
                }
                .background(WindowDragArea())
                HStack(alignment: .center, spacing: 14) {
                    PosturePose(name: "belly-breathing", height: PostureMetrics.questionPose, symbol: "wind")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(state.inhaling ? "吸" : "呼")
                                .font(TypeRole.titleZh)
                                .foregroundStyle(Palette.kraftText)
                            PostureTimer(text: "\(state.remaining)")
                        }
                        Text(state.inhaling ? "用鼻子吸，只让肚子鼓起来" : "用嘴慢慢呼，肚子瘪下去")
                            .font(Typeface.mixed(14, weight: 700))
                            .foregroundStyle(Palette.kraftText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("一只手放在肚子上，胸口和肩膀不动")
                            .font(Typeface.cjk(12, weight: .medium))
                            .foregroundStyle(Palette.kraftTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(WindowDragArea())
                .padding(.top, 6)
                HStack(spacing: 12) {
                    Text("今天第 \(coordinator.breathToday + 1) 次")
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.kraftTextSecondary)
                    Spacer(minLength: 0)
                    Button("跳过") { coordinator.finishBreath(counted: false) }
                        .buttonStyle(BareButtonStyle(color: Palette.kraftTextSecondary, hoverColor: Palette.kraftText))
                        .font(Typeface.mixed(12.5, weight: 700))
                }
                .padding(.top, PostureMetrics.buttonGap)
            }
            .onChange(of: state.finished, initial: true) { _, finished in
                if finished { coordinator.finishBreath(counted: true) }
            }
        }
    }
}

/// 残り時間の模板字(timer-black)。数字ごとに送り幅が違うので、いちばん広い数字の幅で枠を取る
/// (毎秒・毎分で枠の幅が変わらず、横の手順の点が揺れない)。図集が無ければ Archivo の等幅数字
struct PostureTimer: View {
    let text: String

    var body: some View {
        StencilText(text: text, set: "timer-black", fallbackSize: 40, fallbackColor: Palette.kraftText)
            .fixedSize()
            .frame(width: Self.reservedWidth(for: text), alignment: .leading)
    }

    /// 数字はどれも最も広い数字の送り幅、ほかの字(:)はその字の送り幅。図集が無い・字が無ければ nil(枠を決めない)
    @MainActor
    private static func reservedWidth(for text: String) -> CGFloat? {
        guard let set = Baked.glyphSet("timer-black") else { return nil }
        let widest = "0123456789".compactMap { set.glyphs[String($0)]?.advance }.max() ?? 0
        var width: CGFloat = 0
        for character in text {
            if character.isNumber {
                width += widest
            } else if let glyph = set.glyphs[String(character)] {
                width += glyph.advance
            } else {
                return nil
            }
        }
        return width
    }
}

/// 手順の点(焼いた模板の点:済み = 黒、今 = 青 + 黒い輪、まだ = 模板の浅い印)。読み上げは「第 N 步，共 M 步」
private struct PostureStepDots: View {
    let count: Int
    /// count と同じなら全部済み
    let index: Int

    var body: some View {
        StepDots(count: count, index: index)
            .accessibilityRepresentation {
                Text(spoken)
            }
    }

    private var spoken: String {
        index < count ? "第 \(index + 1) 步，共 \(count) 步" : "\(count) 步都做完了"
    }
}

/// 古埃及の壁画带:同じ地平線に手順の人が並ぶ(済み = 淡く + ✓、今 = 漆満ち、まだ = ごく淡い)。下に本物の文字の札。
/// 帯は frieze-ground の配置の枠(316 × 113)。人の置き場所は焼いた frieze-* の origin(帯の左上からの pt)
private struct PostureFrieze: View {
    let steps: [StretchGuide.Step]
    let current: Int

    var body: some View {
        let band = Baked.asset("frieze-ground")?.layoutSize ?? CGSize(width: 316, height: 113)
        let centres = Self.centres(of: steps.map(\.pose), band: band)
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                ground
                ForEach(steps.indices, id: \.self) { i in
                    BakedSprite(id: "frieze-\(steps[i].pose)-\(state(i))")
                        .position(centres[i])
                }
            }
            .frame(width: band.width, height: band.height)
            ZStack(alignment: .topLeading) {
                ForEach(steps.indices, id: \.self) { i in
                    label(i)
                        .frame(width: PostureMetrics.friezeLabelWidth, height: PostureMetrics.friezeLabelHeight,
                               alignment: .top)
                        .position(x: centres[i].x, y: PostureMetrics.friezeLabelHeight / 2)
                }
            }
            .frame(width: band.width, height: PostureMetrics.friezeLabelHeight)
        }
        .frame(maxWidth: .infinity)
    }

    /// 人の中心(帯の左上から)。人数が焼いた人数と同じなら、焼いた置き場所を左から順に使う
    /// (既定の「肩颈三步」なら全員が自分の焼いた場所に立つ)。2 人、または origin の無い古い目録なら帯を等分
    @MainActor
    private static func centres(of poses: [String], band: CGSize) -> [CGPoint] {
        let slots = StretchGuide.friezeNames.keys.compactMap { bakedCentre($0) }.sorted { $0.x < $1.x }
        if slots.count == poses.count {
            return slots
        }
        let n = CGFloat(max(poses.count, 1))
        return poses.indices.map { i in
            CGPoint(x: (CGFloat(i) + 0.5) * band.width / n, y: bakedCentre(poses[i])?.y ?? band.height / 2)
        }
    }

    /// 焼いた人の配置の枠の中心 = origin + 大きさの半分(どの状態の絵も同じ枠なので current で測る)
    @MainActor
    private static func bakedCentre(_ pose: String) -> CGPoint? {
        guard let asset = Baked.asset("frieze-\(pose)-current"), let origin = asset.origin, origin.count >= 2 else {
            return nil
        }
        let size = asset.layoutSize
        return CGPoint(x: origin[0] + size.width / 2, y: origin[1] + size.height / 2)
    }

    private func state(_ i: Int) -> String {
        i < current ? "done" : (i == current ? "current" : "future")
    }

    /// 地平線(素材が無ければ帯の下端に黒い細線)
    @ViewBuilder
    private var ground: some View {
        if Baked.has("frieze-ground") {
            BakedSprite(id: "frieze-ground")
        } else {
            Rectangle()
                .fill(Palette.kraftText)
                .frame(height: 1.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)
        }
    }

    /// 名前(今のは太く)+ 回数・秒(数字は等幅)。札の文字は淡くしない(≥ 4.5:1)
    private func label(_ i: Int) -> some View {
        let step = steps[i]
        let isCurrent = i == current
        let progress: String = i < current ? "完成" : (isCurrent ? "进行中" : "")
        let color = isCurrent ? Palette.kraftText : Palette.kraftTextSecondary
        return VStack(spacing: 2) {
            HStack(spacing: 3) {
                if i < current {
                    StencilIconView(icon: .check, size: 12)
                }
                Text(step.name)
                    .font(Typeface.cjk(13, weight: isCurrent ? .black : .bold))
            }
            if let meta = step.meta {
                PostureNumbers(text: meta, color: color, digits: Typeface.mono(12, weight: 700),
                               words: Typeface.cjk(12, weight: .semibold))
            }
        }
        .lineLimit(1)
        .foregroundStyle(color)
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
            .background { BakedSlice(id: "tape-handle-night", fallback: Palette.tape) }
            .accessibilityAddTraits(.isHeader)
    }
}

/// 問いの段:左に姿勢の剪影(132pt)、右に問い(2 行)と一行の補足。段ぜんぶが窓の持ち手(胶带だけでは小さい)
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
        .background(WindowDragArea())
    }
}

/// 姿勢の剪影。表示の大きさで焼いた素材をほぼ 1 倍で置く(pose-<name> = 132pt、small なら pose-<name>-s = 96pt)。
/// 小さい版が無ければ pose-<name> を、古い 240pt の母版しか無ければそれを縮める。素材が無ければ SF Symbols の人形
struct PosturePose: View {
    let name: String
    let height: CGFloat
    var small = false
    var symbol = "figure.stand"

    var body: some View {
        if let id = Self.asset(name, small: small) {
            BakedSprite.height(id, height)
        } else {
            Image(systemName: symbol)
                .font(.system(size: height * 0.55, weight: .regular))
                .frame(width: height, height: height)
                .foregroundStyle(Palette.kraftText)
                .accessibilityHidden(true)
        }
    }

    @MainActor
    private static func asset(_ name: String, small: Bool) -> String? {
        let candidates = small ? ["pose-\(name)-s", "pose-\(name)"] : ["pose-\(name)"]
        return candidates.first { Baked.has($0) }
    }
}

/// 「已经坐了 47 分钟」:文字は次要色、数字だけ黒の等幅
private struct PostureMinutesLine: View {
    let prefix: String
    let minutes: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(prefix)
                .lineLimit(1)
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

/// 数の入った短い札の文(已站 32 分钟 / 5 秒 · 10 次 / 90°)。空白で区切り、数字で始まる語は JetBrains Mono、ほかは中文
private struct PostureNumbers: View {
    let text: String
    let color: Color
    var digits: Font = Typeface.mono(16, weight: 700)
    var words: Font = Typeface.cjk(13, weight: .bold)

    var body: some View {
        let tokens = text.split(separator: " ").map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token)
                    .font(token.first?.isNumber == true ? digits : words)
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// 牛皮纸の上の焼いた札(黒漆 chip-black-kraft / 橙 tag-orange-kraft、どちらも 100 × 32)。高さ 32、幅は中身なり。
/// 焼いた幅の 0.8 倍より狭い札(90° など)は中央を縮めずに敷き詰める(漆の粒が横に潰れない)
private struct PostureChip<Content: View>: View {
    let asset: String
    let fallback: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: PostureMetrics.chip)
            .background {
                GeometryReader { geo in
                    let baked = Baked.asset(asset)?.layoutSize.width ?? 0
                    BakedSlice(id: asset, fallback: fallback, tile: geo.size.width < baked * 0.8)
                }
            }
            .fixedSize()
    }
}

/// 段の区切り:牛皮纸の折り目(焼いた kraft-score を横に伸ばす。無ければ細い線)
private struct PostureRule: View {
    var body: some View {
        Group {
            if Baked.has("kraft-score") {
                BakedSlice(id: "kraft-score")
            } else {
                Rectangle()
                    .fill(Palette.kraftRule)
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PostureMetrics.ruleHeight)
        .accessibilityHidden(true)
    }
}

/// 神兽の残影(彩蛋):配置の枠 360 × 300 を紙の (0, 84) に置き、紙の形で切る。名前は出さない
private struct PostureGhost: View {
    let id: String

    var body: some View {
        if Baked.has(id) {
            Color.clear
                .overlay(alignment: .topLeading) {
                    BakedSprite(id: id)
                        .offset(y: PostureMetrics.ghostTop)
                }
                .clipShape(RoundedRectangle(cornerRadius: PostureMetrics.sheetRadius, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
