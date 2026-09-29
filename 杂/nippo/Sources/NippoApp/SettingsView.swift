import SwiftUI
import ServiceManagement
import NippoCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var newVacation = Date()
    @State private var vacations: [String] = []

    var body: some View {
        Form {
            Section("会議リマインド") {
                Stepper("開始 \(settings.reminderLeadMinutes) 分前に通知",
                        value: binding(\.reminderLeadMinutes), in: 1...30)
            }

            Section("次のシャチョケン(26卒_新卒社長研修)") {
                TextField("件名キーワード(カンマ区切り)", text: binding(\.shachokenKeywords))
                Text("カレンダーの 90 日先までから、件名にこの言葉を含む次の予定をメニューの下の帯に出します(全角・半角は区別しません)。既定は「\(AppSettings.defaultShachokenKeywords)」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("勤務時間") {
                DatePicker("開始", selection: timeBinding(\.workStartTime),
                           displayedComponents: .hourAndMinute)
                DatePicker("終了", selection: timeBinding(\.workEndTime),
                           displayedComponents: .hourAndMinute)
                Text("立ち作業リマインドはこの時間だけ動きます。会議の通知は勤務日なら時間外の予定にも出ます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("立ち作業・ストレッチ(昇降デスク)") {
                Toggle("座り・立ちの切り替えを知らせる", isOn: binding(\.postureEnabled))
                Stepper("座って \(settings.sitMinutes) 分で立ち作業へ",
                        value: binding(\.sitMinutes), in: 20...90, step: 5)
                    .disabled(!settings.postureEnabled)
                Stepper("立って \(settings.standMinutes) 分で座り作業へ",
                        value: binding(\.standMinutes), in: 5...60, step: 5)
                    .disabled(!settings.postureEnabled)
                Text("時間になると画面上部に小窓で「立ちましたか?」と尋ね、立ったら残り時間とストレッチの手順を出します。Google Meet の会議中と開始 5 分前は出さず、終わってから尋ねます(Meet のリンクが無い予定は会議扱いしません)。座っているあいだ 3 分以上操作がなければ離席とみなして計り直します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("立つたびに順番に 1 つずつ出すストレッチ")
                    TextEditor(text: binding(\.stretches))
                        .font(.body)
                        .frame(height: 220)
                    Text("空行で区切って 1 つ。1 行目が名前(目安時間)、続く行が手順で、小窓では 1 手順ずつ表示します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.postureEnabled)
                Text("既定は胸郭出口症候群でもよく勧められる、腕を頭より上げない穏やかな動きです。担当医・理学療法士のメニューがあれば置き換え、痛みやしびれが出る動きは中止してください。立ち作業では肩の力を抜き、肘が 90 度になる高さに")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("お休みの日(会議通知・立ち作業リマインドを止める)") {
                Text("週末と日本の祝日(振替休日・国民の休日を含む)は自動で判定します。祝日以外の会社休日や有給は下で追加してください。カレンダーの終日予定は見ません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    DatePicker("追加", selection: $newVacation, displayedComponents: .date)
                    Button("追加") {
                        try? coordinator.quietDays.addVacation(DayKey.key(for: newVacation))
                        reloadVacations()
                    }
                }
                ForEach(vacations, id: \.self) { day in
                    HStack {
                        Text(day)
                        Spacer()
                        Button("削除") {
                            try? coordinator.quietDays.removeVacation(day)
                            reloadVacations()
                        }
                    }
                }
            }

            Section("一般") {
                TextField("保存先フォルダ", text: binding(\.reportsRoot))
                Text("DB・ログの保存先。変更はアプリ再起動後に完全反映されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .environment(\.locale, Theme.locale)
        .onAppear { reloadVacations() }
    }

    private func reloadVacations() {
        vacations = (try? coordinator.quietDays.vacations()) ?? []
    }

    /// "HH:mm" の設定値を時刻ピッカー用の Date に相互変換する
    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, String>) -> Binding<Date> {
        Binding(
            get: {
                let (h, m) = settings.timeComponents(settings[keyPath: keyPath], fallback: (9, 0))
                return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
            })
    }

    private func binding<V>(_ keyPath: ReferenceWritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { settings[keyPath: keyPath] = $0 })
    }
}
