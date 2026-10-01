"""Stencil glyphs from the committed atlas (src/glyphs/atlas.png, rendered by glyphs.py with Chromium)."""
import json
import os
from collections import Counter
from contextlib import contextmanager

import numpy as np
from PIL import Image

from . import bake

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src', 'glyphs'))
_ROWS = None


def load():
    global _ROWS
    if bake.ATLAS is None:
        bake.ATLAS = np.asarray(Image.open(os.path.join(SRC, 'atlas.png')).convert('L'), np.float32) / 255
        meta = json.load(open(os.path.join(SRC, 'atlas.json')))
        bake.CELLS = meta['cells']
        _ROWS = meta['rows']
        # bridges the design bakes added on top of bake.BRIDGES (todaybake / today v3)
        bake.BRIDGES.setdefault('R', [('v', .40, -.2, .30)])
        bake.BRIDGES.setdefault(':', [])
        bake.BRIDGES.setdefault('/', [])
    return bake.ATLAS


def row_metrics(prefix):
    """(baseline, cap_top) in px from the top of this row's cells: the most common ink bottom / top over the row's
    glyphs (flat glyphs agree; round ones overshoot by a pixel or two)."""
    load()
    bots, tops = [], []
    for ch in _ROWS[prefix]['glyphs']:
        x, y, w, h, size, _ = bake.CELLS[f'{prefix}:{ch}']
        g = bake.ATLAS[2 * y:2 * (y + h), 2 * x:2 * (x + w)]
        rows = np.where(g.max(1) > 0.5)[0]
        if ch not in ':/!':
            bots.append(int(rows.max()) + 1)
            tops.append(int(rows.min()))
    return Counter(bots).most_common(1)[0][0], Counter(tops).most_common(1)[0][0]


def size_of(prefix):
    load()
    return _ROWS[prefix]['size']


@contextmanager
def bridges(over):
    saved = {k: bake.BRIDGES.get(k) for k in over}
    bake.BRIDGES.update(over)
    try:
        yield
    finally:
        for k, v in saved.items():
            if v is None:
                bake.BRIDGES.pop(k, None)
            else:
                bake.BRIDGES[k] = v


def word(prefix, text, bridge_em=0.065, track_em=0.03, seed=1, over=None):
    """bake.stencil_word against our atlas -> (mask, baseline_px, cap_top_px, ink_w_px, gap_px).
    The mask has the full cell height; columns are cropped to ink (like the design bakes)."""
    load()
    with bridges(over or {}):
        m, top, cap = bake.stencil_word(prefix, text, bridge_em=bridge_em, track_em=track_em,
                                        rng=np.random.default_rng(seed))
    base, ctop = row_metrics(prefix)
    size = size_of(prefix)
    gap = int(track_em * size * 2 + 0.05 * size * 2)
    return m, base, ctop, m.shape[1], gap
