import AppKit
import Combine
import SwiftUI
import NippoCore

/// Yudh(旧 Nippo)。モジュール名・保存先・バンドル ID は既存の設定と権限を保つため Nippo のまま。
/// 常駐アプリ:状態バーの項目と面板(画面中央の浮いた窓)は AppDelegate が AppKit で組む。
/// MenuBarExtra(.window) は状態バーの真下にしか出せず動かせないので使わない
@main
struct NippoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // SwiftUI の App にはシーンが 1 つ要る。設定は SettingsWindowController が AppKit で開くので、ここは空
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    private var panel: MainPanelController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        let panel = MainPanelController(coordinator: coordinator)
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.imagePosition = .imageOnly
            // 状態バーの項目を押した mouseDown は「外を押した」扱いにしない(閉じてすぐ開き直さないように)
            panel.ignoredWindow = button.window
        }
        // 次の会議のカウントダウン。なければ目覚まし時計(立ち作業中は立っている人)
        coordinator.$statusBarTitle.combineLatest(coordinator.$posture)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, posture in
                MainActor.assumeIsolated { self?.updateStatusItem(title: title, posture: posture) }
            }
            .store(in: &cancellables)
    }

    @objc private func togglePanel() {
        panel?.toggle()
    }

    private func updateStatusItem(title: String?, posture: BreakReminder.Posture) {
        guard let button = statusItem?.button else { return }
        if let title {
            button.image = nil
            button.imagePosition = .noImage
            button.title = title
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: posture == .standing ? "figure.stand" : "alarm",
                                   accessibilityDescription: "Yudh")
            button.imagePosition = .imageOnly
        }
    }
}
