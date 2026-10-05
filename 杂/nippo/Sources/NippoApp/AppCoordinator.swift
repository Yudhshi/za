import Foundation
import AppKit
import EventKit
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
    /// 会前に「站着开会？」と聞いている会議(小窓の中身。聞いていなければ nil)。
    /// 会議名や長さが変わったら小窓の高さも合わせ直す
    @Published var meetingAsk: MeetingEvent? {
        didSet { if posturePrompt == .standForMeeting { posturePanel.update() } }
    }
    /// 「站着开 / 坐着开」と答えた会議(その日のうち。同じ会議で何度も聞かない)
    var meetingAskAnswered: Set<String> = []
    /// マイクかカメラが使われている(通話中)。2 回続けて(30 秒以上)見えたら通話とみなす(音声入力の一瞬は数えない)
    @Published var inCall = false
    /// マイク・カメラが続けて見えた / 見えなかった tick の数(始まりも終わりも 2 回続けて見えたら)
    private var callTicks = 0
    private var callMissTicks = 0
    /// ログに残した、いまマイク・カメラを使っているもの(変わったら残し直す)
    private var loggedCallSources: Set<String> = []
    /// いまの通話が始まった時刻と、最後に終わった通話(早く終わった会議を見分ける)
    private var callStartedAt: Date?
    var lastCall: DateInterval?
    /// 会議の最中か通話中だった最後の時刻(終わってすぐ小窓を出さない・会議中の無操作を離席と数えない)と、
    /// その忙しさが始まった時刻(5 分以上続いた会議・通話のあとだけ「开完会了」と添える)
    var lastBusyAt: Date?
    var busySince: Date?
    /// 会議・通話が終わってすぐに出た「站起来了吗？/ 坐下了吗？」(問いの下に「开完会了」と添える)
    @Published var promptAfterMeeting = false
    /// 「坐着开」で会議の終わりまで「站起来了吗？」を待たせている会議(取り消された・早く終わったら待たせない)
    var postureHoldMeetingID: String?
    /// 「15 分钟后」で自分で後回しにした時刻(そのあいだは「站着开会？」も聞かない)
    var postureSnoozedUntil: Date?
    /// メニューから開いた「站起来了吗？」が、会議・通話の最中に開いたものか(それなら通話中でも閉じない)
    var posturePinnedWhileBusy = false
    /// 日历のアカウントに最後に取りに行かせた時刻(5 分ごと)
    private var lastSourceRefreshAt: Date?
    /// 日历が変わった知らせ(臨時の会議が入ったらすぐ読み直す)
    private var calendarObserver: NSObjectProtocol?
    /// 前回の tick。スリープや日付をまたいだら姿勢を計り直す
    private var lastTickAt: Date?
    /// 英語の同期を最後に走らせた時刻(5 分ごと)
    private var lastSyncAt: Date?
    /// ほかの端末(Windows)の日课・腹式呼吸の記録。同期フォルダから読む(5 分ごと・記録したとき)
    @Published private(set) var otherHabits = Habits()
    private var habitsSyncInFlight = false
    /// 書いている最中に記録が増えた(終わったらもう一度書く)
    private var habitsSyncAgain = false
    /// 画面上部の小窓(nil で閉じる)。変わるたびに小窓を出し入れ・サイズ調整する
    @Published var posturePrompt: BreakReminder.Prompt? {
        didSet {
            if posturePrompt == nil { promptAfterMeeting = false }
            posturePanel.update()
        }
    }
    @Published var promptStretch = BreakReminder.Stretch(name: "", steps: [])
    /// 手順の何番目か(毎回の斜角肌 → 順番の分、の通し。promptSteps.count = 完了)
    @Published var stretchStep = 0 {
        didSet {
            stretchStepStartedAt = Date()
            posturePanel.update()
        }
    }
    /// 今の手順を数え始めた時刻(手順が変わる・呼吸が終わる・小窓を開き直すと今から)。時間が来たら小窓が自分で次の手順へ
    var stretchStepStartedAt = Date()
    /// 立ってすぐの腹式呼吸 3 回を始めた時刻(終わる・飛ばすと nil。そのあとが拉伸の手順)
    @Published var breathStartedAt: Date? {
        didSet {
            if breathStartedAt == nil { stretchStepStartedAt = Date() }
            posturePanel.update()
        }
    }
    lazy var posturePanel = PosturePanelController(coordinator: self)
    private lazy var settingsWindow = SettingsWindowController(coordinator: self)
    private lazy var ritualWindow = RitualWindowController(coordinator: self)
    /// 英語タブ(すきま時間の英語)
    lazy var english: EnglishCoordinator = {
        let english = EnglishCoordinator(db: db)
        // Meet の会議中・通話中は語料を自動再生しない(通話にマイクで拾われないように)
        english.isInMeeting = { [weak self] in
            guard let self else { return false }
            // 音を出さないためなので、通話の判定(30 秒待つ)より早く、マイクが使われた時点で止める
            return self.inCall || self.callTicks > 0
                || BreakReminder.isInMeeting(events: self.todayEvents, now: Date())
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
        guard let database = opened else { fatalError("DB 初期化失敗: \(dbNotes)") }
        db = database
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
        // 日历の中身が変わったら(Google から新しい会議が届いた・動いた・取り消された)、30 秒を待たずに読み直す
        calendarObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshTodayEvents()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // 数秒ずれてもよいので、システムに起床をまとめさせる(常駐アプリの省電力)
        timer?.tolerance = 5
        // 日课・呼吸の記録を Windows と足し合わせる(起動時に書いて、向こうの分を読む)
        syncHabits()
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
            meetingAsk = nil
            // 答えた会議は日付が変わったときだけ忘れる(昼休みに合盖しても、同じ会議をもう一度聞かない)
            if DayKey.key(for: last) != DayKey.key(for: now) { meetingAskAnswered = [] }
            lastBusyAt = nil
            busySince = nil
            lastCall = nil
            // 通話の途中で眠ったら、その通話は無かったことにする(朝起きて「夜通しの通話が終わった」と数えない)
            callTicks = 0
            callMissTicks = 0
            callStartedAt = nil
            loggedCallSources = []
            if inCall { inCall = false }
            promptAfterMeeting = false
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

        // 通話中か(マイク・カメラ)。坐站の判定と語料の自動再生に使う。
        // 始まりも終わりも 2 回続けて(30 秒以上)見えたら変える(音声入力の一瞬・通話中の一瞬の途切れは数えない)
        let sources = settings.callDetection ? CallDetector.activeSources() : []
        if sources.isEmpty {
            callTicks = 0
            callMissTicks += 1
        } else {
            callTicks += 1
            callMissTicks = 0
        }
        let call = settings.callDetection && (inCall ? callMissTicks < 2 : callTicks >= 2)
        if call != inCall {
            inCall = call
            if call {
                callStartedAt = now
            } else if let start = callStartedAt {
                // 会議を早く終わらせるのは 5 分以上の通話だけ(短い通話で、その前の通話の記録を上書きしない)
                if now.timeIntervalSince(start) >= BreakReminder.afterMeetingMinimum {
                    lastCall = DateInterval(start: start, end: now)
                }
                callStartedAt = nil
            }
            if working, !call { AppLog.shared.log("posture", "call ended") }
        }
        // 何がマイク・カメラを使っているかを、変わるたびに残す(一日中開けっぱなしのアプリで提醒が止まったときの手がかり)。勤務時間だけ
        let current = Set(sources)
        if call, working, !current.isEmpty, current != loggedCallSources {
            loggedCallSources = current
            AppLog.shared.log("posture", "in call (\(current.sorted().joined(separator: ", ")))")
        }
        if !call { loggedCallSources = [] }

        // Google のアカウントは押し通知が無いので、勤務時間は 5 分ごとに日历へ取りに行かせる(臨時の会議を早く拾う)
        if calendarAuthorized, working, lastSourceRefreshAt.map({ now.timeIntervalSince($0) >= 300 }) ?? true {
            lastSourceRefreshAt = now
            calendarProvider.refreshSources()
        }

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
            syncHabits()
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
        syncHabits()
    }

    /// このパソコンの日课・呼吸の記録(設定の中)
    var ownHabits: Habits {
        Habits(ritual: settings.ritualLog, ritualStrength: settings.ritualStrengthLog, breath: settings.breathLog)
    }

    /// Windows の分も足した記録。連続日数・隔天の力量・今日の呼吸の回数はこれで数える
    var habits: Habits {
        ownHabits.merged(with: otherHabits)
    }

    /// 今日の腹式呼吸の回数(Windows で立ったときの分も含む)
    var breathToday: Int {
        habits.breath[DayKey.key(for: Date())] ?? 0
    }

    /// 同期フォルダに自分の記録を書き(同じ中身なら書かない)、ほかの端末の記録を読み直す。
    /// 端末名を変えたら古い名前のファイルを消す(別の端末として二重に数えないように)。フォルダが無ければ自分の分だけ
    func syncHabits() {
        guard let root = settings.syncRoot else {
            if otherHabits != Habits() { otherHabits = Habits() }
            return
        }
        guard !habitsSyncInFlight else {
            habitsSyncAgain = true
            return
        }
        habitsSyncInFlight = true
        let own = ownHabits
        let device = settings.deviceName
        let folder = URL(fileURLWithPath: root)
        let file = folder.appendingPathComponent(HabitsSync.fileName(for: device)).path
        let previous = settings.habitsWrittenPath
        Task.detached(priority: .utility) { [weak self] in
            // let にしておく(var だと、下の MainActor.run から読めない:並行に動くコードからの捕獲)
            let failure: String?
            do {
                try HabitsSync.write(own, device: device, to: folder)
                if let previous, previous != file,
                   (previous as NSString).deletingLastPathComponent == folder.path {
                    try? FileManager.default.removeItem(atPath: previous)
                }
                failure = nil
            } catch {
                failure = "\(error)"
            }
            let others = HabitsSync.others(device: device, root: folder)
            await MainActor.run {
                guard let self else { return }
                self.habitsSyncInFlight = false
                if let failure {
                    AppLog.shared.log("habits", "habits file write failed: \(failure)")
                } else {
                    self.settings.habitsWrittenPath = file
                }
                if self.otherHabits != others { self.otherHabits = others }
                if self.habitsSyncAgain {
                    self.habitsSyncAgain = false
                    self.syncHabits()
                }
            }
        }
    }

    /// 腹式呼吸 3 回が終わった(飛ばしたときは数えない)。そのまま拉伸の手順へ
    func finishBreath(counted: Bool) {
        guard breathStartedAt != nil else { return }
        if counted {
            settings.breathLog = BreathLog.recording(settings.breathLog, day: DayKey.key(for: Date()))
            syncHabits()
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
            // 会議の前の数分も碎片時間:腹式呼吸を 3 回(习惯にする)。45 分以上の会議は水を持って入る
            var tips: [String] = []
            if settings.breathHabit { tips.append("开会前先做 3 次腹式呼吸") }
            if e.joinURL != nil, BreakReminder.isLong(e) { tips.append("会比较长，倒杯水带进去") }
            let join: String = e.joinURL != nil ? "。点击加入会议" : ""
            let tipText: String = tips.isEmpty ? "" : "。" + tips.joined(separator: "；")
            let body: String = f.string(from: e.start) + " 开始" + join + tipText
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
