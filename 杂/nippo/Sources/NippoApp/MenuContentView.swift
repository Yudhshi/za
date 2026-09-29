import AppKit
import SwiftUI
import NippoCore

/// メニューパネル本体(2026-09 スプラトゥーン × ネオブルータリズム × Liquid Glass)。
/// 日付 → お休み → 勤務時間 → いまのタスク → 次のシャチョケン → 座り/立ち → 次の会議 → 今日の予定。
/// 画面より高くなったらスクロール(下端のフッターは常に見える)
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var contentHeight: CGFloat = 640

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 120
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    })
            }
            .scrollIndicators(.never)
            .frame(height: min(contentHeight, maxHeight))
            // 初回レイアウト前の 0 は無視(高さ 0 に潰れないように)
            .onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }

            PanelFooter()
                .padding(.horizontal, Theme.panelPadding)
                .padding(.bottom, Theme.panelPadding)
                .padding(.trailing, Theme.shadowOffset)
        }
        .frame(width: Theme.panelWidth)
        .background(SplatBackdrop())
        .environment(\.locale, Theme.locale)
        .onAppear {
            coordinator.refreshTodayEvents()
            coordinator.refreshShachoken(force: true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            DateHeader()
            if let reason = coordinator.quietReasonToday {
                CardHeader(symbol: "moon.fill", color: Theme.yellow, title: "今日はお休み(\(reason))",
                           subtitle: "会議の通知と立ち作業リマインドは止まっています", seed: 13)
                    .glassCard()
            }
            WorkTimeCard(coordinator: coordinator)
            TaskMemoCard(coordinator: coordinator)
            if coordinator.calendarAuthorized {
                ShachokenCard(event: coordinator.nextShachoken,
                              keyword: coordinator.settings.shachokenKeywords)
            }
            if coordinator.settings.postureEnabled && coordinator.isWorkingNow {
                PostureCard(coordinator: coordinator)
            }
            meetings
        }
        .padding([.horizontal, .top], Theme.panelPadding)
        .padding(.bottom, Theme.gap)
        .padding(.trailing, Theme.shadowOffset)
    }

    // MARK: - 会議

    @ViewBuilder
    private var meetings: some View {
        let now = Date()
        let hero = NextEventPolicy.currentOrNext(events: coordinator.todayEvents, now: now)
        let rest = coordinator.todayEvents.filter { $0.id != hero?.id }

        if !coordinator.calendarAuthorized {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "calendar.badge.exclamationmark", color: Theme.orange,
                           title: "カレンダーへのアクセスが必要です",
                           subtitle: "会議の表示・通知と、シャチョケンの確認に使います", seed: 19)
                Button("システム設定を開く") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.splat(Theme.yellow))
            }
            .glassCard()
        } else if hero == nil && rest.isEmpty {
            CardHeader(symbol: "calendar", color: Theme.cyan, title: "今日の会議はありません",
                       subtitle: "勤務日は、会議の開始 \(coordinator.settings.reminderLeadMinutes) 分前に通知します",
                       seed: 29)
                .glassCard()
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

// MARK: - 勤務時間(出勤時刻は手入力)

/// 出勤時刻を「853」のように入れると、今日の勤務時間を表示する(勤怠システムとは連携しない)
private struct WorkTimeCard: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var input = ""
    @State private var editing = false
    @State private var error: String?
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        if let began = coordinator.workBeganAt, !editing {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 12) {
                    IconTile(symbol: "briefcase.fill", color: Theme.yellow, seed: 5)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("勤務")
                            .font(.system(size: Theme.Size.subhead, weight: .heavy))
                        Text(WorkStart.durationText(from: began, to: context.date))
                            .font(.system(size: 26, weight: .black))
                            .monospacedDigit()
                        Text("\(began.formatted(Self.time)) から")
                            .font(.system(size: Theme.Size.subhead, weight: .semibold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    Spacer(minLength: 8)
                    Button("修正") {
                        input = ""
                        error = nil
                        editing = true
                    }
                    .buttonStyle(.splat)
                }
                .glassCard()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "briefcase.fill", color: Theme.yellow,
                           title: editing ? "出勤時刻を修正" : "出勤時刻を入力",
                           subtitle: "8:53 なら 853 と入力して Enter", seed: 5)
                HStack(spacing: 10) {
                    // 白い枠の中はダークでも明るい配色で描く(プレースホルダーとカーソルを見えるように)
                    TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.inkSoft))
                        .textFieldStyle(.plain)
                        .environment(\.colorScheme, .light)
                        .font(.system(size: Theme.Size.title, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Theme.white, in: Capsule(style: .circular))
                        .overlay(Capsule(style: .circular).strokeBorder(Theme.ink, lineWidth: 2.5))
                        .onSubmit(save)
                    Button("記録", action: save)
                        .buttonStyle(.splat(Theme.lime, minHeight: 40))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing {
                        Button("やめる") {
                            editing = false
                            error = nil
                        }
                        .buttonStyle(.splat(Theme.white, minHeight: 40))
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: Theme.Size.subhead, weight: .heavy))
                }
            }
            .glassCard()
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

// MARK: - いまのタスク(字下げで中身を細分化するメモ)

/// 「事例公開」「Ph2 - navigate / ・電話 / ・gen1 と gen2 の違い」のように書けるメモ。
/// 表示はタスク名を太字、中身を箇条書きで。編集はそのままのテキストで(Tab で字下げ)
private struct TaskMemoCard: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SplatBadge(text: "いまのタスク", color: Theme.lime, seed: 9, angle: -3)
                Spacer()
                if editing {
                    Button("完了") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(.splat(Theme.lime, minHeight: 32))
                } else {
                    Button("編集") {
                        draft = coordinator.settings.taskMemo
                        editing = true
                    }
                    .buttonStyle(.splat(Theme.white, minHeight: 32))
                }
            }
            if editing {
                TextEditor(text: $draft)
                    .font(.system(size: Theme.Size.body, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .environment(\.colorScheme, .light)
                    .padding(8)
                    .frame(minHeight: 140)
                    .background(Theme.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: 2.5))
                Text("タスク名は字下げなし、中身は Tab で字下げ(または「- 」)。空行でタスクを区切る")
                    .font(.system(size: Theme.Size.subhead, weight: .semibold))
                    .foregroundStyle(Theme.textSoft)
            } else {
                let lines = TaskOutline.parse(coordinator.settings.taskMemo)
                if lines.isEmpty {
                    Text("いま取り組んでいることを書いておけます")
                        .font(.system(size: Theme.Size.subhead, weight: .semibold))
                        .foregroundStyle(Theme.textSoft)
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
        .glassCard()
    }

    @ViewBuilder
    private func row(_ line: TaskOutline.Line) -> some View {
        if line.depth == 0 {
            Text(line.text)
                .font(.system(size: Theme.Size.headline, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(line.depth == 1 ? Theme.pink : Theme.cyan)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(line.text)
                    .font(.system(size: Theme.Size.body, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(line.depth - 1) * 18 + 4)
        }
    }
}

// MARK: - 次のシャチョケン(カレンダーから)

private struct ShachokenCard: View {
    let event: MeetingEvent?
    let keyword: String
    static let date = Date.FormatStyle(locale: Theme.locale).month().day().weekday(.abbreviated)
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                SplatBadge(text: "次のシャチョケン", color: Theme.orange, seed: 15, angle: 3)
                if let event {
                    let countdown = NextEventPolicy.dayCountdown(to: event.start, now: context.date)
                    HStack(alignment: .center, spacing: 14) {
                        SplatNumber(value: countdown.value, unit: countdown.unit,
                                    color: Theme.orange, size: 34, seed: 33)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(event.start.formatted(Self.date))
                                .font(.system(size: Theme.Size.headline, weight: .heavy))
                            Text("\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))")
                                .font(.system(size: Theme.Size.subhead, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.textSoft)
                        }
                    }
                    Text(event.title)
                        .font(.system(size: Theme.Size.subhead, weight: .semibold))
                        .foregroundStyle(Theme.textSoft)
                        .lineLimit(1)
                } else {
                    Text("90 日以内に「\(keyword)」の予定はありません")
                        .font(.system(size: Theme.Size.subhead, weight: .semibold))
                        .foregroundStyle(Theme.textSoft)
                }
            }
            .glassCard()
        }
    }
}

// MARK: - 座り/立ち(昇降デスク)

/// 今の姿勢と経過時間。切り替え時刻を過ぎたらボタンをピンクのインクにする
private struct PostureCard: View {
    @ObservedObject var coordinator: AppCoordinator
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let standing = coordinator.posture == .standing
            let minutes = max(0, Int(context.date.timeIntervalSince(coordinator.postureSince) / 60))
            let due = context.date >= coordinator.postureDueAt
            let inMeeting = BreakReminder.isInMeeting(events: coordinator.todayEvents,
                                                      now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconTile(symbol: standing ? "figure.stand" : "chair.fill",
                             color: standing ? Theme.cyan : Theme.lime, seed: standing ? 37 : 43)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(standing ? "立ち作業" : "座り作業") \(minutes) 分")
                            .font(.system(size: Theme.Size.headline, weight: .heavy))
                            .monospacedDigit()
                        Text(detail(standing: standing, due: due, inMeeting: inMeeting))
                            .font(.system(size: Theme.Size.subhead, weight: .semibold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    Spacer(minLength: 8)
                    Button(standing ? "座った" : "立った") {
                        if standing { coordinator.confirmSat() } else { coordinator.confirmStood() }
                    }
                    .buttonStyle(.splat(due ? Theme.pink : Theme.white))
                    .help(standing ? "座り作業に戻したら押してください" : "デスクを上げて立ったら押してください")
                }
                if standing {
                    // 立ち作業中は、閉じた手順の小窓をここから開き直せる
                    Button {
                        coordinator.showStandingGuide()
                    } label: {
                        Label("ストレッチ「\(coordinator.promptStretch.name)」の手順を開く",
                              systemImage: "figure.cooldown")
                            .font(.system(size: Theme.Size.subhead, weight: .bold))
                    }
                    .buttonStyle(.plain)
                } else {
                    // 次に出すストレッチの予告(ホバーで手順)
                    Label("次のストレッチ:\(coordinator.nextStretch.name)",
                          systemImage: "figure.cooldown")
                        .font(.system(size: Theme.Size.subhead, weight: .bold))
                        .help(BreakReminder.body(for: coordinator.nextStretch))
                }
            }
            .glassCard()
        }
    }

    private func detail(standing: Bool, due: Bool, inMeeting: Bool) -> String {
        let next = standing ? "座り作業" : "立ち作業"
        if due { return inMeeting ? "会議が終わったら\(next)へ" : "そろそろ\(next)へ" }
        return "\(coordinator.postureDueAt.formatted(Self.time)) ごろ\(next)へ"
    }
}

// MARK: - 次の会議

/// 残り時間をインクの上の極太数字で。開催中はバッジとインクがライム色に
private struct NextUpCard: View {
    let event: MeetingEvent
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let running = event.start <= context.date
            let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SplatBadge(text: running ? "開催中" : "次の会議",
                               color: running ? Theme.lime : Theme.pink, seed: 25, angle: -4)
                    Spacer()
                    Text("\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))")
                        .font(.system(size: Theme.Size.subhead, weight: .bold).monospacedDigit())
                }
                Text(event.title)
                    .font(.system(size: Theme.Size.title, weight: .heavy))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center) {
                    SplatNumber(value: countdown.value, unit: countdown.unit,
                                color: running ? Theme.lime : Theme.yellow, seed: 21)
                    Spacer()
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("参加", systemImage: "video.fill")
                                .font(.system(size: Theme.Size.headline, weight: .black))
                        }
                        .buttonStyle(.splat(Theme.pink, minHeight: 44))
                    }
                }
            }
            .glassCard()
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - 今日の予定

private struct ScheduleCard: View {
    let events: [MeetingEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SplatBadge(text: "今日の予定", color: Theme.cyan, seed: 27, angle: 2)
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.outline.opacity(0.18))
                            .frame(height: 1.5)
                    }
                    EventRow(event: event)
                }
            }
        }
        .glassCard()
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
            .background(hovering ? Theme.yellow.opacity(0.5) : .clear, in: Capsule(style: .circular))
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help("クリックで会議に参加")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Text(event.start, format: .dateTime.hour().minute())
                .font(.system(size: Theme.Size.subhead, weight: .heavy).monospacedDigit())
                .foregroundStyle(isPast ? Theme.textSoft : Theme.text)
                .frame(width: 44, alignment: .leading)

            // インクのしずく:オンライン会議はシアン、それ以外・終了済みは白
            let drop = InkSplat(seed: SeededRandom.seed(event.title), lobes: 6, drops: 0, drip: false)
            drop.fill(canJoin ? Theme.cyan : Theme.white)
                .overlay(drop.stroke(Theme.ink, lineWidth: 1.5))
                .frame(width: 14, height: 14)

            Text(event.title)
                .font(.system(size: Theme.Size.body, weight: isPast ? .medium : .bold))
                .foregroundStyle(isPast ? Theme.textSoft : Theme.text)
                .strikethrough(isPast, color: Theme.textSoft)
                .lineLimit(2)
            Spacer(minLength: 8)
            if canJoin {
                Image(systemName: "video.fill")
                    .font(.system(size: Theme.Size.subhead, weight: .bold))
                    .accessibilityLabel("オンライン会議")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }
}
