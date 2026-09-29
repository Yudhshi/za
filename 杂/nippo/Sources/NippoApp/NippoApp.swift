import SwiftUI
import NippoCore

@main
struct NippoApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(coordinator: coordinator)
        } label: {
            // 次の会議のカウントダウン、なければカレンダーアイコン
            if let title = coordinator.statusBarTitle {
                Text(title)
            } else {
                Image(systemName: "calendar")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: coordinator, settings: coordinator.settings)
        }
    }
}
