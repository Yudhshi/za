import Foundation
import UserNotifications
import AppKit

/// UNUserNotificationCenter は .app バンドル内でのみ動作する。
/// 裸バイナリ(swift run)ではクラッシュするため available ガード必須。
public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()

    public let available: Bool

    static let joinURLKey = "joinURL"
    static let meetingCategory = "MEETING"
    static let joinActionID = "JOIN"

    private override init() {
        available = Bundle.main.bundleIdentifier != nil
        super.init()
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // 会議通知には「参加」アクションを付ける
        let join = UNNotificationAction(identifier: Self.joinActionID,
                                        title: "加入会议",
                                        options: [])
        let meeting = UNNotificationCategory(identifier: Self.meetingCategory,
                                             actions: [join],
                                             intentIdentifiers: [])
        center.setNotificationCategories([meeting])
    }

    public func requestPermission() {
        guard available else {
            print("[notify] skipped: not running from an app bundle")
            return
        }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 会議リマインドを OS に事前予約(スリープ中に時刻を跨いでも復帰時に届く)。
    /// identifier に eventID+開始時刻+リード分を含め、変更時は別 ID になる。
    public func scheduleMeetingReminder(identifier: String, title: String, body: String,
                                        joinURL: URL?, fireDate: Date) {
        guard available else { return }
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let joinURL {
            content.categoryIdentifier = Self.meetingCategory
            content.userInfo = [Self.joinURLKey: joinURL.absoluteString]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval,
                                                        repeats: false)
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
        AppLog.shared.log("schedule", "\(identifier) @ \(fireDate)")
    }

    /// 予約済みの通知のうち identifier が prefix で始まるものを全部取消す
    /// (廃止した機能が OS に残した予約の掃除用)
    public func cancelPending(prefix: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
                AppLog.shared.log("schedule", "cancelled \(ids.count) \(prefix)* request(s)")
            }
        }
    }

    /// 予約済み会議リマインドのうち、有効 ID 集合に無いもの(削除・変更された予定)を取消す
    public func reconcileMeetingReminders(validIDs: Set<String>) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("nippo-meet-") && !validIDs.contains($0) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
                AppLog.shared.log("schedule", "cancelled \(stale.count) stale reminder(s)")
            }
        }
    }

    /// メニューバー常駐アプリが前面扱いでもバナーを出す
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler:
                                           @escaping (UNNotificationPresentationOptions) -> Void) {
        // .list も付けないと通知センターに残らず、バナーを見逃すと参加リンクが消える
        completionHandler([.banner, .list, .sound])
    }

    /// 通知本体クリック・「参加」ボタンのどちらでも会議リンクを開く
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo[Self.joinURLKey] as? String,
           let url = URL(string: urlString) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
