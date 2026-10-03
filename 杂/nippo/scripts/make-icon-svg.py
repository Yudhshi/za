"""Yudh icon v12 (Stencil Turf): a 2x2 turf board sprayed on black lacquer.
gen(inset, radius, detail) -> SVG text, 1024 viewBox."""
import random, sys, math

TEAL, ORANGE, BLACK = "#12e9d3", "#ff6412", "#161615"

def star_path(cx, cy, r_out, r_in):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = r_out if i % 2 == 0 else r_in
        pts.append(f"{cx + r*math.cos(a):.1f},{cy + r*math.sin(a):.1f}")
    return "M" + " L".join(pts) + " Z"

def gen(inset=100, radius=185, detail=True, seed=7, tiny=False, shadow=False):
    rnd = random.Random(seed)
    size = 1024 - 2 * inset
    pad = size * 0.17
    gap = size * 0.075
    cell = (size - 2 * pad - gap) / 2
    x0 = y0 = inset + pad
    cells = [(x0, y0), (x0 + cell + gap, y0), (x0, y0 + cell + gap), (x0 + cell + gap, y0 + cell + gap)]
    rough = 'filter="url(#spray)"' if detail else ""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">']
    out.append("""  <!--
    Yudh のアプリアイコン v12「Stencil Turf」:黒漆の地に、地盘格(英語の盘面)の 2×2 を喷漆で。
    青 3 マス(うち 1 つは模板の星 = 太简单)、右下は今のマス(橙の点線)。色は界面と同じ(青 #12e9d3・橙 #ff6412・黒 #161615)。
    macOS のアイコン格子(1024 の中に 824 角の角丸)。Windows 用は余白を詰めて同じ図を書き出す(scripts/make-icon.mjs)
  -->""")
    out.append("  <defs>")
    out.append(f'    <clipPath id="sq"><rect x="{inset}" y="{inset}" width="{size}" height="{size}" rx="{radius}" ry="{radius}"/></clipPath>')
    if detail:
        out.append("""    <filter id="spray" x="-6%" y="-6%" width="112%" height="112%">
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
    </filter>""")
        out.append(f'    <radialGradient id="lacquer" cx="38%" cy="28%" r="85%"><stop offset="0" stop-color="#2b2d2f"/><stop offset="1" stop-color="{BLACK}"/></radialGradient>')
    if shadow:
        out.append('    <filter id="drop" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/></filter>')
    out.append("  </defs>")
    if shadow:
        out.append('  <g filter="url(#drop)">')
    out.append('  <g clip-path="url(#sq)">')
    out.append(f'    <rect width="1024" height="1024" fill="{"url(#lacquer)" if detail else BLACK}"/>')
    if detail:
        out.append('    <rect width="1024" height="1024" filter="url(#grain)"/>')
        # overspray around the teal cells
        for (cx, cy), color in zip(cells[:3], [TEAL] * 3):
            for _ in range(26):
                ang = rnd.uniform(0, 2 * math.pi)
                dist = rnd.uniform(0.52, 0.78) * cell
                px = cx + cell / 2 + math.cos(ang) * dist
                py = cy + cell / 2 + math.sin(ang) * dist
                rr = rnd.uniform(1.6, 5.5)
                out.append(f'    <circle cx="{px:.1f}" cy="{py:.1f}" r="{rr:.1f}" fill="{color}" opacity="{rnd.uniform(0.35, 0.85):.2f}"/>')
    # three teal cells
    for i, (cx, cy) in enumerate(cells[:3]):
        out.append(f'    <rect x="{cx:.1f}" y="{cy:.1f}" width="{cell:.1f}" height="{cell:.1f}" fill="{TEAL}" {rough}/>')
    # stencil star on the top-right cell, with a vertical bridge
    cx, cy = cells[1]
    scx, scy = cx + cell / 2, cy + cell / 2 + cell * 0.03
    bridge = cell * 0.055
    out.append(f'    <mask id="bridge"><rect width="1024" height="1024" fill="#fff"/>'
               f'<rect x="{scx - bridge/2:.1f}" y="{cy:.1f}" width="{bridge:.1f}" height="{cell:.1f}" fill="#000"/></mask>')
    if not tiny:
        out.append(f'    <path d="{star_path(scx, scy, cell*0.30, cell*0.13)}" fill="{BLACK}" fill-opacity="0.92" mask="url(#bridge)"/>')
    # orange dashed current cell: corners + middle dashes
    cx, cy = cells[3]
    w = cell * (0.115 if detail else 0.15)
    a = w / 2
    L = cell * 0.24           # corner arm
    m = cell * 0.14           # middle dash
    x1, y1, x2, y2 = cx + a, cy + a, cx + cell - a, cy + cell - a
    mid = cell / 2
    segs = [
        f"M{x1:.1f},{y1+L:.1f} L{x1:.1f},{y1:.1f} L{x1+L:.1f},{y1:.1f}",
        f"M{x2-L:.1f},{y1:.1f} L{x2:.1f},{y1:.1f} L{x2:.1f},{y1+L:.1f}",
        f"M{x2:.1f},{y2-L:.1f} L{x2:.1f},{y2:.1f} L{x2-L:.1f},{y2:.1f}",
        f"M{x1+L:.1f},{y2:.1f} L{x1:.1f},{y2:.1f} L{x1:.1f},{y2-L:.1f}",
    ]
    if detail:
        segs += [
            f"M{cx+mid-m/2:.1f},{y1:.1f} L{cx+mid+m/2:.1f},{y1:.1f}",
            f"M{cx+mid-m/2:.1f},{y2:.1f} L{cx+mid+m/2:.1f},{y2:.1f}",
            f"M{x1:.1f},{cy+mid-m/2:.1f} L{x1:.1f},{cy+mid+m/2:.1f}",
            f"M{x2:.1f},{cy+mid-m/2:.1f} L{x2:.1f},{cy+mid+m/2:.1f}",
        ]
    if tiny:
        segs = [f"M{x1:.1f},{y1:.1f} L{x2:.1f},{y1:.1f} L{x2:.1f},{y2:.1f} L{x1:.1f},{y2:.1f} Z"]
    out.append(f'    <path d="{" ".join(segs)}" fill="none" stroke="{ORANGE}" stroke-width="{w:.1f}" stroke-linejoin="miter" {rough}/>')
    out.append("  </g>")
    if detail:
        # a thin lacquer rim so the edge reads on dark docks
        out.append(f'  <rect x="{inset+1.5}" y="{inset+1.5}" width="{size-3}" height="{size-3}" rx="{radius}" ry="{radius}" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="3"/>')
    if shadow:
        out.append("  </g>")
    out.append("</svg>")
    return "\n".join(out) + "\n"

if __name__ == "__main__":
    # python3 scripts/make-icon-svg.py <出力先>  → mac.svg(= Resources/AppIcon/AppIcon.svg)と Windows 用 3 種
    # mac.svg は scripts/make-icon.mjs で AppIcon.icns に、Windows 用は 16–24px = win-tiny、32–48px = win-small、
    # それ以上 = win で PNG に書き出して ../yudh-win/app/src-tauri/icons/ の png と icon.ico にまとめる
    import pathlib
    d = pathlib.Path(sys.argv[1])
    (d / "mac.svg").write_text(gen(100, 185, True, shadow=True))
    (d / "win.svg").write_text(gen(28, 210, True))
    (d / "win-small.svg").write_text(gen(16, 170, False))
    (d / "win-tiny.svg").write_text(gen(0, 150, False, tiny=True))
