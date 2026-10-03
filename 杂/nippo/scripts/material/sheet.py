#!/usr/bin/env python3
"""Review contact sheet for Resources/Material (NOT shipped; writes wherever you point it).

    python3 scripts/material/sheet.py /tmp/material-sheet.png          # full sheet
    python3 scripts/material/sheet.py /tmp/x.png --ids hero-calm-night stamp-nice-night --scale 2   # quick look

Compositing is plain sRGB-space alpha "over" with 9-slice stretching — what Core Animation / SwiftUI does — so the
sheet shows the assets the way the app will draw them.
"""
import argparse
import json
import os
import sys

sys.dont_write_bytecode = True

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.abspath(os.path.join(HERE, '..', '..', 'Resources', 'Material'))
BG = (22, 23, 25)
_F = {}


def font(size, bold=False):
    key = (size, bold)
    if key not in _F:
        for p in (['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'] if bold else []) + \
                ['/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
            try:
                _F[key] = ImageFont.truetype(p, size)
                break
            except OSError:
                continue
        else:
            _F[key] = ImageFont.load_default()
    return _F[key]


class M:
    def __init__(self):
        self.m = json.load(open(os.path.join(DEST, 'manifest.json')))
        self.cache = {}

    def img(self, aid):
        if aid not in self.cache:
            e = self.m['assets'].get(aid) or self.m['glyphs'][aid]
            self.cache[aid] = np.asarray(Image.open(os.path.join(DEST, e['file'])).convert('RGBA'), np.float32) / 255
        return self.cache[aid]

    def e(self, aid):
        return self.m['assets'][aid]


def nine(a, insets_pt, w_px, h_px, scale=2):
    """Stretch an RGBA float image to w x h px with 9-slice caps (pt, from the image edge)."""
    H, W = a.shape[:2]
    t, l, b, r = (int(round(v * scale)) for v in insets_pt)
    if w_px < l + r:
        l, r = w_px // 2, w_px - w_px // 2
    if h_px < t + b:
        t, b = h_px // 2, h_px - h_px // 2
    xs = [(0, l, 0, l), (l, W - r, l, w_px - r), (W - r, W, w_px - r, w_px)]
    ys = [(0, t, 0, t), (t, H - b, t, h_px - b), (H - b, H, h_px - b, h_px)]
    out = np.zeros((h_px, w_px, 4), np.float32)
    for sy0, sy1, dy0, dy1 in ys:
        for sx0, sx1, dx0, dx1 in xs:
            if sy1 <= sy0 or sx1 <= sx0 or dy1 <= dy0 or dx1 <= dx0:
                continue
            piece = a[sy0:sy1, sx0:sx1]
            if piece.shape[:2] != (dy1 - dy0, dx1 - dx0):
                pm = np.dstack([piece[..., :3] * piece[..., 3:], piece[..., 3:]])
                pm = np.stack([np.asarray(Image.fromarray(pm[..., i]).resize((dx1 - dx0, dy1 - dy0), Image.BILINEAR))
                               for i in range(4)], -1)
                piece = np.dstack([pm[..., :3] / np.maximum(pm[..., 3:], 1e-6), pm[..., 3:]])
            out[dy0:dy1, dx0:dx1] = piece
    return np.clip(out, 0, 1)


def scaled(a, f):
    if f == 1:
        return a
    H, W = a.shape[:2]
    pm = np.dstack([a[..., :3] * a[..., 3:], a[..., 3:]])
    sz = (max(1, int(round(W * f))), max(1, int(round(H * f))))
    pm = np.stack([np.asarray(Image.fromarray(pm[..., i]).resize(sz, Image.LANCZOS if f < 1 else Image.BILINEAR))
                   for i in range(4)], -1)
    pm = np.clip(pm, 0, 1)
    return np.dstack([pm[..., :3] / np.maximum(pm[..., 3:], 1e-6), pm[..., 3:]])


def over(dst, src, x, y):
    """dst float RGB (H,W,3); src float RGBA; x, y px (top-left, may be fractional -> rounded)."""
    x, y = int(round(x)), int(round(y))
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]
    a = s[..., 3:]
    dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - a) + s[..., :3] * a


def tile_fill(dst, tile, x0, y0, x1, y1, ox=None, oy=None, mask=None):
    """Tile an RGB(A) image over a rect (tiling phase from ox, oy); optional float mask (rect-sized)."""
    ox = x0 if ox is None else ox
    oy = y0 if oy is None else oy
    th, tw = tile.shape[:2]
    ys = (np.arange(y0, y1) - oy) % th
    xs = (np.arange(x0, x1) - ox) % tw
    t = tile[ys][:, xs][..., :3]
    if mask is None:
        dst[y0:y1, x0:x1] = t
    else:
        m = mask[..., None]
        dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - m) + t * m


def rrect_mask(w, h, r, ss=4):
    img = Image.new('L', (w * ss, h * ss), 0)
    ImageDraw.Draw(img).rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius=r * ss, fill=255)
    return np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255


def text(dst, xy, s, size=20, fill=(220, 222, 224), bold=False):
    im = Image.fromarray((np.clip(dst, 0, 1) * 255 + 0.5).astype(np.uint8))
    ImageDraw.Draw(im).text(xy, s, font=font(size, bold), fill=fill)
    dst[:] = np.asarray(im, np.float32) / 255


def quick(path, ids, scale=2, bg=BG):
    mm = M()
    imgs = [scaled(mm.img(i), scale / 2) for i in ids]
    pad = 24
    W = sum(a.shape[1] for a in imgs) + pad * (len(imgs) + 1)
    H = max(a.shape[0] for a in imgs) + 2 * pad + 30
    dst = np.zeros((H, W, 3), np.float32)
    dst[:] = np.array(bg) / 255
    x = pad
    for i, a in zip(ids, imgs):
        over(dst, a, x, pad + 30)
        text(dst, (x, 6), i, 16)
        x += a.shape[1] + pad
    Image.fromarray((dst * 255 + 0.5).astype(np.uint8)).save(path)


def build(path):
    import sheet_full
    sheet_full.build(path, M())


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--ids', nargs='*')
    ap.add_argument('--scale', type=float, default=2)
    a = ap.parse_args()
    if a.ids:
        quick(a.out, a.ids, a.scale)
    else:
        build(a.out)
