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
    /// 明日の予定(今日の会議がもう無いとき、主角卡で明日の最初の会議を予告する。読み込みは今日の分と一緒)
    @Published private(set) var tomorrowEvents: [MeetingEvent] = []
    /// todayEvents / tomorrowEvents を読んだ日("yyyy-MM-dd")。日付が変わって読み直す前の古い予定を、今日・明日と取り違えないため
    @Published private(set) var eventsDay = ""
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
    /// 「关闭」で自分が閉じた立ち作業の手順(会議で隠れたのとは区別して、会議後に戻す)
    var standingGuideDismissed = false
    /// メニューから自分で開いた「站起来了吗?」(時間前でも判定で閉じない)
    var posturePromptPinned = false
    /// 前回の tick。スリープや日付をまたいだら姿勢を計り直す
    private var lastTickAt: Date?
    /// 英語の同期を最後に走らせた時刻(5 分ごと)
    private var lastSyncAt: Date?
    /// 画面上部の小窓(nil で閉じる)。変わるたびに小窓を出し入れ・サイズ調整する
    @Published var posturePrompt: BreakReminder.Prompt? {
        didSet { posturePanel.update() }
    }
    @Published var promptStretch = BreakReminder.Stretch(name: "", steps: [])
    /// 手順の何番目か(steps.count = 完了)
    @Published var stretchStep = 0 {
        didSet { posturePanel.update() }
    }
    /// 立ってすぐの腹式呼吸 3 回を始めた時刻(終わる・飛ばすと nil。そのあとが拉伸の手順)
    @Published var breathStartedAt: Date? {
        didSet { posturePanel.update() }
    }
    lazy var posturePanel = PosturePanelController(coordinator: self)
    private lazy var settingsWindow = SettingsWindowController(coordinator: self)
    private lazy var ritualWindow = RitualWindowController(coordinator: self)
    /// 英語タブ(すきま時間の英語)
    lazy var english: EnglishCoordinator = {
        let english = EnglishCoordinator(db: db)
        // Meet の会議中は語料を自動再生しない(通話にマイクで拾われないように)
        english.isInMeeting = { [weak self] in
            guard let self else { return false }
            return BreakReminder.isInMeeting(events: self.todayEvents, now: Date())
        }
        // 同期(設定でフォルダを選んだときだけ)
        english.deviceName = { [weak self] in self?.settings.deviceName ?? "Mac" }
        english.syncRoot = { [weak self] in self?.settings.syncRoot }
        english.libraryExport = { [weak self] in self?.settings.libraryExport ?? false }
        return english
    }()

    let calendarProvider: CalendarProviding = EventKitCalendar()
    private var timer: Timer?
    @Published var calendarAuthorized = false

    init() {
        // DB は 設定の保存先 → 既定の保存先 → メモリ の順に試す。
        // 設定に書けないパスを入れても、起動のたびに落ちる(fatalError)ループにはしない
        let root = settings.reportsRoot
        let defaultRoot = ("~/Documents/日報" as NSString).expandingTildeInPath
        var opened: AppDatabase?
        var dbNotes: [String] = []
        for dir in [root, defaultRoot] where opened == nil {
            do {
                opened = try AppDatabase(path: (dir as NSString).appendingPathComponent("nippo.sqlite"))
            } catch {
                dbNotes.append("DB を開けない: \(dir): \(error)")
            }
        }
        if opened == nil, let memory = try? AppDatabase.inMemory() {
            opened = memory
            dbNotes.append("メモリ上の DB で動く(休暇日・英語の記録は保存されない)")
        }
        guard let opened else { fatalError("DB 初期化失敗: \(dbNotes)") }
        db = opened
        AppLog.shared.configure(root: URL(fileURLWithPath: root))
        let info = Bundle.main.infoDictionary
        AppLog.shared.log("app", "起動 Yudh \(info?["CFBundleShortVersionString"] as? String ?? "dev") "
                          + "(\(info?["CFBundleVersion"] as? String ?? "-"))")
        dbNotes.forEach { AppLog.shared.log("app", $0) }
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
        // 数秒ずれてもよいので、システムに起床をまとめさせる(常駐アプリの省電力)
        timer?.tolerance = 5
    }

    func tick() {
        let now = Date()

        // スリープや日付をまたいだら(10 分以上 tick が止まっていたら)姿勢は計り直す。
        // 昨日の夕方に立ったまま合盖 → 今朝「已站 900 分钟」と聞かれないように
        if let last = lastTickAt,
           now.timeIntervalSince(last) > 600 || DayKey.key(for: last) != DayKey.key(for: now) {
            posture = .sitting
            resetPostureTimer(now: now)
            standingGuideDismissed = false
            posturePromptPinned = false
            if posturePrompt != nil { posturePrompt = nil }
        }
        lastTickAt = now

        // 起動後にシステム設定でカレンダーを許可された場合に追従する(再起動しなくてよい)
        if !calendarAuthorized, calendarProvider.isAuthorized {
            calendarAuthorized = true
            AppLog.shared.log("app", "カレンダー権限を検出")
            refreshShachoken(force: true)
        }

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
        // メニューバーの残り時間は毎 tick 計算し直す(fetch の完了を待たない・権限が消えたら消す)
        statusBarTitle = calendarAuthorized ? NextEventPolicy.statusTitle(events: todayEvents, now: now) : nil

        // 座り/立ちの切り替え(勤務日の勤務時間のみ・会議中は後回し)
        checkPosture(now: now)

        // 英語の進捗の同期(フォルダを設定しているときだけ、5 分ごと。パネルを開いたときにも走る)
        if settings.syncRoot != nil, lastSyncAt.map({ now.timeIntervalSince($0) >= 300 }) ?? true {
            lastSyncAt = now
            english.syncNow()
        }
    }

    private var eventsRefreshInFlight = false
    /// agenda.json を最後に書けなかった理由(同じ失敗を毎分ログに積まない)
    private var agendaFailure: String?

    func refreshTodayEvents() {
        guard calendarAuthorized, !eventsRefreshInFlight else { return }
        eventsRefreshInFlight = true
        let provider = calendarProvider
        // 同期フォルダがあれば、今日と明日の会議を agenda.json に書く(Windows はこれだけを読む)
        let agendaRoot = settings.agendaExport ? settings.syncRoot : nil
        let device = settings.deviceName
        // EventKit の同期フェッチをメインスレッドから追い出す(終極監査 major の修正)
        Task.detached(priority: .utility) { [weak self] in
            let now = Date()
            let events = provider.events(on: now)
            // 明日の予定も読む(リマインド予約用)。夜のスリープ中に日付が変わっても、朝一の会議の通知が届くように
            let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: now)
            let tomorrow = tomorrowDate.map { provider.events(on: $0) } ?? []
            // 中身が前と同じなら書かない(同期盘が毎分アップロードしないように)
            let agendaFailure: String? = {
                guard let agendaRoot, let tomorrowDate else { return nil }
                do {
                    try AgendaExport.write(days: [AgendaExport.Day(day: DayKey.key(for: now), events: events),
                                                  AgendaExport.Day(day: DayKey.key(for: tomorrowDate), events: tomorrow)],
                                           device: device, to: URL(fileURLWithPath: agendaRoot), now: now)
                    return nil
                } catch {
                    return "\(error)"
                }
            }()
            await MainActor.run {
                guard let self else { return }
                if agendaFailure != self.agendaFailure {
                    if let agendaFailure { AppLog.shared.log("agenda", "agenda.json write failed: \(agendaFailure)") }
                    self.agendaFailure = agendaFailure
                }
                self.eventsRefreshInFlight = false
                self.todayEvents = events
                self.tomorrowEvents = tomorrow
                self.eventsDay = DayKey.key(for: now)
                self.statusBarTitle = NextEventPolicy.statusTitle(events: events, now: Date())
                self.scheduleMeetingReminders(for: events + tomorrow)
            }
        }
    }

    /// 次のシャチョケンを 90 日先まで探す。範囲が広いので 10 分に 1 回まで(メニューを開いたときは即時)
    func refreshShachoken(force: Bool = false) {
        guard calendarAuthorized, !shachokenInFlight else { return }
        // 10 分以内は再取得しない。ただし表示中の予定が終わったらすぐ次を探す
        if !force, let at = shachokenFetchedAt, Date().timeIntervalSince(at) < 600,
           !(nextShachoken.map { $0.end <= Date() } ?? false) { return }
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

    /// 泡完澡了:日课の窓を開く(跟练の動画 → 拉伸 → 腹式呼吸)
    func openRitual() {
        ritualWindow.show()
    }

    /// 日课をやり終えた(最後が仰向けの腹式呼吸なので、呼吸の 1 回にも数える)。力量を入れた日は隔天の記録も
    func recordRitual(strength: Bool) {
        let today = DayKey.key(for: Date())
        settings.ritualLog = BreathLog.recording(settings.ritualLog, day: today)
        if strength {
            settings.ritualStrengthLog = BreathLog.recording(settings.ritualStrengthLog, day: today)
        }
        settings.breathLog = BreathLog.recording(settings.breathLog, day: today)
        objectWillChange.send()
    }

    /// 今日の腹式呼吸の回数
    var breathToday: Int {
        settings.breathLog[DayKey.key(for: Date())] ?? 0
    }

    /// 腹式呼吸 3 回が終わった(飛ばしたときは数えない)。そのまま拉伸の手順へ
    func finishBreath(counted: Bool) {
        guard breathStartedAt != nil else { return }
        if counted {
            settings.breathLog = BreathLog.recording(settings.breathLog, day: DayKey.key(for: Date()))
        }
        breathStartedAt = nil
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

    /// 今日と明日の会議のリマインドを OS に事前予約する(30 秒ポーリング撤廃・スリープ耐性)。
    /// その予定の日がお休み(週末・祝日・休暇日)なら予約しない(今日が休みでも明日が勤務日なら明日の分は予約する)。
    /// 変更・削除された予定の予約は reconcile で取消す。
    func scheduleMeetingReminders(for events: [MeetingEvent]) {
        let lead = settings.reminderLeadMinutes
        var next: [String: String] = [:]
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let now = Date()
        for e in events where !e.isAllDay {
            guard (try? quietDays.reason(for: e.start)) == nil else { continue }
            // すでに始まった予定は対象外。開始 lead 分前を過ぎていてまだ始まっていなければ
            // (起床直後・起動直後)すぐに通知する
            guard e.start.timeIntervalSince(now) > 1 else { continue }
            let fireDate = max(e.start.addingTimeInterval(TimeInterval(-lead * 60)),
                               now.addingTimeInterval(2))
            let id = "nippo-meet-\(e.id)-\(Int(e.start.timeIntervalSince1970))-\(lead)"
            let title = "即将开会：\(e.title)"
            // 会議の前の数分も碎片時間:腹式呼吸を 3 回(习惯にする)
            let body = "\(f.string(from: e.start)) 开始"
                + (e.joinURL != nil ? "。点击加入会议" : "")
                + (settings.breathHabit ? "。开会前先做 3 次腹式呼吸" : "")
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
