"""Concrete: seamless tile + quiet tile, formwork seam strip, panel rim / mask / shadow 9-slices."""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from . import bake, ext, out
from .bake import gnoise, hexrgb, lin, shade_from_height, smoothstep, srgb

S = 2
TILE = 512
QUIET = 0.21          # detail kept under text: p1 / p99 of the luma deviation within ±3 %
_GROUND = {}


def tile_fields():
    if 'tile' not in _GROUND:
        col, hgt, pore = ext.concrete_tile(TILE, 7301, '#2A2D30', max_pore=6.0)
        _GROUND['tile'] = (col, hgt, pore)
    return _GROUND['tile']


def ground_hex():
    """Mean colour of the tile = the nominal ground every concrete-sited sprite is solved against."""
    col = tile_fields()[0]
    m = srgb(col.reshape(-1, 3).mean(0))
    return '#%02X%02X%02X' % tuple(int(v * 255 + 0.5) for v in m)


def detail_stats(col):
    """Luminance deviation from the local mean (sigma 26 px, periodic), in % — p1 / p99."""
    Y = (col * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1)
    m = ext.blur_wrap(Y, 26)
    d = (Y - m) / m * 100
    return float(np.percentile(d, 1)), float(np.percentile(d, 99))


def bake_tiles():
    col, hgt, pore = tile_fields()
    q = ext.quiet_wrap(col, QUIET)
    t_lo, t_hi = detail_stats(col)
    q_lo, q_hi = detail_stats(q)
    out.save('concrete-night', ext.rgb8(col), 'tile',
             f'Seamless sealed-concrete tile 256pt (blotches, formwork grain, pores, aggregate; lit top-left). '
             f'Texture zones only (header band, edge band, board band). Detail {t_lo:+.1f}/{t_hi:+.1f}% luma.')
    out.save('concrete-quiet-night', ext.rgb8(q), 'tile',
             f'Same tile, detail flattened (quiet) — the ground under every text zone; pixel-aligned with '
             f'concrete-night so the two cross-fade. Detail {q_lo:+.1f}/{q_hi:+.1f}% luma.')
    return dict(texture=(t_lo, t_hi), quiet=(q_lo, q_hi))


def bake_seam():
    """Formwork board seam: a shallow groove with a ragged lip, as an overlay strip (periodic along x)."""
    rng = np.random.default_rng(7311)
    W, H = TILE, 24
    hgt = np.zeros((H, W), np.float32)
    wob = ext.gnoise_wrap((1, W), (0.1, 30), rng)[0] * 0.8
    y0 = H // 2
    for dy, d in ((-1, 0.6), (0, 1.3), (1, 0.6)):
        rows = np.clip((y0 + dy + np.round(wob)).astype(int), 0, H - 1)
        hgt[rows, np.arange(W)] -= d
    # the two boards either side differ a hair in tone
    tone = np.ones((H, W), np.float32)
    tone[:y0] *= 1.012
    tone[y0 + 1:] *= 0.992
    B = lin(hexrgb(ground_hex()))
    sh = _shade_xwrap(hgt, 1.1)
    ao = ndi.gaussian_filter(np.minimum(hgt, 0), 1.6, mode=('nearest', 'wrap'))
    T = B * (tone * (1 + 1.25 * sh) * np.clip(1 + 0.10 * ao, 0.55, 1))[..., None]
    fade = smoothstep(0, 5, np.minimum(np.arange(H), H - 1 - np.arange(H)).astype(np.float32))[:, None]
    T = B + (T - B) * fade[..., None]
    out.save('concrete-seam-night', ext.overlay(T, ground_hex()), 'slice',
             'Formwork seam groove (overlay, periodic along x): place only in measured gaps between rows, never '
             'through a card, numeral or text line. Stretch or tile horizontally; layout rect = the 12pt band.',
             bleed=(0, 0, 0, 0), insets=(0, 1, 0, 1))


def _shade_xwrap(h, strength=1.0, blur=0.7):
    hs = ndi.gaussian_filter(h, blur, mode=('nearest', 'wrap'))
    gy = np.gradient(hs, axis=0)
    gx = (np.roll(hs, -1, 1) - np.roll(hs, 1, 1)) / 2
    L = bake.LIGHT
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(hs)
    inv = 1 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return (nx * L[0] + ny * L[1] + nz * L[2]) * inv - L[2]


# ---------------------------------------------------------------- panel rim (todaybake.bake_panel, as overlays)
def chip_polys(W, H, rng, chips):
    spall, cut = [], []
    for edge, c, L, D in chips:
        ts = [0, rng.uniform(.10, .22), rng.uniform(.38, .55), rng.uniform(.66, .80), 1]
        ds = [0, rng.uniform(.55, .8), 1, rng.uniform(.55, .85), 0]
        prof = [(c - L / 2 + L * t, D * d) for t, d in zip(ts, ds)]
        for frac, dst in ((1.0, spall), (0.36, cut)):
            pts = [(a, d * frac) for a, d in prof]
            if edge == 'r':
                q = [(W - d, a) for a, d in pts] + [(W + 4, c + L / 2), (W + 4, c - L / 2)]
            elif edge == 'l':
                q = [(d, a) for a, d in pts] + [(-4, c + L / 2), (-4, c - L / 2)]
            elif edge == 't':
                q = [(a, d) for a, d in pts] + [(c + L / 2, -4), (c - L / 2, -4)]
            else:
                q = [(a, H - d) for a, d in pts] + [(c + L / 2, H + 4), (c - L / 2, H + 4)]
            dst.append(q)
    return spall, cut


def slab_alpha(W, H, radius, polys):
    ss = 4
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W * ss - 1, H * ss - 1], radius=radius * ss, fill=255)
    for pts in polys:
        d.polygon([(x * ss, y * ss) for x, y in pts], fill=0)
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def bake_panel():
    """520 x 400pt nominal slab (radius 20pt): two mortar-plugged tie holes at the top, two small broken arrises
    (top edge inside the top-right cap, left edge inside the bottom-left cap), the lit arris, and the contact +
    faint ambient shadow outside.  Three images with identical geometry / insets:
      panel-shadow-night  black shadow (draw first, under the slab)
      panel-mask          slab outline incl. the chip bites (mask the concrete tiles with it)
      panel-rim-night     lit arris, chip faces, tie holes (overlay drawn over the tiles)"""
    rng = np.random.default_rng(7321)
    Wp, Hp = 520, 400
    W, H = Wp * S, Hp * S
    bleed = (6, 12, 22, 12)
    bt, bl, bb, br = (int(v * S) for v in bleed)
    chips = [('t', W - 120 * S, rng.uniform(24, 28), rng.uniform(12, 14)),
             ('l', H - 92 * S, rng.uniform(28, 32), rng.uniform(15, 18))]
    spall, cutp = chip_polys(W, H, rng, chips)
    alpha = slab_alpha(W, H, 20 * S, cutp)
    # chip fracture faces
    P = ext.poly_mask(W, H, spall)
    dist = ndi.distance_transform_edt(P > 0.5)
    facet = ndi.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 2.2)
    facet /= facet.std() + 1e-9
    rough = ndi.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 0.7)
    rough /= rough.std() + 1e-9
    ch_h = ((-0.8 * dist + 0.55 * facet + 0.25 * rough) * P).astype(np.float32)
    face = P
    adist = ndi.distance_transform_edt(alpha > 0.5)
    ar = -4.0 * (1 - smoothstep(0, 7.0, adist))
    B = lin(hexrgb(ground_hex()))
    col = np.empty((H, W, 3), np.float32)
    col[:] = B
    col *= (1 + 1.1 * shade_from_height(ar, 1.0, 1.2))[..., None]
    agg = ndi.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 0.8)
    agg /= agg.std() + 1e-9
    col *= (1 + face * (1.25 + 0.25 * agg))[..., None]
    col *= np.clip(1 + 1.8 * face * shade_from_height(ch_h, 1.0, 0.6), 0.22, None)[..., None]
    Pb = ndi.gaussian_filter(face, 1.2)
    gy, gx = np.gradient(Pb)
    lx, ly = bake.LIGHT[0], bake.LIGHT[1]
    n = math.hypot(lx, ly)
    facing = np.clip((gx * lx / n + gy * ly / n) / (np.hypot(gx, gy) + 1e-6), 0, 1)
    lip = np.clip(ndi.grey_dilation(face, size=4) - face, 0, 1) * facing
    col *= (1 + 1.1 * lip)[..., None]
    # tie holes (concrete(): recessed cone, mortar plug of a slightly different grey + a little grain)
    hgt = np.zeros((H, W), np.float32)
    plug = np.zeros((H, W), np.float32)
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    for cx, cy in ((26, 26), (W - 26, 26)):
        d = np.sqrt((Y - cy) ** 2 + (X - cx) ** 2)
        hgt -= np.clip(1 - d / 17, 0, 1) * 6
        plug = np.maximum(plug, smoothstep(15, 12, d))
    grain = 0.05 * gnoise((H, W), 0.9, rng) + 0.04 * gnoise((H, W), 3, rng)
    hgt += plug * grain * 2
    sh = shade_from_height(hgt, 1.1)
    col *= (1 + 1.25 * sh)[..., None]
    mortar = lin(hexrgb('#3A3B3A')) * (1 + grain)[..., None]
    col = col * (1 - plug[..., None] * 0.85) + mortar * (plug[..., None] * 0.85) * (1 + 1.2 * sh)[..., None]
    rim = ext.overlay(col, ground_hex())
    rim[..., 3] = (rim[..., 3].astype(np.float32) * alpha + 0.5).astype(np.uint8)
    # place into the bleed canvas
    IW, IH = W + bl + br, H + bt + bb
    A = np.zeros((IH, IW), np.float32)
    A[bt:bt + H, bl:bl + W] = alpha
    rim_img = np.zeros((IH, IW, 4), np.uint8)
    rim_img[bt:bt + H, bl:bl + W] = rim
    contact = ndi.gaussian_filter(ndi.shift(A, (2.0, 0.6), order=1), 1.6) * 0.82
    ambient = ndi.gaussian_filter(ndi.shift(A, (9, 1.5), order=1), 11) * 0.34
    s = 1 - (1 - contact) * (1 - ambient)
    page = lin(hexrgb(ext.PAL['page']))
    shadow = ext.overlay(page * (1 - s)[..., None], ext.PAL['page'])
    # the view clips the concrete tile to a plain 20pt rounded rect: where a chip bit the slab away, the frame
    # paints the void (page colour in the shadow) opaque over the tile
    rr = np.zeros((IH, IW), np.float32)
    rr[bt:bt + H, bl:bl + W] = slab_alpha(W, H, 20 * S, [])
    bite = np.clip(rr - A, 0, 1)
    void = srgb(page * (1 - s)[..., None])
    ra = rim_img[..., 3].astype(np.float32) / 255
    rc = rim_img[..., :3].astype(np.float32) / 255
    sa = shadow[..., 3].astype(np.float32) / 255
    alpha = ra + bite + (1 - rr) * sa
    pm = rc * ra[..., None] + void * bite[..., None]
    rgb = np.clip(pm / np.maximum(alpha, 1e-6)[..., None], 0, 1)
    frame = np.dstack([(rgb * 255 + 0.5).astype(np.uint8), (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)])
    frame[frame[..., 3] == 0, :3] = 0
    insets = (bleed[0] + 96, bleed[1] + 40, bleed[2] + 116, bleed[3] + 150)
    out.save('panel-frame-night', frame, 'slice',
             'Panel frame: contact + faint ambient shadow in the bleed, lit arris, two mortar-plugged tie holes, two '
             'broken arrises (inside the top-right / bottom-left caps); interior transparent — lay concrete tiles '
             'clipped to a 20pt rounded rect underneath. Edges uniform along their length (stretch-safe).',
             bleed=bleed, insets=insets)


def bake_all():
    st = bake_tiles()
    bake_seam()
    bake_panel()
    return st
