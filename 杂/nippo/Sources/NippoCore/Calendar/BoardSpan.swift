import Foundation

/// 今日の盤面(設定の上班〜下班を格に切って、決まった幅 = 472pt に並べる)の割り付け。画面に依らない計算だけ
/// (幅は pt、時刻は 0 時からの分)。
/// 格はふつう 15 分。格の幅が 8.9–12.1pt(焼いた 10.5pt の格の 0.85–1.15 倍)に入らなければ 30 分の格
/// (焼いた 18pt の太い格の 0.85–1.15 倍 = 15.3–20.7pt)。どちらにも入らなければ、範囲に近い方の格を範囲の端の幅にして、
/// 余り(はみ出す分)を時の境目の隙間に均等に配る。夜をまたぐ・1 時間に満たない設定は 9:00–18:00 で描き、isFallback で知らせる
public struct BoardSpan: Equatable, Sendable {
    /// 格のあいだの隙間 / 時の境目(xx:00 の格の前)の隙間(既定)
    public static let baseGap: Double = 2
    public static let baseHourGap: Double = 5
    /// 15 分の格 / 30 分の格の幅の範囲
    public static let narrowRange: ClosedRange<Double> = 8.9...12.1
    public static let wideRange: ClosedRange<Double> = 15.3...20.7
    /// 設定が使えないときの時間(0 時からの分)
    public static let fallbackStart = 9 * 60
    public static let fallbackEnd = 18 * 60

    /// 盤面の下の時刻(整点だけ)
    public struct HourMark: Hashable, Sendable {
        public let hour: Int
        /// 時の境目の x(格のあいだの隙間の真ん中。盤面の両端は 0 / 全幅)
        public let x: Double

        public init(hour: Int, x: Double) {
            self.hour = hour
            self.x = x
        }
    }

    /// 描く時間(0 時からの分)。設定が使えなければ 9:00–18:00
    public let start: Int
    public let end: Int
    /// 設定(夜をまたぐ・1 時間未満)を使えず 9:00–18:00 で描いている
    public let isFallback: Bool
    /// 1 格の分(15 / 30)
    public let slotMinutes: Int
    /// 格の数
    public let count: Int
    public let cellWidth: Double
    /// 格のあいだの隙間 / 時の境目の前の隙間
    public let gap: Double
    public let hourGap: Double
    /// 盤面の幅(格と隙間の合計 = これ)
    public let totalWidth: Double

    public init(startMinutes: Int, endMinutes: Int, totalWidth: Double = 472) {
        let usable = startMinutes >= 0 && endMinutes <= 24 * 60 && endMinutes - startMinutes >= 60
        let s = usable ? startMinutes : Self.fallbackStart
        let e = usable ? endMinutes : Self.fallbackEnd
        let narrow = Self.fit(start: s, end: e, slot: 15, totalWidth: totalWidth)
        let wide = Self.fit(start: s, end: e, slot: 30, totalWidth: totalWidth)

        let chosen: Fit
        let width: Double
        var plainGap = Self.baseGap
        var breakGap = Self.baseHourGap
        if Self.narrowRange.contains(narrow.width) {
            chosen = narrow
            width = narrow.width
        } else if Self.wideRange.contains(wide.width) {
            chosen = wide
            width = wide.width
        } else {
            // どちらにも入らない:範囲に近い方の格を選び、範囲の端の幅にそろえる
            let useNarrow = Self.distance(narrow.width, from: Self.narrowRange)
                <= Self.distance(wide.width, from: Self.wideRange)
            chosen = useNarrow ? narrow : wide
            let range = useNarrow ? Self.narrowRange : Self.wideRange
            let clamped = min(max(chosen.width, range.lowerBound), range.upperBound)
            let fixed = Double(max(0, chosen.count - 1 - chosen.hours)) * Self.baseGap
                + Double(chosen.hours) * Self.baseHourGap
            let rest = totalWidth - Double(chosen.count) * clamped - fixed
            // 余りは時の境目の隙間へ(時の境目が無ければ全部の隙間へ)。
            // 詰める側で普通の隙間より狭くなってしまう(長すぎる時間)ときは、格は元の幅のまま
            let receivers = chosen.hours > 0 ? chosen.hours : chosen.count - 1
            let base = chosen.hours > 0 ? Self.baseHourGap : Self.baseGap
            if receivers > 0, base + rest / Double(receivers) >= Self.baseGap {
                width = clamped
                let widened = base + rest / Double(receivers)
                if chosen.hours > 0 {
                    breakGap = widened
                } else {
                    plainGap = widened
                    breakGap = widened
                }
            } else {
                width = chosen.width
            }
        }
        start = s
        end = e
        isFallback = !usable
        slotMinutes = chosen.slot
        count = chosen.count
        cellWidth = width
        gap = plainGap
        hourGap = breakGap
        self.totalWidth = totalWidth
    }

    /// i 番目の格の前が時の境目(xx:00)か
    public func hourBreak(before index: Int) -> Bool {
        index > 0 && (start + index * slotMinutes) % 60 == 0
    }

    /// i 番目の格の前の隙間(最初の格は 0)
    public func gapBefore(_ index: Int) -> Double {
        guard index > 0 else { return 0 }
        return hourBreak(before: index) ? hourGap : gap
    }

    /// i 番目の格の左端
    public func cellX(_ index: Int) -> Double {
        guard index > 0 else { return 0 }
        let breaks = (1...index).filter { hourBreak(before: $0) }.count
        return Double(index) * (cellWidth + gap) + Double(breaks) * (hourGap - gap)
    }

    /// 盤面の下の時刻(整点だけ。両端の時刻も含む)
    public var hourMarks: [HourMark] {
        guard count > 0 else { return [] }
        let last = start + count * slotMinutes
        return stride(from: (start + 59) / 60, through: last / 60, by: 1).map { hour in
            HourMark(hour: hour, x: boundaryX(minute: hour * 60))
        }
    }

    /// いまの x(0 時からの分、秒まで。盤面の外は nil)。格の中は割合で進み、隙間は飛び越える(戻らない)
    public func nowX(minute: Double) -> Double? {
        guard contains(minute: minute) else { return nil }
        return x(minutes: minute)
    }

    /// いまの時(盤面の中のときだけ)
    public func currentHour(minute: Double) -> Int? {
        guard contains(minute: minute) else { return nil }
        return Int(minute) / 60
    }

    /// 「9:00–18:00」
    public var text: String {
        String(format: "%d:%02d–%d:%02d", start / 60, start % 60, end / 60, end % 60)
    }

    /// 0 時からの分(秒まで)
    public static func minute(of date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    // MARK: - 中身

    private struct Fit {
        let slot: Int
        let count: Int
        /// 時の境目(格の前が xx:00)の数
        let hours: Int
        /// 既定の隙間のまま全幅に並べたときの格の幅
        let width: Double
    }

    private static func fit(start: Int, end: Int, slot: Int, totalWidth: Double) -> Fit {
        let count = max(0, (end - start) / slot)
        let hours = count > 1 ? (1..<count).filter { (start + $0 * slot) % 60 == 0 }.count : 0
        let gaps = Double(max(0, count - 1 - hours)) * baseGap + Double(hours) * baseHourGap
        let width = count > 0 ? (totalWidth - gaps) / Double(count) : 0
        return Fit(slot: slot, count: count, hours: hours, width: width)
    }

    /// 範囲までの距離(範囲の中は 0)
    private static func distance(_ value: Double, from range: ClosedRange<Double>) -> Double {
        if value < range.lowerBound { return range.lowerBound - value }
        if value > range.upperBound { return value - range.upperBound }
        return 0
    }

    private func contains(minute: Double) -> Bool {
        minute >= Double(start) && minute < Double(start + count * slotMinutes)
    }

    /// 0 時からの分 → x(格の中は割合で)
    private func x(minutes: Double) -> Double {
        let offset = minutes - Double(start)
        guard offset > 0, count > 0 else { return 0 }
        guard offset < Double(count * slotMinutes) else { return totalWidth }
        let index = min(count - 1, Int(offset / Double(slotMinutes)))
        let fraction = (offset - Double(index * slotMinutes)) / Double(slotMinutes)
        return cellX(index) + fraction * cellWidth
    }

    /// 時の境目の x(格のあいだの隙間の真ん中。両端は 0 / 全幅)
    private func boundaryX(minute: Int) -> Double {
        let offset = minute - start
        if offset <= 0 { return 0 }
        if offset >= count * slotMinutes { return totalWidth }
        guard offset % slotMinutes == 0 else { return x(minutes: Double(minute)) }
        let index = offset / slotMinutes
        return cellX(index) - gapBefore(index) / 2
    }
}
