import AppKit
import SwiftUI

/// 設定ウインドウ。
/// 以前は SwiftUI の Settings シーン + SettingsLink で開いていたが、常駐アプリ(LSUIElement)では
/// アプリが前面に来ないためウインドウが他のアプリの後ろに開き、「押しても何も起きない」ように見えた。
/// ここでは AppKit のウインドウを自前で持ち、開くあいだだけ通常のアプリ(Dock に出る)にして前面へ出す。
/// 閉じたら常駐アプリに戻す
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let coordinator: AppCoordinator
    private var window: NSWindow?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(
            rootView: SettingsView(coordinator: coordinator, settings: coordinator.settings,
                                   english: coordinator.english))
        let window = NSWindow(contentViewController: host)
        window.title = "Yudh 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // 日课の窓がまだ開いていれば Dock と ⌘-Tab に残す
        DockPresence.update(closing: window)
    }
}

/// 設定・日课の窓(タイトルのある普通の窓)が 1 つでも開いていれば(Dock にしまってあっても)通常のアプリ、
/// 無くなったら常駐アプリ(Dock に出ない)に戻す。片方を閉じても、もう片方が開いていれば Dock と ⌘-Tab から消さない
@MainActor
enum DockPresence {
    static func update(closing: NSWindow?) {
        let open = NSApp.windows.contains { window in
            window !== closing && !(window is NSPanel) && window.styleMask.contains(.titled)
                && (window.isVisible || window.isMiniaturized)
        }
        NSApp.setActivationPolicy(open ? .regular : .accessory)
    }
}
