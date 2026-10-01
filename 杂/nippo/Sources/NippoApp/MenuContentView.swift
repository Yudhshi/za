import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english

    /// UserDefaults の保存先(英語タブの「回到今日」も同じ値を書く)
    static let storageKey = "panelTab"
}

/// メニューパネル本体(2026-10 v12.1「Stencil Turf」夜版)。夜の浇筑混凝土の墙に、焼いた喷块・遮块・模板字を置き、文字は本物。
/// 上から「いま大事な順」:表头(曜日の模板字・已工作・今日 / 英语)→ 接缝 → 主角卡(静 = 黒漆 + 曜日の神兽、動 = 青の満喷 + 垂れ、
/// 00 = 橙)→ 盤面(設定の上下班時間を 15 分ごと)→ 日程 → 接缝 → 任务 → 底栏(模板アイコン + 文字)。
/// 窓は画面の中央に浮き、曜日を掴んで動かせる(MainPanelController)。
/// OOUI:会議・タスク・単語という「もの」を一覧から選び、そのものに付いた操作をする。画面の文字は中国語、喊声は英語の模板字
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage(PanelTab.storageKey) private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360
    /// 今日の日程で選んだ会議(nil = 次の会議)
    @State private var selectedMeetingID: String?

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 200
    }

    var body: some View {
        VStack(spacing: 0) {
            TodayHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.leading, Turf.panelPadding.leading)
                .padding(.trailing, Turf.panelPadding.trailing)
                .padding(.top, Turf.panelPadding.top)

            // 主角卡の飛沫(bleed:上 14・左 14・右 24 まで)は、この内側の余白(上 18・左右 24)に収まる。
            // ScrollView の切り抜きはそのまま(スクロールしたとき表头・底栏に重ならないように)
            ScrollView {
                Group {
                    switch tab {
                    case .today:
                        TodayView(coordinator: coordinator, selectedMeetingID: $selectedMeetingID)
                    case .english:
                        VStack(alignment: .leading, spacing: 0) {
                            TodayMeetingStrip(coordinator: coordinator)
                            EnglishView(english: coordinator.english)
                        }
                    }
                }
                .padding(.leading, Turf.panelPadding.leading)
                .padding(.trailing, Turf.panelPadding.trailing)
                .padding(.top, TodayLayout.headerGap)
                .padding(.bottom, 24)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TodayContentHeightKey.self, value: geo.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight, maxHeight))
            // 表头の下の模板の継ぎ目(表头と主角卡のあいだの 18pt の隙間の中。中身はこの上を流れる)
            .background(alignment: .top) {
                ConcreteSeam()
                    .frame(height: TodayLayout.headerGap)
            }
            // 初回レイアウト前の 0 は無視(高さ 0 に潰れないように)
            // perform は SDK によって @Sendable なので、State へは捕まえた Binding 経由で書く
            .onPreferenceChange(TodayContentHeightKey.self) { [height = $contentHeight] value in
                if value > 0 { height.wrappedValue = value }
            }

            TodayFooter(coordinator: coordinator)
                .padding(.leading, Turf.panelPadding.leading)
                .padding(.trailing, Turf.panelPadding.trailing)
                .padding(.bottom, Turf.panelPadding.bottom)
        }
        .frame(width: Turf.panelWidth)
        // 混凝土の平铺 + 面板の縁(対拉孔・欠け・接地影は素材に焼いてある)+ 每天首开的遮盖纸
        .panelSurface()
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
        .onAppear {
            selectedMeetingID = nil
            coordinator.refreshTodayEvents()
            coordinator.refreshShachoken(force: true)
            coordinator.english.loadIfNeeded()
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .english { coordinator.english.loadIfNeeded() }
        }
        .onDisappear { coordinator.english.panelClosed() }
    }
}

private struct TodayContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - 寸法・字・動きの段取り

private enum TodayLayout {
    /// 表头と主角卡のあいだ(継ぎ目はこの中)
    static let headerGap: CGFloat = 18
    /// 主角卡と盤面のあいだ(静)
    static let boardGap: CGFloat = 34
    /// 動・00 は垂れのぶん盤面との間を 48 に広げる(主角卡の側で足す)
    static let dripRoom: CGFloat = 14
    /// 垂れの長さの上限 = 盤面までの隙間 48 − 6
    static let dripMax: CGFloat = 42
    /// 静の主角卡の件名の幅(右は神兽。2 行まで、末尾は …)
    static let calmTitleWidth: CGFloat = 268
    /// 大数字と単位のあいだ
    static let unitGap: CGFloat = 16
    /// 今日も明日も会議がない / 日历の権限がない:短い黒漆の卡
    static let shortHeroHeight: CGFloat = 150
    /// 区切りの一行(日程 3 / 任务 2)の高さと左の余白
    static let captionRow: CGFloat = 24
    static let captionInset: CGFloat = 12
    /// 日程と任务のあいだ(継ぎ目はこの中)
    static let seamGap: CGFloat = 18
}

/// 今日パネルで繰り返し使う字(Typeface は引数ごとに記憶するので、ここは名前を付けるだけ)
private enum TodayFont {
    static let durationLabel = Typeface.cjk(13, weight: .bold)
    static let durationDigits = Typeface.mono(14, weight: 700)
    static let unit = Typeface.cjk(20, weight: .black)
    static let unitSmall = Typeface.cjk(13, weight: .bold)
    static let footer = Typeface.cjk(13.5, weight: .bold)
    static let footerDigits = Typeface.mono(14, weight: 700)
    /// 日程の時刻(等幅)
    static let scheduleTime = Typeface.mono(15, weight: 700)
    /// 上班時刻の入力欄
    static let workInput = Typeface.archivo(15, weight: 700, width: 100, tnum: true)
}

/// 主角卡の動き(motion.png の 02 / 03。どのコマも焼いた遮罩 + 交差フェード。減らす動きでは最後の絵だけ)
private enum TodayMotion {
    /// 静 → 動(会の 10 分前):青漆が数字から漫る 0–340、模板字の青 → 黒 200–360、按钮 330–450、垂れ 360–600
    static let approachMs: Double = 600
    /// 動 → 00:橙が模板の橋から滲み出て卡に漫る 0–720、按钮の交差 720–900、垂れ 620–900
    static let zeroMs: Double = 900
}

/// 青(静)と黒(動)のあいだの色。t = 0 で from、1 で to
private func todayPanelBlend(_ from: Color, _ to: Color, _ t: Double) -> Color {
    if t <= 0 { return from }
    if t >= 1 { return to }
    return from.mix(with: to, by: t)
}

/// 「9:05」(模板字の時刻と同じ書き方)
private func todayPanelClock(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
}

// MARK: - 表头:曜日・已工作・タブ

/// 曜日は英語の大文字の模板字だけ(TUESDAY、二遍喷の错版は精灵に焼いてある)。月日はどこにも出さない
private struct TodayHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab
    @State private var workError: String?
    /// 上班時刻を書き換え中(入力欄の分だけ横が要るので、表头が曜日の大きさを決めるのに使う)
    @State private var workEditing = false
    static let weekday = Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide)

    var body: some View {
        let name = Date().formatted(Self.weekday)
        // 今日の 20 問が終わったら、数の代わりに模板の ✓
        let englishDone = english.loaded && english.todayCount >= EnglishCoordinator.dailyGoal
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                StencilWord(id: "day-\(name.lowercased())-white-night", fallback: name.uppercased(),
                            fallbackSize: 31, fallbackColor: Palette.white, scale: weekdayScale(name))
                    .padding(.vertical, 4)
                    // ここを掴むと窓が動く
                    .background(WindowDragArea())
                    .help("拖动这里可以移动窗口")
                Spacer(minLength: 8)
                // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
                TodayWorkTime(coordinator: coordinator, allowsInput: tab == .today, error: $workError,
                              editing: $workEditing) {
                    tab = .today
                }
                StencilTabs(items: [
                    TabItem(value: PanelTab.today, title: "今日", shortcut: "1"),
                    TabItem(value: PanelTab.english, title: "英语",
                            badge: english.loaded && !englishDone ? english.remainingTotal : nil,
                            shortcut: "2", done: englishDone),
                ], selection: $tab)
            }
            .frame(height: Turf.topRow)
            if let reason = coordinator.quietReasonToday {
                Text("休息日 · \(reason)")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .help("今天是\(reason)：会议提醒和站立提醒都已暂停")
            }
            if let workError, tab == .today {
                Text(workError)
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.text)
            }
        }
    }

    /// 曜日の倍率。WEDNESDAY や入力欄で 1 行に入らないときだけ縮める(0.7 まで)
    private func weekdayScale(_ name: String) -> CGFloat {
        let id = "day-\(name.lowercased())-white-night"
        let natural = Baked.asset(id)?.layoutSize.width ?? CGFloat(name.count) * 28
        let work: CGFloat
        if coordinator.workBeganAt == nil {
            work = tab == .today ? 86 : 80
        } else {
            work = workEditing && tab == .today ? 130 : 96
        }
        // 間隔 14 × 2 と標籤(数字 3 桁まで)を引いた残り
        let budget = Turf.contentWidth - 28 - 136 - work
        guard natural > 0 else { return 1 }
        return max(0.7, min(1, budget / natural))
    }
}

/// 工作时间(出勤時刻は手入力。勤怠システムとは連携しない)。小さく 1 行で。
/// 入力済みなら「已工作 3:12」(押すと修正)、未入力なら今日タブではその場に小さな入力欄(焼いた遮喷の枠)
private struct TodayWorkTime: View {
    @ObservedObject var coordinator: AppCoordinator
    let allowsInput: Bool
    @Binding var error: String?
    /// 書き換え中(表头が幅を計るので親が持つ)
    @Binding var editing: Bool
    let showToday: () -> Void
    @State private var input = ""
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        if let began = coordinator.workBeganAt, !(editing && allowsInput) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Button {
                    input = ""
                    error = nil
                    editing = true
                    showToday()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("已工作")
                            .font(TypeRole.sectionCaption)
                            .foregroundStyle(Palette.textSecondary)
                        Text(Self.clock(context.date.timeIntervalSince(began)))
                            .font(TypeRole.time)
                            .foregroundStyle(Palette.text)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(began.formatted(Self.time)) 上班，已工作 \(WorkStart.durationText(from: began, to: context.date))。点击修改上班时间")
            }
        } else if !allowsInput {
            Button(action: showToday) {
                Text("填写上班时间")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("去「今日」填写上班时间")
        } else {
            HStack(alignment: .center, spacing: 6) {
                Text("上班")
                    .font(TypeRole.sectionCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .help("上班时间")
                TextField("", text: $input, prompt: Text("853").foregroundStyle(Palette.textSecondary))
                    .font(TodayFont.workInput)
                    .multilineTextAlignment(.center)
                    .frame(width: 60, height: 26)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.text)
                    // 平涂の代わりに混凝土に焼いた小さな遮喷の枠(64×26)
                    .background { BakedSlice(id: "input-frame-small-night", fallback: Palette.cellPastFill) }
                    .onSubmit(save)
                    .help("8:53 上班就输入 853，按回车")
                if editing {
                    Button("取消") {
                        editing = false
                        error = nil
                    }
                    .buttonStyle(BareButtonStyle())
                    .font(TypeRole.caption)
                }
            }
            .fixedSize()
        }
    }

    /// 「3:12」(時:分)
    static func clock(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func save() {
        if let message = coordinator.setWorkBegan(input) {
            error = message
        } else {
            error = nil
            editing = false
            input = ""
        }
    }
}

// MARK: - 今日

private struct TodayView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var selectedMeetingID: String?

    var body: some View {
        let now = Date()
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: now)
        // 選んだ会議が終わったら既定(次の会議)に戻す
        let selected = events.first { $0.id == selectedMeetingID && $0.end > now } ?? next
        // 明日の予定は AppCoordinator が今日の分と一緒に読んである(開いたときに主角卡が後から変わらない)
        let tomorrowFirst = selected == nil
            ? NextEventPolicy.currentOrNext(events: coordinator.tomorrowEvents, now: now) : nil
        let hadMeetings = events.contains { !$0.isAllDay }
        let dayNote = hadMeetings ? "今天的会都结束了" : "今天没有会议"
        let reminderHint = "工作日会在会议开始前 \(coordinator.settings.reminderLeadMinutes) 分钟提醒你"
        let showsNote = selected == nil && tomorrowFirst != nil
        let settings = coordinator.settings
        let span = TodayBoardSpan(start: settings.timeComponents(settings.workStartTime, fallback: (9, 0)),
                                  end: settings.timeComponents(settings.workEndTime, fallback: (18, 0)))

        VStack(alignment: .leading, spacing: 0) {
            // 主役:選んだ会議(既定は次の会議)。今日もう無ければ明日の最初の会議
            Group {
                if !coordinator.calendarAuthorized {
                    TodayCalendarAccessHero()
                } else if let selected {
                    // 選び直したら別の卡(動きは時間で状態が変わったときだけ。選んだときは流さない)
                    TodayMeetingHero(event: selected, isNext: selected.id == next?.id)
                        .id(selected.id)
                } else if let tomorrowFirst {
                    TodayTomorrowHero(event: tomorrowFirst)
                } else {
                    TodayEmptyHero(title: dayNote, hint: reminderHint)
                }
            }
            // 主角卡の飛沫・垂れは盤面の纹理带の上に重なる
            .zIndex(1)

            // 盤面:上下班の時間を 15 分ごと。灰は会議、青は選んだ会議。明日を見ているときは上に一行
            if coordinator.calendarAuthorized {
                if showsNote {
                    Text(dayNote)
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 23)
                        .help(reminderHint)
                }
                TodayDayBoard(events: events, selectedID: selected?.id, span: span, band: !showsNote)
                    .padding(.top, showsNote ? 15 : TodayLayout.boardGap)
            }

            TodaySchedule(events: events, selectedID: selected?.id) { id in
                // 次の会議を選び直したら既定に戻す(時間が進むと自動で次へ移る)
                selectedMeetingID = id == next?.id ? nil : id
            }
            .padding(.top, 14)

            // 日程と任务のあいだの継ぎ目(隙間の中だけ。字は横切らない)
            ConcreteSeam()
                .frame(height: TodayLayout.seamGap)

            TodayTaskList(coordinator: coordinator)
        }
    }
}

// MARK: - 主角卡

/// 主角卡の台:焼いた喷块(九宮格、bleed の飛沫ごと)。動きの途中は次の喷块を焼いた遮罩の帯で漫らせる。
/// 静のときだけ、喷块と文字のあいだに曜日の神兽(第二の模板・灰漆。位置と大きさは creatureLayer = CreatureFit)
private struct TodayHeroCard<Content: View>: View {
    let slab: String
    let fallback: Color
    let flood: TodayHeroFlood?
    let creature: String?
    let minHeight: CGFloat?
    let content: Content

    init(slab: String, fallback: Color, flood: TodayHeroFlood? = nil, creature: String? = nil,
         minHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.slab = slab
        self.fallback = fallback
        self.flood = flood
        self.creature = creature
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(Turf.heroPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            // 重なり順(奥 → 手前):喷块 → 神兽 → 漫ってくる次の喷块 → 文字
            .background { floodLayer }
            .creatureLayer(creature ?? "", enabled: creature != nil)
            .background { BakedSlice(id: slab, fallback: fallback) }
    }

    @ViewBuilder
    private var floodLayer: some View {
        if let flood {
            if Baked.hasFrames(flood.mask, count: 8) {
                // 卡と同じ枠(bleed 込み)に伸ばした遮罩のコマ
                BakedSlice(id: flood.slab, fallback: flood.fallback)
                    .mask { BakedFrame(prefix: flood.mask, count: 8, progress: flood.progress) }
            } else {
                // 遮罩の帯が無いときは淡く重ねるだけ
                BakedSlice(id: flood.slab, fallback: flood.fallback)
                    .opacity(flood.progress)
            }
        }
    }
}

/// 動きの途中で漫ってくる喷块
private struct TodayHeroFlood {
    let slab: String
    let fallback: Color
    /// 遮罩の帯の名前(flood-teal- / flood-orange-、8 コマ)
    let mask: String
    let progress: Double
}

/// 動きの区切り。静 → 会前 10 分(approach)→ 00 から終わりまで(live)。
/// 00 → 進行中・終了では変わらないので、動くのは「静 → 動」と「動 → 00」の 2 回だけ
private enum TodayHeroStage: Equatable {
    case calm, approach, live

    init(phase: HeroPolicy.Phase, started: Bool) {
        switch phase {
        case .calm: self = .calm
        case .event: self = started ? .live : .approach
        case .zero, .ended: self = .live
        }
    }

    var durationMs: Double { self == .live ? TodayMotion.zeroMs : TodayMotion.approachMs }
}

/// ある瞬間の主角卡の見た目(状態 + 動きの進み具合から決める。動いていないときは progress = 1)
private struct TodayHeroLook {
    /// 黒漆の卡・青と白の字・神兽(静と、終わった会議)
    let calm: Bool
    /// 静 → 動の青漆の漫り(動いている間だけ)
    let tealFlood: Double?
    /// 動 → 00 の橙の漫り(動いている間だけ)
    let orangeFlood: Double?
    /// 字の色:0 = 静(青・白)、1 = 動(黒)
    let ink: Double
    /// 動の按钮が現れる(静 → 動の 330–450)
    let buttonFade: Double
    /// 00 の按钮へ交差(720–900)
    let zeroSwap: Double
    /// 青の垂れが伸びる(静 → 動の 360–600)
    let dripGrow: Double
    /// 橙の垂れが伸びる(動 → 00 の 620–900)
    let orangeDripGrow: Double
    /// 00 へ移る途中、橙の垂れが出るまでは青の垂れを残す
    let keepsTealDrips: Bool
    let phase: HeroPolicy.Phase

    init(phase: HeroPolicy.Phase, stage: TodayHeroStage, progress: Double) {
        self.phase = phase
        let playing = progress < 1
        let approach = playing && stage == .approach && phase == .event
        let toZero = playing && phase == .zero
        let a = TodayMotion.approachMs
        let z = TodayMotion.zeroMs
        let isCalm = phase == .calm || phase == .ended
        calm = isCalm
        tealFlood = approach ? motionPhase(progress, totalMs: a, from: 0, to: 340) : nil
        orangeFlood = toZero ? motionPhase(progress, totalMs: z, from: 0, to: 720) : nil
        ink = isCalm ? 0 : (approach ? motionPhase(progress, totalMs: a, from: 200, to: 360) : 1)
        buttonFade = approach ? motionPhase(progress, totalMs: a, from: 330, to: 450) : 1
        zeroSwap = toZero ? motionPhase(progress, totalMs: z, from: 720, to: 900) : 1
        dripGrow = approach ? motionPhase(progress, totalMs: a, from: 360, to: 600) : 1
        orangeDripGrow = toZero ? motionPhase(progress, totalMs: z, from: 620, to: 900) : 1
        keepsTealDrips = toZero && progress * z < 620
    }

    /// 神兽を出す(静。静 → 動の途中は青漆の下に隠れていく)
    var showsCreature: Bool { calm || tealFlood != nil }

    /// いちばん奥の喷块
    var slab: String {
        if calm || tealFlood != nil { return "hero-calm-night" }
        if phase == .zero && orangeFlood == nil { return "hero-zero-night" }
        return "hero-event-night"
    }

    var slabFallback: Color {
        if calm || tealFlood != nil { return Palette.black }
        if phase == .zero && orangeFlood == nil { return Palette.orange }
        return Palette.teal
    }

    var flood: TodayHeroFlood? {
        if let tealFlood {
            return TodayHeroFlood(slab: "hero-event-night", fallback: Palette.teal, mask: "flood-teal-",
                                  progress: tealFlood)
        }
        if let orangeFlood {
            return TodayHeroFlood(slab: "hero-zero-night", fallback: Palette.orange, mask: "flood-orange-",
                                  progress: orangeFlood)
        }
        return nil
    }
}

/// 大数字の横の単位の文言
private enum TodayHeroUnitText {
    static func text(_ unit: HeroPolicy.Unit) -> String {
        switch unit {
        case .minutesUntil: return "分钟后"
        case .startsAt: return "开始"
        case .minutesLeft: return "分钟"
        case .endsAt: return "结束"
        case .zero: return "到点了"
        case .ended: return "已结束"
        }
    }

    /// 1 行で書くとき(英語タブの会議条)
    static func inline(_ unit: HeroPolicy.Unit) -> String {
        unit == .minutesLeft ? "分钟后结束" : text(unit)
    }
}

/// 喊声(NEXT / NOW / LATER / DONE / TOMORROW)。焼いた模板字で、静は青・動は黒。ink で交差フェード
private struct TodayShout: View {
    let word: String
    var ink: Double = 0

    var body: some View {
        if ink <= 0 {
            stencil(black: false)
        } else if ink >= 1 {
            stencil(black: true)
        } else {
            stencil(black: false)
                .opacity(1 - ink)
                .overlay(alignment: .topLeading) {
                    stencil(black: true)
                        .opacity(ink)
                        .accessibilityHidden(true)
                }
        }
    }

    private func stencil(black: Bool) -> StencilWord {
        StencilWord(id: "shout-\(word.lowercased())-\(black ? "black" : "teal")-night",
                    fallback: word, fallbackSize: 21, fallbackColor: black ? Palette.black : Palette.teal)
    }
}

/// 大数字・時刻の模板字(1 倍のまま。時刻 16:30 は 80pt の mid、分は 132pt の big)。ink で青 → 黒の交差フェード。
/// 配置の枠は字身、基線 = 枠の下端
private struct TodayStencilNumber: View {
    let text: String
    var ink: Double = 0

    var body: some View {
        if ink <= 0 {
            number(black: false)
        } else if ink >= 1 {
            number(black: true)
        } else {
            number(black: false)
                .opacity(1 - ink)
                .overlay(alignment: .topLeading) {
                    number(black: true)
                        .opacity(ink)
                        .accessibilityHidden(true)
                }
        }
    }

    private func number(black: Bool) -> StencilText {
        let mid = text.contains(":")
        return StencilText(text: text, set: "\(mid ? "mid" : "big")-\(black ? "black" : "teal")",
                           fallbackSize: mid ? 80 : 132, fallbackColor: black ? Palette.black : Palette.teal)
    }
}

/// 大数字 + 単位。単位は数字の基線にそろえて右 16pt(重ね描き:行の高さ・下端は数字の字身のまま)
private struct TodayNumeral: View {
    let display: HeroPolicy.Display
    let ink: Double

    var body: some View {
        TodayStencilNumber(text: display.value, ink: ink)
            .creatureAvoid()
            .overlay(alignment: .bottomTrailing) {
                unit
                    .fixedSize()
                    .creatureAvoid()
                    .alignmentGuide(.trailing) { _ in -TodayLayout.unitGap }
                    .alignmentGuide(.bottom) { d in d[.lastTextBaseline] }
            }
    }

    @ViewBuilder
    private var unit: some View {
        let color = todayPanelBlend(Palette.teal, Palette.black, ink)
        if display.unit == .minutesLeft {
            // 进行中:还剩 / 分钟 の 2 行
            VStack(alignment: .leading, spacing: 6) {
                Text("还剩")
                    .font(TodayFont.unitSmall)
                Text(TodayHeroUnitText.text(display.unit))
                    .font(TodayFont.unit)
            }
            .foregroundStyle(color)
        } else {
            Text(TodayHeroUnitText.text(display.unit))
                .font(TodayFont.unit)
                .foregroundStyle(color)
        }
    }
}

/// 時長の格(15 分 = 1 格、4 格ごとに少し空ける)
private struct TodayDurationCells: View {
    let kinds: [TurfCell.Kind]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<kinds.count, id: \.self) { i in
                TurfCell(kind: kinds[i])
                    .padding(.leading, i > 0 && i % 4 == 0 ? 3 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 時長の格の青 → 黒の交差フェード(静 → 動の 200–360ms)
private struct TodayInkCells: View {
    let from: [TurfCell.Kind]
    let to: [TurfCell.Kind]
    let ink: Double

    var body: some View {
        if ink <= 0 {
            TodayDurationCells(kinds: from)
        } else if ink >= 1 {
            TodayDurationCells(kinds: to)
        } else {
            TodayDurationCells(kinds: from)
                .opacity(1 - ink)
                .overlay(alignment: .leading) {
                    TodayDurationCells(kinds: to)
                        .opacity(ink)
                }
        }
    }
}

/// 静の卡で ⏎ を押したら加入(加入按钮は出さない。見えない 0pt のボタン)
private struct TodayHiddenJoin: View {
    let url: URL

    var body: some View {
        Button("加入会议") { NSWorkspace.shared.open(url) }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .help("\(url.host ?? "加入会议")（⏎）")
    }
}

/// 動の加入按钮:黒い輪付きの橙(橙が青に触れない)、摄像机 19pt + 加入会议 / 回到会议、120×50
private struct TodayRingedJoin: View {
    let title: String
    let url: URL
    /// ⏎(00 へ移る途中で消えていく方には付けない)
    let shortcut: Bool

    var body: some View {
        let button = Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(alignment: .center, spacing: 7) {
                StencilIconView(icon: .camera, size: 19)
                Text(title)
            }
        }
        .buttonStyle(SprayButtonStyle(kind: .orangeRinged, height: Turf.heroButton.height,
                                      width: Turf.heroButton.width))
        if shortcut {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}

/// 00 の加入按钮:橙の上の黒漆の块 + 白い「马上加入」(104×50)
private struct TodayZeroJoin: View {
    let url: URL

    var body: some View {
        Button("马上加入") { NSWorkspace.shared.open(url) }
            .buttonStyle(SprayButtonStyle(kind: .blackOnOrange, height: Turf.heroButton.height, width: 104))
            .keyboardShortcut(.defaultAction)
    }
}

/// 主役:会議 1 つ。表示が変わる瞬間(分の翻牌・動・00・終了)だけ描き直す
private struct TodayMeetingHero: View {
    let event: MeetingEvent
    let isNext: Bool

    var body: some View {
        let opened = Date()
        let ticks = HeroPolicy.ticks(for: event, after: opened)
        if ticks.isEmpty {
            // もう変わる時刻が無い(終わった会議):30 秒ごと
            TimelineView(.periodic(from: opened, by: 30)) { context in
                TodayMeetingHeroFace(event: event, isNext: isNext, now: max(context.date, Date()))
            }
        } else {
            // 最初の 1 枚はいまの時刻で描く
            TimelineView(.explicit([opened] + ticks)) { context in
                TodayMeetingHeroFace(event: event, isNext: isNext, now: max(context.date, Date()))
            }
        }
    }
}

/// 主角卡の中身。喊声 + 時刻(右上に摄像机)、件名(2 行まで)、大数字 + 単位(動は右に加入按钮)、時長の格。
/// 静 → 動(会前 10 分)と 動 → 00 の瞬間だけ、焼いた帯で 1 回動く
private struct TodayMeetingHeroFace: View {
    let event: MeetingEvent
    let isNext: Bool
    let now: Date
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        let phase = HeroPolicy.phase(for: event, now: now)
        let stage = TodayHeroStage(phase: phase, started: event.start <= now)
        MotionPlayer(trigger: stage, durationMs: stage.durationMs) { progress in
            card(TodayHeroLook(phase: phase, stage: stage, progress: progress))
        }
        // 動・00 は垂れのぶん盤面を下げる(48pt)
        .padding(.bottom, phase == .event || phase == .zero ? TodayLayout.dripRoom : 0)
    }

    private func card(_ look: TodayHeroLook) -> some View {
        TodayHeroCard(slab: look.slab, fallback: look.slabFallback, flood: look.flood,
                      creature: look.showsCreature ? Myth.heroCreature(for: now) : nil) {
            VStack(alignment: .leading, spacing: 0) {
                topRow(look)
                title(look)
                    .padding(.top, 12)
                numeralRow(look)
                    .padding(.top, 22)
                durationRow(look)
                    .padding(.top, 16)
            }
        }
        .overlay(alignment: .bottom) { drips(look) }
    }

    private func topRow(_ look: TodayHeroLook) -> some View {
        let started = event.start <= now
        let kicker = look.phase == .ended ? "DONE" : (started ? "NOW" : (isNext ? "NEXT" : "LATER"))
        let span = "\(event.start.formatted(Self.time))–\(event.end.formatted(Self.time))"
        let link = look.phase == .ended ? nil : event.joinURL
        return HStack(alignment: .center, spacing: 14) {
            TodayShout(word: kicker, ink: look.ink)
                .creatureAvoid()
            Text(span)
                .font(TypeRole.time)
                .foregroundStyle(todayPanelBlend(Palette.text, Palette.black, look.ink))
                .fixedSize()
                .creatureAvoid()
            Spacer(minLength: 8)
            if let link {
                // 白い模板の摄像机(静)/ 黒(動)。主機名は help に
                StencilIconView(icon: .camera, size: 18)
                    .foregroundStyle(todayPanelBlend(Palette.white, Palette.black, look.ink))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .help(link.host ?? "线上会议")
                    .creatureAvoid()
            }
        }
        .background {
            if look.calm, let link {
                TodayHiddenJoin(url: link)
            }
        }
    }

    private func title(_ look: TodayHeroLook) -> some View {
        Text(event.title)
            .font(TypeRole.title(for: event.title))
            .foregroundStyle(todayPanelBlend(Palette.text, Palette.black, look.ink))
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .typesetting(for: event.title)
            .textSelection(.enabled)
            .creatureAvoid()
            .frame(maxWidth: look.showsCreature ? TodayLayout.calmTitleWidth : nil, alignment: .leading)
    }

    private func numeralRow(_ look: TodayHeroLook) -> some View {
        let display = HeroPolicy.display(for: event, now: now)
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            TodayNumeral(display: display, ink: look.ink)
            Spacer(minLength: 12)
            if !look.calm {
                joinAction(look)
                    // 按钮の下端 = 数字の基線の 6pt 上
                    .alignmentGuide(.lastTextBaseline) { d in d.height + 6 }
            }
        }
    }

    /// 動 = 黒い輪付きの橙(加入会议 / 回到会议)、00 = 黒漆の「马上加入」。⏎ で押せる
    @ViewBuilder
    private func joinAction(_ look: TodayHeroLook) -> some View {
        if let url = event.joinURL {
            let help = "\(url.host ?? "加入会议")（⏎）"
            if look.phase == .zero {
                if look.zeroSwap < 1 {
                    ZStack(alignment: .bottomTrailing) {
                        TodayRingedJoin(title: "加入会议", url: url, shortcut: false)
                            .opacity(1 - look.zeroSwap)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        TodayZeroJoin(url: url)
                            .opacity(look.zeroSwap)
                    }
                    .help(help)
                } else {
                    TodayZeroJoin(url: url)
                        .help(help)
                }
            } else {
                TodayRingedJoin(title: event.start <= now ? "回到会议" : "加入会议", url: url, shortcut: true)
                    .opacity(look.buttonFade)
                    .help(help)
            }
        } else {
            Text("没有线上链接")
                .font(TypeRole.caption)
                .foregroundStyle(Palette.black)
        }
    }

    /// 時長の格 + 説明。静 = 青、動 = 黒、進行中は過ぎた分が黒・残りが黒の点、終わった会議は暗い灰
    private func durationRow(_ look: TodayHeroLook) -> some View {
        let cells = HeroPolicy.durationCells(for: event, now: now)
        let running = look.phase == .event && event.start <= now
        let total = max(1, Int((event.end.timeIntervalSince(event.start) / 60).rounded()))
        let elapsed = max(0, Int(now.timeIntervalSince(event.start) / 60))
        let calmKind: TurfCell.Kind = look.phase == .ended ? .meetingPast : .teal
        let calmKinds: [TurfCell.Kind] = Array(repeating: calmKind, count: cells.count)
        let paintKinds: [TurfCell.Kind] = running
            ? Array(repeating: TurfCell.Kind.black, count: cells.elapsed)
                + Array(repeating: TurfCell.Kind.blackDots, count: max(0, cells.count - cells.elapsed))
            : Array(repeating: TurfCell.Kind.black, count: cells.count)
        let strong = todayPanelBlend(Palette.text, Palette.black, look.ink)
        let soft = todayPanelBlend(Palette.textSecondary, Palette.black, look.ink)
        return HStack(alignment: .center, spacing: 12) {
            TodayInkCells(from: calmKinds, to: paintKinds, ink: look.ink)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if running {
                    Text("已进行")
                        .font(TodayFont.durationLabel)
                        .foregroundStyle(soft)
                }
                Text(String(running ? elapsed : total))
                    .font(TodayFont.durationDigits)
                    .foregroundStyle(strong)
                Text("分钟")
                    .font(TodayFont.durationLabel)
                    .foregroundStyle(soft)
            }
        }
        .fixedSize()
        .creatureAvoid()
    }

    /// 動 = 青の垂れ、00 = 橙の垂れ(盤面に届かない長さだけ)。静 → 動の途中は 360ms から伸びる
    @ViewBuilder
    private func drips(_ look: TodayHeroLook) -> some View {
        if look.phase == .event {
            Drips(paint: .teal, maxLength: TodayLayout.dripMax, grow: look.dripGrow)
        } else if look.phase == .zero {
            if look.keepsTealDrips {
                Drips(paint: .teal, maxLength: TodayLayout.dripMax)
            } else {
                Drips(paint: .orange, seed: 3, maxLength: TodayLayout.dripMax, grow: look.orangeDripGrow)
            }
        }
    }
}

/// 明日の最初の会議(今日の会議がもう無いとき)。静の卡に TOMORROW + 曜日、件名、開始時刻(mid の模板字)、
/// 時長の格(枠だけ)、明日の神兽
private struct TodayTomorrowHero: View {
    let event: MeetingEvent
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)
    static let weekday = Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide)

    var body: some View {
        let day = event.start.formatted(Self.weekday)
        let minutes = max(1, Int((event.end.timeIntervalSince(event.start) / 60).rounded()))
        let count = HeroPolicy.durationCells(for: event, now: event.start).count
        TodayHeroCard(slab: "hero-calm-night", fallback: Palette.black,
                      creature: Myth.heroCreature(for: event.start)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    TodayShout(word: "TOMORROW")
                        .creatureAvoid()
                    StencilWord(id: "dayshout-\(day.lowercased())-white-night", fallback: day.uppercased(),
                                fallbackSize: 21, fallbackColor: Palette.white)
                        .creatureAvoid()
                }
                // 今日の卡の 1 行目(時刻の行)と同じ高さ
                .frame(minHeight: 21)
                Text(event.title)
                    .font(TypeRole.title(for: event.title))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .typesetting(for: event.title)
                    .textSelection(.enabled)
                    .creatureAvoid()
                    .frame(maxWidth: TodayLayout.calmTitleWidth, alignment: .leading)
                    .padding(.top, 12)
                TodayStencilNumber(text: todayPanelClock(event.start))
                    .creatureAvoid()
                    .padding(.top, 22)
                HStack(alignment: .center, spacing: 12) {
                    TodayDurationCells(kinds: Array(repeating: TurfCell.Kind.outline, count: count))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(minutes))
                            .font(TodayFont.durationDigits)
                            .foregroundStyle(Palette.text)
                        Text("分钟 · 到")
                            .font(TodayFont.durationLabel)
                            .foregroundStyle(Palette.textSecondary)
                        Text(event.end.formatted(Self.time))
                            .font(TodayFont.durationDigits)
                            .foregroundStyle(Palette.text)
                    }
                }
                .fixedSize()
                .creatureAvoid()
                .padding(.top, 16)
            }
        }
    }
}

/// 短い黒漆の卡(472×150)。今日の神兽が右いっぱいに(空の状態も作品)
private struct TodayShortHero<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let slab = Baked.has("hero-calm-short-night") ? "hero-calm-short-night" : "hero-calm-night"
        TodayHeroCard(slab: slab, fallback: Palette.black, creature: Myth.heroCreature(for: Date()),
                      minHeight: TodayLayout.shortHeroHeight) {
            content
        }
    }
}

/// 今日も明日も会議がない:短い卡に一行 + 提醒の説明、右に今日の神兽
private struct TodayEmptyHero: View {
    let title: String
    let hint: String

    var body: some View {
        TodayShortHero {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(TypeRole.cardTitle)
                    .foregroundStyle(Palette.text)
                    .creatureAvoid()
                Text(hint)
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .creatureAvoid()
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }
}

/// 日历の権限がない:短い卡に説明と「打开系统设置」、右に今日の神兽
private struct TodayCalendarAccessHero: View {
    var body: some View {
        TodayShortHero {
            VStack(alignment: .leading, spacing: 6) {
                Text("需要日历权限")
                    .font(TypeRole.cardTitle)
                    .foregroundStyle(Palette.text)
                    .creatureAvoid()
                Text("用来显示会议、提前提醒，以及查找シャチョケン")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .creatureAvoid()
                    .frame(maxWidth: 260, alignment: .leading)
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SprayButtonStyle(kind: .orangeSmall, height: 34))
                .creatureAvoid()
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - 盤面(設定の上下班時間、15 分 × n 格。幅は 472 のまま)

/// 盤面の時間割り:上班〜下班を 15 分(格が 9pt より細くなるなら 30 分)の格に切り、472pt に並べる。
/// 時の境目(xx:00)の前だけ少し広く空ける
private struct TodayBoardSpan {
    static let gap: CGFloat = 2
    static let hourGap: CGFloat = 5

    /// 0 時からの分
    let start: Int
    let end: Int
    /// 1 格の分(15 / 30)
    let slot: Int
    let count: Int
    let cellWidth: CGFloat

    init(start begin: (hour: Int, minute: Int), end finish: (hour: Int, minute: Int)) {
        var s = begin.hour * 60 + begin.minute
        var e = finish.hour * 60 + finish.minute
        // 夜をまたぐ・1 時間に満たない設定は 9:00–18:00 で描く
        if e - s < 60 {
            s = 9 * 60
            e = 18 * 60
        }
        var chosen = 15
        var n = (e - s) / chosen
        var width = Self.widthOfCell(start: s, slot: chosen, count: n)
        if width < 9 {
            chosen = 30
            n = (e - s) / chosen
            width = Self.widthOfCell(start: s, slot: chosen, count: n)
        }
        start = s
        end = e
        slot = chosen
        count = n
        cellWidth = width
    }

    private static func hourBreaks(start: Int, slot: Int, through index: Int) -> Int {
        guard index >= 1 else { return 0 }
        return (1...index).filter { (start + $0 * slot) % 60 == 0 }.count
    }

    private static func widthOfCell(start: Int, slot: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let hours = hourBreaks(start: start, slot: slot, through: count - 1)
        let gaps = CGFloat(count - 1) * gap + CGFloat(hours) * (hourGap - gap)
        return (Turf.contentWidth - gaps) / CGFloat(count)
    }

    /// i 番目の格の前が時の境目か
    func hourBreak(before index: Int) -> Bool {
        index > 0 && (start + index * slot) % 60 == 0
    }

    /// i 番目の格の左端
    func cellX(_ index: Int) -> CGFloat {
        CGFloat(index) * (cellWidth + Self.gap)
            + CGFloat(Self.hourBreaks(start: start, slot: slot, through: index)) * (Self.hourGap - Self.gap)
    }

    /// 0 時からの分 → x(格の中は割合で)
    private func x(minutes: Double) -> CGFloat {
        let offset = minutes - Double(start)
        guard offset > 0 else { return 0 }
        guard offset < Double(count * slot) else { return Turf.contentWidth }
        let index = Int(offset / Double(slot))
        let fraction = CGFloat((offset - Double(index * slot)) / Double(slot))
        return cellX(index) + fraction * cellWidth
    }

    /// 時の境目の x(格のあいだの隙間の真ん中。両端は 0 / 472)
    private func boundaryX(minute: Int) -> CGFloat {
        let offset = minute - start
        if offset <= 0 { return 0 }
        if offset >= count * slot { return Turf.contentWidth }
        guard offset % slot == 0 else { return x(minutes: Double(minute)) }
        let index = offset / slot
        return cellX(index) - (hourBreak(before: index) ? Self.hourGap : Self.gap) / 2
    }

    /// 盤面の下の時刻(整点だけ)
    var hourMarks: [TodayHourMark] {
        let last = start + count * slot
        return stride(from: (start + 59) / 60, through: last / 60, by: 1).map { hour in
            TodayHourMark(hour: hour, x: boundaryX(minute: hour * 60))
        }
    }

    /// 0 時からの分(秒まで)
    private func minutes(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// いまの x(盤面の外は nil)
    func nowX(_ now: Date) -> CGFloat? {
        let m = minutes(of: now)
        guard m >= Double(start), m < Double(start + count * slot) else { return nil }
        return x(minutes: m)
    }

    /// いまの時(盤面の中のときだけ。下の時刻をその時だけ太字に)
    func currentHour(_ now: Date) -> Int? {
        let m = minutes(of: now)
        guard m >= Double(start), m < Double(start + count * slot) else { return nil }
        return Int(m) / 60
    }

    /// 格の状態(会議・選択・経過は DayTimeline のまま。進行中の選択だけ満 / 点に分ける)
    func kinds(events: [MeetingEvent], selectedID: String?, now: Date) -> [TurfCell.Kind] {
        let slots = DayTimeline.slots(events: events,
                                      start: (hour: start / 60, minute: start % 60),
                                      end: (hour: end / 60, minute: end % 60),
                                      now: now, selectedID: selectedID, slotMinutes: slot)
        let selected = events.first { $0.id == selectedID }
        let live = selected.map { $0.start <= now && now < $0.end } ?? false
        let from = Calendar.current.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: now) ?? now
        let length = Double(slot * 60)
        return slots.enumerated().map { pair -> TurfCell.Kind in
            let cell = pair.element
            if cell.selected {
                guard live else { return .teal }
                // 格の半分以上が過ぎたら満
                let middle = from.addingTimeInterval(Double(pair.offset) * length + length / 2)
                return middle <= now ? .teal : .tealDots
            }
            if cell.meeting { return cell.past ? .meetingPast : .meeting }
            return cell.past ? .past : .empty
        }
    }

    /// 「9:00–18:00」
    var text: String {
        String(format: "%d:%02d–%d:%02d", start / 60, start % 60, end / 60, end % 60)
    }
}

private struct TodayHourMark: Hashable {
    let hour: Int
    let x: CGFloat
}

/// 今日の盤面。灰 = 会議(過ぎたら暗く)、青 = 選んだ会議(進行中は過ぎた分が満・残りが点)、橙の刻み = いま。
/// 上下班の外の会議は載らない。下に整点の時刻(最初は左寄せ、最後は右寄せ、今の時は太字)
private struct TodayDayBoard: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let span: TodayBoardSpan
    /// 盤面の纹理带(上の 34pt + 格の行)。明日の予告の一行があるときは字の下に纹理を敷かない
    let band: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let kinds = span.kinds(events: events, selectedID: selectedID, now: now)
            VStack(alignment: .leading, spacing: 6) {
                cells(kinds)
                    .overlay(alignment: .topLeading) {
                        if let x = span.nowX(now) {
                            TodayNowNotch(x: x)
                        }
                    }
                    .background(alignment: .bottom) {
                        if band {
                            Color.clear
                                .frame(height: TodayLayout.boardGap + 20)
                                .boardBand()
                        }
                    }
                hourLabels(current: span.currentHour(now))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天 \(span.text) 的会议")
        .help("\(span.text)，每格 \(span.slot) 分钟。灰格是会议，青色的格是选中的会议")
    }

    private func cells(_ kinds: [TurfCell.Kind]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<kinds.count, id: \.self) { i in
                TurfCell(kind: kinds[i], width: span.cellWidth)
                    .padding(.leading, i == 0 ? 0 : (span.hourBreak(before: i) ? TodayBoardSpan.hourGap
                                                                               : TodayBoardSpan.gap))
            }
        }
        .frame(width: Turf.contentWidth, height: 20, alignment: .leading)
    }

    private func hourLabels(current: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(span.hourMarks, id: \.self) { mark in
                let label = String(mark.hour)
                // JetBrains Mono 12pt の送りは 7.2pt。両端は盤面からはみ出さない(最初は左寄せ、最後は右寄せになる)
                let half = CGFloat(label.count) * 7.2 / 2
                Text(label)
                    .font(mark.hour == current ? TypeRole.boardLabelNow : TypeRole.boardLabel)
                    .foregroundStyle(mark.hour == current ? Palette.text : Palette.textSecondary)
                    .fixedSize()
                    .position(x: min(max(mark.x, half), Turf.contentWidth - half), y: 8)
            }
        }
        .frame(width: Turf.contentWidth, height: 16)
    }
}

/// いまの刻み(焼いた橙 2pt + 上の三角、黒漆の縁)。下へ 4pt はみ出す
private struct TodayNowNotch: View {
    let x: CGFloat

    var body: some View {
        if let asset = Baked.asset("now-notch-night"), Baked.has("now-notch-night") {
            let size = asset.layoutSize
            // 配置の枠の下端 = 格の下 + 4pt
            BakedSprite(id: "now-notch-night")
                .offset(x: x - size.width / 2, y: 24 - size.height)
        } else {
            Rectangle()
                .fill(Palette.orange)
                .frame(width: 2, height: 24)
                .offset(x: x - 1, y: 0)
        }
    }
}

// MARK: - 区切りの一行

/// 「日程 3」「任务 2」(12pt の次要色、数は等幅)
private struct TodaySectionCaption: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(TypeRole.sectionCaption)
                .tracking(0.7)
            Text(String(count))
                .font(TypeRole.count)
        }
        .foregroundStyle(Palette.textSecondary)
    }
}

// MARK: - 日程

/// 今日日程(会議の一覧)。行を押すとその会議を選ぶ(加入は上の主角卡から)
private struct TodaySchedule: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TodaySectionCaption(title: "日程", count: events.count)
                .padding(.leading, TodayLayout.captionInset)
                .frame(height: TodayLayout.captionRow)
            if events.isEmpty {
                Text("没有安排")
                    .font(TypeRole.body)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.leading, 18)
                    .frame(height: Turf.scheduleRow)
            }
            ForEach(events) { event in
                TodayEventRow(event: event, selected: event.id == selectedID) {
                    select(event.id)
                }
            }
        }
    }
}

/// 1 行 40pt:時刻(等幅)・件名(1 行。欧文は語の切れ目で …、中日文は字で …)・线上なら摄像机。
/// 選んだ行は左に焼いた青い帯(6×24)+ 青い時刻、ホバーは焼いた悬停块
private struct TodayEventRow: View {
    let event: MeetingEvent
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let past = event.end < Date()
        let main: Color = past ? Palette.textSecondary : Palette.text
        let font = selected
            ? Typeface.mixed(15, weight: 700, japanese: Typeface.isJapanese(event.title))
            : TypeRole.body(for: event.title)
        Button(action: action) {
            HStack(spacing: 14) {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(TodayFont.scheduleTime)
                    .foregroundStyle(selected ? Palette.teal : main)
                    .frame(width: 48, alignment: .leading)
                TodayRowTitle(text: event.title, font: font, color: main)
                    .typesetting(for: event.title)
                Spacer(minLength: 8)
                if event.joinURL != nil && !past {
                    StencilIconView(icon: .camera, size: 14)
                        .foregroundStyle(Palette.textSecondary)
                        .help("线上会议")
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .frame(height: Turf.scheduleRow)
            .background { HoverPlate(active: hovering) }
            .overlay(alignment: .leading) {
                if selected {
                    BakedSlice(id: "bar-teal-night", fallback: Palette.teal)
                        .frame(width: Turf.selectedBar, height: 24)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(event.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 日程の件名 1 行。欧文だけの件名は入りきらなければ語の切れ目で切って …(長い順に試す)、中日文は字で切る
private struct TodayRowTitle: View {
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        let cuts = TodayTitleCut.isLatin(text) ? TodayTitleCut.candidates(text) : []
        if cuts.isEmpty {
            line(text)
        } else {
            // 候補は 8 つまで(足りなければ最後の候補を繰り返す)。どれも入らなければ字で切る
            let c = (0..<8).map { cuts[min($0, cuts.count - 1)] }
            ViewThatFits(in: .horizontal) {
                line(text)
                line(c[0])
                line(c[1])
                line(c[2])
                line(c[3])
                line(c[4])
                line(c[5])
                line(c[6])
                line(c[7])
                line(text)
            }
        }
    }

    private func line(_ value: String) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// 欧文の件名を語の切れ目で切る候補
private enum TodayTitleCut {
    /// 漢字・仮名・ハングル・全角記号を含まない(= 語の切れ目で切ってよい)
    static func isLatin(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: return true
            default: return false
            }
        }
    }

    /// 空白の手前で切った「…」付きの候補(長い順、limit 個まで)。末尾の区切り記号(— / , : など)は落とす。
    /// 64 字より長い候補は 1 行に入らないので試さない
    static func candidates(_ text: String, limit: Int = 8) -> [String] {
        var cuts: [String] = []
        var index = text.startIndex
        while let space = text[index...].firstIndex(of: " ") {
            var prefix = String(text[..<space])
            while let last = prefix.last, " —–-/,:;·|&+(".contains(last) {
                prefix.removeLast()
            }
            let candidate = prefix + "…"
            if !prefix.isEmpty, prefix.count <= 64, cuts.last != candidate {
                cuts.append(candidate)
            }
            index = text.index(after: space)
        }
        return Array(cuts.reversed().prefix(limit))
    }
}

// MARK: - 当前任务(1 つずつが「もの」)

/// 当前任务。各タスクは左のチェックボックスで完成(メモから消す・直後なら撤销)。
/// 一覧ごとの操作は「任务 N」の行を押して書き換え(テキスト。書くそばから保存するので閉じても消えない)
private struct TodayTaskList: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""
    @State private var captionHovering = false

    var body: some View {
        let blocks = TaskOutline.blocks(coordinator.settings.taskMemo)
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                HStack(alignment: .center, spacing: 8) {
                    TodaySectionCaption(title: "任务", count: blocks.count)
                        .padding(.leading, TodayLayout.captionInset)
                    Spacer(minLength: 8)
                    Button("完成") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(SprayButtonStyle(kind: .orangeSmall, height: 34))
                }
                TextEditor(text: $draft)
                    .font(TypeRole.body)
                    .foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 150)
                    // 平涂の代わりに混凝土に焼いた遮喷の枠(472×150)
                    .background { BakedSlice(id: "input-frame-concrete-night", fallback: Palette.cellPastFill) }
                    .padding(.top, 10)
                    .onChange(of: draft) { _, text in
                        coordinator.settings.taskMemo = text
                    }
                Text("任务名顶格写，内容用 Tab 缩进（或以「- 」开头），空行分隔任务")
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                // 区切りの一行(任务 N)がそのまま書き換えのボタン。悬停で下に焼いた悬停块(「编辑」とは書かない)
                Button(action: startEditing) {
                    HStack(alignment: .center, spacing: 8) {
                        TodaySectionCaption(title: "任务", count: blocks.count)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, TodayLayout.captionInset)
                    .frame(height: TodayLayout.captionRow)
                    .background { HoverPlate(active: captionHovering, small: true) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { captionHovering = $0 }
                .help("点击编辑")
                .accessibilityLabel("编辑任务")

                if blocks.isEmpty {
                    Button(action: startEditing) {
                        HStack(alignment: .center, spacing: 14) {
                            HandCheckbox(checked: false)
                            Text("写下现在在做的事")
                                .font(Typeface.mixed(14, weight: 600))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.horizontal, TodayLayout.captionInset)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                            TodayTaskRow(block: block) {
                                coordinator.completeTask(at: index)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                if let done = coordinator.lastCompletedTask {
                    HStack(spacing: 8) {
                        StencilIconView(icon: .check, size: 12)
                            .foregroundStyle(Palette.teal)
                        Text("已完成「\(done.title)」")
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button("撤销") { coordinator.undoCompleteTask() }
                            .buttonStyle(BareButtonStyle())
                    }
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, TodayLayout.captionInset)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func startEditing() {
        draft = coordinator.settings.taskMemo
        editing = true
    }
}

/// タスク 1 つ:左の手刻みのチェックボックスで完成(ホバーで勾选の予告)。タスク名と、中身を 1 行にまとめたもの
private struct TodayTaskRow: View {
    let block: TaskOutline.Block
    let complete: () -> Void
    @State private var hovering = false

    var body: some View {
        let title = block.title ?? block.items.first?.text ?? ""
        let rest = block.title == nil ? Array(block.items.dropFirst()) : block.items
        let detail = rest.map(\.text).joined(separator: " · ")
        HStack(alignment: .top, spacing: 14) {
            Button(action: complete) {
                HandCheckbox(checked: hovering)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("完成（从备忘里移除）")
            .accessibilityLabel("完成")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typeface.mixed(15, weight: 600, japanese: Typeface.isJapanese(title)))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .typesetting(for: title)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Typeface.mixed(12.5, weight: 600, japanese: Typeface.isJapanese(detail)))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .typesetting(for: detail)
                        .help(rest.map { String(repeating: "  ", count: max(0, $0.depth - 1)) + $0.text }
                            .joined(separator: "\n"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TodayLayout.captionInset)
    }
}

// MARK: - 英語タブの上:近い会議

/// 英語タブを開いていても、開始 30 分前から会議を見失わない(焼いた黒漆の条 472×50 に 1 行。色面は単語カードに譲る)
private struct TodayMeetingStrip: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            if let event = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: now),
               event.start.timeIntervalSince(now) < 30 * 60 {
                let running = event.start <= now
                let display = HeroPolicy.display(for: event, now: now)
                let strip = Baked.has("strip-black-night") ? "strip-black-night" : "plate-black-night"
                HStack(alignment: .center, spacing: 12) {
                    TodayShout(word: running ? "NOW" : "NEXT")
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(display.value)
                            .font(TypeRole.time)
                        Text(TodayHeroUnitText.inline(display.unit))
                            .font(Typeface.cjk(13, weight: .bold))
                    }
                    .foregroundStyle(Palette.text)
                    .fixedSize()
                    Text(event.title)
                        .font(Typeface.mixed(13, weight: 500, japanese: Typeface.isJapanese(event.title)))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .typesetting(for: event.title)
                    Spacer(minLength: 8)
                    if let url = event.joinURL {
                        Button("加入会议") { NSWorkspace.shared.open(url) }
                            .buttonStyle(FrameButtonStyle(height: 34))
                            .help(url.host ?? "加入会议")
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background { BakedSlice(id: strip, fallback: Palette.black) }
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - 底栏:坐姿・シャチョケン・电源

private struct TodayFooter: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            if coordinator.settings.postureEnabled && coordinator.isWorkingNow {
                TodayPostureStatus(coordinator: coordinator)
            }
            if coordinator.calendarAuthorized {
                TodayShachokenStatus(event: coordinator.nextShachoken,
                                     keyword: coordinator.settings.shachokenKeywords)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
            // 設定ボタンは置かない(使うときは ⌘,)。⌘Q はすぐ終了
            Group {
                Button("设置") { coordinator.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("退出") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            TodayPowerButton()
        }
        .frame(height: Turf.iconButton)
    }
}

/// 电源(退出)。按两下才退出(以免误点后会议提醒和站立提醒都停掉)。上膛した状態は焼いた橙の方形の遮块(38×38)に黒いアイコン
private struct TodayPowerButton: View {
    @State private var armed = false
    @State private var hovering = false

    var body: some View {
        Button {
            if armed {
                NSApp.terminate(nil)
            } else {
                armed = true
            }
        } label: {
            StencilIconView(icon: .power, size: 19)
                .foregroundStyle(armed ? Palette.black : (hovering ? Palette.text : Palette.textSecondary))
                .frame(width: Turf.iconButton, height: Turf.iconButton)
                .background {
                    if armed {
                        BakedSlice(id: Baked.has("tag-orange-square-night") ? "tag-orange-square-night"
                                                                             : "tag-orange-night",
                                   fallback: Palette.orange)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // 3 秒で解除。視図が消えたり状態が変わったりすれば自動で取り消される
        .task(id: armed) {
            guard armed else { return }
            try? await Task.sleep(for: .seconds(3))
            armed = false
        }
        .help(armed ? "再按一次退出" : "退出 Yudh（按两下，或 ⌘Q）。设置：⌘,")
        .accessibilityLabel(armed ? "再按一次退出" : "退出 Yudh")
    }
}

/// 坐姿:椅子(立っていれば人)の模板アイコン + 「已坐 47 分钟」。到点了は焼いた橙の遮喷の札。点击打开屏幕上方的小窗(文は help に)
private struct TodayPostureStatus: View {
    @ObservedObject var coordinator: AppCoordinator
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = coordinator.posture == .standing
            let minutes = max(0, Int(context.date.timeIntervalSince(coordinator.postureSince) / 60))
            let due = context.date >= coordinator.postureDueAt
            let dueAt = coordinator.postureDueAt.formatted(Self.time)
            Button {
                coordinator.openPosturePrompt()
            } label: {
                HStack(alignment: .center, spacing: 7) {
                    StencilIconView(icon: standing ? .stand : .seat, size: 17)
                        .padding(.trailing, 2)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(standing ? "已站" : "已坐")
                            .font(TodayFont.footer)
                        Text(String(minutes))
                            .font(TodayFont.footerDigits)
                        Text("分钟")
                            .font(TodayFont.footer)
                    }
                    if due {
                        PaintTag(text: "到点了")
                            .padding(.leading, 8)
                    }
                }
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(standing ? "已站 \(minutes) 分钟，\(dueAt) 坐下。点击打开拉伸步骤"
                           : "已坐 \(minutes) 分钟，\(dueAt) 站起来\(due ? "（该站起来了）" : "")。点击打开「站起来了吗？」小窗")
        }
    }
}

/// 下一次シャチョケン(26卒_新卒社長研修,日历里 90 天内)。一个月只看两三次,所以小小的。
/// 具体的な日付はここにも出さない(何天后 + 曜日 + 時刻は help に)
private struct TodayShachokenStatus: View {
    let event: MeetingEvent?
    let keyword: String
    static let weekday = Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide)
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("シャチョケン")
                    .font(TodayFont.footer)
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    Text(countdown.value)
                        .font(countdown.value.allSatisfy(\.isNumber) ? TodayFont.footerDigits : TodayFont.footer)
                    if !countdown.unit.isEmpty {
                        Text(countdown.unit)
                            .font(TodayFont.footer)
                    }
                } else {
                    Text("—")
                        .font(TodayFont.footer)
                }
            }
            .foregroundStyle(event == nil ? Palette.textSecondary : Palette.text)
            .lineLimit(1)
            .help(tooltip)
        }
    }

    private var tooltip: String {
        guard let event else { return "シャチョケン：90 天内没有标题含「\(keyword)」的日程" }
        return "シャチョケン：\(event.title)\n\(event.start.formatted(Self.weekday).uppercased()) "
            + "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
    }
}
