import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-09 v6)。主役は 1 つ:
/// 今日タブ = 次の会議(件名・加入・インクの上の残り時間)、英語タブ = 単語カード。ほかは灰色で静かに。
/// OOUI:会議・タスク・単語という「もの」を一覧から選び、そのものに付いた操作をする。
/// 画面の文字は中国語(簡体字)
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("panelTab") private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360
    /// 今日の日程で選んだ会議(nil = 次の会議)
    @State private var selectedMeetingID: String?

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 200
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.horizontal, Theme.padding)
                .padding(.top, 14)

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
                .padding(.vertical, 12)
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
        .background(Theme.stage)
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
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - 上の帯:日付・タブ・工作时间

private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Date(), format: .dateTime.month().day())
                    .font(Theme.font(17, .bold))
                    .foregroundStyle(Theme.white)
                Text(Date(), format: .dateTime.weekday(.abbreviated))
                    .font(Theme.font(15, .medium))
                    .foregroundStyle(Theme.textSoft)
                if let reason = coordinator.quietReasonToday {
                    Text("休息日 · \(reason)")
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.lime)
                        .help("今天是\(reason)：会议提醒和站立提醒都已暂停")
                }
            }
            .fixedSize()
            Spacer(minLength: 8)
            UnderlineTabs(items: [
                TabItem(value: PanelTab.today, title: "今日", shortcut: "1"),
                TabItem(value: PanelTab.english, title: "英语",
                        badge: english.loaded ? english.remainingTotal : nil, shortcut: "2"),
            ], selection: $tab)
            // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
            WorkTime(coordinator: coordinator, allowsInput: tab == .today) {
                tab = .today
            }
        }
    }
}

/// 工作时间(出勤時刻は手入力。勤怠システムとは連携しない)。
/// 入力済みなら「已工作 3小时12分」(押すと修正)、未入力なら今日タブではその場に入力欄
private struct WorkTime: View {
    @ObservedObject var coordinator: AppCoordinator
    let allowsInput: Bool
    let showToday: () -> Void
    @State private var input = ""
    @State private var editing = false
    @State private var error: String?
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    init(coordinator: AppCoordinator, allowsInput: Bool, showToday: @escaping () -> Void) {
        self.coordinator = coordinator
        self.allowsInput = allowsInput
        self.showToday = showToday
    }

    var body: some View {
        if let began = coordinator.workBeganAt, !(editing && allowsInput) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Button {
                    input = ""
                    error = nil
                    editing = true
                    showToday()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("已工作")
                            .font(Theme.font(13, .medium))
                            .foregroundStyle(Theme.textSoft)
                        Text(WorkStart.durationText(from: began, to: context.date))
                            .font(Theme.font(14, .bold).monospacedDigit())
                            .foregroundStyle(Theme.white)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help("\(began.formatted(Self.time)) 上班。点击修改上班时间")
            }
        } else if !allowsInput {
            Button(action: showToday) {
                Text("未填上班时间")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.lime)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("去「今日」填写上班时间")
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(editing ? "修改上班时间" : "上班时间")
                        .font(Theme.font(13, .medium))
                        .foregroundStyle(Theme.textSoft)
                    TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.textFaint))
                        .textFieldStyle(.plain)
                        .font(Theme.font(15, .bold).monospacedDigit())
                        .foregroundStyle(Theme.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 56, height: 28)
                        .background(Theme.tile)
                        .overlay(alignment: .bottom) { Theme.lime.frame(height: 2) }
                        .onSubmit(save)
                        .help("8:53 上班就输入 853，按回车")
                    Button("记录", action: save)
                        .buttonStyle(.command(.primary, height: 28))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing {
                        Button("取消") {
                            editing = false
                            error = nil
                        }
                        .buttonStyle(.command(.quiet, height: 28))
                    }
                }
                if let error {
                    Text(error)
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.lime)
                }
            }
            .fixedSize()
        }
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
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: Date())
        let selected = events.first { $0.id == selectedMeetingID } ?? next

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
                            .font(Theme.font(26, .bold))
                            .foregroundStyle(Theme.white)
                        Text("工作日会在会议开始前 \(coordinator.settings.reminderLeadMinutes) 分钟提醒你")
                            .font(Theme.font(14, .medium))
                            .foregroundStyle(Theme.textSoft)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)

            Theme.hairline.frame(height: 1)

            HStack(alignment: .top, spacing: 28) {
                ScheduleList(events: events, selectedID: selected?.id) { id in
                    // 次の会議を選び直したら既定に戻す(時間が進むと自動で次へ移る)
                    withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                        selectedMeetingID = id == next?.id ? nil : id
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                TaskList(coordinator: coordinator)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 14)
        }
    }
}

/// 主役:会議 1 つ。左に件名と「加入会议」、右に黄緑のインクの上の残り時間
private struct MeetingHero: View {
    let event: MeetingEvent
    let isNext: Bool
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let running = event.start <= now && now < event.end
            let past = event.end <= now
            let countdown: (value: String, unit: String) =
                past ? ("—", "已结束") : NextEventPolicy.heroCountdown(for: event, now: now)
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(running ? "进行中" : (isNext ? "下一个会议" : "选中的会议"))
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.lime)
                        Text("\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))")
                            .font(Theme.font(13, .medium).monospacedDigit())
                            .foregroundStyle(Theme.textSoft)
                    }
                    Text(event.title)
                        .font(Theme.font(26, .bold))
                        .foregroundStyle(Theme.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.bottom, 10)
                    if let url = event.joinURL, !past {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("加入会议", systemImage: "play.fill")
                        }
                        .buttonStyle(.command(.primary))
                        .help(url.host ?? "加入会议")
                    } else if event.joinURL == nil {
                        Text("这个会议没有线上链接")
                            .font(Theme.font(13, .medium))
                            .foregroundStyle(Theme.textSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SplatNumeral(value: countdown.value, unit: countdown.unit)
                    .frame(width: 170)
            }
        }
    }
}

private struct CalendarAccessHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要日历权限")
                .font(Theme.font(26, .bold))
                .foregroundStyle(Theme.white)
            Text("用来显示会议、提前提醒，以及查找シャチョケン")
                .font(Theme.font(14, .medium))
                .foregroundStyle(Theme.textSoft)
            Button("打开系统设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.command(.primary))
            .padding(.top, 6)
        }
    }
}

/// 今日日程(会議の一覧)。行を押すとその会議を選ぶ(加入は上の主役から)
private struct ScheduleList: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "今日日程") {
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(Theme.font(12, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSoft)
                }
            }
            if events.isEmpty {
                Text("没有安排")
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 4)
            }
            ForEach(events) { event in
                EventRow(event: event, selected: event.id == selectedID) {
                    select(event.id)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: MeetingEvent
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let past = event.end < Date()
        Button(action: action) {
            HStack(spacing: 8) {
                Text("▶")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(selected ? Theme.lime : Color.clear)
                    .frame(width: 10)
                Text(event.start, format: .dateTime.hour().minute())
                    .font(Theme.font(14, .semibold).monospacedDigit())
                    .foregroundStyle(past ? Theme.textFaint : (selected ? Theme.white : Theme.textSoft))
                    .strikethrough(past)
                    .frame(width: 42, alignment: .leading)
                Text(event.title)
                    .font(Theme.font(15, selected ? .bold : .medium))
                    .foregroundStyle(past ? Theme.textFaint : Theme.white)
                    .strikethrough(past)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if event.joinURL != nil && !past {
                    Text("线上")
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .padding(.trailing, 6)
            .frame(height: 32)
            .background(hovering && !selected ? Theme.tile : Color.clear)
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

/// 当前任务。各タスクは左の菱形で完成(メモから消す・直後なら撤销)。
/// 一覧ごとの操作は「编辑」(テキストで書き換え。書くそばから保存するので閉じても消えない)
private struct TaskList: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "当前任务") {
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
            if editing {
                TextEditor(text: $draft)
                    .font(Theme.font(14, .regular))
                    .foregroundStyle(Theme.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(Theme.tile)
                    .overlay(alignment: .bottom) { Theme.lime.frame(height: 2) }
                    .onChange(of: draft) { _, text in
                        coordinator.settings.taskMemo = text
                    }
                Text("任务名顶格写，内容用 Tab 缩进（或以「- 」开头），空行分隔任务")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let blocks = TaskOutline.blocks(coordinator.settings.taskMemo)
                if blocks.isEmpty {
                    Text("写下现在在做的事")
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 4)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        TaskRow(block: block) {
                            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                                coordinator.completeTask(at: index)
                            }
                        }
                    }
                }
                if let done = coordinator.lastCompletedTask {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Theme.lime)
                        Text("已完成「\(done.title)」")
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button("撤销") { coordinator.undoCompleteTask() }
                            .buttonStyle(.command(.quiet, height: 20))
                    }
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
        }
    }
}

/// タスク 1 つ:左の菱形で完成。タスク名と中身
private struct TaskRow: View {
    let block: TaskOutline.Block
    let complete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: complete) {
                Rectangle()
                    .fill(hovering ? Theme.lime : Color.clear)
                    .overlay(Rectangle().stroke(hovering ? Theme.lime : Theme.white.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(45))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("完成（从备忘里移除）")
            .accessibilityLabel("完成")
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }

            VStack(alignment: .leading, spacing: 2) {
                if let title = block.title {
                    Text(title)
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(Theme.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    Text(item.text)
                        .font(Theme.font(14, .regular))
                        .foregroundStyle(item.depth == 1 ? Theme.body : Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, CGFloat(max(0, item.depth - 1)) * 12)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - 英語タブの上:近い会議

/// 英語タブを開いていても、開始 30 分前から会議を見失わない
private struct MeetingStrip: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let event = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: context.date),
               event.start.timeIntervalSince(context.date) < 30 * 60 {
                let running = event.start <= context.date
                let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
                let lead: String = running ? "进行中" : countdown.value + countdown.unit
                HStack(spacing: 10) {
                    Text(lead)
                        .font(Theme.font(13, .bold).monospacedDigit())
                        .foregroundStyle(Theme.lime)
                    Text(event.title)
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(Theme.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("加入会议", systemImage: "play.fill")
                        }
                        .buttonStyle(.command(.primary, height: 28))
                    }
                }
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - 下の帯:坐姿・シャチョケン・电源

private struct PanelFooter: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
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
        .padding(.top, 10)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }
}

/// 电源(退出)。按两下才退出(以免误点后会议提醒和站立提醒都停掉)
private struct PowerButton: View {
    @State private var armed = false

    var body: some View {
        Button {
            if armed {
                NSApp.terminate(nil)
            } else {
                withAnimation(.spring(duration: 0.25, bounce: 0.5)) { armed = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { armed = false }
                }
            }
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .black))
        }
        .buttonStyle(.commandSquare(armed ? .primary : .ghost, size: 26))
        .help(armed ? "再按一次退出" : "退出 Yudh（按两下，或 ⌘Q）。设置：⌘,")
        .accessibilityLabel(armed ? "再按一次退出" : "退出 Yudh")
    }
}

/// 坐姿:「已坐 23 分钟 · 11:45 站起来」。到点了变成黄绿色。点击打开屏幕上方的小窗
private struct PostureStatus: View {
    @ObservedObject var coordinator: AppCoordinator
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = coordinator.posture == .standing
            let minutes = max(0, Int(context.date.timeIntervalSince(coordinator.postureSince) / 60))
            let due = context.date >= coordinator.postureDueAt
            let dueAt = coordinator.postureDueAt.formatted(Self.time)
            let detail: String = due ? (standing ? "· 该坐下了" : "· 该站起来了")
                                     : (standing ? "· \(dueAt) 坐下" : "· \(dueAt) 站起来")
            Button {
                coordinator.openPosturePrompt()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(standing ? "已站" : "已坐")
                        .foregroundStyle(Theme.textSoft)
                    Text("\(minutes) 分钟")
                        .font(Theme.font(13, .bold).monospacedDigit())
                        .foregroundStyle(Theme.white)
                    Text(detail)
                        .foregroundStyle(due ? Theme.lime : Theme.textSoft)
                }
                .font(Theme.font(13, .medium))
                .lineLimit(1)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help(standing ? "打开拉伸步骤" : "打开「站起来了吗？」小窗")
        }
    }
}

/// 下一次シャチョケン(26卒_新卒社長研修,日历里 90 天内)。一个月只看两三次,所以小小的
private struct ShachokenStatus: View {
    let event: MeetingEvent?
    let keyword: String
    static let date = Date.FormatStyle(locale: Theme.locale).month(.defaultDigits).day().weekday(.abbreviated)
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("シャチョケン")
                    .foregroundStyle(Theme.textSoft)
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    Text("\(countdown.value)\(countdown.unit)")
                        .font(Theme.font(13, .bold))
                        .foregroundStyle(Theme.white)
                    Text("· \(event.start.formatted(Self.date))")
                        .foregroundStyle(Theme.textSoft)
                } else {
                    Text("暂无")
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .font(Theme.font(13, .medium))
            .lineLimit(1)
            .help(tooltip)
        }
    }

    private var tooltip: String {
        guard let event else { return "90 天内没有标题含「\(keyword)」的日程" }
        return "\(event.title)\n\(event.start.formatted(Self.date)) "
            + "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
    }
}
