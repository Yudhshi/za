import Foundation

/// 坐站の小窓で拉伸をどう見せるか(画面は持たない):名前を「题 · 时长」に分ける、手順ごとの姿勢と札の名前、
/// 古埃及の壁画带にするか、手順の数字の札、立ち作業の残り時間。
/// 絵(pose-* / frieze-*)が本当にあるかは画面の側で素材を見て決める
public enum StretchGuide {
    /// 手順 1 つ
    public struct Step: Equatable, Sendable {
        /// 姿勢の絵の名前(pose-<pose> / frieze-<pose>-*)
        public var pose: String
        /// 壁画带の札の名前:姿勢が混ざる組み立てなら姿勢の名前(转肩)、全部同じなら「第 N 步」
        public var name: String
        /// 画面に出す手順の一行。姿勢の名前が見出しになるときは行頭の「转肩：」を外す
        public var text: String
        /// 手順の中の数(5 秒 · 10 次 / 10 次 / 20 秒 / 1 分钟)。無ければ nil
        public var meta: String?

        public init(pose: String, name: String, text: String, meta: String?) {
            self.pose = pose
            self.name = name
            self.text = text
            self.meta = meta
        }
    }

    /// 壁画带の絵がある姿勢と、その短い名前(scripts/material の frieze と同じ 3 人)
    public static let friezeNames: [String: String] = [
        "shoulder-blades": "夹肩胛骨",
        "shoulder-rolls": "转肩",
        "chin-tuck": "收下巴",
    ]

    /// 壁画带に並べられる人数
    public static let friezeStepRange: ClosedRange<Int> = 2...3

    /// 「夹肩胛骨（约 1 分钟）」→(夹肩胛骨, 1 分钟)。括弧が無ければそのまま
    public static func split(_ name: String) -> (title: String, note: String?) {
        guard let open = name.firstIndex(where: { $0 == "（" || $0 == "(" }) else {
            return (name.trimmingCharacters(in: .whitespaces), nil)
        }
        let title = name[..<open].trimmingCharacters(in: .whitespaces)
        var inside = name[name.index(after: open)...]
        if let close = inside.lastIndex(where: { $0 == "）" || $0 == ")" }) {
            inside = inside[..<close]
        }
        var note = inside.trimmingCharacters(in: .whitespaces)
        if note.hasPrefix("约") {
            note = String(note.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return (title.isEmpty ? name : title, note.isEmpty ? nil : note)
    }

    /// 「夹肩胛骨 · 1 分钟」
    public static func displayName(_ name: String) -> String {
        let parts = split(name)
        guard let note = parts.note else { return parts.title }
        return "\(parts.title) · \(note)"
    }

    /// 手順ごとの姿勢。基本はストレッチ全体の絵で、手順の文が壁画带の姿勢を名指ししているときだけそれに替える
    /// (「肩颈三步」= 夹肩胛骨 / 转肩 / 收下巴 を 1 歩 1 人で並べるため)。
    /// 札の名前は姿勢が混ざるときは姿勢の名前、全部同じなら「第 N 步」
    public static func steps(of stretch: BreakReminder.Stretch) -> [Step] {
        let base = BreakReminder.illustration(for: stretch)
        let poses = stretch.steps.map { line -> String in
            let own = BreakReminder.illustration(for: BreakReminder.Stretch(name: line, steps: []))
            return friezeNames[own] != nil ? own : base
        }
        let distinct = Set(poses).count > 1
        var result: [Step] = []
        for (i, line) in stretch.steps.enumerated() {
            let pose = poses[i]
            let named: String? = distinct ? friezeNames[pose] : nil
            let text = named.map { dropping(prefix: $0, from: line) } ?? line
            result.append(Step(pose: pose, name: named ?? "第 \(i + 1) 步", text: text, meta: metaText(line)))
        }
        return result
    }

    /// 壁画带にするか:2〜3 歩で、姿勢が全部違い、どれも壁画带の絵がある姿勢(同じ人が並ぶだけなら出さない)
    public static func showsFrieze(_ steps: [Step]) -> Bool {
        friezeStepRange.contains(steps.count)
            && Set(steps.map(\.pose)).count == steps.count
            && steps.allSatisfy { friezeNames[$0.pose] != nil }
    }

    /// 今の手順の見出し:姿勢が混ざる組み立てなら姿勢の名前(转肩)、それ以外はストレッチの名前(括弧の前)
    public static func heading(of stretch: BreakReminder.Stretch, steps: [Step], at index: Int) -> String {
        if Set(steps.map(\.pose)).count > 1, steps.indices.contains(index),
           let name = friezeNames[steps[index].pose] {
            return name
        }
        return split(stretch.name).title
    }

    /// 手順の文の中の数を札の一行に(5 秒 · 10 次 / 10 次 / 1 分钟)
    public static func metaText(_ line: String) -> String? {
        let meta = BreakReminder.StepMeta.parse(line)
        if let s = meta.seconds, let r = meta.reps { return "\(s) 秒 · \(r) 次" }
        if let s = meta.seconds { return "\(s) 秒" }
        if let r = meta.reps { return "\(r) 次" }
        if let m = meta.minutes { return "\(m) 分钟" }
        return nil
    }

    /// 残り時間「12:30」。分は 2 桁にそろえる(09:59。模板字の幅が毎秒・毎分で変わらないように)。過ぎたら 00:00
    public static func clock(until due: Date, now: Date) -> String {
        let seconds = max(0, Int(due.timeIntervalSince(now).rounded(.up)))
        return String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
    }

    /// 「转肩：向后转 10 次」→「向后转 10 次」(見出しと同じ名前が行頭にあるときだけ。残りが空ならそのまま)
    static func dropping(prefix: String, from line: String) -> String {
        guard !prefix.isEmpty, line.hasPrefix(prefix) else { return line }
        var rest = line.dropFirst(prefix.count).drop(while: { $0 == " " })
        guard let first = rest.first, first == "：" || first == ":" else { return line }
        rest = rest.dropFirst()
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? line : text
    }
}
