"""icons.svg(模板刻みのアイコン 24×24)→ Sources/NippoApp/StencilIcons.swift の Path コード。

アイコンを描き直したら:  python3 scripts/material/icons_swift.py
円弧は 3 次ベジェに置き換え、線のアイコンは SwiftUI 側で strokedPath(線幅・切りっぱなしの端)にして塗りと合わせる。
"""
import os
import re
import xml.etree.ElementTree as ET

from svgelements import Arc, Close, CubicBezier, Line, Move, Path, QuadraticBezier

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'icons.svg')
OUT = os.path.join(HERE, '..', '..', 'Sources', 'NippoApp', 'StencilIcons.swift')
NS = '{http://www.w3.org/2000/svg}'


def num(v):
    s = f'{v:.3f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def pt(p):
    return f'P({num(p.x)}, {num(p.y)})'


def path_lines(d):
    path = Path(d)
    path.approximate_arcs_with_cubics()
    out = []
    for seg in path:
        if isinstance(seg, Move):
            out.append(f'p.move(to: {pt(seg.end)})')
        elif isinstance(seg, Close):
            out.append('p.closeSubpath()')
        elif isinstance(seg, Line):
            out.append(f'p.addLine(to: {pt(seg.end)})')
        elif isinstance(seg, CubicBezier):
            out.append(f'p.addCurve(to: {pt(seg.end)}, control1: {pt(seg.control1)}, control2: {pt(seg.control2)})')
        elif isinstance(seg, QuadraticBezier):
            out.append(f'p.addQuadCurve(to: {pt(seg.end)}, control: {pt(seg.control)})')
        elif isinstance(seg, Arc):
            raise SystemExit('arc left after approximation')
        else:
            raise SystemExit(f'unsupported segment {seg!r}')
    return out


def parts(symbol):
    """(stroke width or None, [swift lines]) for every drawable element, inheriting stroke from <g>/<symbol>."""
    res = []

    def walk(el, stroke):
        sw = el.get('stroke-width')
        if el.get('stroke') not in (None, 'none') and sw:
            stroke = float(sw)
        if el.get('fill') not in (None, 'none') and el.get('stroke') in (None, 'none'):
            stroke = None if el.tag != NS + 'g' else stroke
        tag = el.tag.replace(NS, '')
        if tag == 'path':
            own = stroke if el.get('fill') in (None, 'none') else None
            if el.get('fill') == 'currentColor':
                own = None
            res.append((own, path_lines(el.get('d'))))
        elif tag == 'circle':
            cx, cy, r = (float(el.get(k)) for k in ('cx', 'cy', 'r'))
            res.append((None, [f'p.addEllipse(in: CGRect(x: {num(cx - r)}, y: {num(cy - r)}, width: {num(2 * r)}, height: {num(2 * r)}))']))
        for child in el:
            walk(child, stroke)

    for child in symbol:
        walk(child, float(symbol.get('stroke-width')) if symbol.get('stroke') not in (None, 'none') and symbol.get('stroke-width') else None)
    return res


def main():
    root = ET.parse(SRC).getroot()
    names, bodies = [], []
    for sym in root.iter(NS + 'symbol'):
        name = sym.get('id').removeprefix('i-')
        names.append(name)
        lines = [f'        case .{name}:']
        for stroke, cmds in parts(sym):
            lines.append('            parts.append(Part(stroke: %s) { p in' % (num(stroke) if stroke else 'nil'))
            lines += ['                ' + c for c in cmds]
            lines.append('            })')
        bodies.append('\n'.join(lines))
    swift = f'''// 生成ファイル:scripts/material/icons_swift.py が scripts/material/icons.svg から書き出す。手で直さない
import SwiftUI

/// 模板刻みのアイコン(24×24 の格子。部品のあいだに 1.5px の橋、輪郭線なし、端は切りっぱなし)。
/// 色は foregroundStyle で付ける(StencilIconShape は塗るだけの Shape)
enum StencilIcon: String, CaseIterable {{
    case {", ".join(names)}

    struct Part {{
        /// nil = 塗り、数値 = その太さの線(24 格子の単位)
        let stroke: CGFloat?
        let build: (inout Path) -> Void
    }}

    var parts: [Part] {{
        var parts: [Part] = []
        switch self {{
{chr(10).join(bodies)}
        }}
        return parts
    }}
}}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {{ CGPoint(x: x, y: y) }}

struct StencilIconShape: Shape {{
    let icon: StencilIcon

    func path(in rect: CGRect) -> Path {{
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
            .scaledBy(x: scale, y: scale)
        var out = Path()
        for part in icon.parts {{
            var path = Path()
            part.build(&path)
            if let width = part.stroke {{
                path = path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .miter))
            }}
            out.addPath(path, transform: transform)
        }}
        return out
    }}
}}

/// アイコン 1 つ(既定 16pt)。色は呼ぶ側の foregroundStyle
struct StencilIconView: View {{
    let icon: StencilIcon
    var size: CGFloat = 16

    var body: some View {{
        StencilIconShape(icon: icon)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }}
}}
'''
    with open(OUT, 'w') as f:
        f.write(swift)
    print('wrote', os.path.relpath(OUT), len(names), 'icons')


if __name__ == '__main__':
    main()
