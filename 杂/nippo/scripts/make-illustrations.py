#!/usr/bin/env python3
"""Instructional illustrations for Yudh (stretches + posture states).

Style: cut-paper figure — paper fill, thick ink outline, orange arrows for the movement, teal for props.
All drawings share one figure vocabulary so they read as a set. viewBox 0 0 240 240, transparent background.
"""
import os

INK = "#0A0A0C"
PAPER = "#F4F2EC"
ORANGE = "#FF7A1A"
TEAL = "#1FD1C4"
GREY = "#B9B9C2"

OUT = os.path.dirname(os.path.abspath(__file__))


def limb(points, w=16, color=PAPER):
    """A limb: ink outline under a paper stroke. points = 'x,y x,y ...'"""
    return (f'<polyline points="{points}" fill="none" stroke="{INK}" stroke-width="{w + 8}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
            f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{w}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def shape(d, fill=PAPER, sw=6, extra=""):
    return f'<path d="{d}" fill="{fill}" stroke="{INK}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'


def line(d, color=INK, sw=6, extra=""):
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" {extra}/>'


def arrow(d, color=ORANGE, sw=9):
    """An arrow along path d; the head is drawn with marker."""
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" '
            f'stroke-linejoin="round" marker-end="url(#ah-{color[1:]})"/>')


def defs():
    out = []
    for c in (ORANGE, TEAL, INK):
        out.append(f'<marker id="ah-{c[1:]}" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="4" markerHeight="4" orient="auto-start-reverse">'
                   f'<path d="M0 0 L10 5 L0 10 Z" fill="{c}"/></marker>')
    return "<defs>" + "".join(out) + "</defs>"


def head_front(cx, cy, r=24, tilt=0, back=False):
    """Front view (eyes) or back view (hair only)."""
    if back:
        hair = f'<path d="M{cx - r} {cy + 2} A{r} {r} 0 0 1 {cx + r} {cy + 2} L{cx + r - 6} {cy + 12} Q{cx} {cy + 18} {cx - r + 6} {cy + 12} Z" fill="{INK}"/>'
        eyes = ""
    else:
        hair = (f'<path d="M{cx - r} {cy - 4} A{r} {r} 0 0 1 {cx + r} {cy - 4} Q{cx + r * 0.6} {cy - r * 0.05} {cx} {cy - r * 0.2} '
                f'Q{cx - r * 0.6} {cy - r * 0.05} {cx - r} {cy - 4} Z" fill="{INK}"/>')
        eyes = (f'<circle cx="{cx - 9}" cy="{cy + 4}" r="3.2" fill="{INK}"/>'
                f'<circle cx="{cx + 9}" cy="{cy + 4}" r="3.2" fill="{INK}"/>')
    return (f'<g transform="rotate({tilt} {cx} {cy})">'
            f'<circle cx="{cx - r}" cy="{cy + 4}" r="6" fill="{PAPER}" stroke="{INK}" stroke-width="5"/>'
            f'<circle cx="{cx + r}" cy="{cy + 4}" r="6" fill="{PAPER}" stroke="{INK}" stroke-width="5"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{PAPER}" stroke="{INK}" stroke-width="6"/>'
            f'{hair}{eyes}</g>')


def head_side(cx, cy, r=24, facing=1, tilt=0):
    """Profile facing +x (facing=1) or -x: nose, one eye, hair at the back."""
    f = facing
    sweep = 0 if f > 0 else 1
    return (f'<g transform="rotate({tilt} {cx} {cy})">'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{PAPER}" stroke="{INK}" stroke-width="6"/>'
            f'<path d="M{cx + f * (r - 3)} {cy - 4} l{f * 9} 9 l{-f * 8} 4" fill="{PAPER}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/>'
            f'<path d="M{cx + f * 2} {cy - r} A{r} {r} 0 0 {1 - sweep} {cx - f * r} {cy + 2} Q{cx - f * r * 0.5} {cy - r * 0.35} {cx + f * 2} {cy - r * 0.45} Z" fill="{INK}"/>'
            f'<circle cx="{cx + f * 10}" cy="{cy - 2}" r="3.2" fill="{INK}"/>'
            f'<circle cx="{cx - f * 8}" cy="{cy + 4}" r="5" fill="{PAPER}" stroke="{INK}" stroke-width="5"/>'
            f'</g>')


def torso_front(cx, top, w=96, h=96):
    """Shoulders at `top`, rounded chest, narrower at the hips."""
    l, r_ = cx - w / 2, cx + w / 2
    return shape(f"M{l} {top + 10} Q{l} {top} {l + 12} {top} L{r_ - 12} {top} Q{r_} {top} {r_} {top + 10} "
                 f"L{r_ - 8} {top + h} L{l + 8} {top + h} Z")


def torso_side(x, top, w=54, h=96, facing=1):
    f = facing
    return shape(f"M{x - w / 2} {top + 8} Q{x - w / 2} {top} {x - w / 2 + 8} {top} L{x + w / 2 - 8} {top} "
                 f"Q{x + w / 2} {top} {x + w / 2} {top + 8} L{x + w / 2 - 2} {top + h} L{x - w / 2 + 2} {top + h} Z")


def svg(body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" width="240" height="240">'
            f'<title>{title}</title>{defs()}{body}</svg>')


D = {}

# 1) shoulder-blades: back view, arrows squeezing the blades to the spine
D["shoulder-blades"] = svg(
    torso_front(120, 92, w=104, h=100)
    + head_front(120, 50, back=True)
    # spine
    + line("M120 100 L120 176", color=INK, sw=4, extra='stroke-dasharray="1 10"')
    # shoulder blades
    + shape("M78 108 Q70 128 82 150 Q98 140 100 112 Z", fill=PAPER, sw=5)
    + shape("M162 108 Q170 128 158 150 Q142 140 140 112 Z", fill=PAPER, sw=5)
    # arms hanging
    + limb("70 100 62 150 66 190")
    + limb("170 100 178 150 174 190")
    # arrows toward the spine
    + arrow("M62 128 L96 128")
    + arrow("M178 128 L144 128"),
    "夹肩胛骨")

# 2) chin-tuck: profile, chin pulled straight back
D["chin-tuck"] = svg(
    # shoulders + neck (profile)
    shape("M56 132 Q56 116 78 116 L162 116 Q184 116 184 132 L184 210 L56 210 Z")
    + shape("M112 92 L142 92 L142 122 L112 122 Z")
    # ghost of the forward head
    + f'<circle cx="152" cy="70" r="30" fill="none" stroke="{GREY}" stroke-width="5" stroke-dasharray="6 8"/>'
    + head_side(126, 74, r=30, facing=1)
    # arrow: chin straight back
    + arrow("M186 88 L152 88")
    # baseline: eyes level
    + line("M60 66 L200 66", color=TEAL, sw=4, extra='stroke-dasharray="8 8"'),
    "收下巴")

# 3) neck-side: front view, head tilted left, shoulders down
D["neck-side"] = svg(
    torso_front(120, 100, w=104, h=96)
    + limb("70 108 60 156 66 196")
    + limb("170 108 180 156 174 196")
    + head_front(112, 58, r=26, tilt=-28)
    # arrow: head tilts to the left (ear toward the shoulder)
    + arrow("M128 18 Q96 20 80 48")
    # keep the other shoulder down
    + f'<circle cx="172" cy="104" r="9" fill="{TEAL}" stroke="{INK}" stroke-width="4"/>'
    + arrow("M172 118 L172 136", color=TEAL, sw=6),
    "颈部侧拉")

# 4) chest-doorway: profile, forearm on the frame, step forward
D["chest-doorway"] = svg(
    # door frame
    f'<rect x="150" y="18" width="16" height="204" fill="{TEAL}" stroke="{INK}" stroke-width="5"/>'
    + torso_side(104, 96, w=52, h=88, facing=1)
    + head_side(104, 58, r=24, facing=1)
    # legs: step forward
    + limb("100 180 92 224")
    + limb("108 180 134 218")
    # arm: upper arm back, forearm up on the frame (below shoulder height)
    + limb("110 102 140 118 140 84")
    # arrow: chest forward (through the doorway)
    + arrow("M96 122 L130 122"),
    "扩胸拉伸")

# 5) shoulder-rolls: front view, circular arrows around both shoulders
D["shoulder-rolls"] = svg(
    torso_front(120, 100, w=104, h=96)
    + head_front(120, 56)
    + limb("70 108 62 158 68 196")
    + limb("170 108 178 158 172 196")
    # circular arrows (front → up → back → down)
    + arrow("M50 118 A24 24 0 1 1 92 100", color=ORANGE, sw=7)
    + arrow("M190 118 A24 24 0 1 0 148 100", color=ORANGE, sw=7),
    "转肩")

# 6) belly-breathing: profile, hand on belly, belly out, air in through the nose
D["belly-breathing"] = svg(
    torso_side(112, 96, w=56, h=100, facing=1)
    + head_side(112, 58, r=24, facing=1)
    # belly (out): a bulge on the front of the torso
    + shape("M138 136 Q168 162 138 192 Z", fill=PAPER, sw=6)
    # hand flat on the belly
    + limb("104 108 128 142 146 160")
    + f'<circle cx="150" cy="164" r="9" fill="{PAPER}" stroke="{INK}" stroke-width="5"/>'
    # belly out arrow, air in through the nose
    + arrow("M160 176 L188 176")
    + arrow("M180 44 Q164 44 146 54", color=TEAL, sw=6),
    "腹式呼吸")

# 7) walk: profile walking with a cup
D["walk"] = svg(
    torso_side(112, 92, w=52, h=84, facing=1)
    + head_side(112, 56, r=24, facing=1)
    # legs mid-stride
    + limb("106 172 84 204 76 226")
    + limb("116 172 140 200 150 224")
    # arms swinging; front hand holds a cup
    + limb("108 100 90 134 100 156")
    + limb("116 100 136 124 152 132")
    + f'<path d="M150 118 h20 v18 q0 6 -6 6 h-8 q-6 0 -6 -6 Z" fill="{TEAL}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>'
    # motion lines
    + line("M52 110 L30 110 M56 130 L26 130 M52 150 L34 150", color=GREY, sw=5),
    "走一走")

# 8) stand-up: profile at a standing desk, elbows 90°, desk rising
D["stand-up"] = svg(
    # desk (top) + column
    f'<rect x="120" y="112" width="104" height="12" fill="{TEAL}" stroke="{INK}" stroke-width="5"/>'
    + line("M176 124 L176 224", color=INK, sw=10)
    + line("M150 224 L202 224", color=INK, sw=8)
    # monitor
    + f'<rect x="164" y="66" width="52" height="40" rx="4" fill="{PAPER}" stroke="{INK}" stroke-width="5"/>'
    + line("M190 106 L190 112", color=INK, sw=6)
    # person
    + torso_side(84, 90, w=50, h=84, facing=1)
    + head_side(84, 54, r=24, facing=1)
    + limb("78 172 76 226")
    + limb("90 172 96 226")
    # arm: elbow at 90°, hand on the desk
    + limb("92 98 96 130 130 118")
    # arrow: desk up
    + arrow("M232 160 L232 132"),
    "站起来")

# 9) sit-down: profile, deep in the chair, feet flat
D["sit-down"] = svg(
    # chair
    f'<path d="M60 118 L60 200" fill="none" stroke="{INK}" stroke-width="10" stroke-linecap="round"/>'
    + f'<rect x="60" y="150" width="90" height="12" fill="{TEAL}" stroke="{INK}" stroke-width="5"/>'
    + line("M72 162 L72 224 M138 162 L138 224", color=INK, sw=8)
    # desk edge
    + f'<rect x="150" y="106" width="76" height="12" fill="{TEAL}" stroke="{INK}" stroke-width="5"/>'
    + line("M212 118 L212 224", color=INK, sw=8)
    # person: thighs horizontal, shins down, feet flat
    + torso_side(92, 82, w=50, h=74, facing=1)
    + head_side(92, 46, r=24, facing=1)
    + limb("96 152 142 152 146 216")
    + line("M132 220 L164 220", color=INK, sw=10)
    + limb("100 92 104 122 150 112")
    # arrow: down
    + arrow("M40 60 L40 96"),
    "坐下")

# 10) standing: front view relaxed, shoulders down (used while standing)
D["standing"] = svg(
    torso_front(120, 96, w=100, h=96)
    + head_front(120, 52)
    + limb("72 104 62 156 66 196")
    + limb("168 104 178 156 174 196")
    + limb("104 190 100 232")
    + limb("136 190 140 232")
    # shoulders relaxed: small down arrows
    + arrow("M70 76 L70 92", color=TEAL, sw=6)
    + arrow("M170 76 L170 92", color=TEAL, sw=6),
    "站立中")

# 11) stretch (fallback): front view, arms out to the sides slightly, one arrow
D["stretch"] = svg(
    torso_front(120, 96, w=100, h=96)
    + head_front(120, 52)
    + limb("72 104 42 138 34 176")
    + limb("168 104 198 138 206 176")
    + limb("104 190 100 232")
    + limb("136 190 140 232")
    + arrow("M42 60 Q60 28 96 40", color=ORANGE, sw=7),
    "拉伸")

for name, content in D.items():
    with open(os.path.join(OUT, f"{name}.svg"), "w", encoding="utf-8") as f:
        f.write(content)
print("wrote", len(D), "svgs")

# contact sheet
cells = "".join(
    f'<figure><img src="{n}.svg" width="240" height="240"><figcaption>{n}</figcaption></figure>' for n in D)
open(os.path.join(OUT, "sheet.html"), "w", encoding="utf-8").write(
    '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:#26262A;color:#ccc;font:12px system-ui;padding:16px}'
    '.g{display:grid;grid-template-columns:repeat(4,240px);gap:16px}figure{margin:0;background:#111114;padding:8px;text-align:center}'
    'img{background:#1FD1C4;display:block}</style></head><body><div class="g">' + cells + '</div></body></html>')
