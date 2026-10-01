import AppKit
import SwiftUI

/// 言葉の設定と、窓まわりの小さな部品(v11 までの Theme.swift から残したものだけ)
enum Theme {
    /// 時刻(14:00)は中国語の 24 時間制。曜日だけ英語
    static let locale = Locale(identifier: "zh_CN")
    static let weekdayLocale = Locale(identifier: "en_US")
    /// 漢字の字形を中国語(簡体字)にそろえる(日本語の件名だけ ja、Typeface.isJapanese)
    static let language = Locale.Language(identifier: "zh-Hans")
    static let japanese = Locale.Language(identifier: "ja")

    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// タブ 1 つ
struct TabItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var badge: Int?
    /// ⌘ と組み合わせるキー
    var shortcut: KeyEquivalent?
    /// 今日の分が終わった(数の代わりに模板の ✓)
    var done = false

    var id: Value { value }
}

/// ここを掴むと窓が動く(枠なしの窓で、曜日の行・胶带を持ち手にする)
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
