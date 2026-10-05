import AppKit
import CoreGraphics
import Foundation
import NippoCore

/// 昇降デスクの座り/立ち切り替え。通知ではなく画面上部の小窓で尋ねる:
/// 「立ちましたか?」→ 立った → 立ち作業の残り時間とストレッチの手順 → 「座りましたか?」。
/// Google Meet の会議中・直前と通話中(マイク・カメラが使われている)は出さず、終わって 1 分たってから聞く。
/// 座っていて会議が近づいたら「站着开会？」。座っているあいだ 3 分以上操作がなければ離席とみなして計り直す
/// (会議・通話のあいだの無操作は数えない)
extension AppCoordinator {
    /// 次に切り替える時刻(「あとで」を押したら postureRemindAt が優先)
    var postureDueAt: Date {
        let limit = posture == .sitting ? settings.sitMinutes : settings.standMinutes
        return postureRemindAt ?? postureSince.addingTimeInterval(TimeInterval(limit * 60))
    }

    /// 次に出すストレッチ(メニューにも予告する。毎回の斜角肌のあとにやる、順番の 1 つ)
    var nextStretch: BreakReminder.Stretch {
        BreakReminder.stretch(at: settings.lastStretchIndex,
                              in: BreakReminder.stretches(from: settings.stretches))
    }

    /// 立つたびに必ずやる拉伸(斜角肌)
    var fixedStretches: [BreakReminder.Stretch] {
        BreakReminder.stretches(from: settings.fixedStretches)
    }

    /// 今回の拉伸:毎回の斜角肌 → 順番の 1 つ(Windows と同じ並び)
    var promptParts: [BreakReminder.Stretch] {
        fixedStretches + (promptStretch.name.isEmpty ? [] : [promptStretch])
    }

    /// 今回の手順(通し)。小窓はこれを 1 歩ずつ、時間が来たら自分で次へ進めて見せる
    var promptSteps: [StretchGuide.Step] {
        StretchGuide.routineSteps(promptParts)
    }

    /// 最後のキーボード・マウス操作からの秒数(権限不要)
    nonisolated static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    /// 坐站の判定に使う今日の会議:通話を見張っていれば、その会議の通話(5 分以上)が終わった会議は「もう終わった」
    /// (予定の終わりまで待たない)。通話中は日历のまま
    func postureEvents(now: Date) -> [MeetingEvent] {
        guard !inCall else { return todayEvents }
        return BreakReminder.excludingEndedEarly(todayEvents, now: now,
                                                 lastCall: settings.callDetection ? lastCall : nil)
    }

    /// 問いに「开完会」と添えるか:もう会議・通話の最中ではなく、5 分以上の会議・通話が終わって 10 分以内
    func saysAfterMeeting(events: [MeetingEvent], now: Date) -> Bool {
        !inCall && !BreakReminder.isInMeeting(events: events, now: now, lead: 0)
            && BreakReminder.saysAfterMeeting(now: now, busySince: busySince, lastBusyAt: lastBusyAt)
    }

    func checkPosture(now: Date) {
        guard settings.postureEnabled, isWorkingNow else {
            if posturePrompt != nil { posturePrompt = nil }
            if meetingAsk != nil { meetingAsk = nil }
            return
        }
        let events = postureEvents(now: now)
        // 「坐着开」で待たせていた会議が取り消された・早く終わったら、待たせるのをやめる(ふつうの切り替え時刻に戻す)
        if let id = postureHoldMeetingID, !events.contains(where: { $0.id == id }) {
            postureHoldMeetingID = nil
            postureRemindAt = nil
        }
        let inMeeting = BreakReminder.isInMeeting(events: events, now: now)
        // 会議の最中(開始前の 5 分は含まない)か通話中なら「忙しい」:終わった直後の猶予と、無操作の数え方と、「开完会了」に使う
        if inCall || BreakReminder.isInMeeting(events: events, now: now, lead: 0) {
            if lastBusyAt.map({ now.timeIntervalSince($0) > 90 }) ?? true { busySince = now }
            lastBusyAt = now
        }
        // 座りっぱなしの計測だけ離席でリセット(立ち作業の残り時間は巻き戻さない)。
        // 会議・通話のあいだの無操作は「座って会議中」(終わった直後にまとめて離席と数えない)。
        // 自動で出た「站起来了吗？」に 10 分答えず何も触らなければ、席を外したとみなして閉じる(会議のあと席を立った人に、
        // 戻ってから水増しした分数を見せない)。自分で開いた小窓・ほかの小窓のあいだは判定しない
        let awayAfter: TimeInterval? = posturePrompt == nil ? 180
            : (posturePrompt == .askStand && !posturePromptPinned ? 600 : nil)
        if posture == .sitting, let awayAfter, !inMeeting, !inCall,
           BreakReminder.awayIdle(idle: Self.idleSeconds(), now: now, lastBusyAt: lastBusyAt) >= awayAfter {
            resetPostureTimer(now: now)
        }
        // 座っていて 10 分以内に会議:「站着开会？」(答えた会議・自分で「15 分钟后」と後回しにしているあいだは聞かない)
        let snoozed = postureSnoozedUntil.map { $0 > now } ?? false
        let ask = settings.meetingStandAsk && !snoozed
            ? BreakReminder.meetingStandAsk(events: events, now: now, posture: posture,
                                            sittingSince: postureSince, answered: meetingAskAnswered)
            : nil
        if ask != meetingAsk { meetingAsk = ask }
        let desired = BreakReminder.desiredPrompt(
            posture: posture, current: posturePrompt, now: now, dueAt: postureDueAt,
            inMeeting: inMeeting, guideDismissed: standingGuideDismissed,
            inCall: inCall, standForMeeting: ask != nil,
            quietUntil: lastBusyAt?.addingTimeInterval(BreakReminder.afterMeetingGrace))
        // 出ている問いの「开完会」を今に合わせる(会議の最中には添えない・10 分たったら外す)
        if posturePrompt == .askStand || posturePrompt == .askSit {
            let says = saysAfterMeeting(events: events, now: now)
            if says != promptAfterMeeting { promptAfterMeeting = says }
        }
        // メニューから自分で開いた「站起来了吗?」・拉伸の手順は、時間前でも閉じない。会議・通話の最中に開いたものはそのまま、
        // 開いたあとで会議・通話に入ったら閉じる
        if desired == nil, posturePromptPinned, posturePrompt == .askStand || posturePrompt == .standing,
           posturePinnedWhileBusy || (!inMeeting && !inCall) { return }
        guard desired != posturePrompt else { return }
        posturePromptPinned = false
        if desired == .askStand { pickStretch() }
        // 5 分以上の会議・通話が終わって 10 分以内に出た問いには「开完会」と添える
        promptAfterMeeting = (desired == .askStand || desired == .askSit) && saysAfterMeeting(events: events, now: now)
        posturePrompt = desired
        AppLog.shared.log("posture", "prompt \(String(describing: desired))")
    }

    /// 会前「站着开」:立って会議に出る。すぐ会議なので拉伸の手順と腹式呼吸は出さず、拉伸の順番も進めない。
    /// 立ち作業の計時はここから(会議中は「坐下了吗？」を出さず、終わってから聞く)
    func standForMeeting() {
        if let meeting = meetingAsk { meetingAskAnswered.insert(meeting.id) }
        meetingAsk = nil
        breathStartedAt = nil
        // 会議のあとメニューから手順を開いたときに出す拉伸(順番は実際に「站起来了」で立ったときだけ進める)
        pickStretch()
        posture = .standing
        resetPostureTimer(now: Date())
        standingGuideDismissed = true
        posturePromptPinned = false
        posturePrompt = nil
        AppLog.shared.log("posture", "stood for a meeting")
    }

    /// 会前「坐着开」:この会議は座って出る。「站起来了吗？」は会議が終わるまで出さない(会議の前に聞き直さない)
    func sitForMeeting() {
        if let meeting = meetingAsk {
            meetingAskAnswered.insert(meeting.id)
            postureRemindAt = max(postureDueAt, meeting.end)
            postureHoldMeetingID = meeting.id
        }
        meetingAsk = nil
        posturePromptPinned = false
        posturePrompt = nil
        AppLog.shared.log("posture", "sitting through a meeting")
    }

    /// 「立った」(小窓・メニュー):立ち作業の残り時間とストレッチの手順を出す
    func confirmStood() {
        if posturePrompt != .askStand { pickStretch() }
        // 実際に立ったときに初めて「このストレッチはやった」と数える(推迟しても飛ばない)
        let count = BreakReminder.stretches(from: settings.stretches).count
        settings.lastStretchIndex = (settings.lastStretchIndex + 1) % max(1, count)
        posture = .standing
        resetPostureTimer(now: Date())
        standingGuideDismissed = false
        // 会議・通話の最中にメニューから開いた問いで立ったなら、手順も会議中に閉じない
        posturePromptPinned = posturePromptPinned && posturePinnedWhileBusy
        // 立ったらまず腹式呼吸を 3 回(习惯にする。拉伸はそのあと)
        breathStartedAt = settings.breathHabit ? Date() : nil
        posturePrompt = .standing
        AppLog.shared.log("posture", "stood")
    }

    /// 「座った」(小窓・メニュー)
    func confirmSat() {
        breathStartedAt = nil
        posture = .sitting
        resetPostureTimer(now: Date())
        standingGuideDismissed = false
        posturePromptPinned = false
        posturePrompt = nil
        AppLog.shared.log("posture", "sat")
    }

    /// 「15分後」「あと5分」:小窓を閉じて、その分だけ後にもう一度尋ねる
    func snoozePosture(minutes: Int) {
        breathStartedAt = nil
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        postureRemindAt = until
        postureSnoozedUntil = until
        postureHoldMeetingID = nil
        posturePromptPinned = false
        posturePrompt = nil
    }

    /// メニューの姿勢チップから小窓を開く:立ち作業中は手順、座り作業中は「立ちましたか?」。
    /// 座り作業中は切り替え時刻を今にする(次の判定で小窓が閉じないように)
    func openPosturePrompt() {
        let now = Date()
        let events = postureEvents(now: now)
        // 会議・通話の最中に自分で開いたら(立って会議に出たい・会議中に拉伸を見たい)、通話中でも閉じない
        posturePinnedWhileBusy = inCall || BreakReminder.isInMeeting(events: events, now: now)
        switch posture {
        case .standing:
            standingGuideDismissed = false
            posturePromptPinned = true
            // 開き直したら今の手順を最初の秒から(閉じていたあいだに時間切れで飛ばさない)
            stretchStepStartedAt = Date()
            posturePrompt = .standing
        case .sitting:
            // 切り替え時刻は変えない(見るだけ)。次の判定で閉じられないように pin する
            posturePromptPinned = true
            promptAfterMeeting = saysAfterMeeting(events: events, now: now)
            if posturePrompt != .askStand { pickStretch() }
            posturePrompt = .askStand
        }
    }

    func closePosturePrompt() {
        breathStartedAt = nil
        standingGuideDismissed = posture == .standing
        posturePromptPinned = false
        posturePrompt = nil
    }

    func moveStretchStep(by delta: Int) {
        stretchStep = min(max(0, stretchStep + delta), promptSteps.count)
    }

    /// 時間が来た手順から自動で次へ(まだ index の手順にいるときだけ。同じ手順で二度進めない)
    func advanceStretchStep(from index: Int) {
        guard stretchStep == index else { return }
        moveStretchStep(by: 1)
    }

    func resetPostureTimer(now: Date) {
        postureSince = now
        postureRemindAt = nil
        postureSnoozedUntil = nil
        postureHoldMeetingID = nil
    }

    /// 今回のストレッチを決めて手順を最初から(次回は次のストレッチ)
    private func pickStretch() {
        promptStretch = nextStretch
        stretchStep = 0
    }
}
