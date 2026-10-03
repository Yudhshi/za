// 生成ファイル:scripts/material/icons_swift.py が scripts/material/icons.svg から書き出す。手で直さない
import SwiftUI

/// 模板刻みのアイコン(24×24 の格子。部品のあいだに 1.5px の橋、輪郭線なし、端は切りっぱなし)。
/// 色は foregroundStyle で付ける(StencilIconShape は塗るだけの Shape)
enum StencilIcon: String, CaseIterable {
    case camera, power, seat, stand, speaker, flame, play, check, cross, star, undo, next, clock

    struct Part {
        /// nil = 塗り、数値 = その太さの線(24 格子の単位)
        let stroke: CGFloat?
        let build: (inout Path) -> Void
    }

    var parts: [Part] {
        var parts: [Part] = []
        switch self {
        case .camera:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(2, 6.5))
                p.addLine(to: P(14.5, 6.5))
                p.addLine(to: P(14.5, 17.5))
                p.addLine(to: P(2, 17.5))
                p.closeSubpath()
            })
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(16, 10.2))
                p.addLine(to: P(22, 6.5))
                p.addLine(to: P(22, 17.5))
                p.addLine(to: P(16, 13.8))
                p.closeSubpath()
            })
        case .power:
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(7.3, 6.4))
                p.addCurve(to: P(4.583, 9.875), control1: P(6.087, 7.281), control2: P(5.145, 8.485))
                p.addCurve(to: P(4.121, 14.261), control1: P(4.021, 11.265), control2: P(3.861, 12.785))
                p.addCurve(to: P(6.054, 18.226), control1: P(4.381, 15.738), control2: P(5.051, 17.112))
                p.addCurve(to: P(9.795, 20.564), control1: P(7.057, 19.34), control2: P(8.354, 20.151))
                p.addCurve(to: P(14.205, 20.564), control1: P(11.236, 20.977), control2: P(12.764, 20.977))
                p.addCurve(to: P(17.946, 18.226), control1: P(15.646, 20.151), control2: P(16.943, 19.34))
                p.addCurve(to: P(19.879, 14.261), control1: P(18.949, 17.112), control2: P(19.619, 15.738))
                p.addCurve(to: P(19.417, 9.875), control1: P(20.139, 12.785), control2: P(19.979, 11.265))
                p.addCurve(to: P(16.7, 6.4), control1: P(18.855, 8.485), control2: P(17.913, 7.281))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(12, 2))
                p.addLine(to: P(12, 10.2))
            })
        case .seat:
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(6.5, 2.5))
                p.addLine(to: P(6.5, 11.5))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(6.5, 14))
                p.addLine(to: P(18.5, 14))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(8, 16.5))
                p.addLine(to: P(8, 22))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(17, 16.5))
                p.addLine(to: P(17, 22))
            })
        case .stand:
            parts.append(Part(stroke: nil) { p in
                p.addEllipse(in: CGRect(x: 9.4, y: 1.4, width: 5.2, height: 5.2))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(12, 8.2))
                p.addLine(to: P(12, 14.5))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(6.5, 10.3))
                p.addLine(to: P(10.1, 10.3))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(13.9, 10.3))
                p.addLine(to: P(17.5, 10.3))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(11, 16.4))
                p.addLine(to: P(8.2, 22))
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(13, 16.4))
                p.addLine(to: P(15.8, 22))
            })
        case .speaker:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(2.5, 8.5))
                p.addLine(to: P(6.7, 8.5))
                p.addLine(to: P(12, 4))
                p.addLine(to: P(12, 20))
                p.addLine(to: P(6.7, 15.5))
                p.addLine(to: P(2.5, 15.5))
                p.closeSubpath()
            })
            parts.append(Part(stroke: 2.4) { p in
                p.move(to: P(15, 8.6))
                p.addCurve(to: P(16.326, 10.741), control1: P(15.632, 9.176), control2: P(16.092, 9.918))
                p.addCurve(to: P(16.326, 13.259), control1: P(16.56, 11.564), control2: P(16.56, 12.436))
                p.addCurve(to: P(15, 15.4), control1: P(16.092, 14.082), control2: P(15.632, 14.824))
            })
            parts.append(Part(stroke: 2.4) { p in
                p.move(to: P(17.8, 5.8))
                p.addCurve(to: P(20.132, 9.72), control1: P(18.916, 6.873), control2: P(19.722, 8.227))
                p.addCurve(to: P(20.132, 14.28), control1: P(20.543, 11.212), control2: P(20.543, 12.788))
                p.addCurve(to: P(17.8, 18.2), control1: P(19.722, 15.773), control2: P(18.916, 17.127))
            })
        case .flame:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(12.8, 1.8))
                p.addCurve(to: P(19, 14.2), control1: P(13.6, 6), control2: P(19, 8.2))
                p.addCurve(to: P(17.663, 18.314), control1: P(19, 15.678), control2: P(18.532, 17.119))
                p.addCurve(to: P(14.163, 20.857), control1: P(16.794, 19.51), control2: P(15.569, 20.401))
                p.addCurve(to: P(9.837, 20.857), control1: P(12.757, 21.314), control2: P(11.243, 21.314))
                p.addCurve(to: P(6.337, 18.314), control1: P(8.431, 20.401), control2: P(7.206, 19.51))
                p.addCurve(to: P(5, 14.2), control1: P(5.468, 17.119), control2: P(5, 15.678))
                p.addCurve(to: P(8.2, 7), control1: P(5, 11), control2: P(6.8, 8.8))
                p.addCurve(to: P(10.5, 11.4), control1: P(8.3, 9.6), control2: P(9.3, 10.8))
                p.addCurve(to: P(12.8, 1.8), control1: P(10.4, 7.4), control2: P(11.4, 4.6))
                p.closeSubpath()
            })
        case .play:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(6.5, 3.5))
                p.addLine(to: P(20, 12))
                p.addLine(to: P(6.5, 20.5))
                p.closeSubpath()
            })
        case .check:
            parts.append(Part(stroke: 3.2) { p in
                p.move(to: P(3.5, 12.6))
                p.addLine(to: P(8.1, 17.2))
            })
            parts.append(Part(stroke: 3.2) { p in
                p.move(to: P(10.2, 16.9))
                p.addLine(to: P(20.6, 6.5))
            })
        case .cross:
            parts.append(Part(stroke: 3.2) { p in
                p.move(to: P(4.5, 4.5))
                p.addLine(to: P(10.7, 10.7))
            })
            parts.append(Part(stroke: 3.2) { p in
                p.move(to: P(13.3, 13.3))
                p.addLine(to: P(19.5, 19.5))
            })
            parts.append(Part(stroke: 3.2) { p in
                p.move(to: P(19.5, 4.5))
                p.addLine(to: P(13.3, 10.7))
            })
            parts.append(Part(stroke: 3.2) { p in
                p.move(to: P(10.7, 13.3))
                p.addLine(to: P(4.5, 19.5))
            })
        case .star:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(11.1, 2.5))
                p.addLine(to: P(8.6, 8.8))
                p.addLine(to: P(2, 9.3))
                p.addLine(to: P(7.1, 13.6))
                p.addLine(to: P(5.5, 20.2))
                p.addLine(to: P(11.1, 16.7))
                p.closeSubpath()
            })
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(12.9, 2.5))
                p.addLine(to: P(15.4, 8.8))
                p.addLine(to: P(22, 9.3))
                p.addLine(to: P(16.9, 13.6))
                p.addLine(to: P(18.5, 20.2))
                p.addLine(to: P(12.9, 16.7))
                p.closeSubpath()
            })
        case .undo:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(2.5, 8.2))
                p.addLine(to: P(8.6, 3))
                p.addLine(to: P(8.6, 13.4))
                p.closeSubpath()
            })
            parts.append(Part(stroke: 3) { p in
                p.move(to: P(10.4, 8.2))
                p.addLine(to: P(14.8, 8.2))
                p.addCurve(to: P(17.915, 9.212), control1: P(15.919, 8.2), control2: P(17.01, 8.554))
                p.addCurve(to: P(19.841, 11.862), control1: P(18.821, 9.87), control2: P(19.495, 10.798))
                p.addCurve(to: P(19.841, 15.138), control1: P(20.186, 12.927), control2: P(20.186, 14.073))
                p.addCurve(to: P(17.915, 17.788), control1: P(19.495, 16.202), control2: P(18.821, 17.13))
                p.addCurve(to: P(14.8, 18.8), control1: P(17.01, 18.446), control2: P(15.919, 18.8))
                p.addLine(to: P(7, 18.8))
            })
        case .next:
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(2.5, 10.5))
                p.addLine(to: P(14.9, 10.5))
                p.addLine(to: P(14.9, 13.5))
                p.addLine(to: P(2.5, 13.5))
                p.closeSubpath()
            })
            parts.append(Part(stroke: nil) { p in
                p.move(to: P(16.4, 5.5))
                p.addLine(to: P(22, 12))
                p.addLine(to: P(16.4, 18.5))
                p.closeSubpath()
            })
        case .clock:
            parts.append(Part(stroke: 2.8) { p in
                p.move(to: P(12, 2.8))
                p.addCurve(to: P(17.279, 4.458), control1: P(13.888, 2.798), control2: P(15.731, 3.377))
                p.addCurve(to: P(20.652, 8.844), control1: P(18.827, 5.539), control2: P(20.005, 7.071))
                p.addCurve(to: P(20.9, 14.372), control1: P(21.3, 10.617), control2: P(21.386, 12.548))
                p.addCurve(to: P(17.932, 19.042), control1: P(20.413, 16.196), control2: P(19.377, 17.827))
                p.addCurve(to: P(12.822, 21.164), control1: P(16.487, 20.257), control2: P(14.702, 20.998))
                p.addCurve(to: P(7.418, 19.972), control1: P(10.941, 21.331), control2: P(9.054, 20.914))
                p.addCurve(to: P(3.676, 15.896), control1: P(5.782, 19.029), control2: P(4.476, 17.606))
                p.addCurve(to: P(2.949, 10.41), control1: P(2.877, 14.185), control2: P(2.623, 12.27))
                p.addCurve(to: P(5.5, 5.5), control1: P(3.275, 8.551), control2: P(4.166, 6.836))
            })
            parts.append(Part(stroke: 2.8) { p in
                p.move(to: P(12, 7))
                p.addLine(to: P(12, 12.2))
                p.addLine(to: P(15.4, 14.6))
            })
        }
        return parts
    }
}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

struct StencilIconShape: Shape {
    let icon: StencilIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
            .scaledBy(x: scale, y: scale)
        var out = Path()
        for part in icon.parts {
            var path = Path()
            part.build(&path)
            if let width = part.stroke {
                path = path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .miter))
            }
            out.addPath(path, transform: transform)
        }
        return out
    }
}

/// アイコン 1 つ(既定 16pt)。色は呼ぶ側の foregroundStyle
struct StencilIconView: View {
    let icon: StencilIcon
    var size: CGFloat = 16

    var body: some View {
        StencilIconShape(icon: icon)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
