import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-09 v5:ゲームの UI)。黒いステージに HUD とメニュー。
/// OOUI:画面は「もの」でできている —— 会議・タスク・単語。一覧から「もの」を選び、そのものに付いた操作をする。
/// 上:日付(黄緑のインク)・タブ(今日 / 英語)・WORK ゲージ
/// 今日:左に MISSION(選んだ会議。既定は次の会議)と QUEST LOG(今日の予定)、右に QUESTS(タスク)
/// 英語:単語・考点词・語料・辞書(会議が近いときは上に会議の帯)
/// 下:SIT / STAND ゲージ・EVENT(シャチョケン)・電源。中段が画面より高いときだけスクロール
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("panelTab") private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360
    /// QUEST LOG で選んだ会議(nil = 次の会議)
    @State private var selectedMeetingID: String?

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 220
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.horizontal, Theme.panelPadding)
                .padding(.top, 14)
                .padding(.bottom, 10)

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
                .padding(.top, 8)
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
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(width: Theme.panelWidth)
        .background(alignment: .bottomTrailing) {
            // ステージの右下にすみれのインク(電源の後ろだけ。文字には重ねない)
            InkSplat(seed: 9, lobes: 9, drops: 2, drip: false, depth: 0.34)
                .fill(Theme.violet)
                .frame(width: 220, height: 190)
                .offset(x: 110, y: 110)
                .allowsHitTesting(false)
        }
        .background(Theme.stage)
        .clipped()
        .environment(\.colorScheme, .dark)
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

// MARK: - 上の帯:日付・タブ・WORK

private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var english: EnglishCoordinator
    @Binding var tab: PanelTab

    var body: some View {
        HStack(spacing: 14) {
            DateMark()
            if let reason = coordinator.quietReasonToday {
                Plate(text: "Off · \(reason)", fill: Theme.violet, textColor: Theme.white)
                    .help("お休み(\(reason)):会議の通知と立ち作業リマインドは止まっています")
            }
            Spacer(minLength: 8)
            TabMenu(tab: $tab, englishBadge: english.loaded ? english.remainingTotal : nil)
            // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
            WorkHUD(coordinator: coordinator, allowsInput: tab == .today) {
                tab = .today
            }
        }
        .frame(minHeight: 58)
    }
}

/// 日付を黄緑のインクの上に刷る(文字は常に墨。インクが文字を必ず覆う大きさにする)
private struct DateMark: View {
    var body: some View {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        HStack(alignment: .center, spacing: 10) {
            Text("\(c.month ?? 0).\(c.day ?? 0)")
                .font(Theme.display(Theme.Size.date))
                .foregroundStyle(Theme.black)
            Plate(text: Date().formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US"))),
                  fill: Theme.black, textColor: Theme.lime)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .background {
            ZStack(alignment: .bottomLeading) {
                InkSplat(seed: 7, lobes: 12, depth: 0.16).fill(Theme.lime).padding(-10)
                // 垂れとしずく(文字の外側だけ)
                InkSplat(seed: 12, lobes: 7, drops: 2, drip: true, depth: 0.3)
                    .fill(Theme.lime)
                    .frame(width: 54, height: 46)
                    .offset(x: 4, y: 28)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Theme.locale)))
    }
}

/// 今日 / 英語(⌘1 / ⌘2)。選んだほうに黄緑の札がすべって来る。英語には今日の残り数
private struct TabMenu: View {
    @Binding var tab: PanelTab
    let englishBadge: Int?
    @Namespace private var plate

    var body: some View {
        HStack(spacing: 2) {
            item(.today, "今日", badge: nil, key: "1")
            item(.english, "英語", badge: englishBadge, key: "2")
        }
        .fixedSize()
    }

    private func item(_ value: PanelTab, _ title: String, badge: Int?, key: KeyEquivalent) -> some View {
        let selected = tab == value
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.35)) { tab = value }
        } label: {
            HStack(spacing: 4) {
                Text("▶")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(selected ? Theme.lime : Color.clear)
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.font(Theme.Size.headline, .black))
                    if let badge, badge > 0 {
                        Plate(text: "\(badge)", fill: Theme.violet, textColor: Theme.white)
                    }
                }
                .foregroundStyle(selected ? Theme.black : Theme.textSoft)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    if selected {
                        Slant().fill(Theme.lime).matchedGeometryEffect(id: "tab", in: plate)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help("\(title)(⌘\(key.character))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// WORK:勤務時間(出勤時刻は手入力。勤怠システムとは連携しない)。ゲージは 1 コマ 1 時間(8 時間)。
/// 入力済みなら HUD(押すと修正)、未入力なら今日タブではその場に入力欄を出す
private struct WorkHUD: View {
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
                let minutes = max(0, context.date.timeIntervalSince(began) / 60)
                Button {
                    input = ""
                    error = nil
                    editing = true
                    showToday()
                } label: {
                    HUDStat(label: "Work", value: WorkStart.durationText(from: began, to: context.date),
                            detail: "\(began.formatted(Self.time))〜", segments: 8,
                            filled: minutes / 60, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("押すと出勤時刻を修正")
            }
        } else if !allowsInput {
            Button(action: showToday) {
                Plate(text: "出勤 未入力", fill: Theme.lime, textColor: Theme.black)
            }
            .buttonStyle(.plain)
            .help("今日タブで出勤時刻を入力")
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text("WORK")
                        .font(Theme.label(11))
                        .tracking(1.2)
                        .foregroundStyle(Theme.lime)
                    TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.textSoft))
                        .textFieldStyle(.plain)
                        .font(Theme.font(Theme.Size.headline, .black).monospacedDigit())
                        .foregroundStyle(Theme.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 64, height: 32)
                        .background(Theme.tile)
                        .overlay(Rectangle().stroke(Theme.lime, lineWidth: 2))
                        .onSubmit(save)
                        .help("出勤時刻。8:53 なら 853 と入力して Enter")
                    Button("記録", action: save)
                        .buttonStyle(.command(.primary, height: 32))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing {
                        Button {
                            editing = false
                            error = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.commandSquare(.ghost, size: 32))
                        .help("やめる")
                    }
                }
                if let error {
                    Text(error)
                        .font(Theme.font(Theme.Size.caption, .heavy))
                        .foregroundStyle(Theme.lime)
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
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                meetings
            }
            .frame(width: Theme.leftColumnWidth)
            QuestsBlock(coordinator: coordinator)
        }
    }

    @ViewBuilder
    private var meetings: some View {
        let events = coordinator.todayEvents
        let next = NextEventPolicy.currentOrNext(events: events, now: Date())
        let selected = events.first { $0.id == selectedMeetingID } ?? next

        if !coordinator.calendarAuthorized {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(en: "Calendar", ja: "カレンダー")
                Text("カレンダーへのアクセスが必要です")
                    .font(Theme.font(Theme.Size.headline, .black))
                Text("会議の表示・通知と、シャチョケンの確認に使います")
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("システム設定を開く") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.command(.primary))
            }
            .foregroundStyle(Theme.white)
        } else if events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(en: "Quest Log", ja: "今日の予定")
                Text("今日の会議はありません")
                    .font(Theme.font(Theme.Size.title, .black))
                    .foregroundStyle(Theme.white)
                Text("勤務日は、会議の開始 \(coordinator.settings.reminderLeadMinutes) 分前に通知します")
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            if let selected {
                MissionBlock(event: selected, isNext: selected.id == next?.id)
            }
            QuestLog(events: events, selectedID: selected?.id) { id in
                // 次の会議を選び直したら既定に戻す(時間が進むと自動で次へ移る)
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                    selectedMeetingID = id == next?.id ? nil : id
                }
            }
        }
    }
}

/// MISSION:選んだ会議(既定は次の会議)。左に件名と参加、右はすみれの布の上に残り時間のタイマー
private struct MissionBlock: View {
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
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(running ? "ON AIR" : (isNext ? "NEXT MISSION" : "MISSION"))
                        .font(Theme.label(12))
                        .tracking(1.4)
                        .foregroundStyle(Theme.lime)
                    Text("\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))")
                        .font(Theme.font(14, .heavy).monospacedDigit())
                        .foregroundStyle(Theme.textSoft)
                    Text(event.title)
                        .font(Theme.font(Theme.Size.title, .black))
                        .foregroundStyle(Theme.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.bottom, 4)
                    if let url = event.joinURL, !past {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("参加", systemImage: "play.fill")
                        }
                        .buttonStyle(.command(.primary))
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
                    .frame(width: 128)
                    .padding(.top, 18)
                    .padding(.trailing, 8)
                    .padding(.bottom, 14)
            }
            .background(alignment: .trailing) {
                // 継ぎ合わせ:右はすみれの布 + 網点
                SlashedPanel()
                    .fill(Theme.violet)
                    .overlay(Halftone().clipShape(SlashedPanel()))
                    .frame(width: 148)
            }
            .background(Theme.surface)
            .clipShape(CutRect(bottomLeading: 16))
        }
    }
}

/// QUEST LOG:今日の予定。行を押すとその会議を選ぶ(参加は MISSION から)
private struct QuestLog: View {
    let events: [MeetingEvent]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(en: "Quest Log", ja: "今日の予定 · \(events.count)")
            VStack(spacing: 2) {
                ForEach(events) { event in
                    EventRow(event: event, selected: event.id == selectedID) {
                        select(event.id)
                    }
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
        let online = event.joinURL != nil
        Button(action: action) {
            HStack(spacing: 10) {
                Text("▶")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(selected ? Theme.black : (hovering ? Theme.lime : Color.clear))
                Text(event.start, format: .dateTime.hour().minute())
                    .font(Theme.font(14, .heavy).monospacedDigit())
                    .strikethrough(past)
                    .frame(width: 44, alignment: .leading)
                // オンライン会議はすみれの菱形
                Rectangle()
                    .fill(online ? (selected ? Theme.black : Theme.violet) : Color.clear)
                    .overlay(Rectangle().stroke(online ? Color.clear : (selected ? Theme.black : Theme.textFaint),
                                                lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45))
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
            .foregroundStyle(selected ? Theme.black : (past ? Theme.textFaint : Theme.white))
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background {
                if selected {
                    Slant().fill(Theme.lime)
                } else if hovering {
                    Slant().fill(Theme.tile)
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

// MARK: - QUESTS(タスク。1 つずつが「もの」)

/// いまのタスクの一覧。各タスクは左の菱形で完了(CLEAR!。直後なら元に戻せる)。
/// 一覧ごとの操作は「編集」(テキストで書き換え。書くそばから保存するので閉じても消えない)
private struct QuestsBlock: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(en: "Quests", ja: "いまのタスク") {
                if editing {
                    Button("完了") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(.command(.primary, height: 26))
                } else {
                    Button("編集") {
                        draft = coordinator.settings.taskMemo
                        editing = true
                    }
                    .buttonStyle(.command(.ghost, height: 26))
                }
            }
            if editing {
                TextEditor(text: $draft)
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 180)
                    .background(Theme.tile)
                    .overlay(Rectangle().stroke(Theme.lime, lineWidth: 2))
                    .onChange(of: draft) { _, text in
                        coordinator.settings.taskMemo = text
                    }
                Text("タスク名は字下げなし、中身は Tab で字下げ(または「- 」)。空行でタスクを区切る")
                    .font(Theme.font(Theme.Size.caption, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let blocks = TaskOutline.blocks(coordinator.settings.taskMemo)
                if blocks.isEmpty {
                    Text("いま取り組んでいることを書いておけます")
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                            if index > 0 {
                                Rectangle().fill(Theme.hairline).frame(height: 1)
                            }
                            QuestItem(block: block) {
                                withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                                    coordinator.completeTask(at: index)
                                }
                            }
                        }
                    }
                }
                if let done = coordinator.lastCompletedTask {
                    HStack(spacing: 8) {
                        Plate(text: "Clear!", fill: Theme.lime, textColor: Theme.black)
                        Text(done.title)
                            .font(Theme.font(Theme.Size.caption, .heavy))
                            .foregroundStyle(Theme.white)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button("元に戻す") { coordinator.undoCompleteTask() }
                            .buttonStyle(.command(.ghost, height: 24))
                    }
                    .padding(.top, 4)
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
        }
    }
}

/// タスク 1 つ:左の菱形で完了。タスク名と中身
private struct QuestItem: View {
    let block: TaskOutline.Block
    let complete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: complete) {
                Rectangle()
                    .fill(hovering ? Theme.lime : Color.clear)
                    .overlay(Rectangle().stroke(hovering ? Theme.lime : Theme.white, lineWidth: 2))
                    .frame(width: 13, height: 13)
                    .rotationEffect(.degrees(45))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("クリア(メモから消す)")
            .accessibilityLabel("完了")
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }

            VStack(alignment: .leading, spacing: 3) {
                if let title = block.title {
                    Text(title)
                        .font(Theme.font(Theme.Size.headline, .black))
                        .foregroundStyle(Theme.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Slant(skew: 2)
                            .fill(item.depth == 1 ? Theme.lime : Theme.violet)
                            .frame(width: 9, height: 3)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        Text(item.text)
                            .font(Theme.font(Theme.Size.body, .semibold))
                            .foregroundStyle(Theme.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(max(0, item.depth - 1)) * 14)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
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
                    Plate(text: running ? "On Air" : "Next", fill: Theme.lime, textColor: Theme.black)
                    Text(event.title)
                        .font(Theme.font(Theme.Size.body, .black))
                        .foregroundStyle(Theme.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(countdown.value)\(countdown.unit)")
                        .font(Theme.font(Theme.Size.caption, .heavy).monospacedDigit())
                        .foregroundStyle(Theme.lime)
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("参加", systemImage: "play.fill")
                        }
                        .buttonStyle(.command(.primary, height: 28))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.surface)
                .clipShape(CutRect(topTrailing: 12))
                .padding(.bottom, Theme.gap)
            }
        }
    }
}

// MARK: - 下の帯:SIT / STAND・EVENT・電源

private struct PanelFooter: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            if coordinator.settings.postureEnabled && coordinator.isWorkingNow {
                PostureHUD(coordinator: coordinator)
            }
            if coordinator.calendarAuthorized {
                ShachokenHUD(event: coordinator.nextShachoken,
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
            PowerButton()
        }
    }
}

/// 電源(終了)。2 回押しで終了(うっかり押して会議の通知や立ち作業リマインドが止まらないように)
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
                .font(.system(size: 15, weight: .black))
        }
        .buttonStyle(.commandSquare(armed ? .primary : .light, size: 30))
        .scaleEffect(armed ? 1.15 : 1)
        .help(armed ? "もう一度押すと終了" : "Yudh を終了(2 回押す・⌘Q)。設定は ⌘,")
        .accessibilityLabel(armed ? "もう一度押すと終了" : "Yudh を終了")
    }
}

/// SIT / STAND:座り(立ち)の時間をゲージで。満ちたら切り替えどき。押すと画面上部の小窓を開く
private struct PostureHUD: View {
    @ObservedObject var coordinator: AppCoordinator
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = coordinator.posture == .standing
            let minutes = max(0, context.date.timeIntervalSince(coordinator.postureSince) / 60)
            let limit = Double(standing ? coordinator.settings.standMinutes : coordinator.settings.sitMinutes)
            let due = context.date >= coordinator.postureDueAt
            let dueAt = coordinator.postureDueAt.formatted(Self.time)
            let detail: String = due ? (standing ? "そろそろ座る" : "そろそろ立つ")
                                     : (standing ? "\(dueAt) まで" : "\(dueAt) に立つ")
            let filled: Double = due ? 9 : minutes / max(limit, 1) * 9
            Button {
                coordinator.openPosturePrompt()
            } label: {
                HUDStat(label: standing ? "Stand" : "Sit", value: "\(Int(minutes))分",
                        detail: detail, segments: 9, filled: filled)
            }
            .buttonStyle(.plain)
            .help(standing ? "ストレッチの手順を開く" : "「立ちましたか?」の小窓を開く")
        }
    }
}

/// EVENT:次のシャチョケン(26卒_新卒社長研修。カレンダーの 90 日先まで)。月に数回見る程度なので小さく
private struct ShachokenHUD: View {
    let event: MeetingEvent?
    let keyword: String
    static let date = Date.FormatStyle(locale: Theme.locale).month(.defaultDigits).day().weekday(.abbreviated)
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 3) {
                HUDStat(label: "Event", value: "シャチョケン",
                        detail: event.map { "\($0.start.formatted(Self.date)) \($0.start.formatted(Self.time))" }
                            ?? "予定なし")
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    Text("\(countdown.value)\(countdown.unit)")
                        .font(Theme.display(15))
                        .foregroundStyle(Theme.white)
                }
            }
            .help(tooltip)
        }
    }

    private var tooltip: String {
        guard let event else { return "90 日以内に「\(keyword)」を含む予定はありません" }
        return "\(event.title)\n\(event.start.formatted(Self.date)) "
            + "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
    }
}
