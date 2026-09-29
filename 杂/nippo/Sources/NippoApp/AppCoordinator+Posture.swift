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
        // 座りっぱなしの計測だけ離席でリセット(立ち作業の残り時間は巻き戻さない)
        if posture == .sitting, Self.idleSeconds() >= 180 {
            resetPostureTimer(now: now)
        }
        let desired = BreakReminder.desiredPrompt(
            posture: posture, current: posturePrompt, now: now, dueAt: postureDueAt,
            inMeeting: BreakReminder.isInMeeting(events: todayEvents, now: now))
        guard desired != posturePrompt else { return }
        // 「15 分後」のあとに出し直すときは同じストレッチのまま(押すたびに次のストレッチへ飛ばない)
        if desired == .askStand && postureRemindAt == nil { pickStretch() }
        posturePrompt = desired
        AppLog.shared.log("posture", "prompt \(String(describing: desired))")
    }

    /// 「立った」(小窓・メニュー):立ち作業の残り時間とストレッチの手順を出す
    func confirmStood() {
        if posturePrompt != .askStand { pickStretch() }
        posture = .standing
        resetPostureTimer(now: Date())
        posturePrompt = .standing
        AppLog.shared.log("posture", "stood")
    }

    /// 「座った」(小窓・メニュー)
    func confirmSat() {
        posture = .sitting
        resetPostureTimer(now: Date())
        posturePrompt = nil
        AppLog.shared.log("posture", "sat")
    }

    /// 「15分後」「あと5分」:小窓を閉じて、その分だけ後にもう一度尋ねる
    func snoozePosture(minutes: Int) {
        postureRemindAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        posturePrompt = nil
    }

    /// メニューの姿勢チップから小窓を開く:立ち作業中は手順、座り作業中は「立ちましたか?」。
    /// 座り作業中は切り替え時刻を今にする(次の判定で小窓が閉じないように)
    func openPosturePrompt() {
        switch posture {
        case .standing:
            posturePrompt = .standing
        case .sitting:
            postureRemindAt = Date()
            if posturePrompt != .askStand { pickStretch() }
            posturePrompt = .askStand
        }
    }

    func closePosturePrompt() {
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
        settings.lastStretchIndex += 1
        stretchStep = 0
    }
}
