import Foundation
import AppKit
import ServiceManagement
import NippoCore

@MainActor
final class AppCoordinator: ObservableObject {
    let settings = AppSettings()
    let db: AppDatabase
    let quietDays: QuietDayChecker

    @Published var todayEvents: [MeetingEvent] = []
    @Published var statusBarTitle: String?
    /// 次のシャチョケン(90 日先まで。件名キーワードは設定で変更可)
    @Published var nextShachoken: MeetingEvent?
    private var shachokenFetchedAt: Date?
    private var shachokenInFlight = false

    // 座り/立ちの切り替え(AppCoordinator+Posture.swift)。extension は stored property を持てないのでここに置く
    @Published var posture: BreakReminder.Posture = .sitting
    @Published var postureSince = Date()
    var postureRemindAt: Date?
    private var wasWorking = false
    /// 画面上部の小窓(nil で閉じる)。変わるたびに小窓を出し入れ・サイズ調整する
    @Published var posturePrompt: BreakReminder.Prompt? {
        didSet { posturePanel.update() }
    }
    @Published var promptStretch = BreakReminder.Stretch(name: "", steps: [])
    /// 手順の何番目か(steps.count = 完了)
    @Published var stretchStep = 0 {
        didSet { posturePanel.update() }
    }
    lazy var posturePanel = PosturePanelController(coordinator: self)
    private lazy var settingsWindow = SettingsWindowController(coordinator: self)
    /// 英語タブ(すきま時間の英語)
    lazy var english = EnglishCoordinator(db: db)

    let calendarProvider: CalendarProviding = EventKitCalendar()
    private var timer: Timer?
    @Published var calendarAuthorized = false

    init() {
        let dbPath = (settings.reportsRoot as NSString)
            .appendingPathComponent("nippo.sqlite")
        do {
            db = try AppDatabase(path: dbPath)
        } catch {
            fatalError("DB 初期化失敗： \(error)")
        }
        AppLog.shared.configure(root: URL(fileURLWithPath: settings.reportsRoot))
        AppLog.shared.log("app", "起動 Yudh v0.5")
        quietDays = QuietDayChecker(db: db)

        if Bundle.main.bundleIdentifier != nil {
            // 2026-09-29 に Nippo.app → Yudh.app へ改名。ログイン項目を新しい場所で登録し直す(一度だけ)
            if !settings.loginItemMovedToYudh {
                try? SMAppService.mainApp.unregister()
                settings.loginItemMovedToYudh = true
            }
            // ログイン時に起動は常にオン(設定の切り替えは無い)。
            // システム設定で明示的に切られた(承認待ち)ときだけは尊重する
            if SMAppService.mainApp.status == .notRegistered {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    AppLog.shared.log("app", "ログイン項目の登録に失敗： \(error)")
                }
            }
        }

        NotificationService.shared.requestPermission()
        // 打刻機能は 2026-09-29 に廃止。旧版が OS に予約した退勤リマインドを掃除する
        NotificationService.shared.cancelPending(prefix: "nippo-punch")
        Task { [weak self] in
            let ok = await self?.calendarProvider.requestAccess() ?? false
            await MainActor.run {
                self?.calendarAuthorized = ok
                self?.refreshTodayEvents()
                self?.refreshShachoken(force: true)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        let now = Date()

        // 勤務時間に入ったら(毎朝・再起動時)座り作業として計り始める
        let working = isWorkingNow
        if working && !wasWorking {
            posture = .sitting
            resetPostureTimer(now: now)
        }
        wasWorking = working

        // メニューの会議一覧はお休みの日でも更新する。
        // 会議リマインドは OS 予約制(scheduleMeetingReminders):スリープで時刻を跨いでも届く
        refreshTodayEvents()
        refreshShachoken()

        // 座り/立ちの切り替え(勤務日の勤務時間のみ・会議中は後回し)
        checkPosture(now: now)
    }

    private var eventsRefreshInFlight = false

    func refreshTodayEvents() {
        guard calendarAuthorized, !eventsRefreshInFlight else { return }
        eventsRefreshInFlight = true
        let provider = calendarProvider
        // EventKit の同期フェッチをメインスレッドから追い出す(終極監査 major の修正)
        Task.detached(priority: .utility) { [weak self] in
            let events = provider.events(on: Date())
            await MainActor.run {
                guard let self else { return }
                self.eventsRefreshInFlight = false
                self.todayEvents = events
                self.statusBarTitle = NextEventPolicy.statusTitle(events: events, now: Date())
                self.scheduleMeetingReminders(for: events)
            }
        }
    }

    /// 次のシャチョケンを 90 日先まで探す。範囲が広いので 10 分に 1 回まで(メニューを開いたときは即時)
    func refreshShachoken(force: Bool = false) {
        guard calendarAuthorized, !shachokenInFlight else { return }
        if !force, let at = shachokenFetchedAt, Date().timeIntervalSince(at) < 600 { return }
        shachokenInFlight = true
        let provider = calendarProvider
        let keywords = settings.shachokenKeywords
            .components(separatedBy: CharacterSet(charactersIn: ",、,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        Task.detached(priority: .utility) { [weak self] in
            let now = Date()
            let events = provider.events(from: Calendar.current.startOfDay(for: now),
                                         to: now.addingTimeInterval(90 * 24 * 3600))
            let next = NextEventPolicy.nextMatching(keywords, in: events, now: now)
            await MainActor.run {
                guard let self else { return }
                self.nextShachoken = next
                self.shachokenFetchedAt = Date()
                self.shachokenInFlight = false
            }
        }
    }

    /// 設定ウインドウを前面に開く(メニューの歯車ボタン)
    func openSettings() {
        settingsWindow.show()
    }

    func saveTaskMemo(_ text: String) {
        settings.taskMemo = text
        lastCompletedTask = nil
        objectWillChange.send()
    }

    /// 完了したタスク(直後なら「元に戻す」で完了前のメモに戻せる)
    struct CompletedTask: Equatable {
        let title: String
        let previousMemo: String
    }
    @Published private(set) var lastCompletedTask: CompletedTask?

    /// タスク 1 つを完了(メモから消す)
    func completeTask(at index: Int) {
        let memo = settings.taskMemo
        let blocks = TaskOutline.blocks(memo)
        guard blocks.indices.contains(index) else { return }
        let block = blocks[index]
        lastCompletedTask = CompletedTask(title: block.title ?? block.items.first?.text ?? "任务",
                                          previousMemo: memo)
        settings.taskMemo = TaskOutline.removing(block: index, from: memo)
        objectWillChange.send()
        AppLog.shared.log("task", "done \(lastCompletedTask?.title ?? "")")
    }

    func undoCompleteTask() {
        guard let done = lastCompletedTask else { return }
        settings.taskMemo = done.previousMemo
        lastCompletedTask = nil
        objectWillChange.send()
    }

    /// 予約済みの会議リマインド(ID → 内容)。30 秒ごとの再計算で同じ予約を積み直さない
    /// (毎回 add+ログしていたため nippo.log が 1 日数千行になり、数日でローテートして履歴が消えていた)
    private var scheduledMeetingReminders: [String: String] = [:]

    /// 今日の残り会議のリマインドを OS に事前予約する(30 秒ポーリング撤廃・スリープ耐性)。
    /// お休みの日(週末・祝日・休暇日)は予約せず取消す。変更・削除された予定の予約も reconcile で取消す。
    func scheduleMeetingReminders(for events: [MeetingEvent]) {
        guard isWorkday else {
            scheduledMeetingReminders.removeAll()
            NotificationService.shared.reconcileMeetingReminders(validIDs: [])
            return
        }
        let lead = settings.reminderLeadMinutes
        var next: [String: String] = [:]
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        for e in events where !e.isAllDay {
            let fireDate = e.start.addingTimeInterval(TimeInterval(-lead * 60))
            guard fireDate.timeIntervalSinceNow > 1 else { continue }
            let id = "nippo-meet-\(e.id)-\(Int(e.start.timeIntervalSince1970))-\(lead)"
            let title = "即将开会：\(e.title)"
            let body = "\(f.string(from: e.start)) 开始"
                + (e.joinURL != nil ? "。点击加入会议" : "")
            let signature = [title, body, e.joinURL?.absoluteString ?? ""]
                .joined(separator: "\n")
            next[id] = signature
            // 同じ ID・同じ内容で予約済みなら積み直さない(件名や参加リンクの変更時だけ差し替え)
            guard scheduledMeetingReminders[id] != signature else { continue }
            NotificationService.shared.scheduleMeetingReminder(
                identifier: id, title: title, body: body,
                joinURL: e.joinURL, fireDate: fireDate)
        }
        scheduledMeetingReminders = next
        NotificationService.shared.reconcileMeetingReminders(validIDs: Set(next.keys))
    }

    /// お休みの日の理由(週末/祝日/設定の休暇日)。勤務日なら nil。カレンダーの予定は見ない
    var quietReasonToday: String? {
        (try? quietDays.reason(for: Date()))?.rawValue
    }

    /// 今日の出勤時刻(手入力)。未入力・前日以前の入力なら nil
    var workBeganAt: Date? {
        guard settings.workBeganDay == DayKey.key(for: Date()),
              let text = settings.workBeganTime,
              let (h, m) = WorkStart.parse(text) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
    }

    /// 「853」などを今日の出勤時刻として保存する。失敗したら理由を返す
    func setWorkBegan(_ text: String) -> String? {
        guard let (h, m) = WorkStart.parse(text) else {
            return "看不懂这个时间（例：8:53 就输入 853）"
        }
        guard let date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()),
              date <= Date() else {
            return "不能填还没到的时间"
        }
        settings.workBeganTime = String(format: "%02d:%02d", h, m)
        settings.workBeganDay = DayKey.key(for: Date())
        objectWillChange.send()
        AppLog.shared.log("work", "began \(settings.workBeganTime ?? "")")
        return nil
    }

    /// 勤務日か(会議リマインドを出す日)
    var isWorkday: Bool { quietReasonToday == nil }

    /// 勤務日の勤務時間内か(立ち作業リマインドを出す時間)
    var isWorkingNow: Bool {
        isWorkday && settings.isWithinWorkHours(Date())
    }
}
