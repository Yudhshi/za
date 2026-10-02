import AppKit
import NippoCore
import SwiftUI
import WebKit

// MARK: - 泡澡のあとの日课(跟练の動画 → 立ってやる拉伸 →(隔天)肩袖の力 → 床の拉伸 → 仰向けの腹式呼吸)

/// 日课の窓。「泡完澡了」で毎回最初(動画 1 本目)から。閉じたら動画のプレーヤーごと捨てる(音を残さない・メモリを返す)
@MainActor
final class RitualWindowController: NSObject, NSWindowDelegate {
    private unowned let coordinator: AppCoordinator
    private var window: NSWindow?
    private var session: RitualSession?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let window = self.window, window.isVisible {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let settings = coordinator.settings
        // 隔天は Windows でやった日课も含めて数える
        let strength = settings.ritualStrengthOn
            && Ritual.includesStrength(log: coordinator.habits.ritualStrength, today: Date())
        let session = RitualSession(videos: Ritual.videos(from: settings.ritualVideos),
                                    standing: settings.ritualStretches,
                                    strength: strength ? settings.ritualStrength : nil,
                                    floor: settings.ritualFloor,
                                    voice: false)
        session.onFinish = { [weak self] withStrength in self?.coordinator.recordRitual(strength: withStrength) }
        self.session = session
        let host = NSHostingController(rootView: RitualView(session: session, coordinator: coordinator))
        let window = NSWindow(contentViewController: host)
        window.title = "泡完澡后的日课"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 1040, height: 660))
        window.contentMinSize = NSSize(width: 880, height: 580)
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        session?.stop()
        session = nil
        window?.contentViewController = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// 日课の進み方。動画は自分で「下一个」(動画の終わりは取れないので)、拉伸は 1 歩ずつ自動で次へ(床にいても手を使わない)。
/// 1 歩の始まりは「准备」:声で読むなら読み終えて 1.5 秒、読まないなら 3 秒たってから秒を数え始める(構えるあいだに減らさない)。
/// 秒の無い構えの行は 10 秒。简版に切り替えると、拉伸は简版の 4 つだけ(力量は入れない)
@MainActor
final class RitualSession: ObservableObject {
    struct StretchStep: Equatable {
        /// いまの歩の見出し(StretchGuide.heading)/ 拉伸の名前(「斜角肌拉伸 · 2 分钟」)
        let heading: String
        let name: String
        let step: StretchGuide.Step
        let stepNumber: Int
        let stepCount: Int
        let stretchNumber: Int
        let duration: TimeInterval
    }

    enum Item: Equatable {
        case video(Ritual.Video, number: Int)
        case stretch(StretchStep)
    }

    /// 秒の書いていない構えの行の長さ
    static let setupSeconds: TimeInterval = 10
    /// 読み終えてから数え始めるまで / 読まないときの准备
    static let afterVoice: TimeInterval = 1.5
    static let quietLead: TimeInterval = 3

    private let videos: [Ritual.Video]
    private let standing: String
    private let strength: String?
    private let floor: String
    let voice: Bool
    /// 終えたとき(力量を入れた日か)
    var onFinish: (Bool) -> Void = { _ in }

    @Published private(set) var items: [Item] = []
    @Published private(set) var stretchNames: [String] = []
    @Published private(set) var short = false
    @Published private(set) var index = 0
    /// 読んでいる / 構えている(まだ秒を数えていない)
    @Published private(set) var preparing = false
    /// いまの歩が終わる時刻(数えているあいだだけ)
    @Published private(set) var endsAt: Date?
    /// 止めたときの残り秒
    @Published private(set) var pausedLeft: TimeInterval?
    @Published private(set) var finished = false
    private var timer: Task<Void, Never>?
    private var lead: Task<Void, Never>?
    /// いまの歩の番号札(遅れて届いた「読み終わり」を前の歩に効かせない)
    private var token = 0

    init(videos: [Ritual.Video], standing: String, strength: String?, floor: String, voice: Bool) {
        self.videos = videos
        self.standing = standing
        self.strength = strength
        self.floor = floor
        self.voice = voice
        rebuild()
    }

    var videoTitles: [String] { videos.map(\.title) }
    var videoCount: Int { videos.count }
    var current: Item? { items.indices.contains(index) ? items[index] : nil }
    /// 今日は力量を入れているか(简版では入れない)
    var hasStrength: Bool { strength != nil && !short }

    private func rebuild() {
        let stretches = Ritual.plan(standing: standing, strength: hasStrength ? strength : nil, floor: floor,
                                    short: short)
        var items: [Item] = videos.enumerated().map { Item.video($0.element, number: $0.offset) }
        for (number, stretch) in stretches.enumerated() {
            let steps = StretchGuide.steps(of: stretch)
            for (i, step) in steps.enumerated() {
                let seconds = Ritual.duration(of: stretch.steps[i]) ?? Self.setupSeconds
                items.append(.stretch(StretchStep(
                    heading: StretchGuide.heading(of: stretch, steps: steps, at: i),
                    name: StretchGuide.displayName(stretch.name), step: step,
                    stepNumber: i, stepCount: steps.count, stretchNumber: number, duration: seconds)))
            }
        }
        self.items = items
        stretchNames = stretches.map { StretchGuide.split($0.name).title }
    }

    /// 简版 / 全部 を切り替える。拉伸の途中なら拉伸の最初から
    func setShort(_ value: Bool) {
        guard value != short else { return }
        let inStretches = index >= videoCount
        short = value
        rebuild()
        if inStretches || finished {
            enter(videoCount)
        }
    }

    /// 次の拉伸の歩(画面の右に予告する)
    var upcoming: StretchStep? {
        guard items.indices.contains(index + 1), case .stretch(let next) = items[index + 1] else { return nil }
        return next
    }

    /// その拉伸の最初の歩の番号(一覧から飛ぶ)
    func firstItem(ofStretch number: Int) -> Int? {
        items.firstIndex { item in
            if case .stretch(let s) = item { return s.stretchNumber == number }
            return false
        }
    }

    func start() { enter(0) }
    func next() { enter(index + 1) }
    func previous() { enter(max(0, min(index, items.count) - 1)) }
    func jump(to item: Int) { enter(item) }

    private func cancelTimers() {
        timer?.cancel()
        timer = nil
        lead?.cancel()
        lead = nil
    }

    private func enter(_ item: Int) {
        cancelTimers()
        token += 1
        endsAt = nil
        pausedLeft = nil
        preparing = false
        guard item < items.count else {
            finish()
            return
        }
        index = item
        finished = false
        switch items[item] {
        case .stretch(let s):
            prepare(s)
        case .video:
            Speaker.shared.stop()
        }
    }

    /// 准备:読み上げる(読むなら読み終わり + 1.5 秒、読まないなら 3 秒)→ 数え始める
    private func prepare(_ s: StretchStep) {
        preparing = true
        let mine = token
        let text = s.stepNumber == 0 ? "\(s.heading)。\(s.step.text)" : s.step.text
        if voice {
            Speaker.shared.guide(text) { [weak self] in
                self?.startAfter(Self.afterVoice, token: mine, seconds: s.duration)
            }
            // 声が出ない環境でも止まらないように:1 字 0.35 秒 + 3 秒で始める
            startAfter(Double(text.count) * 0.35 + 3, token: mine, seconds: s.duration)
        } else {
            // 語音播报は無い:読んで構える時間を文の長さに合わせて 4〜9 秒
            startAfter(min(9, max(Self.quietLead + 1, Double(text.count) * 0.16)), token: mine, seconds: s.duration)
        }
    }

    private func startAfter(_ delay: TimeInterval, token mine: Int, seconds: TimeInterval) {
        lead?.cancel()
        lead = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.token == mine, self.preparing else { return }
            self.preparing = false
            self.run(seconds)
        }
    }

    private func run(_ seconds: TimeInterval) {
        endsAt = Date().addingTimeInterval(seconds)
        let mine = token
        timer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let self, self.token == mine else { return }
            NSSound(named: NSSound.Name("Tink"))?.play()
            self.next()
        }
    }

    /// 准备のあいだは「すぐ始める」、数えているあいだは止める / 続ける
    func togglePause() {
        if preparing, case .stretch(let s)? = current {
            lead?.cancel()
            lead = nil
            preparing = false
            Speaker.shared.stop()
            run(s.duration)
        } else if let left = pausedLeft {
            pausedLeft = nil
            run(left)
        } else if let end = endsAt {
            timer?.cancel()
            timer = nil
            pausedLeft = max(0, end.timeIntervalSinceNow)
            endsAt = nil
            Speaker.shared.stop()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        index = items.count
        if voice { Speaker.shared.guide("今天的日课做完了") }
        onFinish(hasStrength)
    }

    func stop() {
        cancelTimers()
        token += 1
        Speaker.shared.stop()
    }
}

// MARK: - 画面

/// 混凝土の墙:左 = 動画(黒い台)/ 拉伸(牛皮纸の台紙、360 幅のまま)、右 = 日课の一覧
struct RitualView: View {
    @ObservedObject var session: RitualSession
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                header
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            RitualList(session: session, coordinator: coordinator)
                .frame(width: 210)
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 24, trailing: 28))
        .frame(minWidth: 880, minHeight: 580)
        .background { BakedTile(id: "concrete-night") }
        .onAppear { session.start() }
        .background {
            // Space / → = 下一个、← = 上一个(動画を見ているあいだ Space はプレーヤーが先に取る)
            Group {
                Button("") { session.next() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("") { session.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { session.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("泡完澡后的日课")
                .font(TypeRole.titleZh)
                .foregroundStyle(Palette.text)
            Text(subtitle)
                .font(TypeRole.body)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        guard let current = session.current else { return "做完了" }
        switch current {
        case .video(let video, let number):
            return "跟练 \(number + 1) / \(session.videoCount) · \(video.title)"
        case .stretch(let s):
            return "拉伸 \(s.stretchNumber + 1) / \(session.stretchNames.count) · \(s.name)"
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let current = session.current {
            switch current {
            case .video(let video, _):
                RitualVideoStage(video: video)
            case .stretch(let s):
                HStack(alignment: .top, spacing: 32) {
                    RitualStretchCard(session: session, stretch: s)
                    RitualUpcoming(step: session.upcoming)
                    Spacer(minLength: 0)
                }
            }
        } else {
            RitualDone(coordinator: coordinator)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 14) {
            if let current = session.current {
                itemControls(current)
            } else {
                Button("‹ 回到上一步") { session.previous() }
                    .buttonStyle(BareButtonStyle())
                Spacer(minLength: 0)
                Button("关闭") { NSApp.keyWindow?.performClose(nil) }
                    .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, width: 150))
            }
        }
        .font(TypeRole.button)
    }

    @ViewBuilder
    private func itemControls(_ item: RitualSession.Item) -> some View {
        switch item {
        case .video(let video, _):
            Button("‹ 上一个") { session.previous() }
                .buttonStyle(BareButtonStyle())
                .disabled(session.index == 0)
            Button("在浏览器里打开") { NSWorkspace.shared.open(video.page) }
                .buttonStyle(BareButtonStyle())
            Spacer(minLength: 0)
            Button("跟练完了，下一个") { session.next() }
                .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton))
        case .stretch:
            Button("‹ 上一步") { session.previous() }
                .buttonStyle(BareButtonStyle())
            Spacer(minLength: 0)
            Button(session.preparing ? "开始" : (session.pausedLeft == nil ? "暂停" : "继续")) {
                session.togglePause()
            }
            .buttonStyle(FrameButtonStyle(height: Turf.popupButton, width: 110))
            .help(session.preparing ? "不等语音读完，马上开始计时" : "暂停 / 继续计时")
            Button("下一步") { session.next() }
                .buttonStyle(SprayButtonStyle(kind: .teal, height: Turf.popupButton, width: 150))
        }
    }
}

/// 動画:黒い台に公式の埋め込みプレーヤー(16:9)。埋め込めないサイトはブラウザへ
private struct RitualVideoStage: View {
    let video: Ritual.Video

    var body: some View {
        if let embed = video.embed {
            RitualPlayer(url: embed)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background { Palette.black }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("这个视频只能在浏览器里看")
                    .font(TypeRole.cardTitle)
                    .foregroundStyle(Palette.text)
                Text(video.page.absoluteString)
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 公式の埋め込みプレーヤー。参照元(https://yudh.app/)を付けて読み込む(付けないと YouTube の埋め込みが再生を断る)
struct RitualPlayer: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loaded: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .black
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.loaded != url {
            load(into: view, coordinator: context.coordinator)
        }
    }

    /// 次へ進んで消えるとき、音が残らないように空にする
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.loadHTMLString("", baseURL: nil)
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        coordinator.loaded = url
        view.loadHTMLString(Self.page(url), baseURL: URL(string: "https://yudh.app/"))
    }

    static func page(_ url: URL) -> String {
        let src = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="\(src)" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
    }
}

/// 拉伸の 1 歩:牛皮纸の台紙(坐站の小窓と同じ 360 幅)に姿勢の絵・見出し・手順・残り秒・歩の点
private struct RitualStretchCard: View {
    @ObservedObject var session: RitualSession
    let stretch: RitualSession.StretchStep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stretch.heading)
                    .font(Typeface.cjk(15, weight: .black))
                    .foregroundStyle(Palette.kraftText)
                Spacer(minLength: 8)
                StepDots(count: stretch.stepCount, index: stretch.stepNumber)
            }
            HStack(alignment: .center, spacing: 14) {
                PosturePose(name: stretch.step.pose, height: 132, symbol: "figure.cooldown")
                VStack(alignment: .leading, spacing: 8) {
                    if session.preparing {
                        Text("准备")
                            .font(TypeRole.sectionCaption)
                            .foregroundStyle(Palette.kraftTextSecondary)
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        PostureTimer(text: clock(now: context.date))
                    }
                    if let meta = stretch.step.meta {
                        Text(meta)
                            .font(TypeRole.count)
                            .foregroundStyle(Palette.kraftTextSecondary)
                    }
                }
            }
            .padding(.top, 6)
            Text(stretch.step.text)
                .font(Typeface.mixed(17, weight: 700))
                .foregroundStyle(Palette.kraftText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text(BreakReminder.caution)
                .font(Typeface.cjk(12, weight: .medium))
                .foregroundStyle(Palette.kraftTextSecondary)
                .padding(.top, 10)
        }
        .padding(Turf.popupPadding)
        .frame(width: Turf.popupWidth, alignment: .leading)
        .kraftSurface()
    }

    /// 残り(准备のあいだはこの歩の長さ、止めているときは止めた残り)
    private func clock(now: Date) -> String {
        if session.preparing {
            return StretchGuide.clock(until: now.addingTimeInterval(stretch.duration), now: now)
        }
        if let left = session.pausedLeft {
            return StretchGuide.clock(until: now.addingTimeInterval(left), now: now)
        }
        guard let end = session.endsAt else { return "00:00" }
        return StretchGuide.clock(until: end, now: now)
    }
}

/// 次の歩の予告(混凝土の上の白い字)
private struct RitualUpcoming: View {
    let step: RitualSession.StretchStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let step {
                Text("下一步")
                    .font(TypeRole.sectionCaption)
                    .foregroundStyle(Palette.textSecondary)
                Text(step.stepNumber == 0 ? step.name : step.heading)
                    .font(TypeRole.cardTitle)
                    .foregroundStyle(Palette.text)
                Text(step.step.text)
                    .font(TypeRole.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .padding(.top, 24)
    }
}

/// 做完了:連続日数(青の模板字)と、今日の腹式呼吸の回数
private struct RitualDone: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let streak = BreathLog.streak(coordinator.habits.ritual, today: Date())
        VStack(alignment: .leading, spacing: 14) {
            Text("今天的日课做完了")
                .font(TypeRole.titleZh)
                .foregroundStyle(Palette.text)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StencilText(text: "\(streak)", set: "mid-teal", fallbackSize: 64, fallbackColor: Palette.teal)
                Text("天连续")
                    .font(TypeRole.button)
                    .foregroundStyle(Palette.text)
            }
            Text("腹式呼吸今天做了 \(coordinator.breathToday) 次。睡前躺着再做几次，慢慢让它变成平时的呼吸方式")
                .font(TypeRole.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 24)
    }
}

/// 右の一覧:跟练(動画)と拉伸。いまのところは白、終わったところは ✓、押すとそこへ飛ぶ
private struct RitualList: View {
    @ObservedObject var session: RitualSession
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if session.videoCount > 0 {
                caption("跟练")
                ForEach(Array(session.videoTitles.enumerated()), id: \.offset) { number, title in
                    row(title, state: state(first: number, last: number)) { session.jump(to: number) }
                }
            }
            if !session.stretchNames.isEmpty {
                caption(session.short ? "拉伸（简版）" : (session.hasStrength ? "拉伸 · 今天加肩袖力量" : "拉伸"))
                    .padding(.top, session.videoCount > 0 ? 12 : 0)
                ForEach(Array(session.stretchNames.enumerated()), id: \.offset) { number, name in
                    if let first = session.firstItem(ofStretch: number) {
                        let last = (session.firstItem(ofStretch: number + 1) ?? session.items.count) - 1
                        row(name, state: state(first: first, last: last)) { session.jump(to: first) }
                    }
                }
            }
            Spacer(minLength: 12)
            // 累的晚上:拉伸只做 4 个(约 5 分钟)。连续比量重要
            Button(session.short ? "改回全部拉伸" : "今天累了，只做简版（约 5 分钟）") {
                session.setShort(!session.short)
            }
            .buttonStyle(BareButtonStyle())
            .font(TypeRole.caption)
            Text("连续 \(BreathLog.streak(coordinator.habits.ritual, today: Date())) 天 · 腹式呼吸今天 \(coordinator.breathToday) 次")
                .font(TypeRole.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private enum RowState { case done, current, later }

    private func state(first: Int, last: Int) -> RowState {
        if session.index > last { return .done }
        if session.index >= first { return .current }
        return .later
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(TypeRole.sectionCaption)
            .foregroundStyle(Palette.textSecondary)
    }

    private func row(_ title: String, state: RowState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                StencilIconView(icon: state == .done ? .check : .play, size: 12)
                    .opacity(state == .later ? 0.4 : 1)
                Text(title)
                    .font(state == .current ? Typeface.mixed(14, weight: 900) : Typeface.mixed(14, weight: 500))
                    .lineLimit(1)
            }
            .foregroundStyle(state == .current ? Palette.text : Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
