#!/usr/bin/env python3
"""Yudh material baker — the shared bake library of the v2/v3 design (merge2/tex/bake.py, 2026-10-01).

Copied verbatim for the production pipeline; the only changes: no output folder / demo bake at import time, and the
stencil glyph atlas is injected by yudhmat.glyph (bake.ATLAS / bake.CELLS) instead of being read from a sibling file.
Everything is in @2x pixels (1pt = 2px), seeded and deterministic; colour maths in linear light.

  concrete()  sealed fair-faced concrete (pour blotches, formwork grain, pores, tie holes, chips; lit top-left)
  quiet()     flattens texture under text
  spray()     paint sprayed through a hand-cut stencil (passes, orange peel, one-sided underspray, droplets only
              outside the stencil sheet, spits, relief through the film, satin sheen)
  masked()    tape-masked paint
  drips()     gravity drips from the heaviest film
  stencil_word()  stencil glyph masks with bridges cut per the YudhStencil spec
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
LIGHT = np.array([-0.52, -0.62, 0.59])
LIGHT = LIGHT / np.linalg.norm(LIGHT)          # from the top-left, a little above the surface


# ---------------------------------------------------------------- colour helpers
def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


def lin(c):
    c = np.asarray(c, np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def save_rgb(path, col_lin):
    Image.fromarray((srgb(col_lin) * 255 + 0.5).astype(np.uint8), 'RGB').save(path, optimize=True)


def save_rgba(path, col_lin, alpha):
    rgb = (srgb(col_lin) * 255 + 0.5).astype(np.uint8)
    a = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([rgb, a]), 'RGBA').save(path, optimize=True)


def gnoise(shape, sigma, rng, mode='reflect'):
    n = rng.standard_normal(shape).astype(np.float32)
    n = ndi.gaussian_filter(n, sigma, mode=mode)
    return n / (n.std() + 1e-9)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def shade_from_height(h, strength=1.0, blur=0.7):
    hs = ndi.gaussian_filter(h, blur)
    gy, gx = np.gradient(hs)
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(hs)
    inv = 1 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) * inv - LIGHT[2]


# ---------------------------------------------------------------- concrete
def concrete(W, H, seed, base_hex='#2A2D30', seams=(300, 600, 900, 1200), ties=(), chips=(), day=False):
    """Returns (colour_lin HxWx3, height HxW, pore_mask HxW)."""
    rng = np.random.default_rng(seed)
    base = lin(hexrgb(base_hex))
    shape = (H, W)
    # pour variation: big soft blotches + a slight warm/cool drift
    tone = (0.060 * gnoise(shape, 170, rng) + 0.032 * gnoise(shape, 48, rng)
            + 0.016 * gnoise(shape, 11, rng) + 0.022 * gnoise(shape, 1.1, rng))
    warm = 0.025 * gnoise(shape, 230, rng)
    height = np.zeros(shape, np.float32)
    grain = np.zeros(shape, np.float32)
    # formwork boards: each board has its own tone and a faint wood grain imprint
    edges = [0] + [y for y in seams if 0 < y < H] + [H]
    for b0, b1 in zip(edges[:-1], edges[1:]):
        g = gnoise((b1 - b0, W), (0.9, 80), rng) * 0.016 + gnoise((b1 - b0, W), (3, 200), rng) * 0.01
        grain[b0:b1] = g + rng.normal(0, 0.016)
        height[b0:b1] += g * 0.5
        if b0 > 0:   # seam: a shallow groove with a slightly ragged lip
            wob = (gnoise((1, W), (0, 30), rng)[0] * 0.8).astype(np.float32)
            for dy, d in ((-1, 0.6), (0, 1.3), (1, 0.6)):
                rows = np.clip((b0 + dy + np.round(wob)).astype(int), 0, H - 1)
                height[rows, np.arange(W)] -= d
    # pores (bug holes): many small, a few big, depth ~ radius
    n = int(W * H / 1900)
    ys, xs = rng.integers(0, H, n), rng.integers(0, W, n)
    rs = np.clip(rng.lognormal(0.25, 0.6, n), 0.6, 9.0)
    pore = np.zeros(shape, np.float32)
    for y, x, r in zip(ys, xs, rs):
        R = int(math.ceil(r)) + 1
        y0, y1, x0, x1 = max(0, y - R), min(H, y + R + 1), max(0, x - R), min(W, x + R + 1)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        d2 = ((yy - y) ** 2 + (xx - x) ** 2 * rng.uniform(0.7, 1.3)) / (r * r)
        cup = np.clip(1 - d2, 0, 1)
        height[y0:y1, x0:x1] -= cup * r * 0.9
        pore[y0:y1, x0:x1] = np.maximum(pore[y0:y1, x0:x1], (cup > 0.05) * min(1, r / 3))
    # form-tie holes: recessed cone plugged with mortar of a slightly different grey
    plug = np.zeros(shape, np.float32)
    for (cx, cy) in ties:
        yy, xx = np.mgrid[0:H, 0:W]
        d = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
        height -= np.clip(1 - d / 17, 0, 1) * 6
        plug = np.maximum(plug, smoothstep(15, 12, d))
    # small chipped arrises (edge chips): (x, y, w, h)
    for (cx, cy, cw, chh) in chips:
        yy, xx = np.mgrid[0:H, 0:W]
        e = ((xx - cx) / cw) ** 2 + ((yy - cy) / chh) ** 2
        height -= np.clip(1 - e, 0, 1) * 5
    shade = shade_from_height(height, 1.1)
    ao = ndi.gaussian_filter(np.minimum(height, 0), 1.6)
    col = np.empty((H, W, 3), np.float32)
    col[:] = base
    col *= (1 + tone + grain)[..., None]
    col[..., 0] *= 1 + warm
    col[..., 2] *= 1 - warm
    col *= (1 + 1.25 * shade)[..., None]
    col *= np.clip(1 + 0.10 * ao, 0.55, 1)[..., None]
    mortar = lin(hexrgb('#3A3B3A' if not day else '#C9C6BD'))
    col = col * (1 - plug[..., None] * 0.85) + mortar * (plug[..., None] * 0.85) * (1 + 1.2 * shade)[..., None]
    # aggregate specks
    sp = rng.random(shape)
    bright = ndi.gaussian_filter((sp > 0.9994).astype(np.float32), 0.6) * 3.5
    dark = ndi.gaussian_filter((sp < 0.0006).astype(np.float32), 0.6) * 3.5
    col *= (1 + 0.35 * bright - 0.35 * dark)[..., None]
    return col, height, pore


def quiet(col, rects, amount=0.32, feather=10):
    """Flatten texture inside text rectangles (x0, y0, x1, y1): keep the local mean, damp the detail."""
    H, W, _ = col.shape
    m = np.zeros((H, W), np.float32)
    for x0, y0, x1, y1 in rects:
        m[max(0, y0):min(H, y1), max(0, x0):min(W, x1)] = 1
    m = ndi.gaussian_filter(m, feather)
    mean = np.stack([ndi.gaussian_filter(col[..., i], 26) for i in range(3)], -1)
    k = 1 - (1 - amount) * m[..., None]
    return mean + (col - mean) * k


# ---------------------------------------------------------------- stencil masks
def rough_polygon(W, H, pts, rng, jitter=0.9, ss=4):
    """Hand-cut stencil edge: straight-ish segments with tiny knife wobble, anti-aliased."""
    out = []
    for i in range(len(pts)):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
        L = math.hypot(x1 - x0, y1 - y0)
        n = max(2, int(L / 6))
        drift = rng.normal(0, 0.35)
        for j in range(n):
            t = j / n
            nx, ny = -(y1 - y0) / L, (x1 - x0) / L
            w = rng.normal(0, jitter * 0.35) + drift * math.sin(math.pi * t)
            out.append(((x0 + (x1 - x0) * t + nx * w) * ss, (y0 + (y1 - y0) * t + ny * w) * ss))
    img = Image.new('L', (W * ss, H * ss), 0)
    ImageDraw.Draw(img).polygon(out, fill=255)
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def rect_mask(W, H, x0, y0, x1, y1, rng, jitter=0.9):
    c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    c = [(x + rng.normal(0, 0.6), y + rng.normal(0, 0.6)) for x, y in c]
    return rough_polygon(W, H, c, rng, jitter)


ATLAS = None
CELLS = None
BRIDGES = {  # fraction of ink width / cap height; v = vertical bridge (x, y_from, y_to), h = horizontal (x_from, x_to, y)
    'T': [('h', .3, .7, .3)], 'U': [('v', .5, .5, 1.2)], 'E': [('v', .4, -.2, 1.2)], 'S': [('v', .5, -.2, 1.2)],
    'D': [('v', .39, -.2, 1.2)], 'A': [('v', .5, -.2, .46)], 'Y': [('v', .5, -.2, .5)], 'N': [('v', .5, -.2, 1.2)],
    'X': [('v', .5, -.2, 1.2)], 'C': [('v', .5, -.2, 1.2)], 'O': [('v', .5, -.2, 1.2)], 'W': [('v', .5, -.2, 1.2)],
    'M': [('v', .5, -.2, 1.2)], 'I': [('h', -.2, 1.2, .5)], '0': [('v', .5, -.2, 1.2)], '4': [('v', .44, -.2, .86)],
    '6': [('v', .5, -.2, 1.2)], '8': [('v', .5, -.2, 1.2)], '9': [('v', .5, -.2, 1.2)], '3': [('v', .5, -.2, 1.2)],
    '2': [('v', .5, -.2, 1.2)], '5': [('v', .5, -.2, 1.2)], '1': [('h', -.2, 1.2, .56)], '7': [('h', -.2, 1.2, .3)],
}


def _atlas():
    global ATLAS, CELLS
    if ATLAS is None:
        raise RuntimeError('glyph atlas not loaded (yudhmat.glyph.load())')
    return ATLAS, CELLS


def stencil_word(prefix, text, bridge_em=0.065, track_em=0.03, rng=None):
    """Returns (mask, cap_top_px, cap_h_px) — a float mask of the word with stencil bridges cut,
    bridge edges slightly irregular like a hand-cut stencil."""
    atlas, cells = _atlas()
    rng = rng or np.random.default_rng(1)
    pieces, size = [], None
    for ch in text:
        x, y, w, h, size, _ = cells[f'{prefix}:{ch}']
        g = atlas[2 * y:2 * (y + h), 2 * x:2 * (x + w)].copy()
        cols = np.where(g.max(0) > 0.12)[0]
        rows = np.where(g.max(1) > 0.12)[0]
        g = g[:, cols.min():cols.max() + 1]
        top, bot = rows.min(), rows.max()
        capH = bot - top
        gw = g.shape[1]
        bw = bridge_em * size * 2
        for b in BRIDGES.get(ch, []):
            if b[0] == 'v':
                cx = gw * b[1] + rng.normal(0, 0.4)
                ya, yb = int(top + capH * b[2]), int(top + capH * b[3])
                xa, xb = cx - bw / 2, cx + bw / 2
                ys = np.arange(max(0, ya), min(g.shape[0], yb))
                for yy in ys:  # a knife never cuts perfectly straight
                    wob = 0.35 * math.sin(yy * 0.21 + cx)
                    xs = np.arange(g.shape[1])
                    g[yy] *= np.clip(np.maximum(xa + wob - xs, xs - (xb + wob)) + 0.5, 0, 1)
            else:
                cy = top + capH * b[3] + rng.normal(0, 0.4)
                xa, xb = int(gw * b[1]), int(gw * b[2])
                ya, yb = cy - bw / 2, cy + bw / 2
                ys = np.arange(g.shape[0])[:, None]
                cut = np.clip(np.maximum(ya - ys, ys - yb) + 0.5, 0, 1)
                g[:, max(0, xa):min(gw, xb)] *= cut
        pieces.append((g, top, capH))
    gap = int(track_em * size * 2 + 0.05 * size * 2)
    Wt = sum(p[0].shape[1] for p in pieces) + gap * (len(pieces) - 1)
    Ht = pieces[0][0].shape[0]
    m = np.zeros((Ht, Wt), np.float32)
    x = 0
    for g, _, _ in pieces:
        m[:, x:x + g.shape[1]] = np.maximum(m[:, x:x + g.shape[1]], g)
        x += g.shape[1] + gap
    rows = np.where(m.max(1) > 0.12)[0]
    return m, rows.min(), rows.max() - rows.min()


def place(W, H, mask, x, cap_top_y, cap_top_in_mask):
    out = np.zeros((H, W), np.float32)
    y = int(cap_top_y - cap_top_in_mask)
    h, w = mask.shape
    ys0, xs0 = max(0, y), max(0, x)
    ys1, xs1 = min(H, y + h), min(W, x + w)
    out[ys0:ys1, xs0:xs1] = mask[ys0 - y:ys1 - y, xs0 - x:xs1 - x]
    return out


# ---------------------------------------------------------------- spray paint
def spray(col, height, pore, cut, color_hex, seed, passes=4, angle=-7, sheet_pad=34, k=2.6,
          under=(1, 1), droplets=1.0, spits=2, sheen=0.05, thin=0.0, reach=40, relief=0.9, pore_dark=0.35):
    """Spray `color_hex` through stencil `cut` onto `col` (modified copy returned) + (coverage, density)."""
    rng = np.random.default_rng(seed)
    H, W = cut.shape
    ys, xs = np.nonzero(cut > 0.5)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    cx, cy, bw, bh = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    a = math.radians(angle + rng.normal(0, 2))
    u = np.array([math.cos(a), math.sin(a)])
    nrm = np.array([-u[1], u[0]])
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    t = (X - cx) * u[0] + (Y - cy) * u[1]
    dn = (X - cx) * nrm[0] + (Y - cy) * nrm[1]
    ext = abs(bw * nrm[0]) + abs(bh * nrm[1])
    L = abs(bw * u[0]) + abs(bh * u[1])
    D = np.zeros((H, W), np.float32)
    mod = gnoise((H, W), 26, rng)
    starts = []
    for i in range(passes):
        off = ((i + 0.5) / passes - 0.5) * ext + rng.normal(0, ext * 0.05)
        sig = ext / passes * rng.uniform(0.75, 1.1) + 6
        s0 = -L / 2 - rng.uniform(16, 60)
        s1 = L / 2 + rng.uniform(16, 60)
        if rng.random() < 0.5:     # strokes go both ways
            s0, s1 = -s1, -s0
        ramp = smoothstep(s0 - 40, s0 + 30, t) * (1 - smoothstep(s1 - 30, s1 + 40, t))
        D += np.exp(-0.5 * ((dn - off) / sig) ** 2) * ramp * (1 + 0.16 * mod) * rng.uniform(0.85, 1.15)
        starts.append((cx + u[0] * s0 + nrm[0] * off, cy + u[1] * s0 + nrm[1] * off))
    D /= D[cut > 0.5].mean()
    peel = 1 + 0.10 * gnoise((H, W), 0.9, rng) + 0.07 * gnoise((H, W), 3.5, rng)
    Dc = D * peel
    cov = (1 - np.exp(-k * Dc * (1 - thin))) * cut
    # paint creeps under one edge of the stencil where it was not pressed flat
    sh = ndi.shift(cut, (under[1] * 1.6, under[0] * 1.6), order=1)
    bleed = np.clip(ndi.gaussian_filter(sh, 1.8) - cut, 0, 1) * 0.45 * D
    # droplets: only outside the stencil sheet, density follows the strokes
    sheet = np.zeros((H, W), np.float32)
    sheet[max(0, y0 - sheet_pad):y1 + sheet_pad, max(0, x0 - sheet_pad):x1 + sheet_pad] = 1
    dist = ndi.distance_transform_edt(1 - sheet)
    p = np.clip(D * (1 - sheet), 0, None) ** 1.3 * np.exp(-dist / reach)
    total = p.sum()
    drops = np.zeros((H * 2, W * 2), np.uint8)
    img = Image.fromarray(drops)
    dr = ImageDraw.Draw(img)
    if total > 0 and droplets > 0:
        n = int(min(60000, total * 0.022 * droplets))
        idx = rng.choice(H * W, size=n, p=(p / total).ravel())
        py, px = np.divmod(idx, W)
        rad = np.clip(rng.lognormal(-0.45, 0.45, n), 0.35, 2.2)
        alp = rng.uniform(0.55, 1.0, n)
        for yy, xx, r, al in zip(py + rng.random(n), px + rng.random(n), rad, alp):
            dr.ellipse([(xx - r) * 2, (yy - r) * 2, (xx + r) * 2, (yy + r) * 2], fill=int(255 * al))
    # spits: a few fat droplets near where a stroke began
    for sx, sy in starts[:spits]:
        for _ in range(rng.integers(1, 3)):
            r = rng.uniform(2.2, 4.2)
            xx, yy = sx + rng.normal(0, 14), sy + rng.normal(0, 10)
            if 0 < xx < W and 0 < yy < H and sheet[int(min(H - 1, max(0, yy))), int(min(W - 1, max(0, xx)))] < 0.5:
                dr.ellipse([(xx - r) * 2, (yy - r) * 2, (xx + r) * 2, (yy + r) * 2], fill=255)
    drops = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255
    c = np.clip(cov + bleed + drops * (1 - cut), 0, 1)
    P = lin(hexrgb(color_hex))
    # paint sits darker in pores (shadowed, absorbed), relief keeps showing through the film
    Pm = P * (1 - pore_dark * pore[..., None])
    out = col * (1 - c[..., None]) + Pm * c[..., None]
    rel = shade_from_height(height, 1.0)
    out *= (1 + relief * rel * c)[..., None]
    # satin sheen on the thicker film
    film = ndi.gaussian_filter(Dc * cut, 1.1) * 0.9 + 0.12 * gnoise((H, W), 1.4, rng)
    srel = shade_from_height(film * 2.0, 1.0, 0.6)
    out += (np.clip(srel, 0, None) ** 1.5 * sheen * c)[..., None]
    return out, c, D * cut


def masked(col, height, pore, rect, color_hex, seed, ridge=0.10, coverage=0.96):
    """Tape-masked paint: hard edge with micro-roughness, a faint ridge where tape lifted."""
    rng = np.random.default_rng(seed)
    H, W = col.shape[:2]
    x0, y0, x1, y1 = rect
    m = np.zeros((H, W), np.float32)
    m[y0:y1, x0:x1] = 1
    m = smoothstep(0.38, 0.62, ndi.gaussian_filter(m, 0.9) + 0.07 * gnoise((H, W), 0.7, rng))
    cov = m * np.clip(coverage + 0.04 * gnoise((H, W), 2.0, rng), 0, 1)
    P = lin(hexrgb(color_hex)) * (1 - 0.18 * pore[..., None])
    out = col * (1 - cov[..., None]) + P * cov[..., None]
    rim = np.clip(m - ndi.grey_erosion(m, size=3), 0, 1)
    out *= (1 - ridge * rim)[..., None]
    out *= (1 + 0.5 * shade_from_height(height, 1.0) * cov)[..., None]
    return out, cov


def drips(col, cover, density, color_hex, seed, n=3, max_len=110, below=None):
    """Gravity drips from the heaviest paint along the lower edge of `cover`."""
    rng = np.random.default_rng(seed)
    H, W = cover.shape
    P = lin(hexrgb(color_hex))
    filled = cover > 0.6
    bottom = np.where(filled.any(0), H - 1 - np.argmax(filled[::-1], 0), -1)
    weight = np.array([density[b, x] if b > 0 else 0 for x, b in enumerate(bottom)]) ** 4
    if weight.sum() == 0:
        return col
    xs = []
    for _ in range(80):
        x = rng.choice(W, p=weight / weight.sum())
        if all(abs(x - o) > 70 for o in xs):
            xs.append(x)
        if len(xs) >= n:
            break
    ss = 4
    img = Image.new('L', (W * ss, H * ss), 0)
    hi = Image.new('L', (W * ss, H * ss), 0)
    d, dh = ImageDraw.Draw(img), ImageDraw.Draw(hi)
    for i, x in enumerate(xs):
        y = bottom[x] - 2
        short = rng.random() < 0.3
        Ln = rng.uniform(7, 16) if short else min(max_len, rng.lognormal(math.log(46), 0.45))
        w = rng.uniform(6.5, 11) * (0.8 if short else 1)
        phase = rng.uniform(0, 6)
        left, right = [], []
        steps = 24
        for j in range(steps + 1):
            s = j / steps
            yy = y + Ln * s
            ww = w * (1.55 - 0.55 * smoothstep(0, 0.18, s)) * (1 - 0.38 * s)
            xx = x + 0.7 * math.sin(phase + s * 5) * s
            left.append(((xx - ww / 2) * ss, yy * ss))
            right.append(((xx + ww / 2) * ss, yy * ss))
        d.polygon(left + right[::-1], fill=255)
        if not short or rng.random() < 0.5:
            r = w * rng.uniform(0.55, 0.72)
            ex = x + 0.7 * math.sin(phase + 5)
            d.ellipse([(ex - r) * ss, (y + Ln - r * 0.6) * ss, (ex + r) * ss, (y + Ln + r * 1.25) * ss], fill=255)
            dh.ellipse([(ex - r * 0.55) * ss, (y + Ln - r * 0.1) * ss, (ex - r * 0.1) * ss, (y + Ln + r * 0.45) * ss], fill=110)
        dh.line([((x - w * 0.18) * ss, (y + 3) * ss), ((x - w * 0.14) * ss, (y + Ln * 0.85) * ss)], fill=70, width=ss)
    a = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255
    h = np.asarray(hi.resize((W, H), Image.LANCZOS), np.float32) / 255
    a = a * (1 - cover) if below is None else a
    out = col * (1 - a[..., None]) + (P * 0.86) * a[..., None]
    out += (h * a * 0.22)[..., None]
    return out
