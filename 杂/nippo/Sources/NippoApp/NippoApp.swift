import SwiftUI
import NippoCore

/// Yudh(旧 Nippo)。モジュール名・保存先・バンドル ID は既存の設定と権限を保つため Nippo のまま
@main
struct NippoApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(coordinator: coordinator)
        } label: {
            // 次の会議のカウントダウン、なければ目覚まし時計
            if let title = coordinator.statusBarTitle {
                Text(title)
            } else {
                Image(systemName: "alarm")
            }
        }
        .menuBarExtraStyle(.window)
        // 設定ウインドウは SettingsWindowController が AppKit で開く(Settings シーンは常駐アプリでは前面に出なかった)
    }
}
