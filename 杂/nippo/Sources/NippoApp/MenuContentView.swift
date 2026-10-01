import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-10 v12「Stencil Turf」夜版)。平铺の混凝土に、焼いた喷块・遮块・模板字を置き、文字は本物。上から「いま大事な順」:
/// 表头(曜日の模板字・已工作・今日 / 英语)→ 主角卡(次の会議。静 = 黒漆 + 曜日の神兽、動 = 青の満喷 + 垂れ、00 = 橙)→ 盤面(9–18 の 36 格)→ 日程 → 任务 → 底栏(模板アイコン + 文字)。
/// 窓は画面の中央に浮き、曜日を掴んで動かせる(MainPanelController)。
/// OOUI:会議・タスク・単語という「もの」を一覧から選び、そのものに付いた操作をする。画面の文字は中国語、喊声は英語の模板字
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("panelTab") private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360
    /// 今日の日程で選んだ会議(nil = 次の会議)
    @State private var selectedMeetingID: String?

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 200
    }

    /// 選んだ会議(既定は次の会議)。終わった会議は選び直さない
    private var selectedMeeting: MeetingEvent? {
        let now = Date()
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: now)
        guard let selected = events.first(where: { $0.id == selectedMeetingID && $0.end > now }) ?? next,
              selected.end > now else { return nil }
        return selected
    }

    /// 今日の主角卡の強さ:選んだ会議が開始 10 分以内か進行中なら動、それ以外は静
    private var todayIntensity: Intensity {
        guard let selected = selectedMeeting else { return .calm }
        return selected.start.timeIntervalSince(Date()) <= 10 * 60 ? .event : .calm
    }

    /// 旧部品(英語タブなど、まだ \.level を読むもの)向けの関卡色。5 分以内・進行中は橙
    private var todayLevel: Level {
        let now = Date()
        let calm = Level.today(night: Theme.isNight(now))
        guard let selected = selectedMeeting else { return calm }
        return selected.start.timeIntervalSince(now) <= 5 * 60 ? Level.urgent(night: Theme.isNight(now)) : calm
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.leading, Turf.panelPadding.leading)
                .padding(.trailing, Turf.panelPadding.trailing)
                .padding(.top, Turf.panelPadding.top)

            ScrollView {
                Group {
                    switch tab {
                    case .today:
                        TodayView(coordinator: coordinator, selectedMeetingID: $selectedMeetingID)
                    case .english:
                        VStack(alignment: .leading, spacing: 0) {
                            MeetingStrip(coordinator: coordinator)
                            EnglishView(english: coordinator.english)
                        }
                    }
                }
                .padding(.leading, Turf.panelPadding.leading)
                .padding(.trailing, Turf.panelPadding.trailing)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight, maxHeight))
            // 初回レイアウト前の 0 は無視(高さ 0 に潰れないように)
            .onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }

            PanelFooter(coordinator: coordinator)
                .padding(.leading, Turf.panelPadding.leading)
                .padding(.trailing, Turf.panelPadding.trailing)
                .padding(.bottom, Turf.panelPadding.bottom)
        }
        .frame(width: Turf.panelWidth)
        // 混凝土の平铺 + 面板の縁(対拉孔・欠け・接地影は素材に焼いてある)
        .panelSurface()
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
        .environment(\.intensity, tab == .today ? todayIntensity : .calm)
        .environment(\.level, tab == .today ? todayLevel : .english(night: Theme.isNight()))
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

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - 表头:曜日・已工作・タブ

/// 曜日は英語の大文字の模板字だけ(TUESDAY、31pt の白漆)。月日はどこにも出さない
private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab
    @State private var workError: String?
    /// 上班時刻を書き換え中(入力欄の分だけ横が要るので、表头が曜日の大きさを決めるのに使う)
    @State private var workEditing = false
    static let weekday = Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide)

    var body: some View {
        let name = Date().formatted(Self.weekday)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                TodayWeekday(name: name, scale: weekdayScale(name))
                    .padding(.vertical, 4)
                    // ここを掴むと窓が動く
                    .background(WindowDragArea())
                    .help("拖动这里可以移动窗口")
                Spacer(minLength: 8)
                // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
                WorkTime(coordinator: coordinator, allowsInput: tab == .today, error: $workError,
                         editing: $workEditing) {
                    tab = .today
                }
                StencilTabs(items: [
                    TabItem(value: PanelTab.today, title: "今日", shortcut: "1"),
                    TabItem(value: PanelTab.english, title: "英语",
                            badge: english.loaded ? english.remainingTotal : nil, shortcut: "2"),
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
        let natural = Material.asset(id)?.layoutSize.width ?? CGFloat(name.count) * 28
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

/// 表头の曜日(焼いた模板字)。縮めるときは精灵をそのまま縮小、素材がなければ Archivo の本物の文字
private struct TodayWeekday: View {
    /// 英語の曜日(Tuesday)
    let name: String
    var scale: CGFloat = 1

    var body: some View {
        let id = "day-\(name.lowercased())-white-night"
        if scale < 1, Material.has(id), Material.image(id) != nil {
            MaterialSprite(id: id, scale: scale)
                .accessibilityElement()
                .accessibilityLabel(name.uppercased())
        } else {
            StencilWord(id: id, fallback: name.uppercased(), fallbackSize: 31 * scale, fallbackColor: Palette.white)
        }
    }
}

/// 工作时间(出勤時刻は手入力。勤怠システムとは連携しない)。小さく 1 行で。
/// 入力済みなら「已工作 3:12」(押すと修正)、未入力なら今日タブではその場に小さな入力欄
private struct WorkTime: View {
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
                    .frame(width: 52, height: 26)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.text)
                    .background(Palette.cellPastFill)
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
    /// 明日の予定(今日の会議がもう無いとき、主角卡で明日の最初の会議を予告する)
    @State private var tomorrowEvents: [MeetingEvent] = []

    var body: some View {
        let now = Date()
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: now)
        // 選んだ会議が終わったら既定(次の会議)に戻す
        let selected = events.first { $0.id == selectedMeetingID && $0.end > now } ?? next
        let tomorrowFirst = selected == nil ? NextEventPolicy.currentOrNext(events: tomorrowEvents, now: now) : nil
        let hadMeetings = events.contains { !$0.isAllDay }
        let dayNote = hadMeetings ? "今天的会都结束了" : "今天没有会议"
        // 動の主角卡は垂れが下に伸びるので、盤面との間を広げる
        let eventHero = selected.map { $0.end > now && $0.start.timeIntervalSince(now) <= 10 * 60 } ?? false
        let showsNote = selected == nil && tomorrowFirst != nil

        VStack(alignment: .leading, spacing: 0) {
            // 主役:選んだ会議(既定は次の会議)。今日もう無ければ明日の最初の会議
            Group {
                if !coordinator.calendarAuthorized {
                    CalendarAccessHero()
                } else if let selected {
                    MeetingHero(event: selected, isNext: selected.id == next?.id)
                } else if let tomorrowFirst {
                    TodayTomorrowHero(event: tomorrowFirst)
                } else {
                    TodayEmptyHero(title: dayNote,
                                   hint: "工作日会在会议开始前 \(coordinator.settings.reminderLeadMinutes) 分钟提醒你")
                }
            }

            // 盤面:9:00–18:00 を 15 分ごとに。灰は会議、青は選んだ会議。明日を見ているときは上に一行
            if coordinator.calendarAuthorized {
                if showsNote {
                    Text(dayNote)
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 26)
                }
                TodayDayBoard(events: events, selectedID: selected?.id)
                    .padding(.top, showsNote ? 8 : (eventHero ? 48 : 34))
                    .help("9:00–18:00，每格 15 分钟。灰格是会议，青色的格是选中的会议")
            }

            ScheduleList(events: events, selectedID: selected?.id) { id in
                // 次の会議を選び直したら既定に戻す(時間が進むと自動で次へ移る)
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    selectedMeetingID = id == next?.id ? nil : id
                }
            }
            .padding(.top, 18)

            TaskList(coordinator: coordinator)
                .padding(.top, 22)
        }
        .onAppear { loadTomorrow() }
        .onChange(of: coordinator.todayEvents) { loadTomorrow() }
    }

    /// 明日の予定を読む。EventKit の同期フェッチはメインスレッドの外で(AppCoordinator.refreshTodayEvents と同じ)
    private func loadTomorrow() {
        guard coordinator.calendarAuthorized,
              let day = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return }
        let provider = coordinator.calendarProvider
        Task.detached(priority: .utility) {
            let events = provider.events(on: day)
            await MainActor.run {
                tomorrowEvents = events
            }
        }
    }
}

// MARK: - 主角卡

/// 主角卡の強さ。静 = 黒漆、動(10 分以内・進行中)= 青の満喷、00(始まった 1 分)= 橙の満喷
private enum TodayHeroMode {
    case calm, event, zero

    var asset: String {
        switch self {
        case .calm: return "hero-calm-night"
        case .event: return "hero-event-night"
        case .zero: return "hero-zero-night"
        }
    }

    var fallback: Color {
        switch self {
        case .calm: return Palette.black
        case .event: return Palette.teal
        case .zero: return Palette.orange
        }
    }
}

/// 大数字の横の単位
private enum TodayHeroUnit {
    case single(String)
    /// 進行中:还剩 / 分钟 の 2 行
    case remaining
    /// 単位なし(明日の開始時刻)
    case bare
}

private enum TodayHeroLayout {
    /// 静の主角卡で神兽を置く右の空き(文字・数字・格はこの左に収める。間は 9pt)
    static let creatureZone: CGFloat = 200
    static let creatureGap: CGFloat = 9
}

/// 今日パネルで繰り返し使う字(CTFont を毎回作らないように)
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

/// 主角卡の台(472pt 幅の喷块)。上の行(喊声)は全幅、その下は左に文字、静のときだけ右の空きに曜日の神兽(灰漆・左向き)。
/// 動は下縁から青の垂れ(3 本まで)、00 は橙の垂れ
private struct TodayHeroCard<Top: View, Main: View>: View {
    let mode: TodayHeroMode
    /// 神兽の素材(静のときだけ出す)
    let creature: String?
    let creatureMaxHeight: CGFloat
    let top: Top
    let main: Main

    init(mode: TodayHeroMode, creature: String?, creatureMaxHeight: CGFloat = 176,
         @ViewBuilder top: () -> Top, @ViewBuilder main: () -> Main) {
        self.mode = mode
        self.creature = creature
        self.creatureMaxHeight = creatureMaxHeight
        self.top = top()
        self.main = main()
    }

    var body: some View {
        let height = creatureHeight
        VStack(alignment: .leading, spacing: 10) {
            top
            HStack(alignment: .top, spacing: TodayHeroLayout.creatureGap) {
                main
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let creature, height > 0 {
                    // 卡の右端から 6pt まで寄せる(右の余白 20pt の内側へ)
                    MaterialSprite.height(creature, height)
                        .offset(x: Turf.heroPadding.trailing - 6)
                        .frame(width: TodayHeroLayout.creatureZone, alignment: .trailing)
                }
            }
        }
        .padding(Turf.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { MaterialSlice(id: mode.asset, fallback: mode.fallback) }
        .overlay(alignment: .bottom) {
            switch mode {
            case .calm:
                EmptyView()
            case .event:
                Drips(paint: .teal)
            case .zero:
                Drips(paint: .orange, seed: 3)
            }
        }
        .environment(\.intensity, mode == .calm ? .calm : .event)
    }

    /// 神兽の高さ:右の空きの幅に収まり、卡の高さの 7〜8 割ほど。動・素材なしでは 0(出さない)
    private var creatureHeight: CGFloat {
        guard mode == .calm, let creature, let size = Material.asset(creature)?.layoutSize,
              size.width > 0, size.height > 0, Material.image(creature) != nil else { return 0 }
        return min(creatureMaxHeight, TodayHeroLayout.creatureZone * size.height / size.width)
    }
}

/// 喊声(NEXT / NOW / TOMORROW)。焼いた模板字で、静は青・動は黒。素材のない語(LATER / DONE)は本物の文字
private struct TodayShout: View {
    let word: String
    let black: Bool

    var body: some View {
        StencilWord(id: "shout-\(word.lowercased())-\(black ? "black" : "teal")-night",
                    fallback: word, fallbackSize: 21, fallbackColor: black ? Palette.black : Palette.teal)
    }
}

/// 大数字(模板字の精灵)+ 単位。横に入る一番大きな倍率を選ぶ(神兽の隣では少し縮む)
private struct TodayNumeral: View {
    let value: String
    let unit: TodayHeroUnit
    /// 動・00 の卡の上(黒の模板字)
    let black: Bool

    var body: some View {
        // 「16:30」のような時刻は 0.6 倍から、分(2 桁)は原寸から
        let scales: [CGFloat] = value.contains(":") ? [0.6, 0.5, 0.44] : [1, 0.86, 0.74]
        ViewThatFits(in: .horizontal) {
            row(scales[0])
            row(scales[1])
            row(scales[2])
        }
    }

    private func row(_ scale: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            StencilText(text: value, set: black ? "big-black" : "big-teal", scale: scale,
                        fallbackColor: black ? Palette.black : Palette.teal)
            unitView
        }
        .fixedSize()
    }

    @ViewBuilder
    private var unitView: some View {
        let color = black ? Palette.black : Palette.teal
        switch unit {
        case .single(let text):
            Text(text)
                .font(TodayFont.unit)
                .foregroundStyle(color)
        case .remaining:
            VStack(alignment: .leading, spacing: 6) {
                Text("还剩")
                    .font(TodayFont.unitSmall)
                Text("分钟")
                    .font(TodayFont.unit)
            }
            .foregroundStyle(color)
        case .bare:
            EmptyView()
        }
    }
}

/// 時長の格(15 分 = 1 格、4 格ごとに少し空ける)+ 説明。横に入らなければ説明を下の行へ
private struct TodayDurationRow<Label: View>: View {
    let kinds: [TurfCell.Kind]
    let label: Label

    init(kinds: [TurfCell.Kind], @ViewBuilder label: () -> Label) {
        self.kinds = kinds
        self.label = label()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                cells
                label
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                cells
                label
            }
            .fixedSize()
        }
    }

    private var cells: some View {
        HStack(spacing: 2) {
            ForEach(0..<kinds.count, id: \.self) { i in
                TurfCell(kind: kinds[i])
                    .padding(.leading, i > 0 && i % 4 == 0 ? 3 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 00 の橙の満喷の上のボタン:黒漆の遮块 + 白い字(橙の上に橙を重ねない)
private struct TodayZeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeRole.button)
            .tracking(17 * 0.04)
            .foregroundStyle(Palette.white)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(height: Turf.heroButton.height)
            .background { MaterialSlice(id: "plate-black-night", fallback: Palette.black) }
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

/// 主役:会議 1 つ。喊声 + 時刻、件名(2 行まで)、大数字(残り分)、時長の格。加入は静なら右上、動なら大数字の右
private struct MeetingHero: View {
    let event: MeetingEvent
    let isNext: Bool
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let mode = Self.mode(for: event, now: now)
            TodayHeroCard(mode: mode, creature: Myth.heroCreature(for: now)) {
                topRow(mode: mode, now: now)
            } main: {
                mainColumn(mode: mode, now: now)
            }
        }
    }

    private func topRow(mode: TodayHeroMode, now: Date) -> some View {
        let running = event.start <= now && now < event.end
        let past = event.end <= now
        let kicker = running ? "NOW" : (past ? "DONE" : (isNext ? "NEXT" : "LATER"))
        let span = "\(event.start.formatted(Self.time))–\(event.end.formatted(Self.time))"
        return HStack(alignment: .center, spacing: 14) {
            TodayShout(word: kicker, black: mode != .calm)
            Text(span)
                .font(TypeRole.time)
                .foregroundStyle(mode == .calm ? Palette.text : Palette.black)
                .fixedSize()
            Spacer(minLength: 8)
            if mode == .calm {
                joinButton(mode: mode, now: now)
            } else if event.joinURL != nil {
                StencilIconView(icon: .camera, size: 22)
                    .foregroundStyle(Palette.black)
                    .help("线上会议")
            }
        }
    }

    private func mainColumn(mode: TodayHeroMode, now: Date) -> some View {
        let display = Self.display(for: event, mode: mode, now: now)
        return VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .font(TypeRole.cardTitle)
                .foregroundStyle(mode == .calm ? Palette.text : Palette.black)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(alignment: .bottom, spacing: 12) {
                TodayNumeral(value: display.value, unit: display.unit, black: mode != .calm)
                    .layoutPriority(1)
                if mode != .calm {
                    Spacer(minLength: 12)
                    joinButton(mode: mode, now: now)
                        .padding(.bottom, 6)
                }
            }
            .padding(.top, 20)
            durationRow(mode: mode, now: now)
                .padding(.top, 16)
        }
    }

    private func durationRow(mode: TodayHeroMode, now: Date) -> some View {
        let kinds = Self.cells(for: event, mode: mode, now: now)
        let total = max(1, Int((event.end.timeIntervalSince(event.start) / 60).rounded()))
        let running = mode == .event && event.start <= now
        let elapsed = max(0, Int(now.timeIntervalSince(event.start) / 60))
        let strong: Color = mode == .calm ? Palette.text : Palette.black
        let soft: Color = mode == .calm ? Palette.textSecondary : Palette.black
        return TodayDurationRow(kinds: kinds) {
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
    }

    /// 加入会议(静 = 橙の喷块、動 = 黒い輪付きの橙、00 = 黒漆の「已开始」)。⏎ で押せる
    @ViewBuilder
    private func joinButton(mode: TodayHeroMode, now: Date) -> some View {
        let past = event.end <= now
        if let url = event.joinURL, !past {
            let running = event.start <= now
            let title = mode == .zero ? "已开始" : (running ? "回到会议" : "加入会议")
            let help = "\(url.host ?? "加入会议")（⏎）"
            switch mode {
            case .calm:
                Button(title) { NSWorkspace.shared.open(url) }
                    .buttonStyle(SprayButtonStyle(kind: .orange, height: 34))
                    .keyboardShortcut(.defaultAction)
                    .help(help)
            case .event:
                Button(title) { NSWorkspace.shared.open(url) }
                    .buttonStyle(SprayButtonStyle(kind: .orangeRinged, height: Turf.heroButton.height))
                    .keyboardShortcut(.defaultAction)
                    .help(help)
            case .zero:
                Button(title) { NSWorkspace.shared.open(url) }
                    .buttonStyle(TodayZeroButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .help(help)
            }
        } else if event.joinURL == nil, !past {
            Text("没有线上链接")
                .font(TypeRole.caption)
                .foregroundStyle(mode == .calm ? Palette.textSecondary : Palette.black)
        }
    }

    /// 開始 10 分前から動。始まって 1 分は 00(橙)、そのあと終わるまで動。終わったら静
    static func mode(for event: MeetingEvent, now: Date) -> TodayHeroMode {
        guard event.end > now else { return .calm }
        if event.start <= now {
            return now.timeIntervalSince(event.start) < 60 ? .zero : .event
        }
        return event.start.timeIntervalSince(now) <= 10 * 60 ? .event : .calm
    }

    /// 大数字と単位(数字は NextEventPolicy.heroCountdown のまま。分は 2 桁:04 → 03 → … → 00)
    static func display(for event: MeetingEvent, mode: TodayHeroMode, now: Date) -> (value: String, unit: TodayHeroUnit) {
        if event.end <= now { return ("—", .single("已结束")) }
        if mode == .zero { return ("00", .single("到点了")) }
        let countdown = NextEventPolicy.heroCountdown(for: event, now: now)
        let value = countdown.value.count == 1 && countdown.value.allSatisfy(\.isNumber)
            ? "0" + countdown.value : countdown.value
        if countdown.unit == "分钟后结束" { return (value, .remaining) }
        return (value, .single(countdown.unit))
    }

    /// 時長の格(15 分 = 1 格、16 格まで)。静 = 青、動 = 黒、進行中は過ぎた分が黒・残りが黒の点
    static func cells(for event: MeetingEvent, mode: TodayHeroMode, now: Date) -> [TurfCell.Kind] {
        let total = event.end.timeIntervalSince(event.start)
        let count = min(16, max(1, Int((total / 900).rounded(.up))))
        switch mode {
        case .calm:
            let kind = event.end <= now ? TurfCell.Kind.meetingPast : TurfCell.Kind.teal
            return Array(repeating: kind, count: count)
        case .zero:
            return Array(repeating: TurfCell.Kind.black, count: count)
        case .event:
            guard event.start <= now, total > 0 else { return Array(repeating: TurfCell.Kind.black, count: count) }
            let done = min(count, max(0, Int((now.timeIntervalSince(event.start) / total * Double(count)).rounded())))
            return Array(repeating: TurfCell.Kind.black, count: done)
                + Array(repeating: TurfCell.Kind.blackDots, count: count - done)
        }
    }
}

/// 明日の最初の会議(今日の会議がもう無いとき)。静の卡に TOMORROW + 曜日、開始時刻、明日の神兽
private struct TodayTomorrowHero: View {
    let event: MeetingEvent
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)
    static let weekday = Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide)

    var body: some View {
        let day = event.start.formatted(Self.weekday)
        let minutes = max(1, Int((event.end.timeIntervalSince(event.start) / 60).rounded()))
        let count = min(16, max(1, Int((Double(minutes) / 15).rounded(.up))))
        TodayHeroCard(mode: .calm, creature: Myth.heroCreature(for: event.start)) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TodayShout(word: "TOMORROW", black: false)
                StencilWord(id: "dayshout-\(day.lowercased())-white-night", fallback: day.uppercased(),
                            fallbackSize: 21, fallbackColor: Palette.white)
            }
        } main: {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(TypeRole.cardTitle)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                TodayNumeral(value: event.start.formatted(Self.time), unit: .bare, black: false)
                    .padding(.top, 20)
                TodayDurationRow(kinds: Array(repeating: TurfCell.Kind.empty, count: count)) {
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
                .padding(.top, 16)
            }
        }
    }
}

/// 今日も明日も会議がない:静の卡に一行 + 提醒の説明、右に今日の神兽
private struct TodayEmptyHero: View {
    let title: String
    let hint: String

    var body: some View {
        TodayHeroCard(mode: .calm, creature: Myth.heroCreature(for: Date()), creatureMaxHeight: 112) {
            EmptyView()
        } main: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(TypeRole.cardTitle)
                    .foregroundStyle(Palette.text)
                Text(hint)
                    .font(TypeRole.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CalendarAccessHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("需要日历权限")
                .font(TypeRole.cardTitle)
                .foregroundStyle(Palette.text)
            Text("用来显示会议、提前提醒，以及查找シャチョケン")
                .font(TypeRole.caption)
                .foregroundStyle(Palette.textSecondary)
            Button("打开系统设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(SprayButtonStyle(kind: .orange, height: 44))
            .padding(.top, 10)
        }
        .padding(Turf.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .material("hero-calm-night", fallback: Palette.black)
        .environment(\.intensity, .calm)
    }
}

// MARK: - 盤面(9:00–18:00、15 分 × 36 格)

private enum TodayBoardMetrics {
    static let startHour = 9
    static let endHour = 18
    static let cellWidth: CGFloat = 10.5
    static let gap: CGFloat = 2
    static let groupGap: CGFloat = 5

    /// i 番目の格の左端(4 格ごとに group gap)
    static func cellX(_ i: Int) -> CGFloat {
        CGFloat(i) * (cellWidth + gap) + CGFloat(i / 4) * (groupGap - gap)
    }
}

/// 今日の盤面。灰 = 会議(過ぎたら暗く)、青 = 選んだ会議(進行中は過ぎた分が満・残りが点)、橙の刻み = いま。
/// 9–18 の外の会議は載らない。下に時刻(9 は左寄せ、18 は右寄せ、今の時は太字)
private struct TodayDayBoard: View {
    let events: [MeetingEvent]
    let selectedID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let kinds = Self.kinds(events: events, selectedID: selectedID, now: now)
            let hour = Calendar.current.component(.hour, from: now)
            let current = hour >= TodayBoardMetrics.startHour && hour < TodayBoardMetrics.endHour ? hour : -1
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: TodayBoardMetrics.gap) {
                    ForEach(0..<kinds.count, id: \.self) { i in
                        TurfCell(kind: kinds[i])
                            .padding(.leading, i > 0 && i % 4 == 0 ? TodayBoardMetrics.groupGap - TodayBoardMetrics.gap : 0)
                    }
                }
                .frame(width: Turf.contentWidth, height: 20, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    if let x = Self.nowX(now) {
                        TodayNowNotch(x: x)
                    }
                }
                hourLabels(current: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天 9:00–18:00 的会议")
    }

    private func hourLabels(current: Int) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<10, id: \.self) { k in
                let hour = TodayBoardMetrics.startHour + k
                let label = Text(String(hour))
                    .font(hour == current ? TypeRole.boardLabelNow : TypeRole.boardLabel)
                    .foregroundStyle(hour == current ? Palette.text : Palette.textSecondary)
                if k == 0 {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                } else if k == 9 {
                    label.frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    // 時の境目(group gap の真ん中)に中央をそろえる
                    label
                        .fixedSize()
                        .position(x: TodayBoardMetrics.cellX(k * 4) - TodayBoardMetrics.groupGap / 2, y: 8)
                }
            }
        }
        .frame(width: Turf.contentWidth, height: 16)
    }

    /// 36 格の状態(会議・選択・経過は DayTimeline のまま。進行中の選択だけ満 / 点に分ける)
    static func kinds(events: [MeetingEvent], selectedID: String?, now: Date) -> [TurfCell.Kind] {
        let slots = DayTimeline.slots(events: events,
                                      start: (hour: TodayBoardMetrics.startHour, minute: 0),
                                      end: (hour: TodayBoardMetrics.endHour, minute: 0),
                                      now: now, selectedID: selectedID)
        let selected = events.first { $0.id == selectedID }
        let live = selected.map { $0.start <= now && now < $0.end } ?? false
        let from = Calendar.current.date(bySettingHour: TodayBoardMetrics.startHour, minute: 0, second: 0, of: now) ?? now
        return slots.enumerated().map { pair -> TurfCell.Kind in
            let slot = pair.element
            if slot.selected {
                guard live else { return .teal }
                // 格の半分以上が過ぎたら満
                let middle = from.addingTimeInterval(Double(pair.offset) * 900 + 450)
                return middle <= now ? .teal : .tealDots
            }
            if slot.meeting { return slot.past ? .meetingPast : .meeting }
            return slot.past ? .past : .empty
        }
    }

    /// いまの x(9:00 より前・18:00 以降は nil)
    static func nowX(_ now: Date) -> CGFloat? {
        guard let from = Calendar.current.date(bySettingHour: TodayBoardMetrics.startHour, minute: 0, second: 0,
                                               of: now) else { return nil }
        let minutes = now.timeIntervalSince(from) / 60
        let span = Double((TodayBoardMetrics.endHour - TodayBoardMetrics.startHour) * 60)
        guard minutes >= 0, minutes < span else { return nil }
        let cell = Int(minutes / 15)
        let fraction = CGFloat((minutes - Double(cell) * 15) / 15)
        return TodayBoardMetrics.cellX(cell) + fraction * TodayBoardMetrics.cellWidth
    }
}

/// いまの刻み(橙 2pt + 上の 9×6 の三角、黒漆の縁。青に橙を直接触れさせない)。下へ 4pt はみ出す
private struct TodayNowNotch: View {
    let x: CGFloat

    var body: some View {
        if let asset = Material.asset("now-notch-night"), Material.image("now-notch-night") != nil {
            let size = asset.layoutSize
            // 配置の枠の下端 = 格の下 + 4pt
            MaterialSprite(id: "now-notch-night")
                .offset(x: x - size.width / 2, y: 24 - size.height)
        } else {
            VStack(spacing: 0) {
                TodayNotchTriangle()
                    .fill(Palette.orange)
                    .overlay { TodayNotchTriangle().stroke(Palette.black, lineWidth: 1) }
                    .frame(width: 9, height: 6)
                Rectangle()
                    .fill(Palette.orange)
                    .frame(width: 2, height: 24)
                    .padding(.horizontal, 1)
                    .background(Palette.black)
            }
            .offset(x: x - 4.5, y: -6)
        }
    }
}

/// 下向きの三角
private struct TodayNotchTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 日程

/// 今日日程(会議の一覧)。行を押すとその会議を選ぶ(加入は上の主角卡から)
private struct ScheduleList: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                Text("没有安排")
                    .font(TypeRole.body)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.leading, 18)
                    .frame(height: Turf.scheduleRow)
            }
            ForEach(events) { event in
                EventRow(event: event, selected: event.id == selectedID) {
                    select(event.id)
                }
            }
        }
    }
}

/// 1 行 40pt:時刻(等幅)・件名(1 行、はみ出しは …)・线上なら摄像机。選んだ行は左に 6pt の青い帯 + 青い時刻、ホバーは少し明るい混凝土
private struct EventRow: View {
    let event: MeetingEvent
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let past = event.end < Date()
        let main: Color = past ? Palette.textSecondary : Palette.text
        Button(action: action) {
            HStack(spacing: 14) {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(TodayFont.scheduleTime)
                    .foregroundStyle(selected ? Palette.teal : main)
                    .frame(width: 48, alignment: .leading)
                Text(event.title)
                    .font(TypeRole.body)
                    .fontWeight(selected ? .bold : .medium)
                    .foregroundStyle(main)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            .background(hovering ? Palette.rowHover : Color.clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle()
                        .fill(Palette.teal)
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

// MARK: - 当前任务(1 つずつが「もの」)

/// 当前任务。各タスクは左のチェックボックスで完成(メモから消す・直後なら撤销)。
/// 一覧ごとの操作は「任务 N」の行を押して書き換え(テキスト。書くそばから保存するので閉じても消えない)
private struct TaskList: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""
    @State private var captionHovering = false

    var body: some View {
        let blocks = TaskOutline.blocks(coordinator.settings.taskMemo)
        VStack(alignment: .leading, spacing: 0) {
            if editing {
                HStack(alignment: .center, spacing: 8) {
                    caption(blocks.count)
                        .padding(.leading, 12)
                    Spacer(minLength: 8)
                    Button("完成") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(SprayButtonStyle(kind: .orange, height: 32))
                }
                TextEditor(text: $draft)
                    .font(TypeRole.body)
                    .foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 150)
                    .background(Palette.cellPastFill)
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
                // 区切りの一行(任务 N)。押すと書き換え
                Button(action: startEditing) {
                    HStack(alignment: .center, spacing: 8) {
                        caption(blocks.count)
                        Spacer(minLength: 8)
                        if captionHovering {
                            Text("编辑")
                                .font(TypeRole.sectionCaption)
                                .foregroundStyle(Palette.text)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(captionHovering ? Palette.rowHover : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { captionHovering = $0 }
                .help("编辑任务（直接改写备忘）")
                .accessibilityLabel("编辑任务")

                if blocks.isEmpty {
                    Button(action: startEditing) {
                        HStack(alignment: .center, spacing: 14) {
                            HandCheckbox(checked: true)
                            Text("写下现在在做的事")
                                .font(Typeface.cjk(14, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                            TaskRow(block: block) {
                                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                    coordinator.completeTask(at: index)
                                }
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
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
        }
    }

    /// 「任务 2」(12pt の次要色)
    private func caption(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("任务")
                .font(TypeRole.sectionCaption)
                .tracking(0.7)
            Text(String(count))
                .font(TypeRole.count)
        }
        .foregroundStyle(Palette.textSecondary)
    }

    private func startEditing() {
        draft = coordinator.settings.taskMemo
        editing = true
    }
}

/// タスク 1 つ:左の手刻みのチェックボックスで完成(ホバーで勾选の予告)。タスク名と、中身を 1 行にまとめたもの
private struct TaskRow: View {
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
                    .font(Typeface.cjk(15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(TypeRole.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .help(rest.map { String(repeating: "  ", count: max(0, $0.depth - 1)) + $0.text }
                            .joined(separator: "\n"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - 英語タブの上:近い会議

/// 英語タブを開いていても、開始 30 分前から会議を見失わない(黒漆の遮块 1 行。色面は単語カードに譲る)
private struct MeetingStrip: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let event = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: context.date),
               event.start.timeIntervalSince(context.date) < 30 * 60 {
                let running = event.start <= context.date
                let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
                HStack(alignment: .center, spacing: 12) {
                    TodayShout(word: running ? "NOW" : "NEXT", black: false)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(countdown.value)
                            .font(TypeRole.time)
                        Text(countdown.unit)
                            .font(Typeface.cjk(13, weight: .bold))
                    }
                    .foregroundStyle(Palette.text)
                    .fixedSize()
                    Text(event.title)
                        .font(Typeface.cjk(13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if let url = event.joinURL {
                        Button("加入会议") { NSWorkspace.shared.open(url) }
                            .buttonStyle(FrameButtonStyle(height: 34))
                            .help(url.host ?? "加入会议")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .material("plate-black-night", fallback: Palette.cellPastFill)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - 底栏:坐姿・シャチョケン・电源

private struct PanelFooter: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            if coordinator.settings.postureEnabled && coordinator.isWorkingNow {
                PostureStatus(coordinator: coordinator)
            }
            if coordinator.calendarAuthorized {
                ShachokenStatus(event: coordinator.nextShachoken,
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
            PowerButton()
        }
        .frame(height: Turf.iconButton)
    }
}

/// 电源(退出)。按两下才退出(以免误点后会议提醒和站立提醒都停掉)。上膛した状態は橙の遮块に黒いアイコン
private struct PowerButton: View {
    @State private var armed = false
    @State private var hovering = false

    var body: some View {
        Button {
            if armed {
                NSApp.terminate(nil)
            } else {
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { armed = true }
            }
        } label: {
            StencilIconView(icon: .power, size: 19)
                .foregroundStyle(armed ? Palette.black : (hovering ? Palette.text : Palette.textSecondary))
                .frame(width: Turf.iconButton, height: Turf.iconButton)
                .background {
                    if armed {
                        MaterialSlice(id: "tag-orange-night", fallback: Palette.orange)
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
            withAnimation { armed = false }
        }
        .help(armed ? "再按一次退出" : "退出 Yudh（按两下，或 ⌘Q）。设置：⌘,")
        .accessibilityLabel(armed ? "再按一次退出" : "退出 Yudh")
    }
}

/// 坐姿:椅子(立っていれば人)の模板アイコン + 「已坐 47 分钟」。到点了は橙の遮喷の札。点击打开屏幕上方的小窗(文は help に)
private struct PostureStatus: View {
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
private struct ShachokenStatus: View {
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
