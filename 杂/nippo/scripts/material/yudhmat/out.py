"""Output registry: writes @2x PNGs into Resources/Material, optimises them, and builds manifest.json.

manifest.json (schema v1, agreed with the Swift loader — Sources/NippoApp/Baked.swift BakedManifest):
  version, scale
  assets: {id: {file, kind: tile|slice|sprite, size [w,h] pt (whole image), bleed [t,l,b,r] pt outside the layout rect,
                insets [t,l,b,r] pt from the image edge (slice only), anchor [x,y] pt (sprite, optional),
                baseline / capHeight pt (word sprites), purpose,
                ink [x0,y0,x1,y1] pt + contour [32 × x|null] pt (creature-<day>-grey, -grey-m, -grey-s = ink ≈ 180 /
                145 / 114pt: each in its OWN layout-rect coordinates; contour[i] = leftmost stencil ink in the i-th of
                32 equal horizontal bands of the layout rect, top to bottom),
                frames / durationMs (motion sequences), mask true (motion masks: 8-bit GREY PNG at 1×, white = paint
                present, no alpha — file `<id>.png`, pixel size = `size`), origin (frieze), ground (informative)}}
  glyphs: {set: {file, pt, lineHeight [ascent, descent] pt, capTop pt (cell top -> cap top), capHeight pt (cap top ->
                 baseline), glyphs {ch: {rect [x,y,w,h] px, advance pt, bearing pt, inkRight pt (pen -> right edge of
                 the stencil ink, overspray excluded)}}}}
(v12.1: the `words` alias table is gone — use the asset ids.)
"""
import io
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

try:
    import oxipng
except ImportError:          # optional: plain zlib level 9 without it
    oxipng = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
DEST = os.path.join(ROOT, 'Resources', 'Material')
ASSETS, GLYPHS, LOG = {}, {}, {}
OPTIMISE = True
RETIRED = set()          # ids a group no longer bakes (removed from a merged manifest + their PNG deleted)


def _png_bytes(im, keep_format=False):
    """keep_format: oxipng may only re-filter / re-deflate (an 8-bit grey mask stays 8-bit grey, never 1-bit / palette)."""
    b = io.BytesIO()
    im.save(b, 'PNG', optimize=True, compress_level=9)
    data = b.getvalue()
    if oxipng is not None and OPTIMISE:
        kw = dict(bit_depth_reduction=False, color_type_reduction=False, palette_reduction=False,
                  grayscale_reduction=False) if keep_format else {}
        data = oxipng.optimize_from_memory(data, level=4, strip=oxipng.StripChunks.safe(), **kw)
    return data


def _lowpass_err(a, b, alpha=True):
    """Visible error of a dithered palette version: premultiplied sRGB difference after a 1.2 px blur."""
    a = a.astype(np.float32) / 255
    b = b.astype(np.float32) / 255
    if alpha:
        a = np.dstack([a[..., :3] * a[..., 3:4], a[..., 3:4]])
        b = np.dstack([b[..., :3] * b[..., 3:4], b[..., 3:4]])
    d = np.stack([ndi.gaussian_filter(a[..., i] - b[..., i], 1.2) for i in range(a.shape[-1])], -1)
    return float(np.abs(d).mean() * 255), float(np.percentile(np.abs(d), 99.9) * 255)


def kquant(arr, k, seed=1, nsamp=40000):
    """Palette PNG via k-means in premultiplied RGBA (exact transparent index 0, no dithering: the paint / concrete
    noise is its own dither).  Returns (P image with tRNS, decoded RGBA for the error check)."""
    from scipy.cluster.vq import kmeans2
    from scipy.spatial import cKDTree
    H, W = arr.shape[:2]
    f = arr.astype(np.float32) / 255
    if arr.shape[-1] == 3:
        f = np.dstack([f, np.ones((H, W, 1), np.float32)])
    pm = np.dstack([f[..., :3] * f[..., 3:], f[..., 3:]]).reshape(-1, 4)
    vis = pm[:, 3] > 0
    rng = np.random.default_rng(seed)
    idx = np.nonzero(vis)[0]
    samp = pm[rng.choice(idx, size=min(len(idx), nsamp), replace=False)].astype(np.float64)
    kk = min(k - 1, len(np.unique(samp, axis=0)))
    cb, _ = kmeans2(samp, kk, iter=10, minit='++', seed=rng)
    cb = np.vstack([np.zeros((1, 4)), cb])
    _, ix = cKDTree(cb).query(pm)
    ix[~vis] = 0
    pa = np.clip(cb[:, 3], 0, 1)
    prgb = np.clip(cb[:, :3] / np.maximum(pa[:, None], 1e-6), 0, 1)
    im = Image.fromarray(ix.reshape(H, W).astype(np.uint8), 'P')
    im.putpalette((prgb * 255 + 0.5).astype(np.uint8).ravel().tolist())
    trns = bytes((pa * 255 + 0.5).astype(np.uint8).tolist())
    im.info['transparency'] = trns
    back = np.concatenate([(prgb * 255 + 0.5).astype(np.uint8)[ix], (pa * 255 + 0.5).astype(np.uint8)[ix][:, None]], 1).reshape(H, W, 4)
    return im, back


def encode(arr, palette='auto'):
    """uint8 HxWx3|4 -> (png bytes, mode).  'auto': the smallest k-means palette (64…255 colours) whose blurred
    error stays below 0.3/255 mean and 2.5/255 at the 99.9th percentile ("lossless enough"), if smaller than
    truecolour; else truecolour.  Everything goes through oxipng when available."""
    alpha = arr.shape[-1] == 4
    im = Image.fromarray(arr, 'RGBA' if alpha else 'RGB')
    full = _png_bytes(im)
    kind = 'rgba' if alpha else 'rgb'
    if palette is False or not OPTIMISE:
        return full, kind
    ref = arr if alpha else np.dstack([arr, np.full(arr.shape[:2] + (1,), 255, np.uint8)])
    last = None
    for k in (64, 96, 128, 192, 256):
        q, back = kquant(arr, k)
        mean, p999 = _lowpass_err(ref, back, True)
        last = (mean, p999)
        if mean < 0.3 and p999 < 2.5:
            b = io.BytesIO()
            q.save(b, 'PNG', optimize=True, transparency=q.info['transparency'])
            data = b.getvalue()
            if oxipng is not None:
                data = oxipng.optimize_from_memory(data, level=4, strip=oxipng.StripChunks.safe())
            if len(data) < len(full):
                return data, f'palette{k} {mean:.2f}/{p999:.1f}'
            break
    return full, f'{kind} (palette {last[0]:.2f}/{last[1]:.1f})'


def _r(v):
    return round(float(v), 2)


def save(aid, arr, kind, purpose, bleed=(0, 0, 0, 0), insets=None, anchor=None, palette='auto', **extra):
    """aid = asset id = file name without '@2x.png'.  bleed / insets / anchor in pt."""
    assert kind in ('tile', 'slice', 'sprite')
    os.makedirs(DEST, exist_ok=True)
    data, mode = encode(arr, palette)
    fn = f'{aid}@2x.png'
    with open(os.path.join(DEST, fn), 'wb') as f:
        f.write(data)
    H, W = arr.shape[:2]
    e = dict(file=fn, kind=kind, size=[_r(W / 2), _r(H / 2)], bleed=[_r(v) for v in bleed])
    if kind == 'slice':
        assert insets is not None and all(i >= b - 1e-6 for i, b in zip(insets, bleed)), (aid, insets, bleed)
        assert insets[0] + insets[2] < H / 2 and insets[1] + insets[3] < W / 2, (aid, insets, W / 2, H / 2)
        e['insets'] = [_r(v) for v in insets]
    if anchor is not None:
        e['anchor'] = [_r(v) for v in anchor]
    for k, v in extra.items():
        e[k] = ([None if x is None else _r(x) for x in v] if isinstance(v, (list, tuple))
                else (_r(v) if isinstance(v, float) else v))
    e['purpose'] = purpose
    ASSETS[aid] = e
    LOG[aid] = (len(data), mode)
    return e


def save_mask(aid, m2x, purpose, bleed=(0, 0, 0, 0), **extra):
    """Motion reveal mask: float coverage map at @2x -> 8-bit GREY PNG at 1× (2×2 box average = the exact coverage of
    each 1pt pixel; always 8-bit colour type 0, even a constant frame), no alpha; white = the final asset's paint is already there.  File `<id>.png`; manifest entry
    `mask: true`, `size` = pixel size = pt.  Grey value = alpha straight (not gamma-encoded): luminanceToAlpha in the
    gamma working space gives back the coverage."""
    os.makedirs(DEST, exist_ok=True)
    H2, W2 = m2x.shape
    assert H2 % 2 == 0 and W2 % 2 == 0, (aid, m2x.shape)
    m = np.clip(m2x, 0, 1).astype(np.float32).reshape(H2 // 2, 2, W2 // 2, 2).mean((1, 3))
    g8 = (m * 255 + 0.5).astype(np.uint8)
    data = _png_bytes(Image.fromarray(g8, 'L'), keep_format=True)
    fn = f'{aid}.png'
    with open(os.path.join(DEST, fn), 'wb') as f:
        f.write(data)
    H, W = g8.shape
    e = dict(file=fn, kind='sprite', size=[_r(W), _r(H)], bleed=[_r(v) for v in bleed], mask=True)
    for k, v in extra.items():
        e[k] = ([None if x is None else _r(x) for x in v] if isinstance(v, (list, tuple))
                else (_r(v) if isinstance(v, float) else v))
    e['purpose'] = purpose
    ASSETS[aid] = e
    LOG[aid] = (len(data), 'grey 1x')
    return e


def glyph_set(sid, aid, arr, pt, line_height, glyphs, purpose, cap=None):
    """One atlas PNG per glyph set; glyphs = {ch: dict(rect=[x,y,w,h] px, advance=pt, bearing=pt, inkRight=pt)};
    cap = (capTop, capHeight) pt, measured from the cell top at nominal size (capTop + capHeight = ascent)."""
    os.makedirs(DEST, exist_ok=True)
    data, mode = encode(arr)
    fn = f'{aid}@2x.png'
    with open(os.path.join(DEST, fn), 'wb') as f:
        f.write(data)
    e = dict(file=fn, pt=pt, lineHeight=[_r(v) for v in line_height])
    if cap is not None:
        e['capTop'], e['capHeight'] = _r(cap[0]), _r(cap[1])
    e['glyphs'] = {c: dict(rect=[int(v) for v in g['rect']], advance=_r(g['advance']), bearing=_r(g['bearing']),
                           inkRight=_r(g['inkRight']))
                   for c, g in glyphs.items()}
    e['purpose'] = purpose
    GLYPHS[sid] = e
    LOG[aid] = (len(data), mode)


def total_bytes():
    return sum(v[0] for v in LOG.values())


def _remove(fn):
    fp = os.path.join(DEST, fn)
    if os.path.exists(fp):
        os.remove(fp)


def write_manifest(merge=False, drop=()):
    """merge=True (a partial --only run): keep the other groups' entries of the existing manifest, except the ids a
    group retired (`drop`, whose PNGs are deleted too).  An id whose file name changed (a mask moved from
    `<id>@2x.png` to `<id>.png`) loses its old file.  A full run (merge=False) deletes every PNG in Resources/Material
    the new manifest does not reference."""
    a, g = {}, {}
    path = os.path.join(DEST, 'manifest.json')
    old = json.load(open(path)) if os.path.exists(path) else {}
    if merge:
        a, g = dict(old.get('assets', {})), dict(old.get('glyphs', {}))
    for aid in drop:
        a.pop(aid, None)
        if aid not in ASSETS:
            _remove(f'{aid}@2x.png')
            _remove(f'{aid}.png')
    for aid, e in ASSETS.items():
        prev = old.get('assets', {}).get(aid)
        if prev and prev.get('file') != e['file']:
            _remove(prev['file'])
    a.update(ASSETS)
    g.update(GLYPHS)
    m = dict(version=1, scale=2,
             assets={k: a[k] for k in sorted(a)},
             glyphs={k: g[k] for k in sorted(g)})
    tmp = path + f'.{os.getpid()}.tmp'          # atomic: a parallel --only run never reads a half-written file
    with open(tmp, 'w') as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
        f.write('\n')
    os.replace(tmp, path)
    if not merge:
        keep = {e['file'] for e in m['assets'].values()} | {e['file'] for e in m['glyphs'].values()}
        for fn in os.listdir(DEST):
            if fn.endswith('.png') and fn not in keep:
                os.remove(os.path.join(DEST, fn))
    return m
