"""Stencil sprites: glyph sets (big 132pt teal / black, timer 40pt on kraft, count 56pt on the card), whole-word shouts
(NEXT / NOW / TOMORROW, weekday header 31pt, weekday 21pt), and the complete NICE! / ⊘ MISS stamps.
Recipes: merge2/today/todaybake.py (hero stencils), merge2/english/eng_bake.py (TUESDAY, 20/20, stamps),
merge2/posture/popups.py (timer)."""
import math

import numpy as np
from PIL import Image

from . import ext, glyph, out
from .g_concrete import ground_hex
from .g_paint import border_fade

S = 2
BLACK_SLAB = '#1B1C1D'      # nominal ground for teal / white stencils on the calm hero (black film over concrete)
WHITE_CARD = '#F4F3EE'
DAYS = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']
NO_I = {'I': []}            # today v3: a bridged I reads as ':' in FRIDAY

RECIPES = {
    # hero numerals (todaybake): own seed + gun angle per glyph, overspray kept mostly on one side
    'big': dict(passes=3, sheet_pad=14, k=3.0, droplets=0.35, reach=12, spits=0, sheen=0.03, side_min=0.2),
    # small shouts on the hero
    'shout': dict(passes=2, sheet_pad=10, k=3.6, droplets=0.12, reach=8, spits=0, sheen=0.02),
    # header weekday (english_gen: TUESDAY k 3.3, few droplets)
    'day': dict(passes=2, sheet_pad=8, k=3.3, droplets=0.06, reach=6, spits=0, sheen=0.02, relief=0.7),
    # posture timer on kraft (popups): heavy black, bleed tamed
    'timer': dict(passes=3, sheet_pad=8, k=5.2, droplets=0.14, reach=6, spits=0, sheen=0.02, under=(0.4, 0.6)),
    # 20/20 on the white card (english 08)
    'count': dict(passes=2, sheet_pad=8, k=4.6, droplets=0.12, reach=6, spits=0, sheen=0.02, relief=0.7),
}


def spray_mask(m, pad, color, seed, recipe, kind='concrete', ground=None, angle=None, side=None, tame=None):
    """Spray one stencil mask (cell-high, ink-cropped) on a transparent canvas with `pad` = (t, l, b, r) px."""
    t, l, b, r = pad
    H, W = m.shape[0] + t + b, m.shape[1] + l + r
    cut = np.zeros((H, W), np.float32)
    cut[t:t + m.shape[0], l:l + m.shape[1]] = m
    rng = np.random.default_rng(seed)
    kw = dict(RECIPES[recipe])
    side_min = kw.pop('side_min', 0.12)
    L = ext.Layer(W, H, seed + 1, kind)
    L.spray(cut, color, seed + 2, side=side, side_min=side_min,
            angle=angle if angle is not None else rng.uniform(-12, -3), keep_bleed=tame, **kw)
    border_fade(L, 4)
    return ext.export(L.col, L.A, ground)


def glyph_set(sid, aid, prefix, chars, color, bridge, recipe, ground, kind='concrete', pad_pt=(10, 10, 10, 10),
              tame=None, seed=5000, purpose=''):
    """One atlas per set: every glyph sprayed through its own stencil (own seed + gun angle), cells cut with the
    same vertical extent; baseline at `ascent` from the cell top."""
    glyph.load()
    t, l, b, r = (int(v * S) for v in pad_pt)
    pieces = []
    for i, ch in enumerate(chars):
        m, base, ctop, inkw, gap = glyph.word(prefix, ch, bridge_em=bridge, track_em=0.03, seed=seed + 31 * i)
        pieces.append((ch, m, base, ctop, inkw, gap))
    rows = np.where(np.max([p[1].max(1) for p in pieces], 0) > 0.05)[0]
    top, bot = int(rows.min()), int(rows.max()) + 1
    base = pieces[0][2]
    cells, x = [], 0
    rng = np.random.default_rng(seed)
    for i, (ch, m, _, _, inkw, gap) in enumerate(pieces):
        side = None
        if recipe == 'big':
            side = 20 + rng.uniform(-40, 40)
        angle = {'big': rng.uniform(-12, -3), 'timer': -5.0, 'count': -8.0}.get(recipe, rng.uniform(-6, 2))
        img = spray_mask(m[top:bot], (t, l, b, r), color, seed + 101 * i, recipe, kind, ground, angle=angle,
                         side=side, tame=tame)
        cells.append((ch, img, inkw, gap))
    Hc = cells[0][1].shape[0]
    Wa = sum(c[1].shape[1] for c in cells) + 2 * (len(cells) - 1)
    atlas = np.zeros((Hc, Wa, 4), np.uint8)
    glyphs = {}
    for ch, img, inkw, gap in cells:
        atlas[:, x:x + img.shape[1]] = img
        glyphs[ch] = dict(rect=[x, 0, img.shape[1], Hc], advance=(inkw + gap) / S, bearing=-l / S)
        x += img.shape[1] + 2
    ascent = (t + base - top) / S
    descent = (Hc - t - (base - top)) / S
    out.glyph_set(sid, aid, atlas, glyph.size_of(prefix), (ascent, descent), glyphs, purpose)


def word_sprite(aid, prefix, text, color, bridge, recipe, ground, seed, purpose, pad_pt=(8, 8, 8, 8), over=None,
                track=0.03, side=None):
    m, base, ctop, inkw, gap = glyph.word(prefix, text, bridge_em=bridge, track_em=track, seed=seed, over=over)
    rows = np.where(m.max(1) > 0.05)[0]
    top, bot = int(rows.min()), int(rows.max()) + 1
    t, l, b, r = (int(v * S) for v in pad_pt)
    img = spray_mask(m[top:bot], (t, l, b, r), color, seed + 7, recipe, 'concrete', ground,
                     angle=np.random.default_rng(seed).uniform(-6, 2), side=side)
    H, W = img.shape[:2]
    cap_top = (t + ctop - top) / S
    baseline = (t + base - top) / S
    bleed = (cap_top, l / S, H / S - baseline, r / S)
    out.save(aid, img, 'sprite', purpose, bleed=bleed, baseline=baseline, capHeight=baseline - cap_top)


def stamp(kind):
    """eng_bake.stamp at the tokens size: 150 x 60pt hand-cut block sprayed (NICE! orange −7°, MISS grey +5°), then
    the stencil letters (and the ⊘) sprayed black through a second sheet, same rotation; NICE! gets one short drip."""
    glyph.load()
    bw, bh = 150 * S, 60 * S
    ang = -7 if kind == 'nice' else 5
    paint = 'orange' if kind == 'nice' else 'grey'
    bleed = 26
    W, H = bw + 2 * bleed * S, bh + 2 * bleed * S
    x0, y0 = bleed * S, bleed * S
    cx, cy = x0 + bw / 2, y0 + bh / 2
    seed = 5600 if kind == 'nice' else 5620
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=(x0 + 20, y0 + 16, x0 + bw - 20, y0 + bh - 16, 0.4))
    block = ext.rotate_mask(ext.rect_mask(W, H, x0, y0, x0 + bw, y0 + bh, rng, 0.9), ang, cx, cy)
    cov, dens = L.spray(block, paint, seed + 2, side=-17, side_min=0.12, box=(x0, y0, x0 + bw, y0 + bh), passes=3,
                        angle=ang + rng.uniform(-8, 8), sheet_pad=8, k=2.5, droplets=0.55, reach=9, spits=1,
                        sheen=0.05, relief=0.8)
    if kind == 'nice':
        filled = cov > 0.6
        cols = np.where(filled.any(0))[0]
        xs = int(rng.uniform(cols.min() + 0.55 * (cols.max() - cols.min()), cols.min() + 0.8 * (cols.max() - cols.min())))
        yb = int(np.nonzero(filled[:, xs])[0].max())
        a, h = ext.drip_shape(W, H, xs, yb - 2, 30, 8.5, rng.uniform(0, 6))
        a = a * (1 - np.clip(cov, 0, 1))
        P = ext.lin(ext.hexrgb(ext.C(paint)))
        L.col = L.col * (1 - a[..., None]) + (P * 0.86 + h[..., None] * 0.22) * a[..., None]
        L.add(a)
    m, base, ctop, inkw, gap = glyph.word('st', 'NICE!' if kind == 'nice' else 'MISS', bridge_em=0.075, track_em=0.035,
                                          seed=seed + 5)
    rows = np.where(m.max(1) > 0.05)[0]
    cap = base - ctop
    isz = int(round(26 * S)) if kind == 'miss' else 0
    gapx = int(7 * S) if kind == 'miss' else 0
    tw = isz + gapx + m.shape[1]
    k = min(1.0, (bw - 30 * S) / tw)            # fit inside the block with ≥ 15pt each side
    if k < 1:
        m = np.asarray(Image.fromarray(m).resize((int(m.shape[1] * k), int(m.shape[0] * k)), Image.LANCZOS))
        base, ctop, cap, isz, gapx = (int(round(v * k)) for v in (base, ctop, cap, isz, gapx))
        tw = isz + gapx + m.shape[1]
    letters = np.zeros((H, W), np.float32)
    lx = int(round(x0 + (bw - tw) / 2))
    cap_top = int(round(cy - cap / 2))
    letters = np.maximum(letters, _place(H, W, m, lx + isz + gapx, cap_top - ctop))
    if kind == 'miss':
        nm = ext.icon_mask('nope', isz)
        iy, ix = int(round(cy - isz / 2)), lx
        letters[iy:iy + isz, ix:ix + isz] = np.maximum(letters[iy:iy + isz, ix:ix + isz], nm)
    letters = ext.rotate_mask(letters, ang, cx, cy)
    L.spray(letters, 'black', seed + 9, passes=2, angle=ang + 4, sheet_pad=6, k=3.6, droplets=0.10, reach=5,
            spits=0, sheen=0.02, relief=0.6)
    border_fade(L, 8)
    img = ext.export(L.col, L.A, ground_hex())
    out.save(f'stamp-{kind}-night', img, 'sprite',
             ('NICE! stamp: orange block + black stencil letters, −7° and one short drip baked; ' if kind == 'nice' else
              '⊘ MISS stamp: meeting-grey block + black stencil ⊘ and letters, +5° baked; ') +
             'layout rect = the 150×60pt stamp box (slot top-right of the card), anchor = box centre.',
             bleed=(bleed, bleed, bleed, bleed), anchor=(cx / S, cy / S), ground='concrete')


def _place(H, W, m, x, y):
    o = np.zeros((H, W), np.float32)
    h, w = m.shape
    ys0, xs0 = max(0, y), max(0, x)
    ys1, xs1 = min(H, y + h), min(W, x + w)
    o[ys0:ys1, xs0:xs1] = m[ys0 - y:ys1 - y, xs0 - x:xs1 - x]
    return o


def bake_all():
    glyph.load()
    glyph_set('big-teal', 'glyph-big-teal-night', 'big', '0123456789:/', 'teal', 0.06, 'big', BLACK_SLAB,
              pad_pt=(16, 18, 18, 20), seed=5100,
              purpose='Hero numerals on the black slab (calm): teal stencil, YudhStencil bridges 0.06em, 132pt.')
    glyph_set('big-black', 'glyph-big-black-night', 'big', '0123456789:/', 'black', 0.06, 'big', 'teal',
              pad_pt=(16, 18, 18, 20), seed=5200,
              purpose='Hero numerals on the teal / orange flood (event, 00): black stencil, 132pt.')
    glyph_set('timer-black', 'glyph-timer-black', 'tm', '0123456789:', 'black', 0.075, 'timer', 'kraft', kind='kraft',
              pad_pt=(7, 7, 7, 7), tame=0.3, seed=5300,
              purpose='Posture popup timer 12:30: black stencil on kraft, 40pt, bridges 0.075em.')
    glyph_set('count-black', 'glyph-count-black-night', 'n56', '0123456789/', 'black', 0.065, 'count', WHITE_CARD,
              pad_pt=(8, 8, 8, 8), seed=5400,
              purpose='English 20/20 (stage clear): black stencil on the white card, 56pt.')
    for w, wid in (('NEXT', 'next'), ('NOW', 'now'), ('TOMORROW', 'tomorrow')):
        for color, ground in (('teal', BLACK_SLAB), ('black', 'teal')):
            aid = f'shout-{wid}-{color}-night'
            word_sprite(aid, 'sm', w, color, 0.08, 'shout', ground, 5500 + len(w) * 7 + (color == 'black'),
                        f'Hero shout {w} (21pt stencil, {color}{" on the calm black slab" if color == "teal" else " on the teal event flood"}).',
                        over=NO_I)
            out.word(f'shout-{wid}-{color}', aid)
    for i, d in enumerate(DAYS):
        aid = f'day-{d.lower()}-white-night'
        word_sprite(aid, 'day', d, 'white', 0.065, 'day', ground_hex(), 5700 + 13 * i,
                    f'Header weekday {d}: white stencil sprayed on concrete, 31pt.', pad_pt=(7, 7, 8, 9), over=NO_I)
        out.word(f'day-{d.lower()}', aid)
        aid = f'dayshout-{d.lower()}-white-night'
        word_sprite(aid, 'sm', d, 'white', 0.08, 'shout', BLACK_SLAB, 5800 + 13 * i,
                    f'{d} after TOMORROW on the calm hero: white stencil, 21pt.', over=NO_I)
        out.word(f'dayshout-{d.lower()}', aid)
    stamp('nice')
    stamp('miss')
