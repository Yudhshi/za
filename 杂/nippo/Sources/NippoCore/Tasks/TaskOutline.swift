import Foundation

/// 「いまのタスク」メモ:テキストの字下げで階層を表す。
/// 字下げなしの行 = タスク名、字下げ(タブ/空白)や「- 」「・」で始まる行 = その中身。空行 = タスクの区切り
public enum TaskOutline {
    public struct Line: Equatable, Sendable {
        public let text: String
        public let depth: Int   // 0 = タスク名、1 以上 = 中身

        public init(text: String, depth: Int) {
            self.text = text
            self.depth = depth
        }
    }

    static let bullets = ["- ", "・", "* ", "• ", "-", "*"]

    /// nil は区切り(連続する空行は 1 つにまとめ、先頭・末尾の空行は捨てる)
    public static func parse(_ text: String) -> [Line?] {
        var result: [Line?] = []
        for raw in text.components(separatedBy: .newlines) {
            var indent = 0, spaces = 0
            var rest = Substring(raw)
            while let ch = rest.first, ch == "\t" || ch == " " || ch == "\u{3000}" {
                if ch == "\t" { indent += 1 } else { spaces += ch == " " ? 1 : 2 }
                rest = rest.dropFirst()
            }
            // タブ 1 つ、または空白 4 つ(2 つでも)で 1 段
            indent += (spaces + 3) / 4
            var body = String(rest).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else {
                if let last = result.last, last != nil { result.append(nil) }
                continue
            }
            var bulleted = false
            for mark in bullets where body.hasPrefix(mark) {
                body = String(body.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
                bulleted = true
                break
            }
            guard !body.isEmpty else { continue }
            // 字下げ無しの箇条書きも「中身」として扱う
            let depth = min(3, max(indent, bulleted ? 1 : 0))
            result.append(Line(text: body, depth: depth))
        }
        if let last = result.last, last == nil { result.removeLast() }
        return result
    }
}
