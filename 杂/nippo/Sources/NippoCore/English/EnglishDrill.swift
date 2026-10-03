import Foundation

// MARK: - 間隔反復(SM-2)

public enum SRSRating: String, Sendable, CaseIterable {
    case again, hard, good, easy
}

/// カード 1 枚の復習状態。IELTS アプリの srsApplySM2 と同じ式(学習履歴の感覚を揃える)
public struct SRSState: Equatable, Sendable {
    /// 次の復習までの日数(0 = 今日もう一度)
    public var interval: Int
    public var ease: Double
    public var reps: Int
    public var lapses: Int

    public init(interval: Int = 0, ease: Double = 2.5, reps: Int = 0, lapses: Int = 0) {
        self.interval = interval
        self.ease = ease
        self.reps = reps
        self.lapses = lapses
    }

    public func applying(_ rating: SRSRating) -> SRSState {
        var s = self
        switch rating {
        case .again:
            s.interval = 0
            s.ease = max(1.3, ease - 0.2)
            s.reps = 0
            s.lapses += 1
        case .hard:
            // 「模糊」でも間隔は必ず伸びる(1 → 1 に固まらない)
            s.interval = max(interval + 1, Int((Double(max(interval, 1)) * 1.2).rounded()))
            s.ease = max(1.3, ease - 0.15)
            s.reps += 1
        case .good:
            switch reps {
            case 0: s.interval = 1
            case 1: s.interval = max(3, Int((Double(interval) * ease).rounded()))   // 「太简单」の後に縮まない
            default: s.interval = max(1, Int((Double(interval) * ease).rounded()))
            }
            s.reps += 1
        case .easy:
            s.interval = reps == 0 ? 4 : max(1, Int((Double(interval) * ease * 1.3).rounded()))
            s.ease = ease + 0.15
            s.reps += 1
        }
        return s
    }
}

// MARK: - 出題の順番

public enum EnglishQueue {
    /// 次に出すカードの id:期限の来た復習(古い順)→ 今日の新規枠が残っていれば未学習を素材順に。
    /// avoid(いま答えたもの)は、他に出すものが無いときだけ出す(「もう一回」がすぐ戻ってこないように)
    public static func next(due: [String], pool: [String], seen: Set<String>,
                            newToday: Int, newLimit: Int, avoid: String? = nil) -> String? {
        if let id = due.first(where: { $0 != avoid }) { return id }
        if newToday < newLimit, let id = pool.first(where: { !seen.contains($0) && $0 != avoid }) {
            return id
        }
        if let avoid, due.contains(avoid) { return avoid }
        return nil
    }

    /// 今日あと何枚か(復習 + 残りの新規枠。未学習が尽きたらその分は数えない)
    public static func remaining(due: Int, unseen: Int, newToday: Int, newLimit: Int) -> Int {
        due + min(max(0, newLimit - newToday), unseen)
    }
}

// MARK: - 聴写の採点

public enum SpellResult: String, Equatable, Sendable {
    case correct
    /// 1 文字違い(4 文字以上の語)。IELTS アプリと同じく半分正解として明日もう一度
    case almost
    case wrong
}

public enum SpellCheck {
    /// 大文字小文字・前後と連続の空白・全角・曲がった引用符の違いは無視する
    public static func normalize(_ text: String) -> String {
        let half = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let quotes = half.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        return quotes.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static func check(_ input: String, answer: String) -> SpellResult {
        let a = normalize(input), b = normalize(answer)
        if a == b { return .correct }
        if b.count >= 4, !a.isEmpty, levenshtein(a, b) <= 1 { return .almost }
        return .wrong
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[y.count]
    }
}

// MARK: - 同義替換の 4 択

public struct ParaphraseQuestion: Equatable, Sendable {
    public let entry: ParaphraseEntry
    public let choices: [String]
    public let answerIndex: Int
}

public enum ParaphraseQuiz {
    /// entry の言い換えを 1 つ正解に、他の考点词の言い換えから 3 つ誤答を選ぶ
    /// (誤答は毎回作る。固定すると誤答ごと覚えてしまう、という IELTS アプリの方針どおり)
    public static func make<R: RandomNumberGenerator>(entry: ParaphraseEntry, pool: [ParaphraseEntry],
                                                      using rng: inout R) -> ParaphraseQuestion? {
        guard let answer = entry.syn.randomElement(using: &rng) else { return nil }
        let excluded = Set(entry.syn.map { $0.lowercased() } + [entry.w.lowercased()])
        var distractors: [String] = []
        var used = excluded
        for other in pool.shuffled(using: &rng) where other.w != entry.w {
            guard let candidate = other.syn.randomElement(using: &rng),
                  !used.contains(candidate.lowercased()) else { continue }
            used.insert(candidate.lowercased())
            distractors.append(candidate)
            if distractors.count == 3 { break }
        }
        guard distractors.count == 3 else { return nil }
        let choices = (distractors + [answer]).shuffled(using: &rng)
        return ParaphraseQuestion(entry: entry, choices: choices,
                                  answerIndex: choices.firstIndex(of: answer) ?? 0)
    }
}

/// 決まった種から同じ並びを作る乱数(テスト用。アプリは SystemRandomNumberGenerator)
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
