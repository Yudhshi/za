import AppKit
import CoreGraphics
import Foundation
import NippoCore

/// 昇降デスクの座り/立ち切り替え。通知ではなく画面上部の小窓で尋ねる:
/// 「立ちましたか?」→ 立った → 立ち作業の残り時間とストレッチの手順 → 「座りましたか?」。
/// Google Meet の会議中・直前は出さない。座っているあいだ 3 分以上操作がなければ離席とみなして計り直す
extension AppCoordinator {
    /// 次に切り替える時刻(「あとで」を押したら postureRemindAt が優先)
    var postureDueAt: Date {
        let limit = posture == .sitting ? settings.sitMinutes : settings.standMinutes
        return postureRemindAt ?? postureSince.addingTimeInterval(TimeInterval(limit * 60))
    }

    /// 次に出すストレッチ(メニューにも予告する)
    var nextStretch: BreakReminder.Stretch {
        BreakReminder.stretch(at: settings.lastStretchIndex,
                              in: BreakReminder.stretches(from: settings.stretches))
    }

    /// 最後のキーボード・マウス操作からの秒数(権限不要)
    nonisolated static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    func checkPosture(now: Date) {
        guard settings.postureEnabled, isWorkingNow else {
            if posturePrompt != nil { posturePrompt = nil }
            return
        }
        let inMeeting = BreakReminder.isInMeeting(events: todayEvents, now: now)
        // 座りっぱなしの計測だけ離席でリセット(立ち作業の残り時間は巻き戻さない)。
        // 会議中の無操作は「座って会議中」、小窓を出しているあいだは判定しない
        if posture == .sitting, posturePrompt == nil, !inMeeting, Self.idleSeconds() >= 180 {
            resetPostureTimer(now: now)
        }
        let desired = BreakReminder.desiredPrompt(
            posture: posture, current: posturePrompt, now: now, dueAt: postureDueAt,
            inMeeting: inMeeting, guideDismissed: standingGuideDismissed)
        // メニューから自分で開いた「站起来了吗?」は、時間前でも会議に入らない限り閉じない
        if desired == nil, posturePromptPinned, posturePrompt == .askStand, !inMeeting { return }
        guard desired != posturePrompt else { return }
        posturePromptPinned = false
        if desired == .askStand { pickStretch() }
        posturePrompt = desired
        AppLog.shared.log("posture", "prompt \(String(describing: desired))")
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
        posturePromptPinned = false
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
        postureRemindAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        posturePromptPinned = false
        posturePrompt = nil
    }

    /// メニューの姿勢チップから小窓を開く:立ち作業中は手順、座り作業中は「立ちましたか?」。
    /// 座り作業中は切り替え時刻を今にする(次の判定で小窓が閉じないように)
    func openPosturePrompt() {
        switch posture {
        case .standing:
            standingGuideDismissed = false
            posturePrompt = .standing
        case .sitting:
            // 切り替え時刻は変えない(見るだけ)。次の判定で閉じられないように pin する
            posturePromptPinned = true
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
        stretchStep = min(max(0, stretchStep + delta), promptStretch.steps.count)
    }

    func resetPostureTimer(now: Date) {
        postureSince = now
        postureRemindAt = nil
    }

    /// 今回のストレッチを決めて手順を最初から(次回は次のストレッチ)
    private func pickStretch() {
        promptStretch = nextStretch
        stretchStep = 0
    }
}
