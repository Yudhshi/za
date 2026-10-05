"""Gravity drips (bake.drips geometry): six varied drips per paint, each its own length / width / wobble.
Only the event intensity uses them (≤ 3 per card, from the heaviest film at the lower edge)."""
import numpy as np

from . import ext, out
from .bake import hexrgb, lin
from .g_concrete import ground_hex

S = 2
#            length px, width px, end blob
VARIANTS = [(10, 7.0, False), (16, 9.0, True), (30, 8.0, True), (46, 10.0, True), (66, 9.0, True), (96, 11.0, True)]


def drip(aid, color, seed, length, width, blob, purpose):
    rng = np.random.default_rng(seed)
    pad = 6
    W = int(width * 1.6 + 2 * pad + 4)
    W += W % 2
    H = int(length + width * 1.4 + pad + 4)
    H += H % 2
    x, y = W / 2, 2.0
    a, h = ext.drip_shape(W, H, x, y, length, width * rng.uniform(0.92, 1.08), rng.uniform(0, 6), blob)
    P = lin(hexrgb(ext.C(color)))
    col = (P * 0.86)[None, None, :] * a[..., None] + (h * a * 0.22)[..., None]
    ys = np.nonzero(a.max(1) > 0.1)[0]
    reach = (ys.max() + 1 - y) / S                   # how far the drip hangs below its anchor (pt)
    out.save(aid, ext.export(col, a, ground_hex()), 'sprite', purpose.replace('{reach}', f'{reach:.1f}'),
             anchor=(x / S, y / S), ground='concrete', length=reach)


def bake_all():
    for ci, color in enumerate(('teal', 'black', 'orange', 'white')):
        if color == 'black':          # r2: retired (no black drips anywhere); index kept so the seeds stay put
            continue
        for i, (Ln, w, blob) in enumerate(VARIANTS):
            extra = '' if color != 'white' else ' (white word card, English event states)'
            drip(f'drip-{color}-{i + 1}', color, 6000 + 100 * ci + i, Ln, w, blob,
                 f'{color.capitalize()} drip #{i + 1}{extra}: maxLength {{reach}}pt = how far it hangs below the '
                 f'anchor (field `length`); pick only drips with length ≤ the free gap below − 6pt. Hang from the '
                 f'heaviest film at a block\'s lower edge; anchor = top centre where it leaves the paint (overlap 1pt '
                 f'into the block).')
