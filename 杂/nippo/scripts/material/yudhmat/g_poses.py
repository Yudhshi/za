"""Pose silhouettes (10, baked at 132pt and 96pt; 转肩 = 哪吒 混天绫 sash) and the Egyptian frieze (three figures × done /
current / future + the shared ground line).  Black ink + orange accent sprayed on kraft relief, transparent ground.
Recipes: merge2/posture/popups.py (pose spray, tame bleed) and merge2/posture/v3/v3bake.py (frieze)."""
import os

import numpy as np

from . import ext, out, svg
from .g_paint import border_fade

S = 2
SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src'))
POSES = ['stretch', 'walk', 'chest-doorway', 'belly-breathing', 'shoulder-blades', 'shoulder-rolls', 'neck-side',
         'chin-tuck', 'sit-down', 'stand-up']
NAMES = {'stretch': '拉伸', 'walk': '走一走', 'chest-doorway': '扩胸', 'belly-breathing': '腹式呼吸',
         'shoulder-blades': '夹肩胛骨', 'shoulder-rolls': '转肩（混天绫）', 'neck-side': '颈部侧拉',
         'chin-tuck': '收下巴', 'sit-down': '坐下', 'stand-up': '站起来'}
# v12.1: baked at the size the popup shows them (sprite scale stays 1): the question / current pose at 132pt, the
# step pose at 96pt (`-s`).  pose-standing is gone (no code path draws it).
SIZES = [(132, ''), (96, '-s')]


def pose(i, name, size=132, suffix=''):
    f = 'shoulder-rolls-sash' if name == 'shoulder-rolls' else name
    groups = svg.parse(os.path.join(SRC, 'poses', f + '.svg'))[2]
    K = size / 132                           # the popup recipe was tuned at 132pt (264px)
    b = int(round(8 * K)) or 1
    W = H = (size + 2 * b) * S
    sc = size * S / 240                      # art box = 240 units
    ink = svg.raster(groups['ink'], W, H, sc, b * S, b * S)
    acc = svg.raster(groups['accent'], W, H, sc, b * S, b * S)
    seed = 8000 + 37 * i + (0 if size == 132 else 500)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed, 'kraft')
    L.spray(ink, 'black', seed + 1, passes=3, angle=rng.uniform(-9, -2), sheet_pad=int(12 * K), k=5.0,
            droplets=0.32, reach=9 * K, spits=0, sheen=0.02, under=(int(rng.choice([-1, 1])), 1), keep_bleed=0.45)
    if acc.max() > 0.5:
        L.spray(acc, 'orange', seed + 2, passes=2, angle=rng.uniform(-9, -2), sheet_pad=int(8 * K), k=4.2,
                droplets=0.25, reach=7 * K, spits=0, sheen=0.04, keep_bleed=0.5)
    border_fade(L, max(3, int(round(6 * K))))
    where = 'the question pose of popups 09 / 11 and the current step of popup 10' if size == 132 else \
        'the small step pose (popup 09 stretch line, list rows)'
    out.save(f'pose-{name}{suffix}', ext.export(L.col, L.A, 'kraft'), 'sprite',
             f'Pose silhouette {NAMES[name]}: black ink + orange accent sprayed on kraft (bridges per the illustration '
             f'spec), transparent; baked at {size}pt for {where} — layout rect = the {size}pt art box, draw at scale 1.',
             bleed=(b, b, b, b), ground='kraft')


# ---------------------------------------------------------------- frieze (popup 10 v3)
FZ_SRC = (14, 26, 706, 274)       # art units of frieze.svg (720 x 284) kept: register ends trimmed
FZ_W = 316
PT = FZ_W / (FZ_SRC[2] - FZ_SRC[0])          # pt per art unit
FZ_H = (FZ_SRC[3] - FZ_SRC[1]) * PT          # ≈ 113.3pt
REG = 264.5                                  # art y where the register (ground) line starts
STEPS = ['shoulder-blades', 'shoulder-rolls', 'chin-tuck']
FADE = {'done': 0.45, 'current': 1.0, 'future': 0.15}


def frieze_masks(W, H, b):
    g = svg.parse(os.path.join(SRC, 'egypt', 'frieze.svg'))[2]
    sc = PT * S
    ox, oy = b * S - FZ_SRC[0] * sc, b * S - FZ_SRC[1] * sc
    return svg.raster(g['ink'], W, H, sc, ox, oy), svg.raster(g['accent'], W, H, sc, ox, oy)


def columns():
    """Split the frieze into its three figures at the empty columns between them (v3bake.figure_columns)."""
    g = svg.parse(os.path.join(SRC, 'egypt', 'frieze.svg'))[2]
    ink = svg.raster(g['ink'], 720, 284, 1.0)
    acc = svg.raster(g['accent'], 720, 284, 1.0)
    occ = ((ink + acc)[FZ_SRC[1]:FZ_SRC[1] + 236, FZ_SRC[0]:FZ_SRC[2]] > 0.3).any(0)
    runs, x = [], 0
    while x < len(occ):
        if occ[x]:
            s0 = x
            while x < len(occ) and occ[x]:
                x += 1
            runs.append([s0, x])
        x += 1
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < 20:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    assert len(merged) == 3, merged
    return merged


def frieze():
    b = 6
    W, H = int(round((FZ_W + 2 * b) * S)), int(round((FZ_H + 2 * b) * S))
    ink, acc = frieze_masks(W, H, b)
    reg_px = int(round(b * S + (REG - FZ_SRC[1]) * PT * S))
    cols = columns()
    for fi, ((a, c), step) in enumerate(zip(cols, STEPS)):
        x0u, x1u = max(0, a - 6), min(FZ_SRC[2] - FZ_SRC[0], c + 6)
        X0, X1 = int(round(b * S + x0u * PT * S)), int(round(b * S + x1u * PT * S))
        for state in ('done', 'current', 'future'):
            seed = 8600 + 41 * fi + {'done': 1, 'current': 2, 'future': 3}[state]
            rng = np.random.default_rng(seed)
            L = ext.Layer(W, H, seed, 'kraft')
            for m, colr, k in ((ink, 'black', 5.0), (acc, 'orange', 4.2)):
                if colr == 'orange' and state == 'future':
                    continue                     # the future step has no cue yet, only its stencil
                cut = np.zeros_like(m)
                cut[:reg_px, X0:X1] = m[:reg_px, X0:X1]
                if cut.max() < 0.5:
                    continue
                L.spray(cut, colr, int(rng.integers(1, 1 << 30)), passes=3, angle=rng.uniform(-9, -2), sheet_pad=10,
                        k=k, droplets=0.22 if state == 'current' else 0.0, reach=7, spits=0, sheen=0.02,
                        under=(int(rng.choice([-1, 1])), 1), keep_bleed=0.45)
            L.fade(FADE[state])
            # crop to this figure's column (+ bleed) so the sprite stays small; origin = its place in the frieze
            cx0 = max(0, X0 - b * S)
            cx1 = min(W, X1 + b * S)
            col, A = L.col[:, cx0:cx1], L.A[:, cx0:cx1]
            Lb = type('T', (), {})()
            Lb.col, Lb.A = col.copy(), A.copy()
            border_fade(Lb, 6)
            out.save(f'frieze-{step}-{state}', ext.export(Lb.col, Lb.A, 'kraft'), 'sprite',
                     f'Frieze figure {fi + 1} ({["夹肩胛骨", "转肩", "收下巴"][fi]}), {state}: '
                     + {'done': 'sprayed then faded to 45% (label gets ✓)', 'current': 'full black + orange cue',
                        'future': 'stencil only at 15%, no cue'}[state]
                     + f'. All frieze sprites share one height / ground line; place the layout rect at frieze x = origin.',
                     bleed=(b, (X0 - cx0) / S, b, (cx1 - X1) / S), origin=[(X0 - b * S) / S, 0.0], ground='kraft')
    # the shared register (ground) line
    L = ext.Layer(W, H, 8690, 'kraft')
    cut = np.zeros_like(ink)
    cut[reg_px:] = ink[reg_px:]
    L.spray(cut, 'black', 8691, passes=2, angle=-2, sheet_pad=6, k=5.0, droplets=0.0, spits=0, sheen=0.02,
            under=(0, 1), keep_bleed=0.4)
    border_fade(L, 6)
    out.save('frieze-ground', ext.export(L.col, L.A, 'kraft'), 'sprite',
             f'Frieze ground line (one register under all three figures): layout rect = the whole frieze '
             f'{FZ_W}×{FZ_H:.1f}pt, origin (0, 0).', bleed=(b, b, b, b), origin=[0.0, 0.0], ground='kraft')


NO_SMALL = {'sit-down', 'stand-up'}      # r2: only ever shown as the 132pt question pose


def bake_all():
    for i, name in enumerate(POSES):
        for size, suffix in SIZES:
            if suffix and name in NO_SMALL:
                continue
            pose(i, name, size, suffix)
    frieze()
