import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-09 v4 スプラトゥーン × 日本のアヴァンギャルド)。
/// OOUI:画面は「もの」でできている —— 会議・タスク・単語。まず一覧から「もの」を選び、そのものに付いた操作をする。
/// 上:プリーツ・日付(黄緑のインク)・タブ(今日 / 英語)・勤務時間
/// 今日:左に選んだ会議(既定は次の会議)と今日の予定の一覧、右にタスクの一覧(1 つずつ完了できる)
/// 英語:単語・考点词・語料・辞書(会議が近いときは上に会議の帯)
/// 下:座り/立ち・シャチョケン・終了。中段が画面より高いときだけスクロール
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("panelTab") private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360
    /// 一覧で選んだ会議(nil = 次の会議)
    @State private var selectedMeetingID: String?

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 220
    }

    var body: some View {
        VStack(spacing: 0) {
            Pleats()

            PanelHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.horizontal, Theme.panelPadding)
                .padding(.top, 12)
                .padding(.bottom, 12)
            Rectangle()
                .fill(Theme.rule)
                .frame(height: 2)
                .padding(.horizontal, Theme.panelPadding)

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
                .padding(.horizontal, Theme.panelPadding)
                .padding(.top, Theme.gap)
                // 主ボタンの版ずれ(黄緑)が切れないように
                .padding(.trailing, 3)
                .padding(.bottom, 6)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight, maxHeight))
            // 初回レイアウト前の 0 は無視(高さ 0 に潰れないように)
            .onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }

            PanelFooter(coordinator: coordinator)
                .padding(.horizontal, Theme.panelPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
        .environment(\.locale, Theme.locale)
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

// MARK: - 上の帯:日付・タブ・勤務時間

private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab

    var body: some View {
        HStack(spacing: 12) {
            DateMark()
            if let reason = coordinator.quietReasonToday {
                WovenTag(text: "Off · \(reason)", style: .violet)
                    .help("お休み(\(reason)):会議の通知と立ち作業リマインドは止まっています")
            }
            Spacer(minLength: 8)
            TabSwitch(tab: $tab, englishBadge: english.loaded ? english.remainingTotal : nil)
            // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
            WorkTimeChip(coordinator: coordinator, allowsInput: tab == .today) {
                tab = .today
            }
        }
    }
}

/// 日付を黄緑のインクの上に刷る(文字は常に墨。インクが文字を必ず覆う大きさにする)
private struct DateMark: View {
    var body: some View {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(c.month ?? 0).\(c.day ?? 0)")
                .font(Theme.font(Theme.Size.date, .black).width(.expanded))
            Text(Date(), format: .dateTime.weekday(.wide))
                .font(Theme.font(14, .heavy))
        }
        .foregroundStyle(Theme.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            ZStack(alignment: .bottomLeading) {
                InkSplat(seed: 7, lobes: 12, depth: 0.16).fill(Theme.lime).padding(-8)
                // 垂れとしずく(文字の外側だけ)
                InkSplat(seed: 12, lobes: 7, drops: 2, drip: true, depth: 0.3)
                    .fill(Theme.lime)
                    .frame(width: 54, height: 46)
                    .offset(x: 6, y: 26)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// 今日 / 英語 の切り替え(⌘1 / ⌘2)。英語には今日の残り数
private struct TabSwitch: View {
    @Binding var tab: PanelTab
    let englishBadge: Int?

    var body: some View {
        HStack(spacing: 0) {
            segment(.today, "今日", badge: nil, key: "1")
            Rectangle().fill(Theme.rule).frame(width: Theme.line, height: 32)
            segment(.english, "英語", badge: englishBadge, key: "2")
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
    }

    private func segment(_ value: PanelTab, _ title: String, badge: Int?,
                         key: KeyEquivalent) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.font(14, .heavy))
                if let badge, badge > 0 {
                    CountBadge(count: badge)
                }
            }
            .foregroundStyle(selected ? Theme.onInverse : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(selected ? Theme.inverse : Theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help("\(title)(⌘\(key.character))")
    }
}

/// 黄緑の四角に墨の数字(残りの数)
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .black).monospacedDigit())
            .foregroundStyle(Theme.black)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(Theme.lime)
            .overlay(Rectangle().strokeBorder(Theme.black, lineWidth: 1.5))
    }
}

/// 勤務時間(出勤時刻は手入力。勤怠システムとは連携しない)。
/// 入力済みなら小さなチップ(押すと修正)、未入力なら今日タブではその場に入力欄を出す
private struct WorkTimeChip: View {
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
                    HStack(spacing: 6) {
                        Text("勤務")
                            .foregroundStyle(Theme.textSoft)
                        Text(WorkStart.durationText(from: began, to: context.date))
                            .font(Theme.font(Theme.Size.body, .black).monospacedDigit())
                        Text("\(began.formatted(Self.time))〜")
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSoft)
                    }
                    .chip()
                }
                .buttonStyle(.plain)
                .help("押すと出勤時刻を修正")
            }
        } else if !allowsInput {
            Button(action: showToday) {
                Text("出勤 未入力")
                    .chip(fill: Theme.lime, text: Theme.black)
            }
            .buttonStyle(.plain)
            .help("今日タブで出勤時刻を入力")
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Text(editing ? "出勤を修正" : "出勤")
                        .font(Theme.font(Theme.Size.caption, .heavy))
                        .foregroundStyle(Theme.text)
                    // 白い枠の中はダークでも明るい配色で描く(プレースホルダーとカーソルを見えるように)
                    TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.inkSoft))
                        .textFieldStyle(.plain)
                        .environment(\.colorScheme, .light)
                        .font(Theme.font(Theme.Size.headline, .heavy).monospacedDigit())
                        .foregroundStyle(Theme.black)
                        .multilineTextAlignment(.center)
                        .frame(width: 60, height: 32)
                        .background(Theme.white)
                        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
                        .onSubmit(save)
                        .help("8:53 なら 853 と入力して Enter")
                    Button("記録", action: save)
                        .buttonStyle(.sharp(.primary, height: 32))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing {
                        Button {
                            editing = false
                            error = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.sharpSquare())
                        .help("やめる")
                    }
                }
                if let error {
                    Text(error)
                        .font(Theme.font(Theme.Size.caption, .heavy))
                        .foregroundStyle(Theme.text)
                }
            }
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
        HStack(alignment: .top, spacing: Theme.gap) {
            VStack(alignment: .leading, spacing: Theme.gap) {
                meetings
            }
            .frame(width: Theme.leftColumnWidth)
            TaskListBlock(coordinator: coordinator)
        }
    }

    @ViewBuilder
    private var meetings: some View {
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: Date())
        let selected = events.first { $0.id == selectedMeetingID } ?? next

        if !coordinator.calendarAuthorized {
            VStack(alignment: .leading, spacing: 0) {
                BlockHeader(en: "Calendar", ja: "カレンダー")
                VStack(alignment: .leading, spacing: 10) {
                    Text("カレンダーへのアクセスが必要です")
                        .font(Theme.font(Theme.Size.headline, .heavy))
                    Text("会議の表示・通知と、シャチョケンの確認に使います")
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("システム設定を開く") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.sharp(.primary))
                }
                .padding(14)
            }
            .block()
        } else if events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                BlockHeader(en: "Schedule", ja: "今日の予定")
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日の会議はありません")
                        .font(Theme.font(Theme.Size.title, .heavy))
                    Text("勤務日は、会議の開始 \(coordinator.settings.reminderLeadMinutes) 分前に通知します")
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            .block()
        } else {
            if let selected {
                MeetingDetail(event: selected, isNext: selected.id == next?.id)
            }
            ScheduleBlock(events: events, selectedID: selected?.id) { id in
                // 次の会議を選び直したら既定に戻す(時間が進むと自動で次へ移る)
                selectedMeetingID = id == next?.id ? nil : id
            }
        }
    }
}

/// 会議 1 つ(選んだ会議。既定は次の会議)。継ぎ合わせ:左に件名と操作、右は墨の布に残り時間
private struct MeetingDetail: View {
    let event: MeetingEvent
    let isNext: Bool
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let now = context.date
            let running = event.start <= now && now < event.end
            let past = event.end <= now
            let countdown: (value: String, unit: String) =
                past ? ("済", "終了") : NextEventPolicy.heroCountdown(for: event, now: now)
            VStack(spacing: 0) {
                BlockHeader(en: running ? "On Air" : (isNext ? "Next" : "Meeting"),
                            ja: running ? "開催中" : (isNext ? "次の会議" : "選んだ会議")) {
                    Text("\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))")
                        .font(Theme.font(14, .heavy).monospacedDigit())
                }
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(event.title)
                            .font(Theme.font(Theme.Size.title, .heavy))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if let url = event.joinURL, !past {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("参加", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.sharp(.primary))
                            .help(url.host ?? "会議に参加")
                        } else if event.joinURL == nil {
                            Text("会議リンクなし")
                                .font(Theme.font(Theme.Size.caption, .bold))
                                .foregroundStyle(Theme.textSoft)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SplatNumeral(value: countdown.value, unit: countdown.unit)
                        .foregroundStyle(Theme.paper)
                        .padding(.vertical, 12)
                        .frame(width: 118)
                        .frame(maxHeight: .infinity)
                        .background(Theme.black)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.rule).frame(width: Theme.line)
                        }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .block()
        }
    }
}

/// 今日の予定(会議の一覧)。行を押すとその会議を選ぶ(参加は選んだ会議のブロックから)
private struct ScheduleBlock: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            BlockHeader(en: "Schedule", ja: "今日の予定") {
                Text("\(events.count)")
                    .font(Theme.numeral(20))
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                EventRow(event: event, selected: event.id == selectedID) {
                    select(event.id)
                }
            }
        }
        .block()
    }
}

private struct EventRow: View {
    let event: MeetingEvent
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let past = event.end < Date()
        let online = event.joinURL != nil
        Button(action: action) {
            HStack(spacing: 10) {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(Theme.font(14, .heavy).monospacedDigit())
                    .strikethrough(past)
                    .frame(width: 44, alignment: .leading)
                // オンライン会議はすみれの四角
                Rectangle()
                    .fill(online ? Theme.violet : Color.clear)
                    .overlay(Rectangle().strokeBorder(online ? Theme.violet : Theme.textSoft, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                Text(event.title)
                    .font(Theme.font(Theme.Size.body, past ? .medium : .bold))
                    .strikethrough(past)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if online && !past {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12, weight: .bold))
                        .accessibilityLabel("オンライン会議")
                }
            }
            .foregroundStyle(selected ? Theme.onInverse : (past ? Theme.textSoft : Theme.text))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(selected ? Theme.inverse : (hovering ? Theme.hairline : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(event.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - タスク(1 つずつが「もの」)

/// いまのタスクの一覧。各タスクは左の四角で完了(メモから消す・直後なら元に戻せる)。
/// 一覧ごとの操作は「編集」(テキストで書き換え。書くそばから保存するので閉じても消えない)
private struct TaskListBlock: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BlockHeader(en: "Tasks", ja: "いまのタスク") {
                if editing {
                    Button("完了") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(.sharp(.primary, height: 24))
                } else {
                    Button("編集") {
                        draft = coordinator.settings.taskMemo
                        editing = true
                    }
                    .buttonStyle(.sharp(.plain, height: 24))
                }
            }
            if editing {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $draft)
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.black)
                        .scrollContentBackground(.hidden)
                        .environment(\.colorScheme, .light)
                        .padding(8)
                        .frame(minHeight: 180)
                        .background(Theme.white)
                        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
                        .onChange(of: draft) { _, text in
                            coordinator.settings.taskMemo = text
                        }
                    Text("タスク名は字下げなし、中身は Tab で字下げ(または「- 」)。空行でタスクを区切る")
                        .font(Theme.font(Theme.Size.caption, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            } else {
                let blocks = TaskOutline.blocks(coordinator.settings.taskMemo)
                if blocks.isEmpty {
                    Text("いま取り組んでいることを書いておけます")
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        TaskItem(block: block) {
                            coordinator.completeTask(at: index)
                        }
                    }
                }
                if let done = coordinator.lastCompletedTask {
                    HStack(spacing: 8) {
                        Text("「\(done.title)」を完了")
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button("元に戻す") { coordinator.undoCompleteTask() }
                            .buttonStyle(.sharp(.plain, height: 24))
                    }
                    .font(Theme.font(Theme.Size.caption, .bold))
                    .foregroundStyle(Theme.textSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
            }
        }
        .block()
    }
}

/// タスク 1 つ:左の四角で完了。タスク名と中身
private struct TaskItem: View {
    let block: TaskOutline.Block
    let complete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: complete) {
                Rectangle()
                    .fill(hovering ? Theme.lime : Color.clear)
                    .overlay(Rectangle().strokeBorder(hovering ? Theme.black : Theme.rule, lineWidth: 1.5))
                    .overlay {
                        if hovering {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Theme.black)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("完了(メモから消す)")
            .accessibilityLabel("完了")
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }

            VStack(alignment: .leading, spacing: 3) {
                if let title = block.title {
                    Text(title)
                        .font(Theme.font(Theme.Size.headline, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Rectangle()
                            .fill(item.depth == 1 ? Theme.text : Theme.textSoft)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                        Text(item.text)
                            .font(Theme.font(Theme.Size.body, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(max(0, item.depth - 1)) * 14)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 英語タブの上:近い会議の帯

/// 英語タブを開いていても、開始 30 分前から会議を見失わない
private struct MeetingStrip: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            if let event = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: context.date),
               event.start.timeIntervalSince(context.date) < 30 * 60 {
                let running = event.start <= context.date
                let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
                HStack(spacing: 10) {
                    WovenTag(text: running ? "On Air" : "Next", style: .lime)
                    Text(event.title)
                        .font(Theme.font(Theme.Size.body, .heavy))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(countdown.value)\(countdown.unit)")
                        .font(Theme.font(Theme.Size.caption, .heavy).monospacedDigit())
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("参加", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.sharp(.accent, height: 28))
                    }
                }
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.black)
                .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.line))
                .padding(.bottom, Theme.gap)
            }
        }
    }
}

// MARK: - 下の帯:座り/立ち・シャチョケン・終了

private struct PanelFooter: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.settings.postureEnabled && coordinator.isWorkingNow {
                PostureChip(coordinator: coordinator)
            }
            if coordinator.calendarAuthorized {
                ShachokenChip(event: coordinator.nextShachoken,
                              keyword: coordinator.settings.shachokenKeywords)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
            // 設定ボタンは置かない(使うときは ⌘,)。⌘Q はすぐ終了
            Group {
                Button("設定") { coordinator.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("終了") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            QuitButton()
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: Theme.line)
        }
    }
}

/// 終了は 2 回押し(うっかり押して会議の通知や立ち作業リマインドが止まらないように)
private struct QuitButton: View {
    @State private var armed = false

    var body: some View {
        Button {
            if armed {
                NSApp.terminate(nil)
            } else {
                armed = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    armed = false
                }
            }
        } label: {
            Text(armed ? "もう一度押すと終了" : "終了")
                .font(Theme.font(12, .bold))
                .foregroundStyle(armed ? Theme.black : Theme.textSoft)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(armed ? Theme.lime : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Yudh を終了(⌘Q)。設定は ⌘,")
    }
}

/// 座り/立ちの状態だけ(知らせるのは画面上部の小窓)。押すとその小窓を開く
private struct PostureChip: View {
    @ObservedObject var coordinator: AppCoordinator
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = coordinator.posture == .standing
            let minutes = max(0, Int(context.date.timeIntervalSince(coordinator.postureSince) / 60))
            let due = context.date >= coordinator.postureDueAt
            Button {
                coordinator.openPosturePrompt()
            } label: {
                HStack(spacing: 5) {
                    Text("\(standing ? "立ち" : "座り") \(minutes)分")
                        .monospacedDigit()
                    Text(detail(standing: standing, due: due))
                        .foregroundStyle(due ? Theme.black : Theme.textSoft)
                }
                .chip(fill: due ? Theme.lime : Theme.surface, text: due ? Theme.black : Theme.text)
            }
            .buttonStyle(.plain)
            .help(standing ? "ストレッチの手順を開く" : "「立ちましたか?」の小窓を開く")
        }
    }

    private func detail(standing: Bool, due: Bool) -> String {
        if due { return standing ? "そろそろ座る" : "そろそろ立つ" }
        return "· \(coordinator.postureDueAt.formatted(Self.time)) " + (standing ? "まで" : "ごろ立つ")
    }
}

/// 次のシャチョケン(26卒_新卒社長研修。カレンダーの 90 日先まで)。月に数回見る程度なので 1 行で
private struct ShachokenChip: View {
    let event: MeetingEvent?
    let keyword: String
    static let date = Date.FormatStyle(locale: Theme.locale).month(.defaultDigits).day().weekday(.abbreviated)
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 5) {
                Text("シャチョケン")
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    Text("\(event.start.formatted(Self.date)) \(event.start.formatted(Self.time))")
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSoft)
                    Text("· \(countdown.value)\(countdown.unit)")
                        .foregroundStyle(Theme.textSoft)
                } else {
                    Text("予定なし")
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .chip()
            .help(tooltip)
        }
    }

    private var tooltip: String {
        guard let event else { return "90 日以内に「\(keyword)」を含む予定はありません" }
        return "\(event.title)\n\(event.start.formatted(Self.date)) "
            + "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
    }
}
