"""Yudh icon 「30/30」: a clock sprayed on a concrete wall, the sit half grey and the stand half teal.
gen(tier) -> SVG text, 1024 viewBox. Tiers: mac / mac-small / mac-tiny (macOS grid) and win / win-small / win-tiny (Windows)."""
import math, pathlib, random, sys

TEAL, ORANGE, BLACK = "#12e9d3", "#ff6412", "#161615"
CONCRETE, GREY_M, GREY_L = "#3a3d40", "#53585c", "#abafb2"
C = 512

# 板(角丸の地)の位置と半径。mac は macOS のアイコン格子(1024 の中に 824 角)
PLATES = {
    "mac": (100, 185), "mac-small": (100, 185), "mac-tiny": (100, 185),
    "win": (28, 210), "win-small": (16, 170), "win-tiny": (0, 150),
}

DEFS = """    <filter id="spray" x="-6%" y="-6%" width="112%" height="112%">
      <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="3" result="n"/>
      <feDisplacementMap in="SourceGraphic" in2="n" scale="9" xChannelSelector="R" yChannelSelector="G" result="d"/>
      <feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="3" seed="11" result="m"/>
      <feColorMatrix in="m" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -0.9 0.62" result="shade"/>
      <feComposite in="shade" in2="d" operator="in" result="s"/>
      <feMerge><feMergeNode in="d"/><feMergeNode in="s"/></feMerge>
    </filter>
    <filter id="grain" x="0" y="0" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="5"/>
      <feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.07 0"/>
    </filter>
    <filter id="concrete" x="0" y="0" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.016" numOctaves="3" seed="21" result="m"/>
      <feColorMatrix in="m" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.16 -0.05" result="mottle"/>
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="1" seed="4" result="s"/>
      <feColorMatrix in="s" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 2.2 -1.5" result="pits"/>
      <feMerge><feMergeNode in="mottle"/><feMergeNode in="pits"/></feMerge>
    </filter>"""


def half(r, gap, side):
    """Half disc at the centre, pulled gap/2 away from the stencil bridge. side = -1 (sit, left) / 1 (stand, right)."""
    x = C + side * gap / 2
    sweep = 0 if side < 0 else 1
    return f"M{x},{C - r} A{r},{r} 0 0 {sweep} {x},{C + r} Z"


def hand(ang_deg, L, w, edge):
    a = math.radians(ang_deg - 90)
    hx, hy = C + math.cos(a) * L, C + math.sin(a) * L
    line = f'x1="{C}" y1="{C}" x2="{hx:.1f}" y2="{hy:.1f}" stroke-linecap="round"'
    return [f'<line {line} stroke="{BLACK}" stroke-width="{w + 2 * edge}"/>',
            f'<line {line} stroke="{ORANGE}" stroke-width="{w}"/>']


def detailed():
    """大きいサイズ:坐の半分は水泥灰の漆(細かい粒)、站の半分は青を喷漆で。刻度は模板の切り欠き(下の墙が見える)、
    真ん中の縦の隙間は模板の桥。周りに青の飞沫。針は 4 時(120°)= 站の側。"""
    r, gap = 318, 18
    o = [f'<clipPath id="sit"><path d="{half(r, gap, -1)}"/></clipPath>',
         f'<path d="{half(r, gap, -1)}" fill="{GREY_M}"/>',
         '<rect width="1024" height="1024" filter="url(#grain)" clip-path="url(#sit)"/>',
         f'<path d="{half(r, gap, 1)}" fill="{TEAL}" filter="url(#spray)"/>']
    rnd = random.Random(2)
    for _ in range(30):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(300, 380)
        o.append(f'<circle cx="{C + 160 + math.cos(a) * d:.1f}" cy="{C + math.sin(a) * d:.1f}" r="{rnd.uniform(2, 7):.1f}" '
                 f'fill="{TEAL}" opacity="{rnd.uniform(0.35, 0.9):.2f}"/>')
    for i in range(12):
        if i in (0, 6):  # 12 時と 6 時は桥の上
            continue
        a = math.radians(i * 30 - 90)
        L, w = (70, 22) if i % 3 == 0 else (44, 16)
        o.append(f'<line x1="{C + math.cos(a) * (r + 4):.1f}" y1="{C + math.sin(a) * (r + 4):.1f}" '
                 f'x2="{C + math.cos(a) * (r - L):.1f}" y2="{C + math.sin(a) * (r - L):.1f}" stroke="{CONCRETE}" stroke-width="{w}"/>')
    o += hand(120, r * 0.78, 46, 13)
    o.append(f'<circle cx="{C}" cy="{C}" r="40" fill="{BLACK}"/>')
    o.append(f'<circle cx="{C}" cy="{C}" r="14" fill="{GREY_L}"/>')
    return o


def simple(hub=True):
    """小さいサイズ:質感・刻度・飞沫なし。円を大きく、針を太く。"""
    r, gap = 440, 30
    o = [f'<path d="{half(r, gap, -1)}" fill="{GREY_M}"/>', f'<path d="{half(r, gap, 1)}" fill="{TEAL}"/>']
    o += hand(120, r * 0.76, 110, 34)
    if hub:
        o.append(f'<circle cx="{C}" cy="{C}" r="84" fill="{BLACK}"/>')
    return o


def gen(tier):
    inset, radius = PLATES[tier]
    size = 1024 - 2 * inset
    detail = tier in ("mac", "win")
    shadow = tier == "mac"
    # 中身は mac の板(824)/ 小さい板(992)を基準に描いて、板の大きさに合わせて拡大縮小する
    k = size / (824 if detail else 992)
    body = detailed() if detail else simple(hub=not tier.endswith("tiny"))  # 16px では軸が黒い塊になる
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">']
    out.append("""  <!--
    Yudh のアプリアイコン「30/30」:水泥の墙に模板で喷いた時計。左(坐)の半分は灰の漆、右(站)の半分は青(#12e9d3)。
    針は橙(#ff6412)で站の側を指す。刻度は模板の切り欠き、真ん中の縦の隙間は模板の桥。scripts/make-icon-svg.py が作る
  -->""")
    out.append("  <defs>")
    if detail:
        out.append(DEFS)
    if shadow:
        out.append('    <filter id="drop" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/></filter>')
    out.append(f'    <clipPath id="plate"><rect x="{inset}" y="{inset}" width="{size}" height="{size}" rx="{radius}" ry="{radius}"/></clipPath>')
    out.append("  </defs>")
    if shadow:
        out.append('  <g filter="url(#drop)">')
    out.append('  <g clip-path="url(#plate)">')
    out.append(f'    <rect width="1024" height="1024" fill="{CONCRETE}"/>')
    if detail:
        out.append('    <rect width="1024" height="1024" filter="url(#concrete)"/>')
        out.append('    <rect width="1024" height="1024" filter="url(#grain)"/>')
    out.append(f'    <g transform="translate({C} {C}) scale({k:.4f}) translate(-{C} -{C})">')
    out += ["      " + x for x in body]
    out.append("    </g>")
    out.append("  </g>")
    if detail:
        # 暗い Dock でも縁が見えるように、ごく薄い明るい縁
        out.append(f'  <rect x="{inset + 1.5}" y="{inset + 1.5}" width="{size - 3}" height="{size - 3}" rx="{radius}" ry="{radius}" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="3"/>')
    if shadow:
        out.append("  </g>")
    out.append("</svg>")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    # python3 scripts/make-icon-svg.py [出力先]  → 既定は Resources/AppIcon/ に 6 枚:
    #   AppIcon.svg(mac。64px 以上)、AppIcon-small.svg(mac の 32px と 16・32pt の @2x)、AppIcon-tiny.svg(mac の 16px)、
    #   win.svg(64px 以上)、win-small.svg(32–48px)、win-tiny.svg(16–24px = 通知領域)
    # そのあと node scripts/make-icon.mjs で AppIcon.icns と ../yudh-win/app/src-tauri/icons/ の png・icon.ico を作る
    d = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent / "Resources/AppIcon"
    names = {"mac": "AppIcon.svg", "mac-small": "AppIcon-small.svg", "mac-tiny": "AppIcon-tiny.svg", "win": "win.svg", "win-small": "win-small.svg", "win-tiny": "win-tiny.svg"}
    for tier, name in names.items():
        (d / name).write_text(gen(tier))
    print("wrote", ", ".join(names.values()), "to", d)
