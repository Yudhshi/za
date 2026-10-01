"""Cells: day-board cells (10.5 x 20pt) + the now-notch (merge2/today/todaybake.py paint_cell / paint_now) and the
rating cells — paint fullness = rating — at 24 / 18 / 14pt (merge2/english/eng_bake.py cell)."""
import numpy as np

from . import ext, out
from .g_concrete import ground_hex
from .g_paint import border_fade

S = 2
BLACK_PLATE = '#191918'
BLACK_SLAB = '#1B1C1D'
WHITE_CARD = '#F4F3EE'


def new(wpt, hpt, bleed, seed, kind='concrete', q=0.5):
    bt, bl, bb, br = bleed
    W, H = int(round((bl + wpt + br) * S)), int(round((bt + hpt + bb) * S))
    r = (bl * S, bt * S, (bl + wpt) * S, (bt + hpt) * S)
    L = ext.Layer(W, H, seed, kind, quiet=(0, 0, W, H, q))
    return L, r


# ---------------------------------------------------------------- board cells
def board_cell(aid, kind, seed, purpose, ink='teal', ground=None):
    bleed = (1, 1, 1, 1)
    L, r = new(10.5, 20, bleed, seed + 1)
    x0, y0, x1, y1 = r
    rng = np.random.default_rng(seed)
    W, H = L.W, L.H

    def rect(a0=x0, b0=y0, a1=x1, b1=y1):
        return ext.knife_rect(W, H, a0, b0, a1, b1, rng, 0.5)

    def frame(sw):
        return ext.knife_frame(W, H, x0, y0, x1, y1, sw, rng, overcut=False)

    if kind == 'e':
        L.masked(rect(), 'white', seed + 2, coverage=0.04, ridge=0, relief=0.2, jitter=0.004)
        L.masked(frame(3.0), 'estroke', seed + 3, coverage=0.88, ridge=0.03, jitter=0.03)
    elif kind == 'p':
        L.masked(rect(), 'past', seed + 2, coverage=0.84, ridge=0.03, jitter=0.03)
    elif kind == 'g':
        L.masked(rect(), 'grey', seed + 2, coverage=0.96, ridge=0.06, thin=0.06)
    elif kind == 'gp':
        L.masked(rect(), 'greyp', seed + 2, coverage=0.93, ridge=0.05, thin=0.08)
    elif kind == 't':
        dark = ink == 'black'
        L.masked(rect(), ink, seed + 2, coverage=0.992 if dark else 0.97, ridge=0.06, thin=0 if dark else 0.05,
                 jitter=0.006 if dark else 0.03)
    elif kind == 'o':
        L.masked(frame(3.0), 'pale', seed + 2, coverage=0.80, ridge=0.04)
    elif kind == 'd':
        L.masked(frame(2.0), ink, seed + 3, coverage=0.95, ridge=0.03, jitter=0.015)
        L.masked(ext.fine_spray_mask(W, H, x0, y0 + 2, x1 - 2, y1 - 2, rng), ink, seed + 4, coverage=0.97, ridge=0,
                 edge=False, jitter=0.01, relief=0.2)
    border_fade(L, 1)
    g = ground or ground_hex()
    out.save(aid, ext.export(L.col, L.A, g), 'sprite', purpose, bleed=bleed,
             ground={WHITE_CARD: 'white card', BLACK_SLAB: 'black slab'}.get(g, 'teal paint' if g == 'teal' else 'concrete'))


def now_notch():
    """Orange 2pt notch (+4pt overhang top / bottom) + 9 x 6pt triangle, sprayed over a 1pt black paint edge."""
    bleed = (12, 7, 6, 7)
    L, r = new(2, 20, bleed, 6501)
    x = (r[0] + r[2]) / 2
    y0, y1 = r[1], r[3]
    top, bot = y0 - 8, y1 + 8
    tri_h, tri_w = 12, 18

    def shape(grow):
        bar = [(x - 2 - grow, top), (x + 2 + grow, top), (x + 2 + grow, bot + grow), (x - 2 - grow, bot + grow)]
        tri = [(x - tri_w / 2 - grow * 1.3, top - tri_h - grow), (x + tri_w / 2 + grow * 1.3, top - tri_h - grow),
               (x, top + 3 + grow * 1.6)]
        return ext.poly_mask(L.W, L.H, [bar, tri])
    L.masked(shape(2.0), 'black', 6502, coverage=0.97, ridge=0)
    L.masked(shape(0), 'orange', 6503, coverage=0.98, ridge=0.05, thin=0.04)
    out.save('now-notch-night', ext.export(L.col, L.A, ground_hex()), 'sprite',
             'Board "now" marker: orange 2pt notch with 4pt overhang and a 9×6pt triangle above, 1pt black paint edge '
             '(never orange-on-teal without the black line). Layout rect = 2×20pt on the cell row at the now x.',
             bleed=bleed, ground='concrete')


# ---------------------------------------------------------------- rating cells
GROUND = {'black': dict(empty='#6A6F74', ecov=0.70, efill=0.0, hex=BLACK_PLATE),
          'band': dict(empty='#6A6F74', ecov=0.70, efill=0.0, hex=BLACK_PLATE),
          'light': dict(empty='#7B7A77', ecov=0.80, efill=0.03, hex=WHITE_CARD)}


def rate_cell(size, state, ground, seed):
    g = GROUND[ground]
    bleed = (2, 2, 2, 2) if state != 'current' else (3, 3, 3, 3)
    L, r = new(size, size, bleed, seed + 1, q=0.6)
    x0, y0, x1, y1 = r
    s = x1 - x0
    rng = np.random.default_rng(seed)
    W, H = L.W, L.H
    light = ground == 'light'
    sw = max(2.6, s * 0.075)

    def rect(a0, b0, a1, b1, j=0.55):
        return ext.rect_mask(W, H, a0, b0, a1, b1, rng, j)

    if state == 'empty':
        if g['efill']:
            L.mpaint(rect(x0, y0, x1, y1), 'white', rng, cov=g['efill'], ridge=0, rough=0.02, noise=0.0, relief=0.0)
        L.mpaint(ext.rough_frame(W, H, x0, y0, x1, y1, 3.0, rng), g['empty'], rng, cov=g['ecov'], ridge=0, relief=0.3,
                 noise=0.02)
    elif state == 'current':
        L.mpaint(ext.dash_mask(W, H, x0, y0, x1, y1, sw * 1.05, s * 0.2, s * 0.13, rng), 'orange', rng, cov=0.96,
                 ridge=0.04, rough=0.05)
    else:
        if light and state != 'fuzzy':
            L.mpaint(rect(x0 - 2, y0 - 2, x1 + 2, y1 + 2), 'black', rng, cov=0.995, ridge=0, noise=0.004, relief=0.3)
        if state in ('good', 'easy'):
            L.mpaint(rect(x0, y0, x1, y1), 'teal', rng, cov=0.965, thin=0.10, ridge=0.04)
        elif state == 'forgot':
            L.mpaint(rect(x0, y0, x1, y1), 'grey', rng, cov=0.95, thin=0.10, ridge=0.04)
        elif state == 'fuzzy':
            if light:
                L.mpaint(ext.rough_frame(W, H, x0, y0, x1, y1, max(2, sw * 0.7), rng), 'tealdot', rng, cov=0.55, ridge=0)
                L.mpaint(ext.dots_mask(W, H, x0, y0, x1, y1, rng, 0.34, 0.9, 2.2, 0.10), 'tealdot', rng, cov=1.0,
                         ridge=0, edge=False, noise=0, relief=0.4)
            else:
                L.mpaint(ext.dots_mask(W, H, x0, y0, x1, y1, rng, 0.32, 0.9, 2.4, 0.13), 'teal', rng, cov=1.0,
                         ridge=0, edge=False, noise=0, relief=0.4)
        if state in ('easy', 'forgot'):
            sz = int(round(s * (0.7 if state == 'easy' else 0.6)))
            m = ext.icon_mask('star' if state == 'easy' else 'cross', sz)
            ox = int(round(x0 + (s - sz) / 2))
            oy = int(round(y0 + (s - sz) / 2 + (0.3 if state == 'easy' else 0)))
            mm = np.zeros((H, W), np.float32)
            mm[oy:oy + sz, ox:ox + sz] = m
            from scipy import ndimage as ndi
            mm = ndi.gaussian_filter(mm, 0.35)
            L.mpaint(mm, 'black', rng, cov=0.97, thin=0.04, ridge=0, rough=0.03, noise=0.01)
    border_fade(L, 1)
    return ext.export(L.col, L.A, g['hex']), bleed


RATE_TEXT = dict(easy='太简单 (4): teal solid + black stencil star', good='记住了 (3): teal solid',
                 fuzzy='模糊 (2): sparse teal paint dots', forgot='忘了 (1): meeting-grey + black stencil ✕',
                 empty='not answered yet', current='current question: orange dashed tape frame')
RATE_WHERE = {24: ('black', 'session board (4×5) on the black plate'), 18: ('band', 'review history on the black band'),
              14: ('light', 'legend swatch on the white card (1pt black paint edge)')}


def bake_all():
    board = [('cell-empty-night', 'e', 'Board cell, free 15 min: faint white fill + 1.5pt grey masked frame.', 'teal', None),
             ('cell-past-night', 'p', 'Board cell, elapsed free time: dark masked fill, no frame.', 'teal', None),
             ('cell-meeting-night', 'g', 'Board cell, meeting: meeting-grey masked.', 'teal', None),
             ('cell-meeting-past-night', 'gp', 'Board cell, finished meeting: darker grey masked.', 'teal', None),
             ('cell-teal-night', 't', 'Board / duration cell, selected meeting (or elapsed part): teal masked solid.', 'teal', None),
             ('cell-teal-dots-night', 'd', 'Remaining part of an in-progress / next meeting: 1pt teal frame + light '
              'fine spray inside (~40%).', 'teal', None),
             ('cell-black-night', 't', 'Duration strip on the teal event hero: black masked solid.', 'black', 'teal'),
             ('cell-black-dots-night', 'd', 'Duration strip on the teal event hero, remaining part: black frame + '
              'fine black spray.', 'black', 'teal'),
             ('cell-outline-night', 'o', 'Duration strip on the calm hero for tomorrow\'s meeting: pale 1.5pt frame.',
              'teal', BLACK_SLAB)]
    for i, (aid, kind, purpose, ink, ground) in enumerate(board):
        board_cell(aid, kind, 6300 + 17 * i, purpose + ' 10.5×20pt.', ink=ink, ground=ground)
    now_notch()
    for size, (ground, where) in RATE_WHERE.items():
        for j, state in enumerate(('easy', 'good', 'fuzzy', 'forgot', 'empty', 'current')):
            img, bleed = rate_cell(size, state, ground, 6600 + size * 31 + j * 7)
            out.save(f'rate-{size}-{state}', img, 'sprite', f'Rating cell {size}pt, {RATE_TEXT[state]} — {where}.',
                     bleed=bleed, ground={'light': 'white card'}.get(ground, 'black plate'))
