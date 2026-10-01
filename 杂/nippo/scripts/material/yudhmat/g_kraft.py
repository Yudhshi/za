"""Kraft: the posture popup sheet (9-slice, 360pt wide), the crepe-tape drag handle, a dashed score line.
Recipes: merge2/posture/kraftbake.py + popups.py (kraft, ghosts of earlier sprays, edge wear, tape)."""
import math

import numpy as np
from scipy import ndimage as ndi

from . import bake, ext, out
from .bake import hexrgb, lin, smoothstep

S = 2
BW = 360
QUIET = 0.55


def shadow_alpha(s):
    """Linear darkening factor (1 - s) -> alpha of black for sRGB-space over compositing."""
    return 1 - np.power(np.clip(1 - s, 0, 1), 1 / 2.2)


def sheet():
    Hb = 400
    bleed = (8, 14, 28, 14)
    bt, bl, bb, br = (int(v * S) for v in bleed)
    W, H = BW * S + bl + br, Hb * S + bt + bb
    seed = 9005
    rng = np.random.default_rng(seed * 101)
    col, hgt, ab = ext.kraft(W, H, seed, falloff=0.03)
    # text can sit anywhere inside: flatten the fibre detail there like popups.py did under each text line, so
    # #3E2F1C secondary text stays >= 4.5 : 1 against the darkest 5 % of the board (edges keep the full texture)
    col = bake.quiet(col, [(bl + 16 * S, bt + 20 * S, bl + (BW - 16) * S, bt + (Hb - 16) * S)], amount=QUIET, feather=12)

    def P(x, y):                 # board pt -> canvas px
        return bl + x * S, bt + y * S

    cap_t, cap_b = 64, 64
    # ghosts of earlier sprays (the sheet has been used before) — all inside the top / bottom caps
    ghosts = [('haze', 'teal', [(-40, Hb - 60), (60, Hb + 40), (-40, Hb + 40)], 0.24),
              ('haze', 'black', [(290, -40), (420, -40), (420, 34)], 0.16),
              ('dust', 'black', (300, -40, 60, 20), 0.55),
              ('dust', 'orange', (-50, Hb - 52, 30, 40), 0.5)]
    for gi, g in enumerate(ghosts):
        if g[0] == 'haze':
            _, colr, pts, st = g
            cut = ext.rough_polygon(W, H, [P(x, y) for x, y in pts], rng, jitter=0.6)
            o, _, _ = ext.spray(col, hgt, ab, cut, ext.C(colr), seed * 13 + gi, passes=2, angle=rng.uniform(-20, 20),
                                sheet_pad=6, k=2.2, droplets=0.6, reach=16, spits=0, sheen=0.0, under=(0, 0))
            col = col + (o - col) * st
        else:
            _, colr, (gx, gy, gw, gh), st = g
            x0, y0 = P(gx, gy)
            x1, y1 = P(gx + gw, gy + gh)
            x0, y0, x1, y1 = [min(max(v, 2), lim - 3) for v, lim in zip((x0, y0, x1, y1), (W, H, W, H))]
            cut = ext.box_mask(W, H, x0, y0, max(x1, x0 + 2), max(y1, y0 + 2))
            o, _, _ = ext.spray(col, hgt, ab, cut, ext.C(colr), seed * 17 + gi, passes=2, angle=rng.uniform(-30, 30),
                                sheet_pad=4, k=2.0, droplets=1.6, reach=46, spits=1, sheen=0.0)
            col = col + (o - col) * st * (1 - cut[..., None])
    # board edge: hand-cut rounded rect (radius 10pt), nicks only where the 9-slice does not stretch
    rect = (bl, bt, bl + BW * S, bt + Hb * S)

    def along(side, rg):
        if side in (0, 2):
            return rg.uniform(0.12, 0.88)
        return rg.uniform(0.04, (cap_t - 10) / Hb) if rg.random() < 0.5 else rg.uniform(1 - (cap_b - 10) / Hb, 0.96)
    d = ext.board_edge(W, H, rect, 10 * S, seed * 79, nicks=4, along_range=along)
    tx, ty = P(286, Hb)
    cx, cy = P(0, Hb)
    col, hgt = ext.wear_edges(col, hgt, d, seed * 83, tear=(tx, ty, 30, 9.2, 0), crushed=[(cx, cy, 18)])
    alpha = np.clip(0.5 - d, 0, 1)
    s = ext.contact_shadow_alpha(alpha)
    sa = shadow_alpha(s) * (1 - alpha)
    A = alpha + sa
    pm = col * alpha[..., None]
    img = ext.export(pm, A)
    out.save('kraft-sheet-night', img, 'slice',
             'Posture popup board: corrugated kraft (fibres, flutes, mottle), worn edges, a torn liner patch and a '
             'crushed corner at the bottom, ghosts of earlier teal / black / orange sprays in the corners, contact '
             'shadow in the bleed. Width fixed 360pt; height stretches (caps keep every feature).', bleed=bleed,
             insets=(bleed[0] + cap_t, bleed[1] + 36, bleed[2] + cap_b, bleed[3] + 36), ground='kraft')


def tape():
    w, h = 120, 26
    pad = 7
    col, alpha, lift = ext.crepe_tape(w * S, h * S, 9100, ext.C('tape'), angle=-1.2, pad=pad * S)
    sh = ndi.gaussian_filter(ndi.shift(alpha, (2.2, 0.8), order=1), 1.6) * 0.30
    sh += ndi.gaussian_filter(ndi.shift(alpha * lift, (2.5, 1.0), order=1), 2.0) * 0.30
    sh = np.clip(sh, 0, 0.6) * (1 - alpha)
    sa = shadow_alpha(sh)
    A = alpha + sa
    img = ext.export(col * alpha[..., None], A)
    out.save('tape-handle-night', img, 'slice',
             'Crepe masking-tape drag handle across the popup\'s top edge (torn fibrous ends, crinkles, translucent, '
             '−1.2° baked, lift shadow); the label (STAND UP / STRETCH / SIT DOWN) stays live text.',
             bleed=(pad, pad, pad, pad), insets=(pad + 4, pad + 16, pad + 4, pad + 16), ground='kraft')


def score():
    """Dashed score pressed into the board (section divider on the kraft): groove + lit lip, as an overlay."""
    W, H = 316 * S, 8 * S
    B = lin(hexrgb(ext.C('kraft')))
    col = np.empty((H, W, 3), np.float32)
    col[:] = B
    col, _ = ext.score_line(col, np.zeros((H, W), np.float32), 0, W, H / 2, 9200)
    out.save('kraft-score', ext.overlay(col, 'kraft'), 'slice',
             'Dashed score line on the kraft board (overlay): place in the gap between popup sections, 316pt wide.',
             insets=(0, 2, 0, 2))


def bake_all():
    sheet()
    tape()
    score()
