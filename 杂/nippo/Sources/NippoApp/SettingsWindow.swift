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
            rootView: SettingsView(coordinator: coordinator, settings: coordinator.settings))
        let window = NSWindow(contentViewController: host)
        window.title = "Yudh 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
