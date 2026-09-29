import AppKit
import SwiftUI
import NippoCore

/// パネルのタブ(開き直しても前回のタブ)
enum PanelTab: String {
    case today, english
}

/// メニューパネル本体(2026-09 v3 レトロポップ × ネオブルータリズム)。開いてすぐ全体が見える横長:
/// 上:カラーバー・日付・タブ(今日 / 英語)・勤務時間の小さなチップ
/// 中(今日):左に次の会議と今日の予定、右にいまのタスク
/// 中(英語):単語・同替・聴写・辞書(すきま時間の英語)
/// 下:座り/立ち(普段は小窓で知らせるので状態だけ)・シャチョケン(月に数回しか見ない)・終了
/// 中段が画面より高くなったときだけスクロールする(上下の帯は常に見える)
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("panelTab") private var tab: PanelTab = .today
    @State private var contentHeight: CGFloat = 360

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 220
    }

    var body: some View {
        VStack(spacing: 0) {
            ColorBars()

            PanelHeader(coordinator: coordinator, english: coordinator.english, tab: $tab)
                .padding(.horizontal, Theme.panelPadding)
                .padding(.top, 14)
                .padding(.bottom, Theme.gap)

            ScrollView {
                Group {
                    switch tab {
                    case .today: columns
                    case .english: EnglishView(english: coordinator.english)
                    }
                }
                .padding(.horizontal, Theme.panelPadding)
                // カードの右下の影が切れないように
                .padding(.trailing, Theme.shadow)
                .padding(.bottom, Theme.shadow + 2)
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
                .padding(.top, Theme.gap - 2)
                .padding(.bottom, Theme.panelPadding)
        }
        .frame(width: Theme.panelWidth)
        .background(Theme.base)
        .environment(\.locale, Theme.locale)
        .onAppear {
            coordinator.refreshTodayEvents()
            coordinator.refreshShachoken(force: true)
            coordinator.english.loadIfNeeded()
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .english { coordinator.english.loadIfNeeded() }
        }
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
            VStack(alignment: .leading, spacing: Theme.gap) {
                meetings
            }
            .frame(width: Theme.leftColumnWidth)
            TaskMemoCard(coordinator: coordinator)
        }
    }

    // MARK: - 会議

    @ViewBuilder
    private var meetings: some View {
        let now = Date()
        let hero = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: now)
        let rest = coordinator.todayEvents.filter { $0.id != hero?.id }

        if !coordinator.calendarAuthorized {
            VStack(alignment: .leading, spacing: 10) {
                Tag(text: "カレンダー", symbol: "exclamationmark.triangle.fill", color: Theme.pink)
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
                .buttonStyle(.pop(Theme.green))
            }
            .card()
        } else if hero == nil && rest.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Tag(text: "今日の予定", symbol: "calendar", color: Theme.cyan)
                Text("今日の会議はありません")
                    .font(Theme.font(Theme.Size.title, .heavy))
                Text("勤務日は、会議の開始 \(coordinator.settings.reminderLeadMinutes) 分前に通知します")
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        } else {
            if let hero {
                NextUpCard(event: hero)
            }
            if !rest.isEmpty {
                ScheduleCard(events: rest)
            }
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
        HStack(spacing: 10) {
            Mascot(size: 44)
                .padding(.leading, -4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Date(), format: .dateTime.month().day())
                        .font(Theme.font(Theme.Size.date, .black))
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(Theme.font(Theme.Size.body, .bold))
                        .foregroundStyle(Theme.textSoft)
                }
                if let reason = coordinator.quietReasonToday {
                    Tag(text: "お休み(\(reason))", symbol: "moon.zzz.fill", color: Theme.yellow)
                        .help("会議の通知と立ち作業リマインドは止まっています")
                }
            }
            .foregroundStyle(Theme.text)
            .fixedSize()
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            TabSwitch(tab: $tab, englishBadge: english.loaded ? english.remainingTotal : nil)
            // 英語タブでは入力欄を出さない(数字キーの操作と取り合わないように)
            WorkTimeChip(coordinator: coordinator, allowsInput: tab == .today) {
                tab = .today
            }
        }
    }
}

/// 今日 / 英語 の切り替え(⌘1 / ⌘2)。英語には今日の残り数
private struct TabSwitch: View {
    @Binding var tab: PanelTab
    let englishBadge: Int?

    var body: some View {
        HStack(spacing: 2) {
            segment(.today, "今日", badge: nil, key: "1")
            segment(.english, "英語", badge: englishBadge, key: "2")
        }
        .padding(3)
        // iOS 26/27 の切り替えのように、うっすらガラス(文字は 75% の白の上なので読みやすさは保つ)
        .background(Theme.card.opacity(0.75), in: Capsule(style: .continuous))
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.outline, lineWidth: 2))
    }

    private func segment(_ value: PanelTab, _ title: String, badge: Int?,
                         key: KeyEquivalent) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(Theme.font(14, .heavy))
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 12, weight: .black).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .background(Theme.pink, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
                }
            }
            .foregroundStyle(selected ? Theme.card : Theme.text)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(selected ? Theme.text : Color.clear, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help("\(title)(⌘\(key.character))")
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
                        Text(Self.clock(from: began, to: context.date))
                            .font(Theme.font(Theme.Size.headline, .black).monospacedDigit())
                        Text("\(began.formatted(Self.time))〜")
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSoft)
                    }
                    .chip()
                }
                .buttonStyle(.plain)
                .help("勤務 \(WorkStart.durationText(from: began, to: context.date))。押すと出勤時刻を修正")
            }
        } else if !allowsInput {
            Button(action: showToday) {
                Label("出勤 未入力", systemImage: "briefcase.fill")
                    .chip(fill: Theme.yellow, text: Theme.ink)
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
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(width: 64, height: 32)
                        .background(Theme.white, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
                        .onSubmit(save)
                        .help("8:53 なら 853 と入力して Enter")
                    Button("記録", action: save)
                        .buttonStyle(.pop(Theme.green, height: 32))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing {
                        Button {
                            editing = false
                            error = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.popRound(size: 32))
                        .help("やめる")
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.font(Theme.Size.caption, .heavy))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    /// 「3:12」(時間:分)。チップを短く保つ(ホバーで「3時間12分」)
    static func clock(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
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

// MARK: - 次の会議

/// 残り時間を黄色いインクの上の極太数字で。開催中は「ON AIR」
private struct NextUpCard: View {
    let event: MeetingEvent
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let running = event.start <= context.date
            let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Tag(text: running ? "ON AIR" : "次の会議",
                        symbol: running ? "dot.radiowaves.left.and.right" : "alarm.fill",
                        color: running ? Theme.red : Theme.yellow)
                    Spacer()
                    Text("\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))")
                        .font(Theme.font(Theme.Size.body, .heavy).monospacedDigit())
                }
                Text(event.title)
                    .font(Theme.font(Theme.Size.title, .heavy))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(event.title)
                HStack(alignment: .center) {
                    SplatNumber(value: countdown.value, unit: countdown.unit,
                                color: running ? Theme.green : Theme.yellow)
                    Spacer()
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("参加", systemImage: "play.fill")
                        }
                        .buttonStyle(.pop(Theme.green, height: 42))
                        .help("会議に参加")
                    }
                }
            }
            .card()
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - 今日の予定

private struct ScheduleCard: View {
    let events: [MeetingEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Tag(text: "今日の予定", symbol: "calendar", color: Theme.cyan)
                .padding(.bottom, 2)
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 1.5)
                    }
                    EventRow(event: event)
                }
            }
        }
        .card(padding: 12)
    }
}

private struct EventRow: View {
    let event: MeetingEvent
    @State private var hovering = false

    private var isPast: Bool { event.end < Date() }
    private var canJoin: Bool { event.joinURL != nil && !isPast }

    var body: some View {
        if canJoin, let url = event.joinURL {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .background(hovering ? Theme.yellow.opacity(0.45) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help("クリックで会議に参加:\(event.title)")
        } else {
            content
                .help(event.title)
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Text(event.start, format: .dateTime.hour().minute())
                .font(Theme.font(Theme.Size.caption + 1, .heavy).monospacedDigit())
                .foregroundStyle(isPast ? Theme.textSoft : Theme.text)
                .strikethrough(isPast, color: Theme.textSoft)
                .frame(width: 44, alignment: .leading)

            // オンライン会議はシアン、それ以外・終了済みは白抜き
            Circle()
                .fill(canJoin ? Theme.cyan : Theme.white)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                .frame(width: 13, height: 13)

            Text(event.title)
                .font(Theme.font(Theme.Size.body, isPast ? .medium : .bold))
                .foregroundStyle(isPast ? Theme.textSoft : Theme.text)
                .strikethrough(isPast, color: Theme.textSoft)
                .lineLimit(1)
            Spacer(minLength: 6)
            if canJoin {
                Image(systemName: "video.fill")
                    .font(.system(size: Theme.Size.caption, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityLabel("オンライン会議")
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 34)
        .contentShape(Rectangle())
    }
}

// MARK: - いまのタスク(字下げで中身を細分化するメモ)

/// 「事例公開」「Ph2 - navigate / ・電話 / ・gen1 と gen2 の違い」のように書けるメモ。
/// 表示はタスク名を太字、中身を箇条書きで。編集はそのままのテキストで(Tab で字下げ)
private struct TaskMemoCard: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Tag(text: "いまのタスク", symbol: "checklist", color: Theme.pink)
                Spacer()
                if editing {
                    Button("完了") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(.pop(Theme.green, height: 30))
                } else {
                    Button("編集") {
                        draft = coordinator.settings.taskMemo
                        editing = true
                    }
                    .buttonStyle(.pop(Theme.white, height: 30))
                }
            }
            if editing {
                TextEditor(text: $draft)
                    .font(Theme.font(Theme.Size.body, .medium))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .environment(\.colorScheme, .light)
                    .padding(8)
                    .frame(minHeight: 180)
                    .background(Theme.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: 2))
                Text("タスク名は字下げなし、中身は Tab で字下げ(または「- 」)。空行でタスクを区切る")
                    .font(Theme.font(Theme.Size.caption, .medium))
                    .foregroundStyle(Theme.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let lines = TaskOutline.parse(coordinator.settings.taskMemo)
                if lines.isEmpty {
                    Text("いま取り組んでいることを書いておけます")
                        .font(Theme.font(Theme.Size.body, .medium))
                        .foregroundStyle(Theme.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            if let line {
                                row(line)
                            } else {
                                Spacer().frame(height: 6)
                            }
                        }
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func row(_ line: TaskOutline.Line) -> some View {
        if line.depth == 0 {
            Text(line.text)
                .font(Theme.font(Theme.Size.headline, .heavy))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(line.depth == 1 ? Theme.pink : Theme.cyan)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(line.text)
                    .font(Theme.font(Theme.Size.body, .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(line.depth - 1) * 16 + 4)
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
            // 設定ボタンは置かない(使うときは ⌘, で開く)
            Button("設定") { coordinator.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.popRound())
            .help("Yudh を終了")
            .accessibilityLabel("Yudh を終了")
        }
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
                    Image(systemName: standing ? "figure.stand" : "chair.fill")
                    Text("\(standing ? "立ち" : "座り") \(minutes)分")
                        .monospacedDigit()
                    Text(detail(standing: standing, due: due))
                        .foregroundStyle(due ? Theme.ink : Theme.textSoft)
                }
                .chip(fill: due ? Theme.yellow : Theme.card, text: due ? Theme.ink : Theme.text)
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
                Image(systemName: "graduationcap.fill")
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
