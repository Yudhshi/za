import AppKit
import SwiftUI
import NippoCore

/// メニューパネル本体(2026-09 ラバーホース × ガラス)。よく見るものほど上・大きく、開いてすぐ全体が見える横長 2 列:
/// 上:日付と、勤務時間の小さなチップ(お休みの日はその旨も)
/// 中:左に次の会議(残り時間・参加)と今日の予定、右にいまのタスク
/// 下:座り/立ち(普段は小窓で知らせるので状態だけ)・シャチョケン(月に数回しか見ない)・設定・終了
/// 中段が画面より高くなったときだけスクロールする(上下の帯は常に見える)
struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var contentHeight: CGFloat = 360

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 200
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(coordinator: coordinator)
                .padding([.horizontal, .top], Theme.panelPadding)
                .padding(.bottom, Theme.gap)

            ScrollView {
                columns
                    .padding(.horizontal, Theme.panelPadding)
                    // カードの下の影が切れないように
                    .padding(.bottom, Theme.lift + 2)
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
        .background(PanelBackdrop())
        .environment(\.locale, Theme.locale)
        .onAppear {
            coordinator.refreshTodayEvents()
            coordinator.refreshShachoken(force: true)
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
                Tag(text: "カレンダー", symbol: "exclamationmark.triangle.fill", color: Theme.blush)
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
                .buttonStyle(.rubber(Theme.mustard))
            }
            .card()
        } else if hero == nil && rest.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Tag(text: "今日の予定", symbol: "calendar", color: Theme.teal)
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

// MARK: - 上の帯:日付・お休み・勤務時間

private struct PanelHeader: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 10) {
            Mascot(size: 46)
                .padding(.leading, -4)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(Date(), format: .dateTime.month().day())
                    .font(Theme.font(Theme.Size.date, .black))
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(Theme.font(Theme.Size.body, .heavy))
                    .foregroundStyle(Theme.textSoft)
            }
            .foregroundStyle(Theme.text)
            .fixedSize()
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let reason = coordinator.quietReasonToday {
                Label("お休み(\(reason))", systemImage: "moon.zzz.fill")
                    .chip(fill: Theme.mustard, text: Theme.ink)
                    .help("会議の通知と立ち作業リマインドは止まっています")
            }
            WorkTimeChip(coordinator: coordinator)
        }
    }
}

/// 勤務時間(出勤時刻は手入力。勤怠システムとは連携しない)。
/// 入力済みなら小さなチップ(押すと修正)、未入力ならその場に入力欄を出す
private struct WorkTimeChip: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var input = ""
    @State private var editing = false
    @State private var error: String?
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        if let began = coordinator.workBeganAt, !editing {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Button {
                    input = ""
                    error = nil
                    editing = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "briefcase.fill")
                            .foregroundStyle(Theme.textSoft)
                        Text("勤務")
                            .foregroundStyle(Theme.textSoft)
                        Text(WorkStart.durationText(from: began, to: context.date))
                            .font(Theme.font(Theme.Size.headline, .black).monospacedDigit())
                        Text("\(began.formatted(Self.time))〜")
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSoft)
                        Image(systemName: "pencil")
                            .foregroundStyle(Theme.textSoft)
                    }
                    .chip()
                }
                .buttonStyle(.plain)
                .help("出勤時刻を修正")
            }
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Label(editing ? "出勤を修正" : "出勤時刻", systemImage: "briefcase.fill")
                        .font(Theme.font(Theme.Size.caption, .heavy))
                        .foregroundStyle(Theme.text)
                    // 白い枠の中はダークでも明るい配色で描く(プレースホルダーとカーソルを見えるように)
                    TextField("", text: $input, prompt: Text("853").foregroundStyle(Theme.inkSoft))
                        .textFieldStyle(.plain)
                        .environment(\.colorScheme, .light)
                        .font(Theme.font(Theme.Size.headline, .heavy).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(width: 64, height: 30)
                        .background(Theme.white, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
                        .onSubmit(save)
                        .help("8:53 なら 853 と入力して Enter")
                    Button("記録", action: save)
                        .buttonStyle(.rubber(Theme.mustard, height: 30))
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editing {
                        Button {
                            editing = false
                            error = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.rubberRound(size: 30))
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

/// 残り時間を大きな数字で。開催中はタグが青緑に
private struct NextUpCard: View {
    let event: MeetingEvent
    static let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: Theme.locale)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let running = event.start <= context.date
            let countdown = NextEventPolicy.heroCountdown(for: event, now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Tag(text: running ? "開催中" : "次の会議",
                        symbol: running ? "play.fill" : "alarm.fill",
                        color: running ? Theme.teal : Theme.mustard)
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
                    BigNumber(value: countdown.value, unit: countdown.unit)
                    Spacer()
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("参加", systemImage: "hand.point.right.fill")
                        }
                        .buttonStyle(.rubber(Theme.red, text: Theme.white, height: 40))
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
            Tag(text: "今日の予定", symbol: "calendar", color: Theme.teal)
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
            .background(hovering ? Theme.mustard.opacity(0.35) : .clear,
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
        HStack(spacing: 9) {
            Text(event.start, format: .dateTime.hour().minute())
                .font(Theme.font(Theme.Size.caption + 1, .heavy).monospacedDigit())
                .foregroundStyle(isPast ? Theme.textSoft : Theme.text)
                .frame(width: 42, alignment: .leading)

            // オンライン会議は青緑、それ以外・終了済みは白抜き
            Circle()
                .fill(canJoin ? Theme.teal : Theme.cream)
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2))
                .frame(width: 12, height: 12)

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
        .frame(minHeight: 32)
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
                Tag(text: "いまのタスク", symbol: "checklist", color: Theme.blush)
                Spacer()
                if editing {
                    Button("完了") {
                        coordinator.saveTaskMemo(draft)
                        editing = false
                    }
                    .buttonStyle(.rubber(Theme.mustard, height: 28))
                } else {
                    Button("編集") {
                        draft = coordinator.settings.taskMemo
                        editing = true
                    }
                    .buttonStyle(.rubber(Theme.cream, height: 28))
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
                    .fill(line.depth == 1 ? Theme.red : Theme.teal)
                    .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(line.text)
                    .font(Theme.font(Theme.Size.body, .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(line.depth - 1) * 16 + 4)
        }
    }
}

// MARK: - 下の帯:座り/立ち・シャチョケン・設定・終了

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
            Button {
                coordinator.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.rubberRound())
            .help("設定")
            .accessibilityLabel("設定")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.rubberRound())
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
                .chip(fill: due ? Theme.mustard : Theme.card, text: due ? Theme.ink : Theme.text,
                      height: 30)
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
            .chip(height: 30)
            .help(tooltip)
        }
    }

    private var tooltip: String {
        guard let event else { return "90 日以内に「\(keyword)」を含む予定はありません" }
        return "\(event.title)\n\(event.start.formatted(Self.date)) "
            + "\(event.start.formatted(Self.time)) – \(event.end.formatted(Self.time))"
    }
}
