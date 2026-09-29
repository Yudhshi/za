import Foundation

/// 手入力の出勤時刻(勤務時間の表示用。勤怠システムとは連携しない)。
public enum WorkStart {
    /// "853" → 8:53。"0853"・"8:53"・"８５３"(全角)も可。"9" → 9:00、"10" → 10:00。不正なら nil
    public static func parse(_ text: String) -> (hour: Int, minute: Int)? {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let s = halfWidth.trimmingCharacters(in: .whitespaces)
        let h: Int, m: Int
        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]),
                  parts[1].count == 2 else { return nil }
            (h, m) = (hh, mm)
        } else {
            guard !s.isEmpty, s.allSatisfy(\.isASCII), s.allSatisfy(\.isNumber),
                  let n = Int(s) else { return nil }
            switch s.count {
            case 1, 2: (h, m) = (n, 0)
            case 3, 4: (h, m) = (n / 100, n % 100)
            default: return nil
            }
        }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// 「3時間12分」/ 1 時間未満は「45分」
    public static func durationText(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)分" : "\(h)時間\(m)分"
    }
}
