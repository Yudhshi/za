import SwiftUI
import NippoCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    @State private var newVacation = Date()
    @State private var vacations: [String] = []

    var body: some View {
        Form {
            Section("会议提醒") {
                Stepper("开始前 \(settings.reminderLeadMinutes) 分钟提醒",
                        value: binding(\.reminderLeadMinutes), in: 1...30)
            }

            Section("下一次シャチョケン（26卒_新卒社長研修）") {
                TextField("标题关键词（用逗号分隔）", text: binding(\.shachokenKeywords))
                Text("在日历未来 90 天里，找标题含这些词的下一个日程，显示在面板底部（不区分全角半角）。默认是「\(AppSettings.defaultShachokenKeywords)」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("工作时间") {
                DatePicker("开始", selection: timeBinding(\.workStartTime),
                           displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: timeBinding(\.workEndTime),
                           displayedComponents: .hourAndMinute)
                Text("站立提醒只在这个时间段内工作。会议提醒在工作日也会提醒时间段外的日程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("站立与拉伸（升降桌）") {
                Toggle("提醒我切换坐姿和站姿", isOn: binding(\.postureEnabled))
                Stepper("坐 \(settings.sitMinutes) 分钟后站起来",
                        value: binding(\.sitMinutes), in: 20...90, step: 5)
                    .disabled(!settings.postureEnabled)
                Stepper("站 \(settings.standMinutes) 分钟后坐下",
                        value: binding(\.standMinutes), in: 5...60, step: 5)
                    .disabled(!settings.postureEnabled)
                Text("到点后在屏幕上方弹出小窗问「站起来了吗？」，站好后显示剩余时间和拉伸步骤。Google Meet 会议中和开始前 5 分钟不弹，结束后再问（没有 Meet 链接的日程不算会议）。坐着时 3 分钟以上没有操作，就当作离开座位，重新计时")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("每次站起来时按顺序出一个拉伸动作")
                    TextEditor(text: binding(\.stretches))
                        .font(.body)
                        .frame(height: 220)
                    Text("用空行分隔，每段一个动作。第 1 行是名字（大约时长），后面每行是一个步骤，小窗里一次显示一步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.postureEnabled)
                Text("默认动作都很温和、手臂不举过头顶，胸廓出口综合征也常被推荐。如果医生或理疗师给过方案，请换成那个;出现疼痛或麻木就停止。站着工作时放松肩膀，桌子调到手肘 90° 的高度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("休息日（暂停会议提醒和站立提醒）") {
                Text("周末和日本节假日（含调休、国民休息日）会自动判断。公司休息日或年假请在下面添加。不会参考日历里的全天日程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    DatePicker("日期", selection: $newVacation, displayedComponents: .date)
                    Button("添加") {
                        try? coordinator.quietDays.addVacation(DayKey.key(for: newVacation))
                        reloadVacations()
                    }
                }
                ForEach(vacations, id: \.self) { day in
                    HStack {
                        Text(day)
                        Spacer()
                        Button("删除") {
                            try? coordinator.quietDays.removeVacation(day)
                            reloadVacations()
                        }
                    }
                }
            }

            Section("通用") {
                TextField("保存位置", text: binding(\.reportsRoot))
                Text("数据库和日志的保存位置。修改后需重启 app 才能完全生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("登录时总会自动启动")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .environment(\.locale, Theme.locale)
        .typesettingLanguage(Theme.language)
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
