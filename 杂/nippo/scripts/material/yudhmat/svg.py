"""Minimal rasteriser for the stencil-art SVGs (src/creatures, src/poses, src/egypt): every shape there is a filled
<path> of absolute M / L / Z polygons inside <g id="…" fill-rule="evenodd">.  Even-odd per path element, union across
path elements, supersampled 4x and box-filtered — no Chromium needed."""
import re

import numpy as np
from PIL import Image, ImageChops, ImageDraw

_G = re.compile(r'<g id="([^"]+)"[^>]*>(.*?)</g>', re.S)
_D = re.compile(r'<path[^>]*\sd="([^"]+)"')
_T = re.compile(r'[MLZmlz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?')


def parse(path):
    """-> (viewBox w, h, {group id: [path = [subpath = [(x, y), …]]]})"""
    s = open(path).read()
    vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', s).group(1).split()]
    groups = {}
    for gid, body in _G.findall(s):
        paths = []
        for d in _D.findall(body):
            subs, cur, toks, i = [], [], _T.findall(d), 0
            while i < len(toks):
                t = toks[i]
                if t in 'Mm':
                    if cur:
                        subs.append(cur)
                    cur = [(float(toks[i + 1]), float(toks[i + 2]))]
                    i += 3
                elif t in 'Ll':
                    cur.append((float(toks[i + 1]), float(toks[i + 2])))
                    i += 3
                elif t in 'Zz':
                    if cur:
                        subs.append(cur)
                    cur = []
                    i += 1
                else:                       # implicit lineto
                    cur.append((float(toks[i]), float(toks[i + 1])))
                    i += 2
            if cur:
                subs.append(cur)
            paths.append(subs)
        groups[gid] = paths
    return vb[2], vb[3], groups


def raster(paths, W, H, scale, ox=0.0, oy=0.0, flip_w=None, ss=4):
    """Rasterise into a W x H px float mask: pixel = (x * scale + ox, y * scale + oy); flip_w mirrors x within
    [0, flip_w] art units first."""
    acc = Image.new('1', (W * ss, H * ss), 0)
    for subs in paths:
        pm = Image.new('1', (W * ss, H * ss), 0)
        for sp in subs:
            if len(sp) < 3:
                continue
            one = Image.new('1', (W * ss, H * ss), 0)
            pts = [(((flip_w - x) if flip_w else x) * scale + ox, y * scale + oy) for x, y in sp]
            ImageDraw.Draw(one).polygon([(x * ss, y * ss) for x, y in pts], fill=1)
            pm = ImageChops.logical_xor(pm, one)
        acc = ImageChops.logical_or(acc, pm)
    a = np.asarray(acc.convert('L'), np.float32).reshape(H, ss, W, ss).mean((1, 3)) / 255
    return a


def ink_box(m, thr=0.5):
    ys, xs = np.nonzero(m > thr)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
