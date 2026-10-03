import AppKit
import SwiftUI
import NippoCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    @ObservedObject var english: EnglishCoordinator
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
                Text("计划已经定好：坐 \(settings.sitMinutes) 分钟 → 站 \(settings.standMinutes) 分钟，一直循环（一天 8 小时大约站 4 小时；每 30 分钟换一次姿势，比站多久更能放松斜角肌，也避免站太久）")
                Text("到点后在屏幕上方弹出小窗问「站起来了吗？」，站好后显示剩余时间和拉伸步骤。Google Meet 会议中和开始前 5 分钟不问站坐，会议结束 1 分钟后再问（没有 Meet 链接的日程不算会议）。坐着时 3 分钟以上没有操作，就当作离开座位，重新计时（开会时不动不算；小窗弹出后 10 分钟没回应也没操作，同样算离开）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("开会前问要不要站着开", isOn: binding(\.meetingStandAsk))
                    .disabled(!settings.postureEnabled)
                Text("坐了 10 分钟以上、10 分钟内有 Meet 会议时，小窗问「站着开会？」（开始前 5 分钟内、上一个会刚结束时也会问；会议开始或接通后自动关掉）。选「站着开」就从这时算站立时间，会议中不打扰，开完再问坐不坐；选「坐着开」就等开完再提醒站起来")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("麦克风或摄像头在用时当作在开会", isOn: binding(\.callDetection))
                Text("连续 30 秒以上在用才算通话，连续 30 秒以上没在用才算挂断（语音输入一下、通话中断一下都不算）。日历里没有的会（临时拉的会、Slack 通话、Zoom）和超时的会也不打扰，挂断 1 分钟后再问；会提前结束的话也不用等到日历上的结束时间。通话中也不自动朗读英语。只看麦克风和摄像头有没有在被使用，不录音也不需要授权")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    HStack {
                        Text("每次站起来都先做（斜角肌）")
                        Spacer()
                        Button("恢复默认") { settings.fixedStretches = BreakReminder.defaultFixed }
                            .disabled(settings.fixedStretches == BreakReminder.defaultFixed)
                    }
                    TextEditor(text: binding(\.fixedStretches))
                        .font(.body)
                        .frame(height: 110)
                    HStack {
                        Text("然后按顺序轮一个")
                        Spacer()
                        Button("恢复默认") {
                            settings.stretches = BreakReminder.defaultStretches
                            settings.lastStretchIndex = 0
                        }
                        .disabled(settings.stretches == BreakReminder.defaultStretches)
                    }
                    TextEditor(text: binding(\.stretches))
                        .font(.body)
                        .frame(height: 220)
                    Text("用空行分隔，每段一个动作。第 1 行是名字（大约时长），后面每行是一个步骤。小窗里一次显示一步，按步骤里写的秒数和次数自动进入下一步（没写秒数的步骤给 10 秒准备）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.postureEnabled)
                Text("斜角肌（脖子侧面）每次都拉，左右各两个角度、每个停 20 秒；轮换的动作纠正让它发紧的习惯（用胸口呼吸、头往前探、耸肩），手臂不举过头顶。有拉伸感可以，发麻或刺痛传到手上就停；医生或理疗师给过方案的话换成那个。打字时手肘有支撑、键盘鼠标靠近身体，比拉伸更能让斜角肌放松；站着工作时桌子调到手肘 90° 的高度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("每次站起来先做 3 次腹式呼吸（吸 4 秒、呼 6 秒），再开始拉伸。用碎片时间养成腹式呼吸：每次站起来、每次开会前（会议提醒里会提示）、泡完澡的日课最后各做几次。"
                     + "今天 \(coordinator.breathToday) 次，连续 \(BreathLog.streak(coordinator.habits.breath, today: Date())) 天（和 Windows 加在一起算）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("泡完澡后的日课") {
                HStack {
                    Text("跟练视频（每行一个：名字 + 链接，按顺序播放）")
                    Spacer()
                    Button("恢复默认") { settings.ritualVideos = Ritual.defaultVideos }
                        .disabled(settings.ritualVideos == Ritual.defaultVideos)
                }
                TextEditor(text: binding(\.ritualVideos))
                    .font(.body)
                    .frame(height: 90)
                Text("支持 bilibili 和 YouTube 链接，用官方播放器在 app 里播放（不下载）；其他网站会在浏览器里打开")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("跟练之后：站着做的拉伸（写法和上面的拉伸一样）")
                    Spacer()
                    Button("恢复默认") { settings.ritualStretches = Ritual.defaultStretches }
                        .disabled(settings.ritualStretches == Ritual.defaultStretches)
                }
                TextEditor(text: binding(\.ritualStretches))
                    .font(.body)
                    .frame(height: 180)
                HStack {
                    Text("肩袖力量（隔天做，约 6 分钟，徒手 + 一瓶水，在地上做）")
                    Spacer()
                    Button("恢复默认") { settings.ritualStrength = Ritual.defaultStrength }
                        .disabled(settings.ritualStrength == Ritual.defaultStrength)
                }
                TextEditor(text: binding(\.ritualStrength))
                    .font(.body)
                    .frame(height: 110)
                HStack {
                    Text("最后在地上做的拉伸（默认以躺着的腹式呼吸收尾）")
                    Spacer()
                    Button("恢复默认") { settings.ritualFloor = Ritual.defaultFloor }
                        .disabled(settings.ritualFloor == Ritual.defaultFloor)
                }
                TextEditor(text: binding(\.ritualFloor))
                    .font(.body)
                    .frame(height: 120)
                Text("顺序：跟练视频 → 站着的拉伸 →（隔天）肩袖力量 → 地上的拉伸。累的晚上可以在日课窗口里切换成简版（约 5 分钟）。"
                     + "泡完热水澡先喝点水，从地上站起来时慢一点；夜里疼醒、抬手没力气、手发麻，或者不舒服超过 6 周，请去看医生或理疗师")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("晚上和休息日，面板底部会出现「泡完澡了」。已连续 \(BreathLog.streak(coordinator.habits.ritual, today: Date())) 天（在 Windows 上做的也算）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("现在开始") { coordinator.openRitual() }
                }
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

            Section("同步（和 Windows 共享单词进度和会议）") {
                HStack {
                    TextField("同步文件夹（OneDrive / iCloud Drive 里的一个文件夹）", text: syncRootBinding)
                    Button("选择…") { chooseSyncFolder() }
                }
                TextField("这台设备的名字", text: binding(\.deviceName))
                Toggle("把今天和明天的会议写给 Windows（agenda.json）", isOn: binding(\.agendaExport))
                Toggle("把词表复制一份给 Windows（english-library，只供自己学习）", isOn: binding(\.libraryExport))
                HStack {
                    Button("立即同步") { english.syncNow() }
                        .disabled(settings.syncRoot == nil)
                    Text(english.syncStatus ?? "每台设备只写自己的文件；打开面板时和每 5 分钟合并一次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var syncRootBinding: Binding<String> {
        Binding(get: { settings.syncRoot ?? "" },
                set: { settings.syncRoot = $0.isEmpty ? nil : $0 })
    }

    private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选一个 OneDrive / iCloud Drive 里的文件夹，Windows 也指到同一个文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            settings.syncRoot = url.path
            english.syncNow()
        }
    }
}
