"""Sprayed blocks (喷): hero slabs, word card, primary buttons, stage-clear badge plate — transparent 9-slices with the
overspray baked into the bleed.  Recipes: merge2/today/todaybake.py (hero, buttons), merge2/english/eng_bake.py (card),
merge2/posture/popups.py (teal popup button), merge2/english/v3/v3build.py (badge plate)."""
import math

import numpy as np
from scipy import ndimage as ndi

from . import ext, out
from .bake import hexrgb, lin, shade_from_height, smoothstep
from .g_concrete import ground_hex

S = 2


def canvas(w, h, bleed):
    bt, bl, bb, br = bleed
    W, H = int(round((bl + w + br) * S)), int(round((bt + h + bb) * S))
    r = (int(round(bl * S)), int(round(bt * S)), int(round((bl + w) * S)), int(round((bt + h) * S)))
    return W, H, r


def border_fade(L, px=10):
    """Overspray never gets cut by the image edge: fade it out over the last `px` pixels."""
    H, W = L.A.shape
    y = np.minimum(np.arange(H), H - 1 - np.arange(H)).astype(np.float32)
    x = np.minimum(np.arange(W), W - 1 - np.arange(W)).astype(np.float32)
    f = smoothstep(0, px, y)[:, None] * smoothstep(0, px, x)[None, :]
    L.col *= f[..., None]
    L.A *= f


def interior(r, inset_pt, k):
    x0, y0, x1, y1 = r
    i = inset_pt * S
    return (x0 + i, y0 + i, x1 - i, y1 - i, k)


def calm_film(L, cov, dens, r, rng):
    """todaybake calm hero: satin black film over concrete — lit pore / grain facets, shadowed facets sink, pass
    banding and stroke ends where the film thins and greys."""
    rel = shade_from_height(L.hgt, 1.5, 0.7)
    cv = np.clip(cov, 0, 1)[..., None]
    L.col = L.col + cv * (lin(hexrgb('#5A5E60')) * np.clip(rel, 0, None)[..., None] * 0.55)
    L.col = L.col * (1 + cv * 0.9 * np.clip(rel, None, 0)[..., None])
    dn = dens / max(1e-6, float(dens[cov > 0.5].mean()))
    dn = ndi.gaussian_filter(dn, 3)
    u = (np.arange(L.W, dtype=np.float32) - r[0]) / max(1, r[2] - r[0])
    eL, eR = rng.uniform(0.12, 0.22), rng.uniform(0.04, 0.10)
    if rng.random() < 0.5:
        eL, eR = eR, eL
    ends = 0.74 + 0.26 * smoothstep(0, eL, u) * smoothstep(0, eR, 1 - u)
    dn = dn * ends[None, :]
    thin = np.clip(1 - dn, -0.25, 0.45) * np.clip(cov, 0, 1)
    L.col = L.col * (1 + 1.0 * thin)[..., None]


def hero(aid, paint, seed, event, purpose, side=20, w=472, h=270):
    """v12.1: baked at the real layout size (472 × 270, used 250–300; short 472 × 150) — ≤ ±20 % stretch."""
    bleed = (14, 14, 30, 24) if event else (6, 6, 18, 24)   # right: the panel padding — overspray never leaves the slab
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, 26, 0.45))
    cut = ext.knife_rect(W, H, *r, rng, 0.9)
    cov, dens = L.spray(cut, paint, seed + 2, side=side, side_min=0.10 if event else 0.0, box=r,
                        passes=4 if h > 200 else 3, angle=rng.uniform(-9, -2), sheet_pad=26,
                        droplets=0.9 if event else 0.45, reach=34 if event else 22,
                        sheen=0.05 if event else 0.06, k=2.2 if event else 1.55)
    if not event:
        calm_film(L, cov, dens, r, rng)
    border_fade(L)
    caps = (36, 48, 36, 48)
    out.save(aid, ext.export(L.col, L.A, ground_hex()), 'slice', purpose, bleed=bleed,
             insets=tuple(b + c for b, c in zip(bleed, caps)), ground='concrete')


def card_white(aid='card-white-night', w=308, h=380, seed=4410, purpose=None):
    """eng_bake card: white sprayed through a hand-cut sheet, overspray left / down (inside the 24pt panel padding)."""
    bleed = (12, 22, 26, 12)
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, 18, 0.6))
    cut = ext.knife_rect(W, H, *r, rng, 1.0)
    L.spray(cut, 'white', seed + 2, side=156, side_min=0.12, box=r, passes=4 if h > 200 else 3,
            angle=rng.uniform(-9, -2), sheet_pad=24, k=2.6, droplets=0.36, reach=14, spits=1, sheen=0.035,
            relief=0.55, pore_dark=0.4)
    border_fade(L)
    caps = (28, 28, 28, 28)
    out.save(aid, ext.export(L.col, L.A, ground_hex()), 'slice',
             purpose or (f'English word card (card mode, {w}×{h}pt): white paint sprayed through a hand-cut sheet (thin '
                         f'spots, pores, overspray left / down inside the panel padding). Hang 1–2 drip-white-* from '
                         f'its lower edge in the event states.'), bleed=bleed,
             insets=tuple(b + c for b, c in zip(bleed, caps)), ground='concrete')


def button(aid, w, h, paint, seed, purpose, ring=None, kind='concrete', ground=None, recipe='today', label=None, k=2.6):
    """Sprayed primary button.  ground = hex / palette name the alpha is solved against (default: the concrete);
    label = the manifest `ground` text."""
    rb = 3 if ring else 0
    bleed = (9 + rb, 9 + rb, 10 + rb, 10 + rb)
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, kind, quiet=interior(r, 8, 0.85))
    if ring:
        x0, y0, x1, y1 = r
        m = ext.knife_rect(W, H, x0 - 6, y0 - 6, x1 + 6, y1 + 6, rng, 0.5)
        L.masked(m, ring, seed + 3, coverage=0.97, ridge=0.04)
    cut = ext.knife_rect(W, H, *r, rng, 0.6)
    if recipe == 'popup':
        L.spray(cut, paint, seed + 2, passes=3, angle=rng.uniform(-9, -2), sheet_pad=8, k=3.0, droplets=0.42,
                reach=10, spits=1, sheen=0.035, under=(1, 1), keep_bleed=0.45)
    else:
        L.spray(cut, paint, seed + 2, passes=3 if h > 40 else 2, angle=rng.uniform(-9, -2), sheet_pad=6, k=k,
                droplets=0.18, reach=6, spits=0, sheen=0.05)
    border_fade(L, 6)
    caps = (14, 16, 14, 16) if h > 40 else (11, 14, 11, 14)
    if label is None:
        label = kind if ground is None else ('teal paint' if ground == 'teal' else kind)
    out.save(aid, ext.export(L.col, L.A, ground or ground_hex()), 'slice', purpose, bleed=bleed,
             insets=tuple(b + c for b, c in zip(bleed, caps)), ground=label)


def strip_black():
    """English page meeting strip: a narrow calm slab — black sprayed through a long hand-cut sheet, satin film with
    pass banding, overspray only a whisker beyond the cut (it sits in the column, 472 wide)."""
    w, h = 472, 50
    bleed = (5, 5, 9, 8)
    W, H, r = canvas(w, h, bleed)
    seed = 4495
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, 9, 0.5))
    cut = ext.knife_rect(W, H, *r, rng, 0.8)
    cov, dens = L.spray(cut, 'black', seed + 2, side=30, side_min=0.0, box=r, passes=2, angle=rng.uniform(-9, -2),
                        sheet_pad=8, droplets=0.25, reach=8, sheen=0.06, k=1.7)
    calm_film(L, cov, dens, r, rng)
    border_fade(L, 5)
    caps = (14, 40, 14, 40)
    out.save('strip-black-night', ext.export(L.col, L.A, ground_hex()), 'slice',
             'English page meeting strip (next meeting at the top of 英语): black sprayed on the concrete like a thin '
             'calm hero, satin film; live white text on it. 472×50pt.', bleed=bleed,
             insets=tuple(b + c for b, c in zip(bleed, caps)), ground='concrete')


def play_button():
    d = 44
    bleed = (8, 8, 8, 8)
    W, H, r = canvas(d, d, bleed)
    seed = 4470
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'flat')
    cx, cy, rr = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2, d
    pts = [(cx + math.cos(2 * math.pi * k / 28) * rr, cy + math.sin(2 * math.pi * k / 28) * rr) for k in range(28)]
    cut = ext.rough_polygon(W, H, pts, rng, jitter=0.7)
    L.spray(cut, 'orange', seed + 2, passes=3, angle=rng.uniform(-9, -2), sheet_pad=6, k=3.6, droplets=0.26,
            reach=6, spits=0, sheen=0.05, relief=0.7)
    border_fade(L, 5)
    out.save('button-play-orange-night', ext.export(L.col, L.A, '#F4F3EE'), 'sprite',
             'Dictation play button: orange paint sprayed through a hand-cut circle (on the white card); the play '
             'icon is a live Shape.', bleed=bleed, anchor=(W / 2 / S, H / 2 / S), ground='white card')


def badge_plate():
    """v3build.myth_hook: chamfered (stencil-plate corners) black plaque 142 x 105pt, sprayed through a hand-cut
    sheet, tilted -2°.  The teal creature (creature-<day>-teal) is sprayed on top, centred, same tilt."""
    w, h = 142, 105
    bleed = (14, 12, 16, 18)
    W, H, r = canvas(w, h, bleed)
    seed = 4480
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, 12, 0.5))
    x0, y0, x1, y1 = r
    c = 15 * S
    pts = [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]
    cut = ext.rotate_mask(ext.rough_polygon(W, H, pts, rng, jitter=1.0), -2.0, (x0 + x1) / 2, (y0 + y1) / 2)
    L.spray(cut, 'black', seed + 2, side=27, side_min=0.12, box=r, passes=3, angle=rng.uniform(-8, -3), sheet_pad=6,
            k=5.0, droplets=0.35, reach=8, spits=0, sheen=0.03, relief=0.6)
    border_fade(L, 6)
    out.save('badge-plate-night', ext.export(L.col, L.A, '#F4F3EE'), 'slice',
             'Stage-clear badge plate (English 20/20): black, cut corners, −2° baked; layout rect 142×105pt; lay '
             'creature-<day>-teal centred on it. No caption.', bleed=bleed,
             insets=(bleed[0] + 24, bleed[1] + 24, bleed[2] + 24, bleed[3] + 24), ground='white card')


def bake_all():
    hero('hero-calm-night', 'black', 4401, False,
         'Today hero, calm: black paint sprayed through a hand-cut sheet, satin film with pass banding (concrete '
         'reads through); overspray only to the right. Layout 472×270pt (used 250–300); the weekday creature is a '
         'separate layer.')
    hero('hero-event-night', 'teal', 4421, True,
         'Today hero, event (≤10 min / in progress): teal flood with overspray all round (heavier right / down); '
         'hang ≤3 drip-teal-* from the lower edge. Layout 472×270pt (used 250–300).')
    hero('hero-zero-night', 'orange', 4441, True,
         'Today hero at countdown 00: orange flood (black stencil numerals on it). Layout 472×270pt (used 250–300).',
         side=-25)
    hero('hero-calm-short-night', 'black', 4405, False,
         'Today hero, short calm slab 472×150pt (no meetings today / no calendar access): black spray, satin film; '
         'the weekday creature fills its right side.', h=150)
    card_white()
    card_white('card-white-wide-night', 472, 340, 4415,
               'Wide white card 472×340pt (English stage clear, dictionary result): white paint sprayed through a '
               'hand-cut sheet, overspray left / down. Orange regmark-orange-night at its four corners on stage clear.')
    card_white('card-white-short-night', 472, 160, 4418,
               'Short white card 472×160pt (dictionary empty state, missing-material notice): white spray, '
               'overspray left / down.')
    button('button-orange-night', 120, 50, 'orange', 4451,
           'Primary button (orange spray, live label); nominal = hero max 120×50pt, also English 显示释义 / 下一个 / 回到今日.')
    button('button-orange-ringed-night', 120, 50, 'orange', 4461,
           'Primary button on the teal event hero: 3pt black masked ring first, then orange spray '
           '(orange never touches teal). 120×50pt (camera icon 19pt + 加入会议 / 回到会议).', ring='black', ground='teal')
    button('button-orange-small-night', 100, 34, 'orange', 4466,
           'Small primary button 100×34pt (task 完成 and other small main actions): orange spray on the concrete, '
           'live black label.')
    button('button-black-zero', 104, 50, 'black', 4468,
           'Countdown-00 button 104×50pt: black paint sprayed on the ORANGE flood (hero-zero-night), live white '
           '「马上加入」.', ground='orange', label='orange paint', k=9.0)
    button('button-teal-night', 169, 50, 'teal', 4491,
           'Posture popup primary button: teal spray on kraft (bleed tamed); 169×50pt.', kind='kraft',
           ground='kraft', recipe='popup')
    strip_black()
    play_button()
    badge_plate()
