import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-09 v7)。1 列で、上から「いま大事な順」:
/// 日付と工作时间(小さく)→ 主役のカード(次の会議 / 単語)→ 今日日程 → 当前任务 → 下の 1 行(坐姿・シャチョケン・电源)。
/// OOUI:会議・タスク・単語という「もの」を一覧から選び、そのものに付いた操作をする。
/// 画面の文字は中国語(簡体字)。短いラベルと掛け声は英語(NEXT・NICE!)
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

// MARK: - 上の帯:日付・工作时间・タブ

private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab
    @State private var workError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Date(), format: .dateTime.month().day())
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(Theme.white)
                    Text(Date(), format: .dateTime.weekday(.abbreviated))
                        .font(Theme.font(15, .regular))
                        .foregroundStyle(Theme.textSoft)
                    if let reason = coordinator.quietReasonToday {
                        Text("休息日 · \(reason)")
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(Theme.textSoft)
                            .help("今天是\(reason)：会议提醒和站立提醒都已暂停")
                    }
                }
                .fixedSize()
                // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
                WorkTime(coordinator: coordinator, allowsInput: tab == .today, error: $workError) {
                    tab = .today
                }
                Spacer(minLength: 8)
                PillTabs(items: [
                    TabItem(value: PanelTab.today, title: "今日", shortcut: "1"),
                    TabItem(value: PanelTab.english, title: "英语",
                            badge: english.loaded ? english.remainingTotal : nil, shortcut: "2"),
                ], selection: $tab)
            }
            if let workError, tab == .today {
                Text(workError)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.lime)
            }
        }
    }
}

/// 工作时间(出勤時刻は手入力。勤怠システムとは連携しない)。小さく 1 行で。
/// 入力済みなら「已工作 3小时12分」(押すと修正)、未入力なら今日タブではその場に小さな入力欄
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
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("已工作")
                            .foregroundStyle(Theme.textFaint)
                        Text(WorkStart.durationText(from: began, to: context.date))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSoft)
                    }
                    .font(Theme.font(12, .semibold))
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help("\(began.formatted(Self.time)) 上班。点击修改上班时间")
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
                Text("上班")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.textFaint)
                TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.textFaint))
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
                            .font(Theme.font(22, .semibold))
                            .foregroundStyle(Theme.white)
                        Text("工作日会在会议开始前 \(coordinator.settings.reminderLeadMinutes) 分钟提醒你")
                            .font(Theme.font(13, .regular))
                            .foregroundStyle(Theme.textSoft)
                    }
                    .card()
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

/// 主役:会議 1 つ。左に件名と「加入会议」、右に黄緑の大きな残り時間
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
            let kicker: String = running ? "NOW" : (past ? "DONE" : (isNext ? "NEXT" : "LATER"))
            let span = "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(lead: kicker, text: span)
                    Text(event.title)
                        .font(Theme.font(22, .semibold))
                        .foregroundStyle(Theme.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                    if let url = event.joinURL, !past {
                        Button("加入会议") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.command(.primary))
                            .help(url.host ?? "加入会议")
                            .padding(.top, 16)
                    } else if event.joinURL == nil {
                        Text("这个会议没有线上链接")
                            .font(Theme.font(12, .medium))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BigNumber(value: countdown.value, unit: countdown.unit,
                          color: past ? Theme.textFaint : Theme.lime)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            .card()
        }
    }
}

private struct CalendarAccessHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("需要日历权限")
                .font(Theme.font(22, .semibold))
                .foregroundStyle(Theme.white)
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
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "今日日程") {
                if !events.isEmpty {
                    Text("\(events.count)")
                        .font(Theme.font(12, .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.bottom, 4)
            if events.isEmpty {
                Text("没有安排")
                    .font(Theme.font(15, .regular))
                    .foregroundStyle(Theme.textFaint)
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

/// 1 行:時刻・件名・「线上」。選んだ行は左に黄緑の短い線
private struct EventRow: View {
    let event: MeetingEvent
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let past = event.end < Date()
        Button(action: action) {
            HStack(spacing: 14) {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(Theme.font(14, .medium).monospacedDigit())
                    .foregroundStyle(past ? Theme.textFaint : (selected ? Theme.white : Theme.textSoft))
                    .frame(width: 44, alignment: .leading)
                Text(event.title)
                    .font(Theme.font(15, selected ? .semibold : .regular))
                    .foregroundStyle(past ? Theme.textFaint : Theme.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if event.joinURL != nil && !past {
                    Text("线上")
                        .font(Theme.font(12, .medium))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .frame(height: 34)
            .background {
                if hovering && !selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.card)
                        .padding(.horizontal, -8)
                }
            }
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(Theme.lime)
                        .frame(width: 3, height: 16)
                        .offset(x: -12)
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
/// 一覧ごとの操作は「编辑」(テキストで書き換え。書くそばから保存するので閉じても消えない)
private struct TaskList: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.bottom, 6)
            if editing {
                TextEditor(text: $draft)
                    .font(Theme.font(14, .regular))
                    .foregroundStyle(Theme.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 150)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
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
                        .foregroundStyle(Theme.textFaint)
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
                            .foregroundStyle(Theme.lime)
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

/// タスク 1 つ:左のチェックボックスで完成。タスク名と、中身を 1 行にまとめたもの
private struct TaskRow: View {
    let block: TaskOutline.Block
    let complete: () -> Void
    @State private var hovering = false

    var body: some View {
        let title = block.title ?? block.items.first?.text ?? ""
        let rest = block.title == nil ? Array(block.items.dropFirst()) : block.items
        let detail = rest.map(\.text).joined(separator: " · ")
        HStack(alignment: .top, spacing: 12) {
            Button(action: complete) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(hovering ? Theme.lime : Theme.rgb(0x5A5A5A), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hovering ? Theme.lime : Color.clear))
                    .overlay {
                        if hovering {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.black)
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
        .padding(.vertical, 6)
    }
}

// MARK: - 英語タブの上:近い会議

/// 英語タブを開いていても、開始 30 分前から会議を見失わない(小さなカード 1 行)
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
                            .buttonStyle(.command(.primary, height: 28))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { armed = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { armed = false }
                }
            }
        } label: {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.commandSquare(armed ? .primary : .quiet, size: 24))
        .help(armed ? "再按一次退出" : "退出 Yudh（按两下，或 ⌘Q）。设置：⌘,")
        .accessibilityLabel(armed ? "再按一次退出" : "退出 Yudh")
    }
}

/// 坐姿:「已坐 23 分钟」。到点了加上「该站起来了」(黄緑)。点击打开屏幕上方的小窗
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(standing ? "已站" : "已坐")
                        .foregroundStyle(Theme.textFaint)
                    Text("\(minutes) 分钟")
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSoft)
                    if due {
                        Text(standing ? "· 该坐下了" : "· 该站起来了")
                            .foregroundStyle(Theme.lime)
                    }
                }
                .font(Theme.font(12, .semibold))
                .lineLimit(1)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help(standing ? "\(dueAt) 坐下。点击打开拉伸步骤" : "\(dueAt) 站起来。点击打开「站起来了吗？」小窗")
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
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("シャチョケン")
                    .foregroundStyle(Theme.textFaint)
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    Text("\(countdown.value)\(countdown.unit)")
                        .foregroundStyle(Theme.textSoft)
                } else {
                    Text("暂无")
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .font(Theme.font(12, .semibold))
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
