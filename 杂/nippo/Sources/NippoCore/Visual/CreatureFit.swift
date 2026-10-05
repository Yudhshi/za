import CoreGraphics
import Foundation

/// 主角卡の第二の模板(曜日の神兽)をどこに・どの大きさで喷くか。
/// 神兽は卡の右に寄せ(墨の右端を卡の右から inset)、墨の下端を卡の下から bottom に置く。
/// 墨の高さは卡の高さ × target から始めて、文字・数字・格(avoid)と clearance 以上離れるまで縮める(min まで)。
/// 離れ具合は素材の左の輪郭(contour:配置の枠を上から等分した帯ごとの、いちばん左の墨の x)で測る
public enum CreatureFit {
    public struct Art: Equatable, Sendable {
        /// 配置の枠(素材の layoutSize、pt)
        public var box: CGSize
        /// 墨の外接矩形(配置の枠の座標)
        public var ink: CGRect
        /// 帯ごとのいちばん左の墨の x(配置の枠の座標)。墨のない帯は nil
        public var contour: [CGFloat?]

        public init(box: CGSize, ink: CGRect, contour: [CGFloat?]) {
            self.box = box
            self.ink = ink
            self.contour = contour
        }
    }

    public struct Placement: Equatable, Sendable {
        /// 配置の枠の左上(卡の座標)
        public var origin: CGPoint
        public var scale: CGFloat

        public init(origin: CGPoint, scale: CGFloat) {
            self.origin = origin
            self.scale = scale
        }
    }

    public static func place(art: Art, card: CGSize, avoid: [CGRect],
                             target: CGFloat = 0.76, minimum: CGFloat = 0.6,
                             inset: CGFloat = 6, bottom: CGFloat = 12, clearance: CGFloat = 9) -> Placement? {
        guard art.ink.height > 0, art.box.height > 0, !art.contour.isEmpty,
              card.width > 0, card.height > 0, minimum <= target else { return nil }
        var fraction = target
        while fraction >= minimum - 0.0001 {
            let scale = card.height * fraction / art.ink.height
            let origin = CGPoint(x: card.width - inset - art.ink.maxX * scale,
                                 y: card.height - bottom - art.ink.maxY * scale)
            if fits(art: art, origin: origin, scale: scale, card: card, avoid: avoid, clearance: clearance) {
                return Placement(origin: origin, scale: scale)
            }
            fraction -= 0.02
        }
        return nil
    }

    static func fits(art: Art, origin: CGPoint, scale: CGFloat, card: CGSize, avoid: [CGRect],
                     clearance: CGFloat) -> Bool {
        // 墨が卡の上にはみ出さない
        if origin.y + art.ink.minY * scale < clearance { return false }
        let bands = art.contour.count
        let bandHeight = art.box.height * scale / CGFloat(bands)
        for (index, left) in art.contour.enumerated() {
            guard let left else { continue }
            let top = origin.y + CGFloat(index) * bandHeight
            let inkLeft = origin.x + left * scale
            for rect in avoid where rect.width > 0 && rect.height > 0 {
                // 縦に重なる帯で、墨の左端が枠の右端 + clearance より左なら近すぎる
                let overlapsVertically = top < rect.maxY + clearance && top + bandHeight > rect.minY - clearance
                if overlapsVertically && inkLeft < rect.maxX + clearance && origin.x + art.box.width * scale > rect.minX {
                    return false
                }
            }
        }
        return true
    }
}
