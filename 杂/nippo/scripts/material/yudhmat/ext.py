"""Extensions of bake.py used by the production assets.

Most helpers are lifted from the design bakes (merge2/today/todaybake.py, merge2/english/eng_bake.py,
merge2/posture/kraftbake.py + popups.py, merge2/illus/make.py) so the production sprites carry exactly the recipes
the renders were judged on.  New here:

  Layer        a TRANSPARENT canvas: every bake operation runs on premultiplied linear colour over a zero ground,
               so `out` of bake.spray()/masked() is directly the premultiplied paint layer and its coverage the alpha.
               A substrate (concrete or kraft height + pore map) still gives the film its relief.
  export()     premultiplied linear layer -> straight sRGB RGBA, with the alpha/colour re-solved so that plain
               sRGB-space "over" compositing (Core Animation / SwiftUI) reproduces the linear-light bake over the
               asset's nominal ground (`ground`), while keeping the physical coverage as the see-through amount.
  overlay()    a lit/shaded effect computed over a flat ground -> the minimum-alpha RGBA overlay that reproduces it.
  concrete_tile()  bake.concrete()'s recipe made periodic (FFT noise, wrapped pores) for a seamless tile.
"""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from . import bake
from .bake import (LIGHT, gnoise, hexrgb, lin, rect_mask, rough_polygon, shade_from_height, smoothstep, spray,  # noqa: F401
                   srgb)

PAL = dict(teal='#12E9D3', orange='#FF6412', black='#161615', white='#F4F3EE', grey='#C3C6C7', greyp='#7E8286',
           pale='#D5D8D9', estroke='#80858A', past='#1F2124', page='#161719', slate='#4B5055', concrete='#2A2D30',
           kraft='#C49C69', tape='#E6D9B0', creature='#42464A', ghost='#3B2814', mortar='#3A3B3A',
           tealdot='#0FBFAD')


def C(name):
    return PAL.get(name, name)


# ================================================================ periodic noise / concrete tile
def gnoise_wrap(shape, sigma, rng):
    """bake.gnoise() but periodic (Gaussian low-pass of white noise in the Fourier domain)."""
    n = rng.standard_normal(shape).astype(np.float64)
    sy, sx = (sigma, sigma) if np.isscalar(sigma) else sigma
    fy = np.fft.fftfreq(shape[0])[:, None]
    fx = np.fft.rfftfreq(shape[1])[None, :]
    H = np.exp(-2 * (math.pi ** 2) * ((fy * sy) ** 2 + (fx * sx) ** 2))
    out = np.fft.irfft2(np.fft.rfft2(n) * H, s=shape)
    out -= out.mean()
    return (out / (out.std() + 1e-12)).astype(np.float32)


def blur_wrap(a, sigma):
    return ndi.gaussian_filter(a, sigma, mode='wrap')


def shade_wrap(h, strength=1.0, blur=0.7):
    hs = blur_wrap(h, blur)
    gy = (np.roll(hs, -1, 0) - np.roll(hs, 1, 0)) / 2
    gx = (np.roll(hs, -1, 1) - np.roll(hs, 1, 1)) / 2
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(hs)
    inv = 1 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) * inv - LIGHT[2]


def concrete_tile(N, seed, base_hex='#2A2D30', max_pore=6.0, day=False):
    """bake.concrete() without seams / ties / chips, every field periodic -> (col_lin, height, pore), N x N."""
    rng = np.random.default_rng(seed)
    base = lin(hexrgb(base_hex))
    shape = (N, N)
    tone = (0.060 * gnoise_wrap(shape, 170, rng) + 0.032 * gnoise_wrap(shape, 48, rng)
            + 0.016 * gnoise_wrap(shape, 11, rng) + 0.022 * gnoise_wrap(shape, 1.1, rng))
    warm = 0.025 * gnoise_wrap(shape, 230, rng)
    g = gnoise_wrap(shape, (0.9, 80), rng) * 0.016 + gnoise_wrap(shape, (3, 200), rng) * 0.01
    grain = g + rng.normal(0, 0.016)
    height = (g * 0.5).astype(np.float32)
    n = int(N * N / 1900)
    ys, xs = rng.integers(0, N, n), rng.integers(0, N, n)
    rs = np.clip(rng.lognormal(0.25, 0.6, n), 0.6, max_pore)
    pore = np.zeros(shape, np.float32)
    for y, x, r in zip(ys, xs, rs):
        R = int(math.ceil(r)) + 1
        yy, xx = np.mgrid[y - R:y + R + 1, x - R:x + R + 1]
        d2 = ((yy - y) ** 2 + (xx - x) ** 2 * rng.uniform(0.7, 1.3)) / (r * r)
        cup = np.clip(1 - d2, 0, 1)
        iy, ix = yy % N, xx % N
        height[iy, ix] -= cup * r * 0.9
        pore[iy, ix] = np.maximum(pore[iy, ix], (cup > 0.05) * min(1, r / 3))
    shade = shade_wrap(height, 1.1)
    ao = blur_wrap(np.minimum(height, 0), 1.6)
    col = np.empty((N, N, 3), np.float32)
    col[:] = base
    col *= (1 + tone + grain)[..., None]
    col[..., 0] *= 1 + warm
    col[..., 2] *= 1 - warm
    col *= (1 + 1.25 * shade)[..., None]
    col *= np.clip(1 + 0.10 * ao, 0.55, 1)[..., None]
    sp = rng.random(shape)
    bright = blur_wrap((sp > 0.9994).astype(np.float32), 0.6) * 3.5
    dark = blur_wrap((sp < 0.0006).astype(np.float32), 0.6) * 3.5
    col *= (1 + 0.35 * bright - 0.35 * dark)[..., None]
    return col, height, pore


def quiet_wrap(col, amount, sigma=26):
    """bake.quiet() over the whole (periodic) tile."""
    mean = np.stack([blur_wrap(col[..., i], sigma) for i in range(3)], -1)
    return mean + (col - mean) * amount


# ================================================================ substrates for transparent sprites
_SUB = {}


def substrate(W, H, seed, kind='concrete', quiet=None):
    """Height + pore/absorb maps for paint relief.  quiet = (x0, y0, x1, y1, k): damp relief inside a rect
    (text sits there) by factor k, feathered."""
    key = (W, H, seed, kind)
    if key not in _SUB:
        if kind == 'kraft':
            _, h, p = kraft(W, H, seed)
        elif kind == 'flat':
            h, p = np.zeros((H, W), np.float32), np.zeros((H, W), np.float32)
        else:
            _, h, p = bake.concrete(W, H, seed, seams=(), ties=(), chips=())
        _SUB[key] = (h.astype(np.float32), p.astype(np.float32))
    h, p = (a.copy() for a in _SUB[key])
    if quiet:
        x0, y0, x1, y1, k = quiet
        Q = np.zeros((H, W), np.float32)
        Q[max(0, int(y0)):int(y1), max(0, int(x0)):int(x1)] = 1
        Q = ndi.gaussian_filter(Q, 8)
        hm = ndi.gaussian_filter(h, 24)          # damp the detail around the local mean, never the mean itself
        h = hm + (h - hm) * (1 - k * Q)
        p = p * (1 - (k + (1 - k) * 0.4) * Q)
    return h, p


class Layer:
    """Transparent paint layer: premultiplied linear colour `col` + coverage `A`."""

    def __init__(self, W, H, seed, kind='concrete', quiet=None):
        self.W, self.H = W, H
        self.col = np.zeros((H, W, 3), np.float32)
        self.A = np.zeros((H, W), np.float32)
        self.hgt, self.pore = substrate(W, H, seed, kind, quiet)

    def add(self, c):
        self.A = np.clip(c + self.A * (1 - c), 0, 1)

    def spray(self, cut, color, seed, side=None, side_min=0.12, box=None, keep_bleed=None, **kw):
        """bake.spray() through `cut`.  side: direction (deg, 0 = right, 90 = down) the can was held from —
        overspray outside the stencil sheet stays on that side and thins to side_min elsewhere (todaybake.Slab)."""
        before = self.col
        out, cov, dens = spray(self.col, self.hgt, self.pore, cut, C(color), seed, **kw)
        if side is not None:
            ys, xs = np.nonzero(cut > 0.5)
            x0, y0, x1, y1 = (xs.min(), ys.min(), xs.max(), ys.max()) if box is None else box
            sp = kw.get('sheet_pad', 34)
            inside = np.zeros(cut.shape, np.float32)
            inside[max(0, y0 - sp):y1 + sp, max(0, x0 - sp):x1 + sp] = 1
            inside = ndi.gaussian_filter(inside, 2)
            Y, X = np.mgrid[0:self.H, 0:self.W].astype(np.float32)
            vx = (X - (x0 + x1) / 2) / max(8, (x1 - x0) / 2 + sp)
            vy = (Y - (y0 + y1) / 2) / max(8, (y1 - y0) / 2 + sp)
            nv = np.sqrt(vx * vx + vy * vy) + 1e-6
            a = math.radians(side)
            dd = (vx * math.cos(a) + vy * math.sin(a)) / nv
            wgt = side_min + (1 - side_min) * smoothstep(-0.35, 0.85, dd)
            wgt = inside + (1 - inside) * wgt
            out = before + (out - before) * wgt[..., None]
            cov = cov * wgt
        if keep_bleed is not None:            # kraftbake.tame_bleed: pull back the soft creep at the stencil edge
            out = tame_bleed(before, out, cut, keep=keep_bleed)
        self.col = out
        self.add(cov)
        return cov, dens

    def masked(self, m, color, seed, **kw):
        out, cov = masked_paint(self.col, self.hgt, self.pore, m, C(color), seed, **kw)
        self.col = out
        self.add(cov)
        return cov

    def mpaint(self, m, color, rng, **kw):
        out, cov = mpaint(self.col, self.hgt, self.pore, m, C(color), rng, **kw)
        self.col = out
        self.add(cov)
        return cov

    def fade(self, f, region=None):
        """Scale the layer's paint (a faded / sanded spray)."""
        if region is None:
            self.col *= f
            self.A *= f
        else:
            k = 1 - (1 - f) * region
            self.col *= k[..., None]
            self.A *= k


# ================================================================ export
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


def export(col, A, ground=None):
    """Premultiplied linear (col, A) -> straight sRGB RGBA uint8.
    Colour = the paint's own (straight) colour, so a sprite keeps its hue on any ground.  With `ground` (hex) the alpha
    is re-solved per pixel so that sRGB-space "over" compositing (Core Animation / SwiftUI) on that flat ground has
    the luminance of the linear-light bake col + ground (1 - A); without it alpha = coverage."""
    A = np.clip(A, 0, 1).astype(np.float32)
    straight = col / np.maximum(A, 1e-6)[..., None]
    sC = np.clip(srgb(straight), 0, 1)
    a = A
    if ground is not None:
        B = lin(hexrgb(C(ground)))
        sT = srgb(np.clip(col + B * (1 - A)[..., None], 0, 1))
        sB = srgb(B)
        yT, yB, yC = (sT * LUMA).sum(-1), float((sB * LUMA).sum()), (sC * LUMA).sum(-1)
        den = yC - yB
        ok = np.abs(den) > 0.03
        a = np.where(ok, (yT - yB) / np.where(ok, den, 1), A)
        a = np.clip(np.where(A > 0, a, 0), 0, 1)
    a8 = (a * 255 + 0.5).astype(np.uint8)
    rgb8 = (sC * 255 + 0.5).astype(np.uint8)
    rgb8[a8 == 0] = 0
    return np.dstack([rgb8, a8])


def overlay(T_lin, ground):
    """A lit / shaded effect T computed over a flat `ground` -> minimum-alpha RGBA overlay reproducing it."""
    B = lin(hexrgb(C(ground)))
    sT, sB = srgb(np.clip(T_lin, 0, 1)), srgb(B)
    up = np.where(sT > sB, (sT - sB) / np.maximum(1 - sB, 1e-6), 0).max(-1)
    dn = np.where(sT < sB, (sB - sT) / np.maximum(sB, 1e-6), 0).max(-1)
    a = np.clip(np.maximum(up, dn), 0, 1)
    rgb = np.clip((sT - sB * (1 - a)[..., None]) / np.maximum(a, 1e-6)[..., None], 0, 1)
    a8 = (a * 255 + 0.5).astype(np.uint8)
    rgb8 = (rgb * 255 + 0.5).astype(np.uint8)
    rgb8[a8 == 0] = 0
    return np.dstack([rgb8, a8])


def rgb8(col_lin):
    return (srgb(col_lin) * 255 + 0.5).astype(np.uint8)


# ================================================================ masks
def poly_mask(W, H, polys, ss=4):
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    for pts in polys:
        d.polygon([(x * ss, y * ss) for x, y in pts], fill=255)
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def knife_rect(W, H, x0, y0, x1, y1, rng, jitter=0.7):
    return rect_mask(W, H, x0, y0, x1, y1, rng, jitter)


def knife_frame(W, H, x0, y0, x1, y1, sw, rng, overcut=True):
    """todaybake: hand-cut square frame, corners not perfect, optional hairline overcut."""
    def corners(a0, b0, a1, b1, sd):
        return [(a0 + rng.normal(0, sd), b0 + rng.normal(0, sd)), (a1 + rng.normal(0, sd), b0 + rng.normal(0, sd)),
                (a1 + rng.normal(0, sd), b1 + rng.normal(0, sd)), (a0 + rng.normal(0, sd), b1 + rng.normal(0, sd))]
    outer = rough_polygon(W, H, corners(x0, y0, x1, y1, 0.3), rng, 0.6)
    inner = rough_polygon(W, H, corners(x0 + sw, y0 + sw, x1 - sw, y1 - sw, 0.25), rng, 0.5)
    m = np.clip(outer - inner, 0, 1)
    if overcut:
        polys = []
        for _ in range(rng.integers(1, 3)):
            cx, cy = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)][rng.integers(0, 4)]
            horiz = rng.random() < 0.5
            L = rng.uniform(1.6, 3.2)
            sx = -1 if cx == x0 else 1
            sy = -1 if cy == y0 else 1
            if horiz:
                yy = cy - sy * sw * 0.5
                polys.append([(cx, yy - .45), (cx + sx * L, yy - .3), (cx + sx * L, yy + .3), (cx, yy + .45)])
            else:
                xx = cx - sx * sw * 0.5
                polys.append([(xx - .45, cy), (xx - .3, cy + sy * L), (xx + .3, cy + sy * L), (xx + .45, cy)])
        m = np.maximum(m, poly_mask(W, H, polys) * 0.8)
    return m


def rough_frame(W, H, x0, y0, x1, y1, sw, rng):
    """eng_bake.paint_frame look (outer rough rect minus inner rough rect) with the corner noise of todaybake's
    knife_frame, so a thin stroke can never be eaten away when both edges wander towards each other."""
    return knife_frame(W, H, x0, y0, x1, y1, sw, rng, overcut=False)


def fine_spray_mask(W, H, x0, y0, x1, y1, rng, cover=0.40, pitch=2.0, ss=4):
    """todaybake: a deliberate light pass, fine droplets on a jittered grid, hard-clipped to the cell."""
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    r0 = pitch * math.sqrt(cover / math.pi)
    for yy in np.arange(y0 + pitch / 2, y1, pitch):
        for xx in np.arange(x0 + pitch / 2, x1, pitch):
            x = xx + rng.uniform(-0.38, 0.38) * pitch
            y = yy + rng.uniform(-0.38, 0.38) * pitch
            r = r0 * rng.uniform(0.8, 1.2)
            d.ellipse([(x - r) * ss, (y - r) * ss, (x + r) * ss, (y + r) * ss], fill=int(255 * rng.uniform(0.85, 1)))
    m = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255
    clip = np.zeros((H, W), np.float32)
    clip[max(0, int(math.ceil(y0))):int(y1), max(0, int(math.ceil(x0))):int(x1)] = 1
    return m * clip


def dots_mask(W, H, x0, y0, x1, y1, rng, density, rmin=1.0, rmax=2.6, mist=0.10, ss=4):
    """eng_bake.dots_into: sparse paint dots ('not sprayed full') + a faint mist, clipped to the box."""
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    area = (x1 - x0) * (y1 - y0)
    rr = rng.uniform(rmin, rmax, 4000)
    n = int(density * area / (math.pi * np.mean(rr ** 2)))
    for _ in range(n):
        r = rng.uniform(rmin, rmax) * (1.4 if rng.random() < 0.06 else 1)
        px, py = rng.uniform(x0, x1), rng.uniform(y0, y1)
        d.ellipse([(px - r) * ss, (py - r * rng.uniform(.8, 1.1)) * ss, (px + r) * ss, (py + r) * ss],
                  fill=int(255 * rng.uniform(0.75, 1)))
    m = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255
    box = np.zeros((H, W), np.float32)
    box[int(y0):int(y1), int(x0):int(x1)] = 1
    return np.clip(m * box + mist * box * (0.7 + 0.3 * gnoise((H, W), 3, rng)), 0, 1)


def rotate_mask(m, angle_css, cx_, cy_):
    """Rotate like CSS rotate(angle) (clockwise for positive) about (cx_, cy_)."""
    im = Image.fromarray(np.clip(m, 0, 1).astype(np.float32), 'F')
    im = im.rotate(-angle_css, resample=Image.BICUBIC, center=(cx_, cy_))
    return np.clip(np.asarray(im, np.float32), 0, 1)


def _seg(x0, y0, x1, y1, w):
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * w / 2, dx / L * w / 2
    return [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]


STAR = [[(11.1, 2.5), (8.6, 8.8), (2, 9.3), (7.1, 13.6), (5.5, 20.2), (11.1, 16.7)],
        [(12.9, 2.5), (15.4, 8.8), (22, 9.3), (16.9, 13.6), (18.5, 20.2), (12.9, 16.7)]]
CROSS = [_seg(4.2, 4.2, 10.6, 10.6, 4.0), _seg(13.4, 13.4, 19.8, 19.8, 4.0),
         _seg(19.8, 4.2, 13.4, 10.6, 4.0), _seg(10.6, 13.4, 4.2, 19.8, 4.0)]


def icon_mask(name, size, ss=8):
    """eng_bake.icon_mask: star | cross | nope (stencil ⊘ with two ring bridges), from the icons.svg 24 grid."""
    N = size * ss
    img = Image.new('L', (N, N), 0)
    d = ImageDraw.Draw(img)
    k = N / 24
    if name in ('star', 'cross'):
        for p in (STAR if name == 'star' else CROSS):
            d.polygon([(x * k, y * k) for x, y in p], fill=255)
    elif name == 'nope':
        c, ro, ri = 12 * k, 11.4 * k, 7.0 * k
        d.ellipse([c - ro, c - ro, c + ro, c + ro], fill=255)
        d.ellipse([c - ri, c - ri, c + ri, c + ri], fill=0)
        d.polygon([(x * k, y * k) for x, y in _seg(5.2, 18.8, 18.8, 5.2, 4.0)], fill=255)
        for ang in (135, 315):
            a = math.radians(ang)
            ux, uy = math.cos(a), -math.sin(a)
            p0 = (12 + ux * 6.0, 12 + uy * 6.0)
            p1 = (12 + ux * 12.4, 12 + uy * 12.4)
            d.polygon([(x * k, y * k) for x, y in _seg(*p0, *p1, 1.7)], fill=0)
    return np.asarray(img.resize((size, size), Image.LANCZOS), np.float32) / 255


def circle_mask(W, H, cx, cy, r, ring=0):
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
    d = np.hypot(X - cx, Y - cy)
    m = np.clip(r - d + 0.5, 0, 1)
    if ring:
        m *= np.clip(d - (r - ring) + 0.5, 0, 1)
    return m


def box_mask(W, H, x0, y0, x1, y1):
    m = np.zeros((H, W), np.float32)
    m[max(0, int(round(y0))):max(0, int(round(y1))), max(0, int(round(x0))):max(0, int(round(x1)))] = 1
    return m


# ================================================================ paint ops
def masked_paint(col, height, pore, m, color_hex, seed, ridge=0.06, coverage=0.95, thin=0.0,
                 relief=0.5, pore_k=0.20, edge=True, jitter=0.035):
    """todaybake.masked_paint: bake.masked() through any mask, `thin` = patches where the ground shows."""
    rng = np.random.default_rng(seed)
    H, W = col.shape[:2]
    if edge:
        m = smoothstep(0.30, 0.70, ndi.gaussian_filter(m, 0.7) + 0.06 * gnoise((H, W), 0.7, rng)) * (m.max() > 0)
    cv = coverage + jitter * gnoise((H, W), 2.0, rng)
    if thin:
        cv = cv - thin * smoothstep(0.5, 1.9, gnoise((H, W), 7, rng)) - 0.4 * thin * smoothstep(1.0, 2.6, gnoise((H, W), 2.2, rng))
    cov = m * np.clip(cv, 0, 1)
    P = lin(hexrgb(color_hex)) * (1 - pore_k * pore[..., None])
    out = col * (1 - cov[..., None]) + P * cov[..., None]
    if ridge:
        rim = np.clip(m - ndi.grey_erosion(m, size=3), 0, 1)
        out *= (1 - ridge * rim)[..., None]
    out *= (1 + relief * shade_from_height(height, 1.0) * cov)[..., None]
    return out, cov


def mpaint(col, hgt, pore, m, color_hex, rng, cov=0.965, thin=0.0, ridge=0.05, relief=0.45, pore_k=0.2,
           rough=0.07, thin_sigma=9, noise=None, edge=True):
    """eng_bake.mpaint: tape-masked paint through an arbitrary mask (thin patches + pin-holes)."""
    H, W = m.shape
    mm = smoothstep(0.36, 0.64, ndi.gaussian_filter(m, 0.65) + rough * gnoise((H, W), 0.7, rng)) if edge else m
    noise = 0.035 * min(1.0, cov / 0.5) if noise is None else noise
    c = np.clip(cov + noise * gnoise((H, W), 2.0, rng), 0, 1)
    if thin:
        c = c * (1 - thin * smoothstep(0.2, 1.7, gnoise((H, W), thin_sigma, rng)))
        c = c * (1 - 0.5 * thin * smoothstep(1.4, 2.6, gnoise((H, W), 1.3, rng)))
    c = mm * c
    P = lin(hexrgb(color_hex))
    Pm = P * (1 - pore_k * pore[..., None])
    out = col * (1 - c[..., None]) + Pm * c[..., None]
    rim = np.clip(mm - ndi.grey_erosion(mm, size=3), 0, 1)
    out = out * (1 - ridge * rim)[..., None]
    out = out * (1 + relief * shade_from_height(hgt, 1.0) * c)[..., None]
    return out, c


def tame_bleed(before, after, cut, keep=0.35, width=5):
    """kraftbake: pull back the soft creep just outside a stencil edge (black on pale kraft reads as blur)."""
    band = np.clip(ndi.grey_dilation(cut, size=2 * width + 1) - cut, 0, 1)
    band = ndi.gaussian_filter(band, 0.8)[..., None] * (1 - cut[..., None])
    return after * (1 - (1 - keep) * band) + before * ((1 - keep) * band)


def dash_mask(W, H, x0, y0, x1, y1, sw, dash, gap, rng, angle=0.0, ss=4):
    """eng_bake.dash_frame geometry: a dashed frame of short tape strips (corners first), rotatable."""
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    W_, H_ = x1 - x0, y1 - y0
    ccx, ccy = x0 + W_ / 2, y0 + H_ / 2
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))

    def R(px, py):
        dx, dy = px - ccx, py - ccy
        return ((ccx + dx * ca - dy * sa) * ss, (ccy + dx * sa + dy * ca) * ss)

    def strip(ax, ay, bx, by):
        L = math.hypot(bx - ax, by - ay)
        nx, ny = -(by - ay) / L * sw / 2, (bx - ax) / L * sw / 2
        j = [rng.normal(0, 0.18) for _ in range(4)]
        pts = [(ax + nx + j[0], ay + ny + j[1]), (bx + nx + j[2], by + ny + j[3]),
               (bx - nx - j[0], by - ny - j[3]), (ax - nx - j[2], ay - ny - j[1])]
        d.polygon([R(*p) for p in pts], fill=255)

    corners = [(x0 + sw / 2, y0 + sw / 2), (x0 + W_ - sw / 2, y0 + sw / 2),
               (x0 + W_ - sw / 2, y0 + H_ - sw / 2), (x0 + sw / 2, y0 + H_ - sw / 2)]
    for i in range(4):
        (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
        L = math.hypot(bx - ax, by - ay)
        ux, uy = (bx - ax) / L, (by - ay) / L
        n = max(1, round((L + gap) / (dash + gap)))
        dd = (L - (n - 1) * gap) / n
        t = -sw / 2
        for k in range(n):
            e = dd * rng.uniform(0.92, 1.06)
            s0, s1 = max(-sw / 2, t), min(L + sw / 2, t + e + (sw / 2 if k == 0 else 0))
            strip(ax + ux * s0, ay + uy * s0, ax + ux * s1, ay + uy * s1)
            t += dd + gap
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def four_stroke_frame(W, H, x0, y0, x1, y1, sw, rng):
    """kraftbake.frame geometry: four separate tape strokes, corners overlap or fall short a pixel."""
    j = lambda: rng.uniform(-0.8, 1.3)   # noqa: E731
    return [box_mask(W, H, x0 - j(), y0, x1 + j(), y0 + sw), box_mask(W, H, x0 - j(), y1 - sw, x1 + j(), y1),
            box_mask(W, H, x0, y0 - j(), x0 + sw, y1 + j()), box_mask(W, H, x1 - sw, y0 - j(), x1, y1 + j())]


def masked_mask(col, height, pore, mask, color_hex, seed, ridge=0.10, coverage=0.96, rough=0.07, alpha=1.0, var=1.0):
    """kraftbake.masked_mask: bake.masked() for any mask."""
    rng = np.random.default_rng(seed)
    H, W = col.shape[:2]
    m = smoothstep(0.38, 0.62, ndi.gaussian_filter(mask, 0.6) + rough * gnoise((H, W), 0.7, rng))
    cov = m * np.clip(coverage + var * (0.05 * gnoise((H, W), 2.0, rng) + 0.03 * gnoise((H, W), 0.8, rng)), 0, 1) * alpha
    P = lin(hexrgb(color_hex)) * (1 - 0.18 * pore[..., None])
    out = col * (1 - cov[..., None]) + P * cov[..., None]
    rim = np.clip(m - ndi.grey_erosion(m, size=3), 0, 1)
    out *= (1 - ridge * rim * alpha)[..., None]
    out *= (1 + 0.5 * shade_from_height(height, 1.0) * cov)[..., None]
    return out, cov


# ================================================================ drips (bake.drips geometry, one drip, explicit)
def drip_shape(W, H, x, y, length, width, phase, blob=True, ss=4):
    """One gravity drip hanging from (x, y): returns (alpha, highlight) — bake.drips() polygon + end blob."""
    img = Image.new('L', (W * ss, H * ss), 0)
    hi = Image.new('L', (W * ss, H * ss), 0)
    d, dh = ImageDraw.Draw(img), ImageDraw.Draw(hi)
    left, right = [], []
    steps = 32
    for j in range(steps + 1):
        s = j / steps
        yy = y + length * s
        ww = width * (1.55 - 0.55 * smoothstep(0, 0.18, s)) * (1 - 0.38 * s)
        xx = x + 0.7 * math.sin(phase + s * 5) * s
        left.append(((xx - ww / 2) * ss, yy * ss))
        right.append(((xx + ww / 2) * ss, yy * ss))
    d.polygon(left + right[::-1], fill=255)
    if blob:
        r = width * 0.64
        ex = x + 0.7 * math.sin(phase + 5)
        d.ellipse([(ex - r) * ss, (y + length - r * 0.6) * ss, (ex + r) * ss, (y + length + r * 1.25) * ss], fill=255)
        dh.ellipse([(ex - r * 0.55) * ss, (y + length - r * 0.1) * ss, (ex - r * 0.1) * ss, (y + length + r * 0.45) * ss], fill=110)
    dh.line([((x - width * 0.18) * ss, (y + 3) * ss), ((x - width * 0.14) * ss, (y + length * 0.85) * ss)], fill=70, width=ss)
    a = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255
    h = np.asarray(hi.resize((W, H), Image.LANCZOS), np.float32) / 255
    return a, h


# ================================================================ kraft (posture/kraftbake.py)
def _fibres(W, H, n, rng, ang_sd=22, lmean=13, wmax=3, fill=(70, 255)):
    ss = 2
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    xs, ys = rng.uniform(-20, W + 20, n), rng.uniform(-20, H + 20, n)
    angs = np.radians(rng.normal(0, ang_sd, n) + np.where(rng.random(n) < 0.12, rng.uniform(-90, 90, n), 0))
    lens = np.clip(rng.lognormal(math.log(lmean), 0.55, n), 3, 70)
    ws = rng.integers(1, wmax + 1, n)
    vs = rng.integers(fill[0], fill[1], n)
    bend = rng.normal(0, 0.18, n)
    for x, y, a, L, w, v, b in zip(xs, ys, angs, lens, ws, vs, bend):
        pts = []
        for t in (0, 0.33, 0.66, 1):
            aa = a + b * (t - 0.5) * 2
            pts.append(((x + math.cos(aa) * L * t) * ss, (y + math.sin(aa) * L * t) * ss))
        d.line(pts, fill=int(v), width=int(w))
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def kraft(W, H, seed, base_hex='#C49C69', flute_period=9.4, flute_amp=0.026, fibre_k=1.0, falloff=0.07):
    """Corrugated kraft board -> (colour_lin, height, absorb).  Verbatim kraftbake.kraft()."""
    rng = np.random.default_rng(seed)
    base = lin(hexrgb(base_hex))
    shape = (H, W)
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    tone = (0.040 * gnoise(shape, (70, 130), rng) + 0.030 * gnoise(shape, (12, 24), rng)
            + 0.026 * gnoise(shape, (2.6, 5.5), rng) + 0.020 * gnoise(shape, 0.7, rng))
    warm = 0.030 * gnoise(shape, 150, rng)
    fd = _fibres(W, H, int(W * H / 70 * fibre_k), rng, 24, 6.5, 1, (50, 200))
    fl = _fibres(W, H, int(W * H / 420 * fibre_k), rng, 18, 9, 1, (60, 180))
    fs = _fibres(W, H, int(W * H / 9000 * fibre_k), rng, 30, 16, 2, (120, 230))
    felt = gnoise(shape, (0.7, 1.6), rng)
    sp = rng.random(shape)
    specks = ndi.gaussian_filter((sp > 0.99965).astype(np.float32), 0.7) * 4.0
    flecks = ndi.gaussian_filter((sp < 0.00012).astype(np.float32), 0.6) * 3.0
    wob = 2.2 * gnoise(shape, (90, 1e-3), rng) + 0.8 * gnoise(shape, (20, 1e-3), rng)
    phase = 2 * math.pi * (X + wob) / flute_period
    vis = np.clip(0.75 + 0.35 * gnoise(shape, (160, 60), rng), 0.3, 1.3)
    flute = np.sin(phase) * vis
    flute_shade = -np.cos(phase) * vis * flute_amp * (-LIGHT[0] / 0.52)
    cockle = gnoise(shape, 110, rng)
    height = (0.45 * fl + 0.30 * fs - 0.30 * fd - 0.6 * specks + 0.07 * flute + 2.2 * cockle).astype(np.float32)
    col = np.empty((H, W, 3), np.float32)
    col[:] = base
    col *= (1 + tone)[..., None]
    col[..., 0] *= 1 + warm
    col[..., 2] *= 1 - 1.4 * warm
    dark_f = lin(hexrgb('#6F5131'))
    pale_f = lin(hexrgb('#E2C9A0'))
    a_d = np.clip(fd * 0.26, 0, 1)[..., None]
    a_l = np.clip(fl * 0.13 + fs * 0.16, 0, 1)[..., None]
    col *= (1 + 0.028 * felt)[..., None]
    col = col * (1 - a_d) + dark_f * a_d
    col = col * (1 - a_l) + pale_f * a_l
    col *= (1 - 0.45 * np.clip(specks, 0, 1) + 0.18 * np.clip(flecks, 0, 1))[..., None]
    col *= (1 + flute_shade + 0.55 * shade_from_height(cockle * 3.0, 1.0, 2.0))[..., None]
    col *= (1 + 0.6 * shade_from_height(0.6 * fl - 0.4 * fd, 1.0, 0.5))[..., None]
    col *= (base / col.reshape(-1, 3).mean(0))[None, None, :]
    col *= (1 - falloff * ((X / W - 0.5) * 0.8 + (Y / H - 0.5) * 1.0))[..., None]
    absorb = np.clip(0.55 * fd + 0.25 * smoothstep(0.5, 2.0, -tone / 0.04), 0, 1)
    return col, height, absorb


def rounded_sdf(W, H, x0, y0, x1, y1, r):
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = np.abs(X - cx) - hx, np.abs(Y - cy) - hy
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def board_edge(W, H, rect, r, seed, nicks=4, sides=(0, 1, 2, 3), along_range=None):
    """kraftbake.board_edge: signed distance (px, < 0 inside) of a hand-cut board edge with nicks.
    sides / along_range: where nicks may fall (kept inside 9-slice caps)."""
    rng = np.random.default_rng(seed)
    d = rounded_sdf(W, H, *rect, r)
    d = d + 0.18 * gnoise((H, W), 0.9, rng) + 0.32 * gnoise((H, W), 7, rng) + 0.45 * gnoise((H, W), 40, rng)
    x0, y0, x1, y1 = rect
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    for _ in range(nicks):
        side = sides[rng.integers(0, len(sides))]
        t = rng.uniform(0.12, 0.88) if along_range is None else along_range(side, rng)
        cx = x0 + (x1 - x0) * t if side in (0, 2) else (x0 if side == 3 else x1)
        cy = y0 + (y1 - y0) * t if side in (1, 3) else (y0 if side == 0 else y1)
        along = rng.uniform(3.5, 7.0)
        depth = rng.uniform(0.9, 1.8)
        ex, ey = ((X - cx) / along, (Y - cy) / depth) if side in (0, 2) else ((X - cx) / depth, (Y - cy) / along)
        bite = depth * (1 - np.hypot(ex, ey)) + 0.35 * gnoise((H, W), 0.8, rng)
        d = np.maximum(d, bite)
    return d


def wear_edges(col, height, d, seed, tear=None, crushed=()):
    """kraftbake.wear_edges: scuffed liner, grime, crushed corners, rolled-edge light, torn liner patch."""
    rng = np.random.default_rng(seed)
    H, W = d.shape
    gy, gx = np.gradient(ndi.gaussian_filter(d, 1.5))
    gn = np.hypot(gx, gy) + 1e-6
    nx, ny = gx / gn, gy / gn
    facing = (nx * LIGHT[0] + ny * LIGHT[1]) / math.hypot(LIGHT[0], LIGHT[1])
    band1 = smoothstep(-3.5, -0.4, d)
    band2 = smoothstep(-16, -2, d) * (1 - band1)
    scuff = smoothstep(0.1, 1.1, gnoise((H, W), 4, rng) + 0.5 * gnoise((H, W), 1.2, rng))
    pale = lin(hexrgb('#DCC196'))
    a = (0.55 * band1 * scuff)[..., None]
    col = col * (1 - a) + pale * a
    grime = np.clip(0.6 + 0.6 * gnoise((H, W), 22, rng), 0, 1.3)
    col *= (1 - 0.07 * band2 * grime - 0.05 * band1 * (1 - scuff))[..., None]
    col *= (1 + 0.16 * band1 * facing)[..., None]
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    for (cx, cy, rad) in crushed:
        k = np.clip(1 - np.hypot(X - cx, Y - cy) / rad, 0, 1) ** 1.5
        col *= (1 - 0.18 * k * (0.7 + 0.3 * gnoise((H, W), 2, rng)))[..., None]
        height -= k * 1.5
    if tear is not None:
        cx, cy, rx, ry, ang = tear
        ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        u = ((X - cx) * ca + (Y - cy) * sa) / rx
        v = (-(X - cx) * sa + (Y - cy) * ca) / ry
        blob = 1 - (u * u + v * v) + 0.22 * gnoise((H, W), 2.2, rng) + 0.12 * gnoise((H, W), 0.8, rng)
        m = smoothstep(0.0, 0.18, blob) * (d < 1)
        rim = np.clip(smoothstep(-0.12, 0.0, blob) - m, 0, 1)
        flute = np.sin(2 * math.pi * X / 9.4)
        inner = lin(hexrgb('#B98D58')) * (1 + 0.16 * flute - 0.10 * np.cos(2 * math.pi * X / 9.4))[..., None]
        inner = inner * (1 + 0.05 * gnoise((H, W), 0.8, rng))[..., None]
        col = col * (1 - m[..., None]) + inner * m[..., None]
        col = col * (1 - 0.6 * rim[..., None]) + lin(hexrgb('#E6D2AE')) * 0.6 * rim[..., None]
        sh = np.clip(ndi.shift(m, (-1.5, -1.0), order=1) - m, 0, 1)
        col *= (1 - 0.25 * sh)[..., None]
        height -= m * 1.2
    return col, height


def score_line(col, height, x0, x1, y, seed, dash=11, gap=7, depth=1.0, dark=0.30):
    """kraftbake.score_line: dashed score pressed into the board."""
    rng = np.random.default_rng(seed)
    H, W = col.shape[:2]
    x = x0 + rng.uniform(0, 3)
    img = Image.new('L', (W * 4, H * 4), 0)
    dr = ImageDraw.Draw(img)
    while x < x1:
        L = dash + rng.normal(0, 0.8)
        yy = y + rng.normal(0, 0.25)
        dr.rounded_rectangle([x * 4, (yy - 1.1) * 4, min(x1, x + L) * 4, (yy + 1.1) * 4], radius=4, fill=255)
        x += L + gap + rng.normal(0, 0.6)
    m = np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255
    height = height - depth * ndi.gaussian_filter(m, 0.6)
    lip = np.clip(ndi.shift(ndi.gaussian_filter(m, 0.8), (1.6, 0.4), order=1) - m, 0, 1)
    col = col * (1 - dark * m)[..., None] * (1 + 0.10 * lip)[..., None]
    return col, height


def contact_shadow_alpha(alpha, contact=(1.0, 3.0, 2.0, 0.62), ambient=(0.0, 12.0, 16.0, 0.20)):
    """kraftbake.contact_shadow as a shadow strength map (darken factor = 1 - s)."""
    s = np.zeros_like(alpha)
    for dx, dy, sig, k in (contact, ambient):
        s = 1 - (1 - s) * (1 - k * ndi.gaussian_filter(ndi.shift(alpha, (dy, dx), order=1), sig))
    return s


def crepe_tape(w, h, seed, color_hex='#E6D9B0', angle=-1.2, pad=14):
    """kraftbake.crepe_tape: crepe masking tape torn at both ends -> (colour_lin, alpha, lift), rotated."""
    rng = np.random.default_rng(seed)
    Wt, Ht = int(w + 2 * pad), int(h + 2 * pad)
    Y, X = np.mgrid[0:Ht, 0:Wt].astype(np.float32)

    def tear_line(x_base, slope):
        n1 = gnoise((Ht, 1), (3.2, 0), rng)[:, 0] * 2.6
        n2 = gnoise((Ht, 1), (0.9, 0), rng)[:, 0] * 0.9
        return x_base + slope * (np.arange(Ht) - Ht / 2) + n1 + n2
    xl = tear_line(pad + rng.uniform(-1, 2), rng.uniform(-0.12, 0.12))
    xr = tear_line(pad + w + rng.uniform(-2, 1), rng.uniform(-0.12, 0.12))
    yt = pad + 0.35 * gnoise((1, Wt), (0, 6), rng)[0]
    yb = pad + h + 0.35 * gnoise((1, Wt), (0, 6), rng)[0]
    dx = np.minimum(X - xl[:, None], xr[:, None] - X)
    dy = np.minimum(Y - yt[None, :], yb[None, :] - Y)
    a = np.clip(dx + 0.5, 0, 1) * np.clip(dy + 0.5, 0, 1)
    img = Image.new('L', (Wt * 3, Ht * 3), 0)
    dr = ImageDraw.Draw(img)
    for xs, sgn in ((xl, -1), (xr, 1)):
        for _ in range(int(h * 0.55)):
            yy = rng.uniform(pad + 1, pad + h - 1)
            x0 = xs[int(yy)]
            L = rng.lognormal(math.log(2.6), 0.5)
            an = math.radians(rng.normal(0, 35))
            dr.line([(x0 * 3, yy * 3), ((x0 + sgn * L * math.cos(an)) * 3, (yy + L * math.sin(an)) * 3)],
                    fill=int(rng.uniform(90, 200)), width=1)
    hairs = np.asarray(img.resize((Wt, Ht), Image.LANCZOS), np.float32) / 255
    shear = 6 * gnoise((Ht, Wt), (30, 30), rng)
    crink = (ndi.map_coordinates(gnoise((Ht, Wt), (5, 0.55), rng), [Y, np.clip(X + shear * 0.15, 0, Wt - 1)], order=1) * 0.55
             + gnoise((Ht, Wt), (1.6, 1.1), rng) * 0.45)
    mott = gnoise((Ht, Wt), 9, rng)
    endzone = smoothstep(5, 0, dx)
    alpha = a * np.clip(0.90 + 0.04 * crink + 0.025 * mott - 0.20 * endzone, 0, 1)
    alpha = np.maximum(alpha, hairs * 0.5)
    shade = shade_from_height(crink * 0.7 + 1.2 * mott, 1.0, 0.5)
    col = np.empty((Ht, Wt, 3), np.float32)
    col[:] = lin(hexrgb(color_hex))
    col *= (1 + 0.34 * shade + 0.03 * mott)[..., None]
    col *= (1 + 0.05 * smoothstep(1.5, 0, dy) * np.sign(np.gradient(Y)[0]))[..., None]
    lift = endzone * a

    def rot(arr, order=1):
        return ndi.rotate(arr, -angle, reshape=False, order=order, mode='constant', cval=0)
    col = np.stack([rot(col[..., i]) for i in range(3)], -1)
    alpha = np.clip(rot(alpha), 0, 1)
    lift = np.clip(rot(lift), 0, 1)
    return col, alpha, lift


# ================================================================ glyph metrics helper
def ink_box(m, thr=0.12):
    ys, xs = np.nonzero(m > thr)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
