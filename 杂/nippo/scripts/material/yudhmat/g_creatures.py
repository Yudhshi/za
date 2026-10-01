"""The seven weekday creatures (final stencils, merge2/illus/creatures): grey second stencil for the calm hero, teal
stage-clear art for the badge, and the faint kraft ghost for the posture popups.  The UI never names them."""
import math
import os

import numpy as np
from scipy import ndimage as ndi

from . import ext, out, svg
from .bake import gnoise, smoothstep
from .g_paint import border_fade

S = 2
SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src', 'creatures'))
DAYS = [('mon', 'mon-lamassu'), ('tue', 'tue-griffin'), ('wed', 'wed-baku'), ('thu', 'thu-sphinx'),
        ('fri', 'fri-garuda'), ('sat', 'sat-sleipnir'), ('sun', 'sun-phoenix')]
SIDES = [18, 165, -15, 200, 30, 150, 10]      # today v3 week sheet: can held from … (deg), creature sprayed from +180
BLACK_SLAB = '#1B1C1D'
BLACK_PLATE = '#191918'
GHOST_STRENGTH = 0.12
TEXT_ZONES = [(168, 47, 176, 98), (138, 207, 200, 22)]     # board pt: popups 09 / 11 text on kraft


def paths(name):
    return svg.parse(os.path.join(SRC, name + '.svg'))[2]['creature']


def grey(i, day, name):
    """today v3 hero_hook: #42464A through the creature's own sheet, k 1.5 (the black slab reads through)."""
    bw, bh = 280, 210                         # art box 400 x 300 -> 280 x 210pt master (hero scales it by height)
    bleed = (8, 8, 8, 8)
    W, H = (bw + 16) * S, (bh + 16) * S
    ox, oy = 8 * S, 8 * S
    m = svg.raster(paths(name), W, H, bw * S / 400, ox, oy)
    seed = 7000 + 31 * i
    L = ext.Layer(W, H, seed, 'concrete')
    L.spray(m, 'creature', seed + 600, side=SIDES[i] + 180, side_min=0.0, passes=3, angle=-9 + (seed + 600) % 8,
            sheet_pad=8, k=1.5, droplets=0.10, reach=7, spits=0, sheen=0.03, under=(0.6, 0.6), relief=1.0)
    border_fade(L, 6)
    x0, y0, x1, y1 = svg.ink_box(m)
    out.save(f'creature-{day}-grey', ext.export(L.col, L.A, BLACK_SLAB), 'sprite',
             f'Calm hero second stencil ({day.upper()}): non-fluorescent grey paint, faces left; layout rect = the '
             f'400×300 art box (280×210pt master). ink = stencil-ink box [x0, y0, x1, y1] and contour = leftmost '
             f'stencil ink per band ({BANDS} equal horizontal bands of the layout rect, top to bottom; null = no ink), '
             f'both in layout-rect pt (overspray excluded) — CreatureFit scales the ink to 0.76 × card height and '
             f'shrinks until ≥9pt clear of text / numerals / cells. Never in event states.', bleed=bleed,
             ink=[(x0 - ox) / S, (y0 - oy) / S, (x1 - ox) / S, (y1 - oy) / S], contour=contour(m, ox, oy, bw, bh),
             feetY=286 * bh / 300, ground='black slab')


BANDS = 32


def contour(m, ox, oy, bw, bh, thr=0.5):
    """Leftmost stencil ink (pt, layout-rect x) in each of BANDS equal horizontal bands of the bw × bh pt layout
    rect; None where a band has no ink.  A band includes every pixel row it touches."""
    ink = m > thr
    res = []
    for i in range(BANDS):
        r0 = int(math.floor(oy + i * bh * S / BANDS))
        r1 = int(math.ceil(oy + (i + 1) * bh * S / BANDS))
        cols = np.nonzero(ink[r0:r1, int(ox):int(ox + bw * S)].any(0))[0]
        res.append(None if len(cols) == 0 else round(float(cols.min()) / S, 2))
    return res


def teal(i, day, name):
    """v3build.myth_hook: the creature sprayed teal through its stencil on the badge plate, inset 8pt, tilted −2°."""
    hpx = 105 * S - 2 * 8 * S
    wpx = int(round(hpx * 4 / 3))
    bleed = 6
    W, H = wpx + 2 * bleed * S, hpx + 2 * bleed * S
    ox, oy = bleed * S, bleed * S
    m = svg.raster(paths(name), W, H, wpx / 400, ox, oy)
    m = ext.rotate_mask(m, -2.0, ox + wpx / 2, oy + hpx / 2)
    seed = 7300 + 31 * i
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed, 'concrete', quiet=(0, 0, W, H, 0.4))
    L.spray(m, 'teal', seed + 1, passes=3, angle=rng.uniform(-9, -2), sheet_pad=4, k=3.2, droplets=0.08, reach=4,
            spits=0, sheen=0.04, relief=0.75)
    border_fade(L, 4)
    out.save(f'creature-{day}-teal', ext.export(L.col, L.A, BLACK_PLATE), 'sprite',
             f'Stage-clear badge art ({day.upper()}): teal stencil, −2° baked like the plate; layout rect 119×89pt, '
             f'centre it on badge-plate-night. No caption.', bleed=(bleed,) * 4, anchor=(W / 2 / S, H / 2 / S),
             ground='black plate')


def ghost(i, day, name):
    """posture/myth creature_ghost: sprayed long ago through this kraft sheet in dark kraft-brown, a misregistered
    second pass, sanded in patches and along −18° abrasion streaks.  Generic (no text map), so the strength is kept low
    near the text of popups 09 / 11 that #3E2F1C 12pt text stays ≥ 4.5:1."""
    Wp, Hp = 360, 300
    W, H = Wp * S, Hp * S
    bh = 300
    bw = bh * 4 / 3
    ox = (Wp - bw) / 2 * S
    m = svg.raster(paths(name), W, H, bh * S / 300, ox, 0, flip_w=400)
    seed = 7600 + 31 * i
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed, 'kraft')
    out1, c1, _ = ext.spray(L.col, L.hgt, L.pore, m, ext.C('ghost'), seed + 1, passes=4, angle=rng.uniform(-25, 25),
                            sheet_pad=16, k=3.2, droplets=0.35, reach=18, spits=0, sheen=0.0, under=(0, 0))
    m2 = ndi.shift(m, (-5, 7), order=1)
    out2, c2, _ = ext.spray(L.col, L.hgt, L.pore, m2, ext.C('ghost'), seed + 2, passes=2, angle=rng.uniform(-25, 25),
                            sheet_pad=16, k=1.4, droplets=0.0, spits=0, sheen=0.0, under=(0, 0))
    col = out1 + 0.45 * out2 * (1 - c1[..., None])
    A = c1 + 0.45 * c2 * (1 - c1)
    patches = smoothstep(0.55, 1.5, gnoise((H, W), 55, rng) + 0.5 * gnoise((H, W), 16, rng))
    st = ndi.rotate(gnoise((H + 200, W + 200), (0.7, 26), rng), -18, reshape=False, order=1)[100:100 + H, 100:100 + W]
    streaks = smoothstep(0.6, 1.8, st / (st.std() + 1e-6))
    wear = np.clip(1 - 0.8 * patches - 0.22 * streaks, 0.08, 1)
    # thinned 92 % under the text of popups 09 / 11 (question + sub line, 09's step row), like posture/myth did
    q = np.zeros((H, W), np.float32)
    for x, y, w, h in TEXT_ZONES:
        q[max(0, int((y - 84 - 5) * S)):int((y - 84 + h + 5) * S), int((x - 5) * S):int((x + w + 5) * S)] = 1
    q = np.clip(ndi.gaussian_filter(q, 12) * 1.6, 0, 1)
    k = GHOST_STRENGTH * wear * (1 - 0.92 * q)
    col, A = col * k[..., None], A * k
    out.save(f'kraft-ghost-{day}', ext.export(col, A, 'kraft'), 'sprite',
             f'Posture popup easter egg ({day.upper()}): faint, misregistered, sanded ghost of the weekday creature '
             f'(dark kraft-brown, faces right); lay over kraft-sheet-night under everything else, layout rect = '
             f'360×300pt at board (0, 84), clipped to the board. Thinned under the 09 / 11 text zones (board pt '
             f'168,47 176×98 and 138,207 200×22) so 12pt #3E2F1C stays ≥ 4.5:1.', ground='kraft')


def bake_all():
    for i, (day, name) in enumerate(DAYS):
        grey(i, day, name)
        teal(i, day, name)
        ghost(i, day, name)
