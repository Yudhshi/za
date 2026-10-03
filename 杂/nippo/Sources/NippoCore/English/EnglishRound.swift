import Foundation

/// 英語の「地盘」:答えた結果を格の漆の満ち具合で見せる(满 + 星 / 满 / まばら / 灰 + ✕ / 空 / いまの 1 問)
public enum RoundMark: String, Equatable, Sendable, CaseIterable {
    case easy, good, fuzzy, forgot, empty, current
}

public enum EnglishRound {
    /// english_log の結果 → 漆(「知ってる」は太简单と同じ满 + 星)
    public static func mark(result: String) -> RoundMark {
        if result == "known" { return .easy }
        return SRSRating(rawValue: result).map(mark(rating:)) ?? .good
    }

    /// 評分 → 漆(忘了 = 灰 ✕、模糊 = まばら、记住了 = 满、太简单 = 满 + 星)
    public static func mark(rating: SRSRating) -> RoundMark {
        switch rating {
        case .again: return .forgot
        case .hard: return .fuzzy
        case .good: return .good
        case .easy: return .easy
        }
    }

    /// 本轮の盤面:今日答えた順に goal マス + いまの 1 問(橙の破線)+ 空き。
    /// 結果が答えた数より少ない(同期より前の記録)ところは「记住了」で塗る
    public static func board(results: [String], answered: Int, goal: Int, pending: Bool) -> [RoundMark] {
        (0..<max(goal, 0)).map { index -> RoundMark in
            if index < answered {
                return results.indices.contains(index) ? mark(result: results[index]) : .good
            }
            return index == answered && pending ? .current : .empty
        }
    }

    /// 卡の复习记录:最近の slots 回(答える前なら最後の 1 マスは「いまの 1 問」)
    public static func history(_ ratings: [SRSRating], answered: Bool, slots: Int) -> [RoundMark] {
        guard slots > 0 else { return [] }
        var marks = ratings.suffix(answered ? slots : slots - 1).map(mark(rating:))
        if !answered { marks.append(.current) }
        return marks
    }
}
