import SwiftUI

// MARK: - v12「Stencil Turf」の色と寸法(scratchpad の tokens.json v3 から。夜版)

/// 色。大きな色面はすべて焼いた素材から来るので、ここの色を面に塗るのは素材がないときの代わりだけ。
/// 本物の文字・アイコン・細い線にはこの色をそのまま使う
enum Palette {
    // 固定の色(MERGE.md の決定。調整しない)
    static let teal = Theme.rgb(0x12E9D3)
    static let orange = Theme.rgb(0xFF6412)
    /// 漆の黒(色面の上の文字)
    static let black = Theme.rgb(0x161615)
    static let white = Theme.rgb(0xF4F3EE)
    static let meetingGrey = Theme.rgb(0xC3C6C7)
    static let tape = Theme.rgb(0xE6D9B0)
    static let kraft = Theme.rgb(0xC49C69)

    // 夜の混凝土
    static let surface = Theme.rgb(0x2A2D30)
    static let text = Theme.rgb(0xF4F3EE)
    static let textSecondary = Theme.rgb(0xABAFB2)
    static let meetingCellPast = Theme.rgb(0x7E8286)
    static let cellEmptyStroke = Theme.rgb(0x80858A)
    static let cellPastFill = Theme.rgb(0x1F2124)
    static let disabledFill = Theme.rgb(0x45494D)
    static let disabledText = Theme.rgb(0xA3A7AA)

    // 白漆の単語卡の上
    static let cardText = Theme.rgb(0x161615)
    static let cardTextSecondary = Theme.rgb(0x2A2926)

    // 牛皮紙(坐站の小窓)の上
    static let kraftText = Theme.rgb(0x161615)
    static let kraftTextSecondary = Theme.rgb(0x3E2F1C)
    static let kraftRule = Theme.rgb(0x281A0A).opacity(0.35)
}

/// 余白と寸法(pt)
enum Turf {
    static let panelWidth: CGFloat = 520
    /// 面板の内側の余白(上・左・下・右)
    static let panelPadding = EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24)
    static let contentWidth: CGFloat = 472
    static let popupWidth: CGFloat = 360
    static let popupPadding = EdgeInsets(top: 30, leading: 22, bottom: 22, trailing: 22)
    static let heroPadding = EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20)
    static let panelRadius: CGFloat = 20

    static let xxl: CGFloat = 22

    static let topRow: CGFloat = 40
    static let tabHeight: CGFloat = 32
    static let scheduleRow: CGFloat = 40
    static let selectedBar: CGFloat = 6
    static let iconButton: CGFloat = 38
    static let primaryButton: CGFloat = 54
    static let heroButton = CGSize(width: 120, height: 50)
    static let ratingButton: CGFloat = 52
    static let optionButton: CGFloat = 56
    static let popupButton: CGFloat = 50
    static let checkbox: CGFloat = 17
}

// MARK: - 曜日の神兽(名前・文化・説明は画面のどこにも出さない)

/// 一週間の七つの神兽。素材の名前に使う曜日の略号を返すだけ(神兽が何かは書かない)
enum Myth {
    /// Calendar の weekday(1 = 日曜)→ 素材の略号
    private static let keys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: date)
        return keys[(weekday - 1 + 7) % 7]
    }

    /// 静の主角卡の第二の模板(灰漆)
    static func heroCreature(for date: Date) -> String { "creature-\(dayKey(for: date))-grey" }
    /// 英語 20/20 の奖章(青漆。切り角の黒い底板の上)
    static func badgeCreature(for date: Date) -> String { "creature-\(dayKey(for: date))-teal" }
    /// 坐站小窓の牛皮纸の淡い残影(彩蛋)
    static func ghostCreature(for date: Date) -> String { "kraft-ghost-\(dayKey(for: date))" }
}
