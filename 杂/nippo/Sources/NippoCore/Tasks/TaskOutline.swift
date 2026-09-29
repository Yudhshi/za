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

    /// タスク 1 つ(タスク名 + 中身)。画面ではこれを 1 つのオブジェクトとして扱い、「完了」で丸ごと消す
    public struct Block: Equatable, Sendable {
        /// タスク名(先頭が中身だけのときは nil)
        public let title: String?
        public let items: [Line]
        /// メモの何行目から何行目までか(完了で消す範囲。後ろの空行も含む)
        public let lines: Range<Int>
    }

    static let bullets = ["- ", "・", "* ", "• ", "-", "*"]

    /// 1 行を読む。空行・中身の無い箇条書きは nil
    static func line(_ raw: String) -> Line? {
        var indent = 0, spaces = 0
        var rest = Substring(raw)
        while let ch = rest.first, ch == "\t" || ch == " " || ch == "\u{3000}" {
            if ch == "\t" { indent += 1 } else { spaces += ch == " " ? 1 : 2 }
            rest = rest.dropFirst()
        }
        // タブ 1 つ、または空白 4 つ(2 つでも)で 1 段
        indent += (spaces + 3) / 4
        var body = String(rest).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        var bulleted = false
        for mark in bullets where body.hasPrefix(mark) {
            body = String(body.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            bulleted = true
            break
        }
        guard !body.isEmpty else { return nil }
        // 字下げ無しの箇条書きも「中身」として扱う
        return Line(text: body, depth: min(3, max(indent, bulleted ? 1 : 0)))
    }

    /// nil は区切り(連続する空行は 1 つにまとめ、先頭・末尾の空行は捨てる)
    public static func parse(_ text: String) -> [Line?] {
        var result: [Line?] = []
        for raw in text.components(separatedBy: .newlines) {
            guard let line = line(raw) else {
                if let last = result.last, last != nil { result.append(nil) }
                continue
            }
            result.append(line)
        }
        if let last = result.last, last == nil { result.removeLast() }
        return result
    }

    /// タスクごとのまとまり。字下げなしの行で次のタスクが始まる
    public static func blocks(_ text: String) -> [Block] {
        let raws = text.components(separatedBy: .newlines)
        var blocks: [Block] = []
        var title: String?
        var items: [Line] = []
        var start: Int?
        func close(at end: Int) {
            if let s = start, title != nil || !items.isEmpty {
                blocks.append(Block(title: title, items: items, lines: s..<end))
            }
            title = nil
            items = []
            start = nil
        }
        for (index, raw) in raws.enumerated() {
            guard let line = line(raw) else { continue }
            if line.depth == 0 {
                close(at: index)
                title = line.text
                start = index
            } else {
                if start == nil { start = index }
                items.append(line)
            }
        }
        close(at: raws.count)
        return blocks
    }

    /// index 番目のタスクを消したメモ(前後の空行を整えて、タスクの間は空行 1 つ)
    public static func removing(block index: Int, from text: String) -> String {
        let all = blocks(text)
        guard all.indices.contains(index) else { return text }
        var raws = text.components(separatedBy: .newlines)
        raws.removeSubrange(all[index].lines)
        var result: [String] = []
        for raw in raws {
            let blank = raw.trimmingCharacters(in: .whitespaces).isEmpty
            if blank && (result.isEmpty || result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true) {
                continue
            }
            result.append(raw)
        }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }
}
