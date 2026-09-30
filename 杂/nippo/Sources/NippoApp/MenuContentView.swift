import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-09 v10「Phantom Glass」)。ガラスの窓に切り紙の札を並べる。上から「いま大事な順」:
/// 上の帯(曜日の札・工作时间の絵文字・ガラスの切り替え)→ 関卡カード(次の会議 / 単語)→ 褶皺の時間線 → 今日日程(メニュー)→ 当前任务(メニュー)→ 下のガラスの帯(絵文字だけ)。
/// 一画面に一枚の色面:今日も英语も青(選んだ会議が 5 分以内・進行中なら橙)。数字の墨迹は反対の色。
/// 窓は画面の中央に浮き、曜日の札を掴んで動かせる(MainPanelController)。
/// OOUI:会議・タスク・単語という「もの」を一覧から選び、そのものに付いた操作をする。画面の文字は中国語、短いラベルと掛け声は英語
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("panelTab") private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360
    /// 今日の日程で選んだ会議(nil = 次の会議)
    @State private var selectedMeetingID: String?

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 200
    }

    /// 今日タブの関卡:選んだ会議(既定は次の会議)が開始 5 分以内か進行中なら橙、それ以外は青(夜は少し落とす)
    private var todayLevel: Level {
        let now = Date()
        let calm = Level.today(night: Theme.isNight(now))
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: now)
        guard let selected = events.first(where: { $0.id == selectedMeetingID && $0.end > now }) ?? next,
              selected.end > now else { return calm }
        return selected.start.timeIntervalSince(now) <= 5 * 60 ? Level.urgent(night: Theme.isNight(now)) : calm
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.horizontal, Theme.padding)
                .padding(.top, 16)

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
                .padding(.horizontal, Theme.padding)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight, maxHeight))
            // 初回レイアウト前の 0 は無視(高さ 0 に潰れないように)
            .onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }

            PanelFooter(coordinator: coordinator)
                .padding(.horizontal, Theme.padding)
                .padding(.bottom, 12)
        }
        .frame(width: Theme.panelWidth)
        // 窓そのものが Liquid Glass(机が透ける)。文字は札の上に置く
        .glassEffect(.regular.tint(Theme.stage.opacity(0.62)), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Theme.locale)
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

// MARK: - 上の帯:曜日・工作时间・タブ

/// 曜日は英語の大文字だけ(TUESDAY)、傾いた白い札に。月日はどこにも出さない
private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab
    @Environment(\.level) private var level
    @State private var workError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Text(Date(), format: Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide))
                        .textCase(.uppercase)
                        .font(Theme.shout(15))
                        .tracking(0.6)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(PhantomPlate().fill(Theme.paper))
                        .rotationEffect(.degrees(-4))
                    if let reason = coordinator.quietReasonToday {
                        Text("休息日 · \(reason)")
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(Theme.textFaint)
                            .help("今天是\(reason)：会议提醒和站立提醒都已暂停")
                    }
                }
                .fixedSize()
                .padding(.vertical, 4)
                // ここを掴むと窓が動く
                .background(WindowDragArea())
                .help("拖动这里可以移动窗口")
                // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
                WorkTime(coordinator: coordinator, allowsInput: tab == .today, error: $workError) {
                    tab = .today
                }
                Spacer(minLength: 8)
                PillTabs(items: [
                    TabItem(value: PanelTab.today, title: "今日", shortcut: "1"),
                    TabItem(value: PanelTab.english, title: "英语",
                            badge: english.loaded ? english.remainingTotal : nil, shortcut: "2"),
                ], selection: $tab, color: level.color)   // 選んだ瓦片は今の関卡色(朱红なら朱红)
            }
            if let workError, tab == .today {
                Text(workError)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.white)
            }
        }
    }
}

/// 工作时间(出勤時刻は手入力。勤怠システムとは連携しない)。小さく 1 行で。
/// 入力済みなら 公文包の絵文字 + 3:12(押すと修正)、未入力なら今日タブではその場に小さな入力欄
private struct WorkTime: View {
    @ObservedObject var coordinator: AppCoordinator
    let allowsInput: Bool
    @Binding var error: String?
    let showToday: () -> Void
    @State private var input = ""
    @State private var editing = false
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
                    HStack(spacing: 5) {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(Self.clock(context.date.timeIntervalSince(began)))
                            .font(Theme.font(13, .bold).monospacedDigit())
                    }
                    .foregroundStyle(Theme.white)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help("\(began.formatted(Self.time)) 上班，已工作 \(WorkStart.durationText(from: began, to: context.date))。点击修改上班时间")
            }
        } else if !allowsInput {
            Button(action: showToday) {
                Text("填写上班时间")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("去「今日」填写上班时间")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "briefcase")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.white)
                    .help("上班时间")
                TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.textSoft))
                    .font(Theme.font(13, .semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 52, height: 24)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.white)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit(save)
                    .help("8:53 上班就输入 853，按回车")
                if editing {
                    Button("取消") {
                        editing = false
                        error = nil
                    }
                    .buttonStyle(.command(.quiet, height: 24))
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
        let settings = coordinator.settings
        let start = settings.timeComponents(settings.workStartTime, fallback: (9, 0))
        let end = settings.timeComponents(settings.workEndTime, fallback: (18, 0))

        VStack(alignment: .leading, spacing: 0) {
            // 主役:選んだ会議(既定は次の会議)
            Group {
                if !coordinator.calendarAuthorized {
                    CalendarAccessHero()
                } else if let selected {
                    MeetingHero(event: selected, isNext: selected.id == next?.id)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今天没有会议")
                            .font(Theme.font(22, .semibold))
                        Text("工作日会在会议开始前 \(settings.reminderLeadMinutes) 分钟提醒你")
                            .font(Theme.font(13, .regular))
                            .foregroundStyle(Theme.textSoft)
                    }
                    .card()
                }
            }

            // 褶皺の時間線:勤務時間を 15 分ごとに。灰は会議、関卡色は選んだ会議。文字は載せない
            if coordinator.calendarAuthorized {
                let slots = DayTimeline.slots(events: events, start: start, end: end, now: now,
                                              selectedID: selected?.id)
                if !slots.isEmpty {
                    HStack(spacing: 10) {
                        PleatGauge(states: slots.map { slot -> PleatState in
                            if slot.selected { return .selected }
                            if slot.meeting { return slot.past ? .pastMeeting : .meeting }
                            return slot.past ? .past : .empty
                        })
                        Text(String(format: "%d:%02d – %d:%02d", start.hour, start.minute, end.hour, end.minute))
                            .font(Theme.font(12, .semibold).monospacedDigit())
                            .foregroundStyle(Theme.textFaint)
                            .fixedSize()
                    }
                    .padding(.top, 10)
                    .help("今天的工作时段，每格 15 分钟。灰格是会议，关卡色的格是选中的会议")
                }
            }

            ScheduleList(events: events, selectedID: selected?.id) { id in
                // 次の会議を選び直したら既定に戻す(時間が進むと自動で次へ移る)
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    selectedMeetingID = id == next?.id ? nil : id
                }
            }
            .padding(.top, 22)

            TaskList(coordinator: coordinator)
                .padding(.top, 20)
        }
    }
}

/// 主役:会議 1 つ。色布(看)に件名、里布(做)に墨迹に載った残り時間と「加入会议」。終わった会議は灰いカード
private struct MeetingHero: View {
    let event: MeetingEvent
    let isNext: Bool
    @Environment(\.level) private var level
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let running = event.start <= now && now < event.end
            let past = event.end <= now
            let countdown: (value: String, unit: String) =
                past ? ("—", "已结束") : NextEventPolicy.heroCountdown(for: event, now: now)
            let kicker: String = running ? "NOW" : (past ? "DONE" : (isNext ? "NEXT" : "LATER"))
            let span = "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
            SeamLayout {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(lead: kicker, text: span)
                    Text(event.title)
                        .font(Theme.font(22, .semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
            } right: {
                VStack(alignment: .trailing, spacing: 12) {
                    if past {
                        BigNumber(value: countdown.value, unit: countdown.unit, color: Theme.textFaint)
                    } else {
                        SplatNumber(unit: countdown.unit) {
                            Text(countdown.value)
                                .contentTransition(.numericText())
                        }
                    }
                    if let url = event.joinURL, !past {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("加入会议", systemImage: "video.fill")
                        }
                        .buttonStyle(.command(.primary, wide: true))
                        .keyboardShortcut(.defaultAction)
                        .help("\(url.host ?? "加入会议")（⏎）")
                    } else if event.joinURL == nil, !past {
                        Text("没有线上链接")
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(Theme.textSoft)
                    }
                }
            }
            .hero(seam: !past)
            .environment(\.level, past ? .done : level)
        }
    }
}

private struct CalendarAccessHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("需要日历权限")
                .font(Theme.font(22, .semibold))
            Text("用来显示会议、提前提醒，以及查找シャチョケン")
                .font(Theme.font(13, .regular))
                .foregroundStyle(Theme.textSoft)
            Button("打开系统设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.command(.primary))
            .padding(.top, 10)
        }
        .card()
    }
}

/// 今日日程(会議の一覧)。行を押すとその会議を選ぶ(加入は上のカードから)
private struct ScheduleList: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "SCHEDULE", symbol: "calendar") {
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(Theme.font(12, .bold).monospacedDigit())
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .padding(.bottom, 4)
            if events.isEmpty {
                Text("没有安排")
                    .font(Theme.font(15, .regular))
                    .foregroundStyle(Theme.textSoft)
                    .frame(height: 34)
            }
            ForEach(events) { event in
                EventRow(event: event, selected: event.id == selectedID) {
                    select(event.id)
                }
            }
        }
    }
}

/// 1 行 = 1 枚の札:時刻・件名・摄像机(线上)。選んだ行は関卡色の札に ▶、ホバーは白い札
private struct EventRow: View {
    let event: MeetingEvent
    let selected: Bool
    let action: () -> Void
    @Environment(\.level) private var level
    @State private var hovering = false

    var body: some View {
        let past = event.end < Date()
        let onPaper = selected || hovering
        let main: Color = onPaper ? Theme.ink : (past ? Theme.textFaint : Theme.white)
        let soft: Color = onPaper ? Theme.ink.opacity(0.7) : (past ? Theme.textFaint : Theme.textSoft)
        Button(action: action) {
            HStack(spacing: 12) {
                if selected {
                    Text("▶")
                        .font(Theme.shout(9))
                        .foregroundStyle(main)
                }
                Text(event.start, format: .dateTime.hour().minute())
                    .font(Theme.font(14, .semibold).monospacedDigit())
                    .foregroundStyle(soft)
                    .frame(width: 44, alignment: .leading)
                Text(event.title)
                    .font(Theme.font(15, selected ? .bold : .medium))
                    .foregroundStyle(main)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if event.joinURL != nil && !past {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(soft)
                        .help("线上会议")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(PhantomPlate().fill(selected ? level.color : (hovering ? Theme.paper : Theme.plate)))
            .contentShape(PhantomPlate())
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
/// 一覧ごとの操作は「编辑」(テキストで書き換え。書くそばから保存するので閉じても消えない)
private struct TaskList: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.level) private var level
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "TASKS", symbol: "checklist") {
                if editing {
                    Button("完成") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(.command(.primary, height: 24))
                } else {
                    Button("编辑") {
                        draft = coordinator.settings.taskMemo
                        editing = true
                    }
                    .buttonStyle(.command(.quiet, height: 20))
                }
            }
            .padding(.bottom, 6)
            if editing {
                TextEditor(text: $draft)
                    .font(Theme.font(14, .regular))
                    .foregroundStyle(Theme.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 150)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.blockRadius, style: .continuous))
                    .onChange(of: draft) { _, text in
                        coordinator.settings.taskMemo = text
                    }
                Text("任务名顶格写，内容用 Tab 缩进（或以「- 」开头），空行分隔任务")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                let blocks = TaskOutline.blocks(coordinator.settings.taskMemo)
                if blocks.isEmpty {
                    Text("写下现在在做的事")
                        .font(Theme.font(15, .regular))
                        .foregroundStyle(Theme.textSoft)
                        .frame(height: 30)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        TaskRow(block: block) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                coordinator.completeTask(at: index)
                            }
                        }
                    }
                }
                if let done = coordinator.lastCompletedTask {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(level.color)
                        Text("已完成「\(done.title)」")
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button("撤销") { coordinator.undoCompleteTask() }
                            .buttonStyle(.command(.quiet, height: 20))
                    }
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
        }
    }
}

/// タスク 1 つ = 1 枚の黒い札:左の(傾いた)チェックボックスで完成。タスク名と、中身を 1 行にまとめたもの
private struct TaskRow: View {
    let block: TaskOutline.Block
    let complete: () -> Void
    @Environment(\.level) private var level
    @State private var hovering = false

    var body: some View {
        let title = block.title ?? block.items.first?.text ?? ""
        let rest = block.title == nil ? Array(block.items.dropFirst()) : block.items
        let detail = rest.map(\.text).joined(separator: " · ")
        HStack(alignment: .top, spacing: 12) {
            Button(action: complete) {
                PhantomPlate(skew: 3)
                    .stroke(hovering ? level.color : Theme.paper, lineWidth: 2)
                    .background(PhantomPlate(skew: 3).fill(hovering ? level.color : Color.clear))
                    .overlay {
                        if hovering {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("完成（从备忘里移除）")
            .accessibilityLabel("完成")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Theme.font(13, .regular))
                        .foregroundStyle(Theme.textSoft)
                        .lineLimit(2)
                        .help(rest.map { String(repeating: "  ", count: max(0, $0.depth - 1)) + $0.text }
                            .joined(separator: "\n"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(PhantomPlate().fill(Theme.plate))
    }
}

// MARK: - 英語タブの上:近い会議

/// 英語タブを開いていても、開始 30 分前から会議を見失わない(灰いカード 1 行。色面は単語カードに譲る)
private struct MeetingStrip: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let event = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: context.date),
               event.start.timeIntervalSince(context.date) < 30 * 60 {
                let running = event.start <= context.date
                let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
                HStack(spacing: 10) {
                    Eyebrow(lead: running ? "NOW" : "NEXT")
                        .foregroundStyle(Theme.white)
                    Text(countdown.value + countdown.unit)
                        .font(Theme.font(13, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.white)
                        .fixedSize()
                    Text(event.title)
                        .font(Theme.font(13, .regular))
                        .foregroundStyle(Theme.textSoft)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let url = event.joinURL {
                        Button("加入会议") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.command(.secondary, height: 28))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(PhantomPlate().fill(Theme.plate))
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - 下の 1 行:坐姿・シャチョケン・电源

private struct PanelFooter: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
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
        .glassBar()
        .padding(.top, 14)
    }
}

/// 电源(退出)。按两下才退出(以免误点后会议提醒和站立提醒都停掉)。上膛した状態は関卡色
private struct PowerButton: View {
    @State private var armed = false

    var body: some View {
        Button {
            if armed {
                NSApp.terminate(nil)
            } else {
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { armed = true }
            }
        } label: {
            Image(systemName: armed ? "power.circle.fill" : "power")
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.commandSquare(armed ? .primary : .quiet, size: 24))
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

/// 坐姿:椅子の絵文字 + 分。到点了ら橙になって菱形が付く。点击打开屏幕上方的小窗(文は help に)
private struct PostureStatus: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.level) private var level
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
                HStack(spacing: 5) {
                    Image(systemName: standing ? "figure.stand" : "chair.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(minutes)")
                        .font(Theme.font(13, .bold).monospacedDigit())
                    if due {
                        Rectangle()
                            .fill(Theme.orange)
                            .frame(width: 7, height: 7)
                            .rotationEffect(.degrees(45))
                    }
                }
                .foregroundStyle(due ? Theme.orange : Theme.white)
                .lineLimit(1)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help(standing ? "已站 \(minutes) 分钟，\(dueAt) 坐下。点击打开拉伸步骤"
                           : "已坐 \(minutes) 分钟，\(dueAt) 站起来\(due ? "（该站起来了）" : "")。点击打开「站起来了吗？」小窗")
        }
    }
}

/// 下一次シャチョケン(26卒_新卒社長研修,日历里 90 天内)。一个月只看两三次,所以小小的。
/// 具体的な日付はここにも出さない(何天后 + 曜日 + 時刻)
private struct ShachokenStatus: View {
    let event: MeetingEvent?
    let keyword: String
    static let weekday = Date.FormatStyle(locale: Theme.weekdayLocale).weekday(.wide)
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 5) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12, weight: .bold))
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    Text("\(countdown.value)\(countdown.unit)")
                        .font(Theme.font(13, .bold).monospacedDigit())
                } else {
                    Text("—")
                        .font(Theme.font(13, .bold))
                }
            }
            .foregroundStyle(event == nil ? Theme.textSoft : Theme.white)
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
