"""Concrete (V4 §2.1): the quiet 512pt base tile, the texture bands that sit on it only where the wall shows its
pour (left / right edge 18pt, the board band), the formwork seam (one whole 520pt groove, no period), the masking-tape
residue of the empty stamp slot, and the panel frame 9-slice (rim / tie holes / chips / shadow)."""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from . import bake, ext, out
from .bake import gnoise, hexrgb, lin, shade_from_height, smoothstep, srgb

S = 2
TILE = 1024           # px = 512pt: big enough that nothing repeats visibly on a 520 x 900pt panel
QUIET = 0.5           # concrete-quiet-night keeps half the base tile's (already quiet) detail
GROUND_HEX = '#292C2F'  # v12 nominal concrete ground; the base tile is normalised to it so every sprite solved
#                         against ground_hex() keeps its look
_GROUND = {}
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


def quiet_tile(N, seed, base_hex=GROUND_HEX, pore_div=3000, rmax=2.3):
    """Quiet poured concrete, periodic: no pour blotches (nothing above σ 90px), mid mottling ±2–3 %, fine grain,
    sparse small bug holes lit from the top-left -> (col_lin, height, pore).  Detail p1 / p99 within ±3 %."""
    rng = np.random.default_rng(seed)
    shape = (N, N)
    g = ext.gnoise_wrap
    tone = (0.010 * g(shape, 90, rng) + 0.012 * g(shape, 40, rng) + 0.006 * g(shape, 24, rng)
            + 0.004 * g(shape, 7, rng) + 0.005 * g(shape, 1.1, rng))
    warm = 0.006 * g(shape, 40, rng)
    fg = g(shape, (0.9, 80), rng) * 0.004 + g(shape, (3, 160), rng) * 0.003      # faint formwork grain
    height = (fg * 0.5).astype(np.float32) + 0.03 * g(shape, 1.6, rng)
    n = int(N * N / pore_div)
    ys, xs = rng.integers(0, N, n), rng.integers(0, N, n)
    rs = np.clip(rng.lognormal(-0.05, 0.35, n), 0.5, rmax)
    pore = np.zeros(shape, np.float32)
    for y, x, r in zip(ys, xs, rs):
        R = int(math.ceil(r)) + 1
        yy, xx = np.mgrid[y - R:y + R + 1, x - R:x + R + 1]
        d2 = ((yy - y) ** 2 + (xx - x) ** 2 * rng.uniform(0.7, 1.3)) / (r * r)
        cup = np.clip(1 - d2, 0, 1)
        iy, ix = yy % N, xx % N
        height[iy, ix] -= cup * r * 0.9
        pore[iy, ix] = np.maximum(pore[iy, ix], (cup > 0.05) * min(1, r / 3))
    shade = ext.shade_wrap(height, 1.1)
    ao = ext.blur_wrap(np.minimum(height, 0), 1.6)
    col = np.empty((N, N, 3), np.float32)
    col[:] = lin(hexrgb(base_hex))
    col *= (1 + tone + fg)[..., None]
    col[..., 0] *= 1 + warm
    col[..., 2] *= 1 - warm
    pz = (height < -0.05).astype(np.float32)
    col *= (1 + (0.55 + 0.6 * ext.blur_wrap(pz, 1.0)) * shade)[..., None]
    col *= np.clip(1 + 0.08 * ao, 0.6, 1)[..., None]
    sp = rng.random(shape)
    bright = ext.blur_wrap((sp > 0.99975).astype(np.float32), 0.6) * 3.5
    dark = ext.blur_wrap((sp < 0.00025).astype(np.float32), 0.6) * 3.5
    col *= (1 + 0.16 * bright - 0.16 * dark)[..., None]
    return _to_mean(col), height, pore


def _to_mean(col, hexc=GROUND_HEX):
    return col * (lin(hexrgb(hexc)) / col.reshape(-1, 3).mean(0))[None, None, :]


def tile_fields():
    if 'tile' not in _GROUND:
        _GROUND['tile'] = quiet_tile(TILE, 7401)
    return _GROUND['tile']


def textured_fields():
    """The v12 textured recipe (bake.concrete: pour blotches, formwork grain, bug holes up to 6px, aggregate), periodic
    1024px, blotches halved so a texture band never reads as a stain; same mean as the base tile."""
    if 'tex' not in _GROUND:
        col, hgt, pore = ext.concrete_tile(TILE, 7301, GROUND_HEX, max_pore=6.0)
        _GROUND['tex'] = (_to_mean(_flatten(col, ext.blur_wrap)), hgt, pore)
    return _GROUND['tex']


def _flatten(col, blur, sigma=48):
    """Remove the pour blotches and the warm / cool drift (everything above σ 48px, per channel) from a textured
    field: a texture band must add bug holes, aggregate and grain, never a stain of another tone."""
    out = np.empty_like(col)
    for c in range(3):
        low = blur(col[..., c], sigma)
        out[..., c] = col[..., c] * (low.mean() / low)
    return out


def ground_hex():
    """Mean colour of the base tile = the nominal ground every concrete-sited sprite is solved against."""
    col = tile_fields()[0]
    m = srgb(col.reshape(-1, 3).mean(0))
    return '#%02X%02X%02X' % tuple(int(v * 255 + 0.5) for v in m)


def detail_stats(col, wrap=True):
    """Luminance deviation from the local mean (sigma 26 px), in % — p1 / p99."""
    Y = (col * LUMA).sum(-1)
    m = ext.blur_wrap(Y, 26) if wrap else ndi.gaussian_filter(Y, 26)
    d = (Y - m) / m * 100
    return float(np.percentile(d, 1)), float(np.percentile(d, 99))


def bake_tiles():
    col, hgt, pore = tile_fields()
    q = ext.quiet_wrap(col, QUIET)
    t_lo, t_hi = detail_stats(col)
    q_lo, q_hi = detail_stats(q)
    out.save('concrete-night', ext.rgb8(col), 'tile',
             f'Base wall: quiet poured-concrete tile 512pt (no pour blotches, mid mottling, fine grain, sparse small '
             f'bug holes lit top-left) — tile it under the WHOLE panel; it never visibly repeats on 520×900. '
             f'Detail {t_lo:+.1f}/{t_hi:+.1f}% luma (text may sit anywhere on it). Texture only comes from '
             f'concrete-edge-night and concrete-band-night laid on top.')
    out.save('concrete-quiet-night', ext.rgb8(q), 'tile',
             f'Optional: the base tile with half its detail ({q_lo:+.1f}/{q_hi:+.1f}% luma), pixel-aligned with '
             f'concrete-night. Since v12.1 concrete-night is itself quiet, so this is redundant — kept only so older '
             f'code keeps drawing; new code needs just concrete-night.')
    return dict(base=(t_lo, t_hi), quiet=(q_lo, q_hi))


def _rgba(col, a):
    a8 = (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    rgb = ext.rgb8(col)
    rgb[a8 == 0] = 0
    return np.dstack([rgb, a8])


def bake_edge():
    """V4 §2.1 edge texture, as its own vertical-tile 9-slice (not folded into panel-frame-night, whose edges
    stretch: a stretched pour texture smears).  Left / right 18pt of full texture, then a ragged 24pt feather."""
    col, _, _ = textured_fields()
    band, feather = 18, 24
    w = band + feather
    Wp = (2 * w + 1) * S
    H = TILE
    rng = np.random.default_rng(7331)
    out_col = np.zeros((H, Wp, 3), np.float32)
    A = np.zeros((H, Wp), np.float32)
    x = np.arange(w * S, dtype=np.float32) + 0.5
    for side in (0, 1):
        ragged = 7 * ext.gnoise_wrap((H, 1), (22, 0.1), rng) + 3 * ext.gnoise_wrap((H, 1), (5, 0.1), rng)
        d = x[None, :] - (band * S + ragged)                  # distance past the full-texture band, px
        a = 1 - smoothstep(0, feather * S * 0.85, d)
        if side == 0:
            out_col[:, :w * S] = col[:, :w * S]
            A[:, :w * S] = a
        else:
            out_col[:, -w * S:] = col[:, -w * S:]
            A[:, -w * S:] = a[:, ::-1]
    out.save('concrete-edge-night', _rgba(out_col, A), 'slice',
             f'Panel edge texture (V4 §2.1; the edge is its own asset, NOT folded into panel-frame-night): pour '
             f'blotches, bug holes, aggregate in the outer {band}pt of the left and right edge, feathered inward over '
             f'~{feather}pt with a ragged line; transparent between. Draw over concrete-night, under the frame, as '
             f'BakedSlice(tile: true) over the full 520×H panel: insets keep the two edges, the middle column is '
             f'empty; vertically periodic (512pt), so it tiles with no seam.',
             insets=(0, w, 0, w), ground='concrete')


def bake_band():
    """V4 §2.1 board band: the pour texture behind the day board (34pt above the cells + the cell row)."""
    Wp, Hp = 520, 60
    W, H = Wp * S, Hp * S
    rng = np.random.default_rng(7341)
    col, hgt, pore = bake.concrete(W, H, 7342, base_hex=GROUND_HEX, seams=(), ties=(), chips=())
    col = _to_mean(_flatten(col, ndi.gaussian_filter))
    y = np.arange(H, dtype=np.float32)[:, None] + 0.5
    xx = np.arange(W, dtype=np.float32)[None, :] + 0.5
    rag_t = 5 * gnoise((1, W), (0.1, 26), rng) + 2 * gnoise((1, W), (0.1, 6), rng)
    rag_b = 4 * gnoise((1, W), (0.1, 26), rng) + 2 * gnoise((1, W), (0.1, 6), rng)
    a = smoothstep(2 * S, 14 * S, y + rag_t) * (1 - smoothstep(H - 8 * S, H - 1 * S, y + rag_b))
    a *= smoothstep(0, 34 * S, xx) * smoothstep(0, 34 * S, W - xx)
    out.save('concrete-band-night', _rgba(col, a), 'sprite',
             'Board band (V4 §2.1): pour texture (blotches, bug holes, aggregate) behind the day board — layout rect '
             '520×60pt at panel x 0, its bottom ~6pt below the cell row (texture covers the 34pt above the cells + the '
             'row); top / bottom / both ends feathered to transparent on a ragged line. Over concrete-night, under '
             'the cells; board labels stay on the quiet base below it.', ground='concrete')


def bake_seam():
    """Formwork board seam (V4 §2.1): ONE whole 520pt groove with a ragged lip, depth that wanders, the two boards a
    hair apart in tone; dies out at both panel edges.  Overlay over the base tile."""
    rng = np.random.default_rng(7311)
    Wp, Hp = 520, 12
    W, H = Wp * S, Hp * S
    hgt = np.zeros((H, W), np.float32)
    wob = gnoise((1, W), (0.1, 30), rng)[0] * 0.8 + gnoise((1, W), (0.1, 140), rng)[0] * 0.9
    depth = np.clip(1 + 0.35 * gnoise((1, W), (0.1, 60), rng)[0], 0.45, 1.5)
    xs = np.arange(W, dtype=np.float32)
    ends = smoothstep(0, 46 * S, xs) * smoothstep(0, 46 * S, W - 1 - xs)
    y0 = H // 2
    for dy, d in ((-1, 0.6), (0, 1.3), (1, 0.6)):
        rows = np.clip((y0 + dy + np.round(wob)).astype(int), 0, H - 1)
        hgt[rows, np.arange(W)] -= d * depth
    # a few broken bits of the lip (the board edge chipped when the formwork came off)
    for _ in range(5):
        cx = rng.uniform(60, W - 60)
        L = rng.uniform(6, 16)
        k = np.clip(1 - np.abs(xs - cx) / L, 0, 1)
        r = int(np.clip(y0 - 2 + np.round(wob[int(cx)]), 0, H - 1))
        hgt[r] -= 0.9 * k
    tone = np.ones((H, W), np.float32)
    tone[:y0] *= 1.010
    tone[y0 + 1:] *= 0.993
    B = lin(hexrgb(ground_hex()))
    hs = ndi.gaussian_filter(hgt, 0.7)
    gy, gx = np.gradient(hs)
    L3 = bake.LIGHT
    nx, ny, nz = -gx * 1.1, -gy * 1.1, np.ones_like(hs)
    sh = (nx * L3[0] + ny * L3[1] + nz * L3[2]) / np.sqrt(nx * nx + ny * ny + nz * nz) - L3[2]
    ao = ndi.gaussian_filter(np.minimum(hgt, 0), 1.6)
    T = B * (tone * (1 + 1.25 * sh) * np.clip(1 + 0.10 * ao, 0.55, 1))[..., None]
    fade = smoothstep(0, 5, np.minimum(np.arange(H), H - 1 - np.arange(H)).astype(np.float32))[:, None]
    T = B + (T - B) * (fade * ends[None, :])[..., None]
    out.save('concrete-seam-night', ext.overlay(T, ground_hex()), 'slice',
             'Formwork seam (V4 §2.1): one whole 520pt groove, NOT periodic — draw it once at panel x 0, width 520 '
             '(no stretch), only in a measured gap (under the header; between schedule and tasks), never through a '
             'card, numeral or text line. Dies out over ~46pt at both panel edges; layout rect = the 12pt band.',
             bleed=(0, 0, 0, 0), insets=(0, 60, 0, 60), ground='concrete')


def bake_slot():
    """Empty stamp slot (V4 §2.3): where a sheet was taped to the wall and torn off — the cleaner rectangle it covered,
    four strips of crepe-tape adhesive residue across its edges (dust line along each tape edge, crepe texture,
    torn ends, a few scraps of tape paper left behind).  Faint; an overlay on the concrete."""
    rng = np.random.default_rng(7351)
    w, h = 148, 86
    b = 10
    W, H = (w + 2 * b) * S, (h + 2 * b) * S
    x0, y0, x1, y1 = b * S, b * S, (b + w) * S, (b + h) * S
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
    B = lin(hexrgb(ground_hex()))
    # 1. the sheet kept the wall a little cleaner (crisp edge, slightly uneven)
    sheet = ext.rect_mask(W, H, x0, y0, x1, y1, rng, 0.6)
    clean = sheet * (0.052 + 0.010 * gnoise((H, W), 30, rng))
    # 2. tape strips: (cx, cy, length, angle) — across the four edges, tape ~ 11pt wide
    tw = 11 * S
    strips = [((x0 + x1) / 2 + rng.uniform(-8, 8), y0, w * S * rng.uniform(0.55, 0.7), rng.uniform(-2.5, 2.5)),
              ((x0 + x1) / 2 + rng.uniform(-14, 14), y1, w * S * rng.uniform(0.35, 0.5), rng.uniform(-3, 3)),
              (x0, (y0 + y1) / 2 + rng.uniform(-6, 6), h * S * rng.uniform(0.45, 0.6), 90 + rng.uniform(-3, 3)),
              (x1, (y0 + y1) / 2 + rng.uniform(-6, 6), h * S * rng.uniform(0.4, 0.55), 90 + rng.uniform(-3, 3))]
    resid = np.zeros((H, W), np.float32)
    dust = np.zeros((H, W), np.float32)
    scraps = np.zeros((H, W), np.float32)
    for k, (cx, cy, L, ang) in enumerate(strips):
        ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        u = (X - cx) * ca + (Y - cy) * sa            # along the strip
        v = -(X - cx) * sa + (Y - cy) * ca           # across
        tear = 3.0 * gnoise((H, W), (6, 6), rng) + 1.2 * gnoise((H, W), 1.2, rng)
        along = np.clip(L / 2 - np.abs(u) + tear, 0, None)
        across = tw / 2 - np.abs(v + 0.6 * gnoise((H, W), (40, 40), rng))
        m = np.clip(along, 0, 1) * np.clip(across + 0.5, 0, 1)
        crepe = ndi.rotate(gnoise((H + 40, W + 40), (5, 0.6), rng), -ang, reshape=False, order=1)[20:20 + H, 20:20 + W]
        patchy = np.clip(0.55 + 0.45 * gnoise((H, W), 9, rng), 0, 1)
        resid = np.maximum(resid, m * patchy * (0.75 + 0.25 * crepe))
        edge = np.clip(1 - np.abs(np.abs(v) - tw / 2) / 1.2, 0, 1) * np.clip(along / 3, 0, 1)
        dust = np.maximum(dust, edge * np.clip(0.5 + 0.5 * gnoise((H, W), 12, rng), 0, 1))
        # scraps of tape paper that stayed stuck (small, torn, near the ends)
        for _ in range(int(rng.integers(0, 2))):
            t = rng.choice([-1, 1]) * rng.uniform(0.3, 0.47) * L
            sx, sy = cx + t * ca + rng.normal(0, 3), cy + t * sa + rng.normal(0, 3)
            r = rng.uniform(1.6, 3.2)
            blob = 1 - np.hypot((X - sx) / r, (Y - sy) / (r * rng.uniform(0.6, 1.4))) + 0.35 * gnoise((H, W), 1.0, rng)
            scraps = np.maximum(scraps, smoothstep(0.0, 0.25, blob) * m)
    tape = lin(hexrgb(ext.C('tape')))
    T = B * (1 + clean)[..., None]
    T = T * (1 - 0.21 * resid[..., None]) + (B * 1.55 + tape * 0.04) * (0.21 * resid[..., None])
    T = T * (1 - 0.14 * dust)[..., None]
    T = T * (1 - 0.30 * scraps[..., None]) + tape * 0.45 * (0.30 * scraps[..., None])
    fade = smoothstep(0, 6, np.minimum(np.minimum(X, W - X), np.minimum(Y, H - Y)))
    T = B + (T - B) * fade[..., None]
    out.save('stamp-slot-night', ext.overlay(T, ground_hex()), 'sprite',
             'Empty stamp slot (V4 §2.3): the faint mark of a sheet once taped to the wall — slightly cleaner '
             'rectangle, crepe-tape adhesive residue across its four edges (dust line along each tape edge, torn ends, '
             'two or three scraps of tape paper). A world detail, not a frame: layout rect 148×86pt (the slot), '
             'overlay on the concrete; the NICE! / MISS stamp lands on it.', bleed=(b, b, b, b), ground='concrete')


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
    """520 x 760pt nominal slab (radius 20pt): two mortar-plugged tie holes at the top, two small broken arrises
    (top edge inside the top-right cap, left edge inside the bottom-left cap), the lit arris, and the contact +
    faint ambient shadow outside.  Three images with identical geometry / insets:
      panel-shadow-night  black shadow (draw first, under the slab)
      panel-mask          slab outline incl. the chip bites (mask the concrete tiles with it)
      panel-rim-night     lit arris, chip faces, tie holes (overlay drawn over the tiles)"""
    rng = np.random.default_rng(7321)
    Wp, Hp = 520, 760          # v12.1: nominal = the real panel height (Today / English ~640–900pt): ≤ ±20 % stretch
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
    bake_edge()
    bake_band()
    bake_seam()
    bake_slot()
    bake_panel()
    return st
