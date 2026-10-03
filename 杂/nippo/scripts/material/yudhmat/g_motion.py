"""Motion frames (V4 §2.7, merge2/motion: motion.png + mb_core / mb_today / mb_english).  Every moving moment is
baked: SwiftUI only swaps these frames, masks, offsets, rotates and fades.

Two kinds of output:
  * reveal MASKS (8-bit GREY PNG at 1×, no alpha, `mask: true`; kind "sprite"): grey = the share of the FINAL
    asset's paint that is already on the wall at that frame (mb_core.rel_mask: coverage now / coverage at the end),
    white = all of it.  Computed at @2x like everything else, then 2×2 box-averaged to 1pt pixels (pixel size = pt
    size incl. bleed: a fifth of the decoded memory of an @2x RGBA mask).  Use them as `.luminanceToAlpha()` `.mask`
    on the final asset, drawn at the same frame (same size + bleed); the last frame is fully white, so
    final.mask(last) is the final asset pixel for pixel, and the hold frame needs no mask.
      flood-teal-0…7     hero-event-night over the calm card (teal flood out of the numerals)
      flood-orange-0…7   hero-zero-night over the event card (orange seeps out of the 00 bridges, then floods)
      drip-grow-0…3      any drip-<paint>-n, scaled to the drip's box (gravity growth, meniscus front)
      stamp-mask-0…3     stamp-nice-night / stamp-miss-night (one set, both rotations; the NICE! drip box is held
                         back for drip-grow, see `dripBox`)
      badge-mask-0…3     badge-plate-night
  * SPRITES: stamp-<nice|miss>-sheet (the hand-cut kraft stencil over the stamp box), rate-30-<kind>-mist (the
    first pass on a round-board cell), cover-sheet-night + cover-sheet-corner-night (masking paper over the panel on
    the first open of the day, 9-slice, centre band tile-safe).

The flood masks are a time-resolved spray (mb_core.spray_seq / front_masks): an arrival field from the source
(numerals / stencil bridges) pushed around by low-frequency noise and by the gun's strokes (fingers along the
stroke centres), two passes that build the film up (thin, banded front; thick behind), a faint haze and droplets
that land ahead of the front.  Droplets OUTSIDE the slab are revealed one by one (each real droplet of the final
asset, as its own connected component) when the front reaches them; badge / stamps replay the exact strokes and
droplets of their bakes (g_paint.badge_plate, g_stencil.stamp: same seeds, same draw order).
"""
import math
import os
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from . import bake, ext, glyph, out
from .bake import gnoise, hexrgb, lin, shade_from_height, smoothstep
from .g_concrete import ground_hex
from .g_paint import border_fade

S = 2
HERO = (472, 270)                      # V4 §3: hero layout 472×270 (actual 250–300)
HERO_BLEED = (14, 14, 30, 24)          # hero-event-night / hero-zero-night bleed (t, l, b, r) pt
NUM_X, NUM_CAP_TOP = 20, 122           # big numerals: pen x / cap top in the 270pt card (two-line title)
NOTES = []


# ================================================================ helpers
def ease(x1, y1, x2, y2):
    """cubic-bezier(x1, y1, x2, y2) as a function of x."""
    def f(p):
        p = min(1.0, max(0.0, float(p)))
        lo, hi = 0.0, 1.0
        for _ in range(48):
            t = (lo + hi) / 2
            x = 3 * x1 * t * (1 - t) ** 2 + 3 * x2 * t * t * (1 - t) + t ** 3
            lo, hi = (t, hi) if x < p else (lo, t)
        t = (lo + hi) / 2
        return 3 * y1 * t * (1 - t) ** 2 + 3 * y2 * t * t * (1 - t) + t ** 3
    return f


def entry(aid):
    """Manifest entry of another group's asset: this run's registry first, then the manifest on disk."""
    if aid in out.ASSETS:
        return out.ASSETS[aid]
    path = os.path.join(out.DEST, 'manifest.json')
    if os.path.exists(path):
        return json.load(open(path)).get('assets', {}).get(aid)
    return None


def load_rgba(e):
    p = os.path.join(out.DEST, e['file'])
    if not os.path.exists(p):
        return None
    return np.asarray(Image.open(p).convert('RGBA'), np.float32) / 255


def nine_alpha(a, insets_pt, W, H):
    """9-slice stretch of a float map (the way SwiftUI stretches the slice) to W x H px."""
    h0, w0 = a.shape[:2]
    t, l, b, r = (int(round(v * S)) for v in insets_pt)
    xs = [(0, l, 0, l), (l, w0 - r, l, W - r), (w0 - r, w0, W - r, W)]
    ys = [(0, t, 0, t), (t, h0 - b, t, H - b), (h0 - b, h0, H - b, H)]
    o = np.zeros((H, W) + a.shape[2:], np.float32)
    for sy0, sy1, dy0, dy1 in ys:
        for sx0, sx1, dx0, dx1 in xs:
            if sy1 <= sy0 or sx1 <= sx0 or dy1 <= dy0 or dx1 <= dx0:
                continue
            p = a[sy0:sy1, sx0:sx1]
            if p.shape[:2] != (dy1 - dy0, dx1 - dx0):
                chans = [p] if p.ndim == 2 else [p[..., i] for i in range(p.shape[2])]
                rs = [np.asarray(Image.fromarray(c.astype(np.float32), 'F').resize((dx1 - dx0, dy1 - dy0), Image.BILINEAR))
                      for c in chans]
                p = rs[0] if p.ndim == 2 else np.stack(rs, -1)
            o[dy0:dy1, dx0:dx1] = p
    return o


def hero_target(aid):
    """(bleed pt, alpha map px at the 472×270 layout) of the hero slab the flood reveals.  Reads the manifest; a hero
    not yet re-baked at 472×270 is 9-sliced to it (the masks then still fit the re-bake: same bleed / caps)."""
    e = entry(aid)
    bleed = HERO_BLEED
    if e is not None:
        bt, bl, bb, br = e['bleed']
        lw, lh = e['size'][0] - bl - br, e['size'][1] - bt - bb
        if (round(lw), round(lh)) == HERO:
            bleed = tuple(e['bleed'])
        else:
            NOTES.append(f'{aid} is {lw:g}×{lh:g}pt in the manifest (not yet re-baked to 472×270): masks assume layout '
                         f'472×270, bleed {"/".join(str(int(v)) for v in HERO_BLEED)}; re-run --only motion after it is.')
    W = int(round((bleed[1] + HERO[0] + bleed[3]) * S))
    H = int(round((bleed[0] + HERO[1] + bleed[2]) * S))
    A = None
    if e is not None:
        img = load_rgba(e)
        if img is not None:
            A = img[..., 3] if img.shape[:2] == (H, W) else nine_alpha(img[..., 3], e['insets'], W, H)
    if A is None:                                   # nothing baked yet: a plain slab
        A = np.zeros((H, W), np.float32)
        A[int(bleed[0] * S):H - int(bleed[2] * S), int(bleed[1] * S):W - int(bleed[3] * S)] = 1
    return bleed, A


def save_mask(aid, m, purpose, bleed=(0, 0, 0, 0), **extra):
    """@2x coverage map -> 8-bit grey PNG at 1× (out.save_mask: `<id>.png`, `mask: true`)."""
    return out.save_mask(aid, m, purpose, bleed=bleed, **extra)


def dot_field(shape, n, rng, rmin=0.35, rmax=2.2):
    """n droplets (x, y, r, alpha) uniformly over the canvas; radii like bake.spray (lognormal, px)."""
    H, W = shape
    x = rng.uniform(0, W, n)
    y = rng.uniform(0, H, n)
    r = np.clip(rng.lognormal(-0.25, 0.45, n), rmin, rmax)
    a = rng.uniform(0.6, 1.0, n)
    return x, y, r, a


def render_dots(shape, x, y, r, a, ss=3):
    H, W = shape
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    for xx, yy, rr, aa in zip(x, y, r, a):
        d.ellipse([(xx - rr) * ss, (yy - rr) * ss, (xx + rr) * ss, (yy + rr) * ss], fill=int(255 * aa))
    return np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255


def stroke_bands(shape, rng, angle, spacing, phase=None):
    """The gun's strokes: Gaussian bands across the stroke direction, normalised 0..1 (centres = 1)."""
    H, W = shape
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    a = math.radians(angle)
    across = -(X - W / 2) * math.sin(a) + (Y - H / 2) * math.cos(a)
    span = abs(W * math.sin(a)) + abs(H * math.cos(a))
    c0 = -span / 2 - spacing + (rng.uniform(0, spacing) if phase is None else phase)
    B = np.zeros((H, W), np.float32)
    c = c0
    while c < span / 2 + spacing:
        cc = c + rng.normal(0, spacing * 0.10)
        sig = spacing * rng.uniform(0.30, 0.40)
        B += rng.uniform(0.75, 1.15) * np.exp(-0.5 * ((across - cc) / sig) ** 2)
        c += spacing * rng.uniform(0.9, 1.1)
    lo, hi = np.percentile(B, 3), np.percentile(B, 97)
    return np.clip((B - lo) / max(hi - lo, 1e-6), 0, 1)


def arrival(src, rng, aniso=1.35, warp=(24.0, 7.0), fingers=0.22, angle=-6.0, spacing=70):
    """Distance (px) the paint front has to travel from `src` to each pixel: anisotropic (the gun sweeps sideways),
    pushed around by low-frequency noise, faster along the stroke centres (fingers) — never a geometric circle."""
    H, W = src.shape
    d = ndi.distance_transform_edt(src < 0.5, sampling=(aniso, 1.0)).astype(np.float32)
    d = d + warp[0] * gnoise((H, W), 46, rng) * smoothstep(0, 90, d) + warp[1] * gnoise((H, W), 7, rng) * smoothstep(0, 30, d)
    B = stroke_bands((H, W), rng, angle, spacing)
    d = d * (1 - fingers * (B - 0.5))
    return np.maximum(d, 0).astype(np.float32), B


def components_reveal(alpha, region, dist, lead):
    """Each droplet of the final asset outside the slab (connected component of its alpha in `region`) appears whole
    when the front gets within `lead` px of it.  Returns (labels, per-label distance) for frame tests."""
    lab, n = ndi.label((alpha > 0.03) & region)
    if n == 0:
        return lab, np.zeros(1, np.float32)
    idx = np.arange(1, n + 1)
    dmin = ndi.minimum(dist, lab, idx).astype(np.float32)
    return lab, np.concatenate([[1e9], dmin - lead[:n]])


class Flood:
    """Time-resolved flood over a slab: film from two passes + haze + droplets ahead + real droplets outside."""

    def __init__(self, alpha, rect, d, B, rng, k=2.2, lag=90.0, drops_per_px=0.007, lead_mean=26.0):
        H, W = alpha.shape
        self.H, self.W, self.d, self.k, self.lag = H, W, d, k, lag
        x0, y0, x1, y1 = rect
        slab = np.zeros((H, W), np.float32)
        slab[y0:y1, x0:x1] = 1
        self.slab = ndi.grey_dilation(slab, size=(13, 13))            # film reveal covers the cut edge + under-bleed
        self.edge = 1 - ndi.gaussian_filter(self.slab, 1.0)
        # two passes; the second interleaves with the first (bands offset by half a stroke)
        B2 = np.roll(B, int(35), axis=0)
        self.m1 = 0.58 * (1 + 0.42 * (B - 0.5))
        self.m2 = 0.52 * (1 + 0.30 * (B2 - 0.5))
        self.peel = 1 + 0.10 * gnoise((H, W), 0.9, rng) + 0.07 * gnoise((H, W), 3.5, rng)
        self.rag = 5.0 * gnoise((H, W), 1.3, rng) + 3.0 * gnoise((H, W), 4.0, rng)
        self.haze_n = 0.6 + 0.4 * smoothstep(-1, 1.5, gnoise((H, W), 2.0, rng))
        Dend = self.m1 + self.m2
        self.Cend = 1 - np.exp(-k * Dend * self.peel)
        n = int(H * W * drops_per_px)
        self.dx, self.dy, self.dr, self.da = dot_field((H, W), n, rng)
        iy = np.clip(self.dy.astype(int), 0, H - 1)
        ix = np.clip(self.dx.astype(int), 0, W - 1)
        self.dd = d[iy, ix] * (1 - 0.0 * self.da)
        self.dlead = np.minimum(rng.exponential(lead_mean, n), 120)
        inside = self.slab[iy, ix] > 0.5
        self.dx, self.dy, self.dr, self.da, self.dd, self.dlead = (v[inside] for v in
                                                                   (self.dx, self.dy, self.dr, self.da, self.dd, self.dlead))
        lead = np.minimum(rng.exponential(lead_mean * 1.2, 200000), 140).astype(np.float32)
        self.lab, self.ldist = components_reveal(alpha, self.slab < 0.5, d, lead)

    def frame(self, R1, R2=None):
        R2 = R1 - self.lag if R2 is None else R2
        S1 = smoothstep(-10, 10, R1 - self.d + self.rag)
        S2 = smoothstep(-10, 10, R2 - self.d + self.rag)
        D = self.m1 * S1 + self.m2 * S2
        C = 1 - np.exp(-self.k * D * self.peel)
        film = np.clip(C / np.maximum(self.Cend, 1e-6), 0, 1)
        haze = 0.13 * smoothstep(-30, 30, R1 + 46 - self.d) * self.haze_n
        sel = self.dd < R1 + self.dlead
        dots = render_dots((self.H, self.W), self.dx[sel], self.dy[sel], self.dr[sel], self.da[sel])
        inner = np.maximum(np.maximum(film, haze), dots) * self.slab
        drops = (self.ldist[self.lab] < R1).astype(np.float32) * (self.lab > 0)
        behind = smoothstep(-20, 20, R2 - 30 - self.d)          # anything the second pass has crossed
        outer = np.maximum(drops, behind) * (1 - self.slab)
        return np.clip(np.maximum(inner, outer), 0, 1)


def numeral_mask(W, H, text, bleed):
    """The big stencil numerals (glyph atlas, same bridges as g_stencil) where TodayNumeral draws them."""
    m, base, ctop, inkw, gap = glyph.word('big', text, bridge_em=0.06, track_em=0.03, seed=1)
    x = int(round((bleed[1] + NUM_X) * S))
    y = int(round((bleed[0] + NUM_CAP_TOP) * S)) - ctop
    o = np.zeros((H, W), np.float32)
    h, w = m.shape
    o[max(0, y):y + h, x:x + w] = m[max(0, -y):, :min(w, W - x)]
    return o, (x, y + ctop, x + inkw, y + base)


# ================================================================ ① calm -> event: teal flood
FLOOD_TEAL_MS = 340


def flood_teal():
    bleed, A = hero_target('hero-event-night')
    H, W = A.shape
    rect = (int(bleed[1] * S), int(bleed[0] * S), W - int(bleed[3] * S), H - int(bleed[2] * S))
    rng = np.random.default_rng(8801)
    src, nb = numeral_mask(W, H, '10', bleed)
    src = ndi.grey_dilation((src > 0.4).astype(np.float32), size=(7, 7))
    d, B = arrival(src, rng, aniso=1.35, warp=(26, 7), fingers=0.24, angle=rng.uniform(-9, -2), spacing=72)
    fl = Flood(A, rect, d, B, rng, k=2.2, lag=110)
    Dmax = float(d[A > 0.02].max())
    # motion.png ②: 0 青漆从模板数字往外漫开 340ms ease-out .25,.3,.4,1 — sampled inside each 42.5ms frame, the
    # first one early so it is still a halo round the numerals
    e = ease(.25, .3, .4, 1)
    starts = [round(FLOOD_TEAL_MS * i / 8) for i in range(8)]
    frames = []
    for i, t in enumerate((0.022, 0.13, 0.27, 0.42, 0.57, 0.71, 0.86)):
        frames.append(fl.frame(14 + (Dmax + 70) * e(t)))
    frames.append(np.ones((H, W), np.float32))
    box = [round(nb[0] / S - bleed[1], 1), round(nb[1] / S - bleed[0], 1), round((nb[2] - nb[0]) / S, 1),
           round((nb[3] - nb[1]) / S, 1)]
    for i, m in enumerate(frames):
        extra = dict(frames=8, durationMs=FLOOD_TEAL_MS, numeralBox=box) if i == 0 else {}
        save_mask(f'flood-teal-{i}', m,
                  f'Calm→event flood, frame {i}/7 (starts {starts[i]}ms of 340): reveal mask for hero-event-night — '
                  'apply as .mask on hero-event-night drawn over the calm card, same frame (layout 472×270 + bleed); '
                  'teal spreads out of the 10 numerals (numeralBox, card pt) with stroke fingers, a thin banded front '
                  'and droplets ahead. Frame 7 is opaque = hero-event-night exactly; hold = unmasked hero.',
                  bleed=bleed, **extra)
    return starts


# ================================================================ ② 01 -> 00: orange out of the bridges, then flood
SEEP_MS, FLOOD_ORANGE_MS = 240, 720


def flood_orange():
    bleed, A = hero_target('hero-zero-night')
    H, W = A.shape
    rect = (int(bleed[1] * S), int(bleed[0] * S), W - int(bleed[3] * S), H - int(bleed[2] * S))
    rng = np.random.default_rng(8821)
    num, nb = numeral_mask(W, H, '00', bleed)
    # the bridges of the two 0s: bake.BRIDGES['0'] = a full-height vertical cut at half the ink width (top gap,
    # counter, bottom gap); glyph i starts at pen + i * (ink + gap)
    m0, _, _, ink0, gap0 = glyph.word('big', '0', bridge_em=0.06, track_em=0.03, seed=1)
    gaps = [nb[0] + i * (ink0 + gap0) + ink0 * bake.BRIDGES['0'][0][1] for i in range(2)]
    y_top, y_bot = nb[1], nb[3]
    line = np.zeros((H, W), np.float32)
    for gx in gaps:
        line[int(y_top - 4):int(y_bot + 4), int(round(gx - 3)):int(round(gx + 4))] = 1
    pts = np.zeros((H, W), np.float32)                 # the gap mouths seep hardest
    for gx in gaps:
        for gy in (y_top + 3, y_bot - 3):
            pts[int(gy) - 3:int(gy) + 4, int(gx) - 3:int(gx) + 4] = 1
    dl = ndi.distance_transform_edt(line < 0.5, sampling=(1.15, 1.0)).astype(np.float32)
    dp = ndi.distance_transform_edt(pts < 0.5).astype(np.float32)
    ds = np.minimum(dl * 1.35, dp * 0.85)
    ds = np.maximum(0, ds + 7 * gnoise((H, W), 3.0, rng) * smoothstep(2, 14, ds)
                    + 10 * gnoise((H, W), 11, rng) * smoothstep(8, 30, ds))
    seep_r = [5.0, 14.0, 28.0]                          # px: 0–240ms, three frames (bridgeBleed .2,.7,.3,1)
    satel = dot_field((H, W), 900, rng, 0.35, 1.5)
    sd = ds[np.clip(satel[1].astype(int), 0, H - 1), np.clip(satel[0].astype(int), 0, W - 1)]
    slead = rng.uniform(3, 16, len(sd))
    frames = []
    for R in seep_r:
        core = smoothstep(-2.5, 2.5, R - ds)
        sel = sd < R + slead
        frames.append(np.maximum(core, render_dots((H, W), *(v[sel] for v in satel))))
    seeped = (ds < seep_r[-1]).astype(np.float32)
    d, B = arrival(np.maximum(seeped, line), rng, aniso=1.3, warp=(24, 7), fingers=0.24,
                   angle=rng.uniform(-9, -2), spacing=70)
    fl = Flood(A, rect, d, B, rng, k=3.2, lag=100)    # orange goes on thicker: the thin front stays orange, not mud
    Dmax = float(d[A > 0.02].max())
    e = ease(.3, 0, .2, 1)                              # floodCard 240–720, sampled inside each 96ms frame
    seep_end = frames[-1]
    for t in (0.2, 0.42, 0.62, 0.8):
        frames.append(np.maximum(seep_end, fl.frame(10 + (Dmax + 70) * e(t))))
    frames.append(np.ones((H, W), np.float32))
    starts = [round(SEEP_MS * i / 3) for i in range(3)] + [round(SEEP_MS + (FLOOD_ORANGE_MS - SEEP_MS) * j / 5) for j in range(5)]
    box = [round(nb[0] / S - bleed[1], 1), round(nb[1] / S - bleed[0], 1), round((nb[2] - nb[0]) / S, 1),
           round((nb[3] - nb[1]) / S, 1)]
    for i, m in enumerate(frames):
        extra = dict(frames=8, durationMs=FLOOD_ORANGE_MS, numeralBox=box,
                     frameStartsMs=starts) if i == 0 else {}
        what = 'orange seeps out of the stencil bridges of 00' if i < 3 else 'orange floods the card'
        save_mask(f'flood-orange-{i}', m,
                  f'01→00, frame {i}/7 (starts {starts[i]}ms of 720; 0–2 = 240ms bridge bleed, 3–7 = 480ms flood): '
                  f'reveal mask for hero-zero-night ({what}). Draw hero-zero-night masked by it between hero-event-night '
                  'and the black stencils (00 / NEXT / cells), same frame; frame 7 opaque; hold = unmasked hero.',
                  bleed=bleed, **extra)
    return starts


# ================================================================ drips: vertical growth
DRIP_MS = 200


def drip_grow():
    w, h = 20, 64
    W, H = w * S, h * S
    rng = np.random.default_rng(8841)
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (X - W / 2 + 0.5) / (W / 2)
    frac = [0.10, 0.22, 0.45]                     # ≈ gravity .55,0,1,.45 at the frame ends, the bud kept visible
    wob = 0.8 * gnoise((1, W), 2.0, rng)[0]
    starts = [round(DRIP_MS * i / 4) for i in range(4)]
    for i in range(4):
        if i < 3:
            yf = frac[i] * H
            front = yf + 4.0 * (1 - np.clip(u * u, 0, 1)) + wob[None, :]     # meniscus: the bead leads in the middle
            m = smoothstep(-1.6, 1.6, front - Y)
        else:
            m = np.ones((H, W), np.float32)
        extra = dict(frames=4, durationMs=DRIP_MS) if i == 0 else {}
        save_mask(f'drip-grow-{i}', m,
                  f'Drip growth, frame {i}/3 (starts {starts[i]}ms of 200; gravity .55,0,1,.45, hold 280ms for the '
                  'orange / stamp drips): reveal mask, top = where the drip leaves the paint. Scale the 20×64pt box to '
                  'the drip sprite\'s layout rect and use as its .mask; frame 3 opaque.', **extra)
    return starts


# ================================================================ spray replay (bake.spray, same RNG order)
def spray_replay(cut, seed, passes=4, angle=-7, sheet_pad=34, k=2.6, droplets=1.0, spits=2, reach=40):
    """Replays bake.spray()'s random draws (strokes, peel, droplets) and keeps what bake.spray throws away: each
    stroke separately and the time each droplet landed.  Returns density(f), the end density, droplets with times."""
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
    ext_ = abs(bw * nrm[0]) + abs(bh * nrm[1])
    L = abs(bw * u[0]) + abs(bh * u[1])
    mod = gnoise((H, W), 26, rng)
    strokes, starts = [], []
    for i in range(passes):
        off = ((i + 0.5) / passes - 0.5) * ext_ + rng.normal(0, ext_ * 0.05)
        sig = ext_ / passes * rng.uniform(0.75, 1.1) + 6
        s0 = -L / 2 - rng.uniform(16, 60)
        s1 = L / 2 + rng.uniform(16, 60)
        flip = rng.random() < 0.5
        if flip:
            s0, s1 = -s1, -s0
        ramp = smoothstep(s0 - 40, s0 + 30, t) * (1 - smoothstep(s1 - 30, s1 + 40, t))
        prof = np.exp(-0.5 * ((dn - off) / sig) ** 2) * ramp * (1 + 0.16 * mod) * rng.uniform(0.85, 1.15)
        # the nozzle travels s0 -> s1, or the other way for a flipped stroke
        strokes.append(dict(a=s1 if flip else s0, b=s0 if flip else s1, sig=sig, prof=prof.astype(np.float32)))
        starts.append((cx + u[0] * s0 + nrm[0] * off, cy + u[1] * s0 + nrm[1] * off))
    D_end = sum(s['prof'] for s in strokes)
    norm = D_end[cut > 0.5].mean()
    peel = 1 + 0.10 * gnoise((H, W), 0.9, rng) + 0.07 * gnoise((H, W), 3.5, rng)
    sheet = np.zeros((H, W), np.float32)
    sheet[max(0, y0 - sheet_pad):y1 + sheet_pad, max(0, x0 - sheet_pad):x1 + sheet_pad] = 1
    dist = ndi.distance_transform_edt(1 - sheet)
    p = np.clip(D_end / norm * (1 - sheet), 0, None) ** 1.3 * np.exp(-dist / reach)
    total = p.sum()
    drops = []
    if total > 0 and droplets > 0:
        n = int(min(60000, total * 0.022 * droplets))
        idx = rng.choice(H * W, size=n, p=(p / total).ravel())
        py, px = np.divmod(idx, W)
        rad = np.clip(rng.lognormal(-0.45, 0.45, n), 0.35, 2.2)
        alp = rng.uniform(0.55, 1.0, n)
        jy, jx = py + rng.random(n), px + rng.random(n)
        best = np.argmax(np.stack([s['prof'][py, px] for s in strokes]), 0)
        tt = t[py, px]
        times = np.empty(n, np.float32)
        for i, s in enumerate(strokes):
            sel = best == i
            q = np.clip((tt[sel] - s['a']) / (s['b'] - s['a']), 0, 1)
            times[sel] = (i + q) / passes
        drops = list(zip(jx, jy, rad, alp, times))
    for i, (sx, sy) in enumerate(starts[:spits]):
        for _ in range(rng.integers(1, 3)):
            r = rng.uniform(2.2, 4.2)
            xx, yy = sx + rng.normal(0, 14), sy + rng.normal(0, 10)
            if 0 < xx < W and 0 < yy < H and sheet[int(min(H - 1, max(0, yy))), int(min(W - 1, max(0, xx)))] < 0.5:
                drops.append((xx, yy, r, 1.0, i / passes + 0.01))

    def density(f):
        D = np.zeros((H, W), np.float32)
        for i, s in enumerate(strokes):
            q = float(np.clip(f * passes - i, 0, 1))
            if q <= 0:
                continue
            if q >= 1:
                D += s['prof']
                continue
            pos = s['a'] + (s['b'] - s['a']) * q
            w = max(8.0, s['sig'] * 0.8)
            win = 1 - smoothstep(pos - w, pos + w, t) if s['b'] > s['a'] else smoothstep(pos - w, pos + w, t)
            D += s['prof'] * win
        return D / norm
    return dict(density=density, D_end=D_end / norm, peel=peel, drops=drops, sheet=sheet, k=k)


def replay_reveal(rp, f, alpha, slab, k, shape):
    """Reveal (0..1) of a replayed spray at fraction f: film coverage now / at the end inside the slab, droplets
    whole once the nozzle passed them, plus everything the stroke has fully covered outside."""
    H, W = shape
    D, De = rp['density'](f), rp['D_end']
    C = 1 - np.exp(-k * D * rp['peel'])
    Ce = 1 - np.exp(-k * De * rp['peel'])
    film = np.clip(C / np.maximum(Ce, 1e-6), 0, 1)
    sel = [dd for dd in rp['drops'] if dd[4] <= f]
    if sel:
        xx, yy, rr, aa, _ = (np.array(v) for v in zip(*sel))
        dots = render_dots((H, W), xx, yy, rr, np.ones_like(aa), ss=3)
        dots = np.clip(dots * 1.6, 0, 1)
    else:
        dots = np.zeros((H, W), np.float32)
    frac = np.clip(D / np.maximum(De, 1e-3), 0, 1)
    out_ = np.maximum(dots, smoothstep(0.75, 0.98, frac))
    return np.clip(film * slab + out_ * (1 - slab), 0, 1)


# ================================================================ ③ NICE! / MISS: stencil sheet + spray masks
STAMP = dict(nice=dict(seed=5600, ang=-7, paint='orange', side=-17), miss=dict(seed=5620, ang=5, paint='grey', side=-17))
STAMP_BOX, STAMP_BLEED = (150, 60), 26
STAMP_MS = dict(nice=130, miss=160)


def stamp_replay(kind):
    """g_stencil.stamp(kind) up to the block spray: same canvas, same rng draws -> the block cut + stroke replay."""
    k = STAMP[kind]
    bw, bh = STAMP_BOX[0] * S, STAMP_BOX[1] * S
    W, H = bw + 2 * STAMP_BLEED * S, bh + 2 * STAMP_BLEED * S
    x0 = y0 = STAMP_BLEED * S
    cx, cy = x0 + bw / 2, y0 + bh / 2
    rng = np.random.default_rng(k['seed'])
    block = ext.rotate_mask(ext.rect_mask(W, H, x0, y0, x0 + bw, y0 + bh, rng, 0.9), k['ang'], cx, cy)
    angle = k['ang'] + rng.uniform(-8, 8)
    rp = spray_replay(block, k['seed'] + 2, passes=3, angle=angle, sheet_pad=8, k=2.5, droplets=0.55, spits=1, reach=9)
    return block, rp, (W, H, cx, cy)


def stamp_masks():
    reps = {kind: stamp_replay(kind) for kind in STAMP}
    W, H, cx, cy = reps['nice'][2]
    union = np.maximum(reps['nice'][0], reps['miss'][0])
    slab = ndi.grey_dilation((union > 0.05).astype(np.float32), size=(9, 9))
    # the NICE! drip (baked into stamp-nice-night below the block): held back for drip-grow
    drip_box = None
    e = entry('stamp-nice-night')
    img = load_rgba(e) if e else None
    if img is not None and img.shape[:2] == (H, W):
        blk = ndi.grey_dilation((reps['nice'][0] > 0.3).astype(np.uint8), size=(7, 7))
        lab, n = ndi.label((img[..., 3] > 0.45) & (blk == 0))
        best = None
        for sl in ndi.find_objects(lab):
            hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
            if hh >= 12 and ww <= 30 and (best is None or hh > best[0]):
                best = (hh, sl)
        if best:
            sl = best[1]
            drip_box = (sl[1].start - 3, sl[0].start - 4, sl[1].stop + 3, sl[0].stop + 3)
        iou = float(((img[..., 3] > 0.5) & (reps['nice'][0] > 0.5)).sum() / max(1, ((img[..., 3] > 0.5) | (reps['nice'][0] > 0.5)).sum()))
        if iou < 0.85:
            NOTES.append(f'stamp-nice-night no longer matches g_stencil.stamp() (IoU {iou:.2f}); stamp masks are generic')
    hold = np.ones((H, W), np.float32)
    if drip_box:
        x0, y0, x1, y1 = drip_box
        blocks = ndi.grey_dilation((union > 0.3).astype(np.float32), size=(5, 5))
        hold[y0:y1, x0:x1] = blocks[y0:y1, x0:x1]       # NICE!'s drip below its block; MISS's block stays whole
    fr = [0.25, 0.5, 0.75, 1.0]
    rpN, rpM = reps['nice'][1], reps['miss'][1]
    for i, f in enumerate(fr):
        if f < 1:
            a = replay_reveal(rpN, f, None, slab, 2.5, (H, W))
            b = replay_reveal(rpM, f, None, slab, 2.5, (H, W))
            m = np.maximum(a, b * (1 - slab))         # film: NICE! strokes; droplets: both stamps' real droplets
        else:
            m = np.ones((H, W), np.float32)
        m = m * hold
        extra = {}
        if i == 0:
            extra = dict(frames=4, durationMs=STAMP_MS['nice'], anchor=(cx / S, cy / S))
            if drip_box:
                extra['dripBox'] = [round(drip_box[0] / S - STAMP_BLEED, 1), round(drip_box[1] / S - STAMP_BLEED, 1),
                                    round((drip_box[2] - drip_box[0]) / S, 1), round((drip_box[3] - drip_box[1]) / S, 1)]
        save_mask(f'stamp-mask-{i}', m,
                  f'Stamp spray, frame {i}/3 (NICE! 90–220ms: starts {90 + round(130 * i / 4)}; MISS 110–270ms: starts '
                  f'{110 + round(160 * i / 4)}): reveal mask for stamp-nice-night AND stamp-miss-night (same 202×112 '
                  'canvas, box 150×60, anchor = box centre) under the stencil sheet. dripBox (box pt) is 0 in every '
                  'frame: NICE! grows its drip there with drip-grow-0…3 (320–600ms) after the sheet lifts; MISS just '
                  'drops the mask after frame 3.', bleed=(STAMP_BLEED,) * 4, **extra)
    return reps, drip_box


def uniform_field(shape, seed):
    rng = np.random.default_rng(seed)
    f = ndi.gaussian_filter(rng.random(shape).astype(np.float32), 0.7).ravel()
    r = np.empty(f.size, np.float32)
    r[np.argsort(f)] = np.linspace(0, 1, f.size, dtype=np.float32)
    return r.reshape(shape)


def shadow_alpha(s):
    return 1 - np.power(np.clip(1 - s, 0, 1), 1 / 2.2)


def stamp_sheet(kind, rep):
    """mb_english.stamp_demo's sheet: hand-cut kraft (13pt round the window, same tilt), old paint on it (lip
    build-up at the window, droplet fog, a ghost of an earlier pull), lit cut edges, soft contact shadow."""
    block, rp, (W0, H0, cx0, cy0) = rep
    k = STAMP[kind]
    pad = (40 - STAMP_BLEED) * S                     # sheet canvas: box + 40pt each side
    W, H = W0 + 2 * pad, H0 + 2 * pad
    cx, cy = cx0 + pad, cy0 + pad
    cut = np.pad(block, pad)
    D_end = np.pad(rp['D_end'] * rp['peel'], pad)
    rng = np.random.default_rng(8860 + (kind == 'miss'))
    bw, bh = STAMP_BOX[0] * S, STAMP_BOX[1] * S
    ox, oy = cx - bw / 2, cy - bh / 2
    m_ = 26
    ca, sa = math.cos(math.radians(k['ang'])), math.sin(math.radians(k['ang']))

    def rot(px, py):
        dx, dy = px - cx, py - cy
        return (cx + dx * ca - dy * sa, cy + dx * sa + dy * ca)
    poly = [rot(ox - m_, oy - m_ - 6), rot(ox + bw + m_ + 4, oy - m_), rot(ox + bw + m_, oy + bh + m_),
            rot(ox - m_ - 3, oy + bh + m_ + 2)]
    outer = bake.rough_polygon(W, H, poly, rng, jitter=1.2)
    col, hgt, _ = ext.kraft(W, H, 8870 + (kind == 'miss'), flute_amp=0.010, flute_period=7.0, fibre_k=0.8)
    a = np.clip(outer * (1 - cut), 0, 1)
    edge = shade_from_height(ndi.gaussian_filter(a, 0.9) * 6, 1.0, 0.5)
    col = col * (1 + 0.9 * edge)[..., None]
    # paint caught on the sheet by earlier pulls: lip at the window, then fog that is really droplets
    rf = uniform_field((H, W), 8880 + (kind == 'miss'))
    d = ndi.distance_transform_edt(cut < 0.5)
    base = (1 - np.exp(-1.4 * D_end)) * np.exp(-d / 30)
    lip = base * smoothstep(9, 2, d)
    fog = smoothstep(-0.05, 0.05, base * 0.9 - rf)
    cp = np.maximum(lip, fog) * (1 - cut)
    g = ndi.shift(cp, (-9, 5), order=1) * 0.32 * smoothstep(-0.4, 1.1, gnoise((H, W), 7, rng))
    paint = np.clip(np.maximum(cp * 0.85, g), 0, 1)
    P = lin(hexrgb(ext.C(k['paint']))) * 0.92
    col = col * (1 - paint[..., None]) + P * paint[..., None]
    s = ext.contact_shadow_alpha(a, contact=(1.5, 2.5, 2.2, 0.55), ambient=(2.0, 9.0, 12.0, 0.22))
    sa_ = shadow_alpha(s) * (1 - a)
    A = a + sa_
    img = ext.export(col * a[..., None], A)
    b = 40
    out.save(f'stamp-{kind}-sheet', img, 'sprite',
             f'{"NICE!" if kind == "nice" else "MISS"} stencil sheet: hand-cut kraft with the block window, {k["ang"]:+d}° '
             'like the stamp, old paint on it (lip + droplet fog + a ghost pull), lit cut edges, soft contact shadow. '
             'Layout rect = the 150×60pt stamp box, anchor = its centre (same as the stamp). Place 0–90ms (drop: '
             'scale 1.04→1, fade in), hold over the spray, lift 220–320ms (offset (+18, −26)pt, fade out).',
             bleed=(b, b, b, b), anchor=(cx / S, cy / S), ground='concrete')


# ================================================================ ④ round-board cell: the mist frame
def rate_mist():
    rng0 = np.random.default_rng(8900)
    g = ground_hex()
    for j, kind in enumerate(('easy', 'good', 'fuzzy', 'forgot')):
        fin = entry(f'rate-30-{kind}')
        size = 30.0
        bleed = (2, 2, 2, 2)
        if fin is not None:
            bleed = tuple(fin['bleed'])
            size = fin['size'][0] - bleed[1] - bleed[3]
        bt, bl, bb, br = bleed
        W, H = int(round((bl + size + br) * S)), int(round((bt + size + bb) * S))
        x0, y0, x1, y1 = (int(round(v)) for v in (bl * S, bt * S, (bl + size) * S, (bt + size) * S))
        rng = np.random.default_rng(8910 + 7 * j)
        L = ext.Layer(W, H, 8911 + 7 * j, 'concrete', quiet=(0, 0, W, H, 0.6))
        color = 'grey' if kind == 'forgot' else 'teal'
        src = load_rgba(fin) if fin is not None else None
        if kind == 'fuzzy' and src is not None and src.shape[:2] == (H, W):
            # the final's own dots, about 45 % of them (they stay), plus the first faint mist
            lab, n = ndi.label(src[..., 3] > 0.25)
            keep = np.concatenate([[0], (rng.random(n) < 0.35).astype(np.float32)])
            m = src[..., 3] * keep[lab]
            m = np.clip(m + 0.05 * (0.7 + 0.3 * gnoise((H, W), 3, rng)) * np.pad(np.ones((y1 - y0, x1 - x0)), ((y0, H - y1), (x0, W - x1))), 0, 1)
        else:
            dens = 0.07 if kind == 'fuzzy' else 0.09
            m = ext.dots_mask(W, H, x0, y0, x1, y1, rng, dens, 0.6, 1.6, 0.05)
            # a few droplets past the box edge (through the gaps of the dashed tape frame)
            spill = ext.dots_mask(W, H, x0 - 3, y0 - 3, x1 + 3, y1 + 3, rng, 0.012, 0.5, 1.2, 0.0)
            m = np.maximum(m, spill)
        L.mpaint(m, color, rng, cov=1.0, ridge=0, edge=False, noise=0, relief=0.4)
        border_fade(L, 1)
        out.save(f'rate-30-{kind}-mist', ext.export(L.col, L.A, g), 'sprite',
                 f'Round-board cell 30pt, {kind}: the first pass (0–60ms) — sparse {"meeting-grey" if color == "grey" else "teal"} '
                 f'droplets + faint mist on concrete; same box / bleed as rate-30-{kind}. Show it 0–60ms over the '
                 f'current cell, crossfade to rate-30-{kind} 60–160ms (the orange tape frame peels 80–140ms), then the '
                 'star / ✕ lands 160–200ms (1.15→1).', bleed=bleed, ground='concrete')
        if fin is None and j == 0:
            NOTES.append('rate-30-* not in the manifest yet: mist frames use the rate-24 recipe at 30pt, bleed 2')


# ================================================================ ⑤ stage clear: the badge plate sprayed on
BADGE_MS = 340


def badge_masks():
    from .g_paint import canvas
    w, h = 142, 105
    bleed = (14, 12, 16, 18)
    W, H, r = canvas(w, h, bleed)
    seed = 4480
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = r
    c = 15 * S
    pts = [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]
    cut = ext.rotate_mask(ext.rough_polygon(W, H, pts, rng, jitter=1.0), -2.0, (x0 + x1) / 2, (y0 + y1) / 2)
    angle = rng.uniform(-8, -3)
    rp = spray_replay(cut, seed + 2, passes=3, angle=angle, sheet_pad=6, k=5.0, droplets=0.35, spits=0, reach=8)
    e = entry('badge-plate-night')
    img = load_rgba(e) if e else None
    if img is not None and img.shape[:2] == (H, W):
        iou = float(((img[..., 3] > 0.5) & (cut > 0.5)).sum() / max(1, ((img[..., 3] > 0.5) | (cut > 0.5)).sum()))
        if iou < 0.85:
            NOTES.append(f'badge-plate-night no longer matches g_paint.badge_plate() (IoU {iou:.2f})')
    slab = ndi.grey_dilation((cut > 0.05).astype(np.float32), size=(7, 7))
    starts = [round(BADGE_MS * i / 4) for i in range(4)]
    for i, f in enumerate([0.25, 0.5, 0.75, 1.0]):
        m = replay_reveal(rp, f, None, slab, 5.0, (H, W)) if f < 1 else np.ones((H, W), np.float32)
        extra = dict(frames=4, durationMs=BADGE_MS) if i == 0 else {}
        save_mask(f'badge-mask-{i}', m,
                  f'Stage-clear badge, frame {i}/3 (starts {starts[i]}ms of 340; three passes, linear): reveal mask for '
                  'badge-plate-night (same 172×135pt canvas, layout 142×105, −2° baked) — the replayed strokes and '
                  'droplets of its bake. Then lift the creature stencil off creature-<day>-teal (offset, 340–650ms). '
                  'Frame 3 opaque.', bleed=bleed, **extra)
    return starts


# ================================================================ ⑥ first open of the day: the masking-paper cover
COVER_W = 520
COVER_CAPS = (220, 140)            # top / bottom cap pt; the band between them (COVER_BAND) is tiled
COVER_BAND = 40
PAPER_INSET = (12, 10, 12, 10)     # paper edge inside the panel (t, l, b, r) pt: the tape bridges onto the concrete


def _fibres_wrap(W, P, n, rng, ang_sd, lmean, fill, vert=False):
    """Short paper fibres on a strip P px high that wraps vertically (each fibre also drawn one period up / down)."""
    img = Image.new('L', (W * 3, P * 3), 0)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.uniform(0, W), rng.uniform(0, P)
        L = rng.exponential(lmean)
        a = math.radians(rng.normal(90 if vert else 0, ang_sd) + (0 if rng.random() < 0.5 else 180))
        x1, y1 = x + L * math.cos(a), y + L * math.sin(a)
        v = int(rng.uniform(*fill))
        for dy in (-P, 0, P):
            d.line([(x * 3, (y + dy) * 3), (x1 * 3, (y1 + dy) * 3)], fill=v, width=2)
    return np.asarray(img.resize((W, P), Image.LANCZOS), np.float32) / 255


def paper_strip(W, P, rng):
    """Masking paper: a P-px strip, periodic vertically (fine felt, fibres, faint mottle) -> (tone, height)."""
    def gw(sig):
        return gnoise((P, W), sig, rng, mode='wrap')
    tone = 0.022 * gw((1.0, 2.2)) + 0.016 * gw(0.7) + 0.012 * gw((5, 9))
    fd = _fibres_wrap(W, P, int(W * P / 120), rng, 25, 6.0, (60, 190))
    fl = _fibres_wrap(W, P, int(W * P / 500), rng, 20, 9.0, (60, 170))
    height = 0.30 * fl - 0.20 * fd + 0.05 * gw(1.4)
    return tone, fd, fl, height


def crease_lines(W, H, segs, ss=2):
    """Sharp paper creases: each segment (x0, y0, x1, y1, h, width) -> a tent ridge in a height map."""
    img = Image.new('F', (W, H), 0.0)
    acc = np.zeros((H, W), np.float32)
    for x0, y0, x1, y1, hh, wd in segs:
        im = Image.new('L', (W * ss, H * ss), 0)
        ImageDraw.Draw(im).line([(x0 * ss, y0 * ss), (x1 * ss, y1 * ss)], fill=255, width=max(1, int(wd * ss)))
        m = np.asarray(im.resize((W, H), Image.BILINEAR), np.float32) / 255
        acc += hh * ndi.gaussian_filter(m, wd * 0.9 + 0.6)
    del img
    return acc


def cover_paper(corner=False):
    W = COVER_W * S
    tc, bc = COVER_CAPS[0] * S, COVER_CAPS[1] * S
    P = COVER_BAND * S
    H = tc + P + bc
    rng = np.random.default_rng(8950)                  # identical draws for both variants (same paper)
    pt, pl, pb, pr = (v * S for v in PAPER_INSET)
    # ---- band-periodic texture (fine) tiled over the whole sheet
    tone_s, fd_s, fl_s, h_s = paper_strip(W, P, rng)
    reps = int(math.ceil(H / P)) + 1
    off = tc % P                                        # phase so the band rows [tc, tc+P) are exactly the strip

    def tile(a):
        t = np.concatenate([a] * reps, 0)
        return np.roll(t, off, 0)[:H]
    tone, fd, fl, hgt = tile(tone_s), tile(fd_s), tile(fl_s), tile(h_s)
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    # weight of everything that is NOT y-invariant: 1 inside the caps, 0 in (and 24px around) the band
    wcap = np.maximum(smoothstep(tc - 24, tc - 90, Y), smoothstep(tc + P + 24, tc + P + 90, Y))
    # ---- folds: long vertical folds (the paper is pulled tight between the top and bottom tape) + cap crinkles
    fx = np.zeros(W, np.float32)
    for _ in range(9):
        c, wd, a = rng.uniform(pl + 30, W - pr - 30), rng.uniform(6, 34), rng.uniform(0.5, 1.4) * rng.choice([-1, 1])
        fx += a * np.exp(-0.5 * ((np.arange(W) - c) / wd) ** 2)
    fx += 0.5 * ndi.gaussian_filter(rng.standard_normal(W).astype(np.float32), 40) * 6
    folds = np.broadcast_to(fx[None, :], (H, W)).astype(np.float32)
    segs = []
    tapes = [('h', 40, 0, 150, 18, -1.6), ('h', 228, 0, 104, 18, 1.2), ('v', 0, 64, 18, 92, 0.8),
             ('v', 1, 250, 18, 70, -1.0), ('h', 56, 2, 140, 18, 1.0), ('h', 300, 2, 120, 18, -1.3)]
    # crinkles radiate from the taped edges (inside the caps only)
    anchors = []
    for kind, a_, b_, la, lb, ang in tapes:
        if kind == 'h':
            yy = pt if b_ == 0 else H - pb
            for _ in range(7):
                anchors.append((rng.uniform(a_, a_ + la) * S, yy, 1 if b_ == 0 else -1))
        else:
            xx = pl if a_ == 0 else W - pr
            ys0 = b_ * S if b_ < 200 else H - bc + (b_ - 200) * S
            for _ in range(6):
                anchors.append((xx, ys0 + rng.uniform(0, lb * S), 0))
    for x0, y0, sgn in anchors:
        for _ in range(2):
            ln = rng.uniform(40, 170)
            if sgn == 0:
                a = math.radians(rng.normal(0 if x0 < W / 2 else 180, 35))
            else:
                a = math.radians(rng.normal(90 if sgn > 0 else -90, 32))
            segs.append((x0, y0, x0 + ln * math.cos(a), y0 + ln * math.sin(a), rng.uniform(0.4, 1.1) * rng.choice([-1, 1]),
                         rng.uniform(0.8, 1.8)))
    for _ in range(26):                                 # loose crinkles anywhere in the caps
        yy = rng.uniform(pt + 20, tc - 70) if rng.random() < 0.6 else rng.uniform(H - bc + 70, H - pb - 16)
        xx, ln, a = rng.uniform(pl + 20, W - pr - 20), rng.uniform(20, 90), math.radians(rng.uniform(0, 180))
        segs.append((xx, yy, xx + ln * math.cos(a), yy + ln * math.sin(a), rng.uniform(0.3, 0.8) * rng.choice([-1, 1]),
                     rng.uniform(0.7, 1.4)))
    crink = crease_lines(W, H, segs) * wcap
    cockle = gnoise((H, W), (60, 30), rng) * wcap
    # crumple: the sheet was balled up once and smoothed out — straight creases (slope breaks, the height stays
    # continuous: h = a·R·tanh(|d|/R) across each crease line, fading out along it); caps only
    facet = np.zeros((H, W), np.float32)
    for _ in range(64):
        cx_ = rng.uniform(0, W)
        cy_ = rng.uniform(0, tc - 40) if rng.random() < 0.62 else rng.uniform(H - bc + 40, H)
        an = rng.uniform(0, math.pi)
        L, R, amp = rng.uniform(90, 320), rng.uniform(18, 50), rng.uniform(0.04, 0.10) * rng.choice([-1, 1])
        along = (X - cx_) * math.cos(an) + (Y - cy_) * math.sin(an)
        dperp = -(X - cx_) * math.sin(an) + (Y - cy_) * math.cos(an)
        env = 1 - smoothstep(L / 2 - 40, L / 2 + 40, np.abs(along))
        facet += amp * R * np.tanh(np.sqrt(dperp * dperp + 0.8) / R) * env
    facet = facet * wcap
    hgt = hgt + 1.6 * folds + 3.4 * crink + 1.2 * cockle + facet
    # ---- colour
    base = lin(hexrgb('#C9A473'))
    col = np.empty((H, W, 3), np.float32)
    col[:] = base
    col *= (1 + tone)[..., None]
    col *= (1 + 0.035 * gnoise((H, W), (120, 200), rng) * wcap)[..., None]
    a_d = np.clip(fd * 0.22, 0, 1)[..., None]
    a_l = np.clip(fl * 0.14, 0, 1)[..., None]
    col = col * (1 - a_d) + lin(hexrgb('#7A5A36')) * a_d
    col = col * (1 - a_l) + lin(hexrgb('#E4CDA4')) * a_l
    col *= np.clip(1 + 0.65 * shade_from_height(hgt, 1.0, 0.9), 0.55, 1.6)[..., None]
    # ghosts of earlier jobs (the cover is a re-used sheet): faint, matte, inside the caps
    for hexc, (cxp, cyp, rx, ry), amt in (('#12E9D3', (0.40, 0.17, 0.26, 0.10), 0.10),
                                          ('#FF6412', (0.80, 0.86, 0.10, 0.06), 0.12),
                                          ('#161615', (0.22, 0.30, 0.20, 0.03), 0.09)):
        e = ((X / W - cxp) / rx) ** 2 + ((Y / H - cyp) / ry) ** 2
        env = np.clip(1 - e, 0, 1) ** 0.8 * wcap
        gg = env * amt * (0.45 + 0.55 * smoothstep(-1.0, 1.6, gnoise((H, W), 34, rng)))
        dots = (rng.random((H, W)) < 0.006 * env).astype(np.float32)
        gg = np.clip(gg * 0.6 + ndi.gaussian_filter(dots, 0.6) * 2.5 * amt * 3, 0, 0.45)
        col = col * (1 - gg[..., None]) + lin(hexrgb(hexc)) * gg[..., None]
    # ---- paper outline: factory-straight sides, serrated (dispenser-cut) top and bottom, inside the panel
    xl, xr = float(pl), float(W - pr)
    yt = pt + 1.0 * np.abs(((np.arange(W) / 6.0) % 2) - 1) + 0.6 * gnoise((1, W), 3, rng)[0]
    yb = H - pb - 1.0 * np.abs(((np.arange(W) / 6.0 + 0.5) % 2) - 1) - 0.6 * gnoise((1, W), 3, rng)[0]
    yt = yt * 1.0
    yb = yb * 1.0
    a = (np.clip(X - xl + 0.5, 0, 1) * np.clip(xr - X + 0.5, 0, 1) * np.clip(Y - yt[None, :] + 0.5, 0, 1)
         * np.clip(yb[None, :] - Y + 0.5, 0, 1)).astype(np.float32)
    # thin paper edge: a lit lip on the top / left edges, a darker one on the bottom / right
    lip = shade_from_height(ndi.gaussian_filter(a, 0.8) * 3, 1.0, 0.5)
    col *= (1 + 0.5 * lip)[..., None]
    flap = None
    if corner:
        col, a, flap = peel_corner(col, a, W, H, rng)
    # ---- tape strips (crepe tape over the paper edge onto the concrete)
    tcol = np.zeros((H, W, 3), np.float32)
    tal = np.zeros((H, W), np.float32)
    tlift = np.zeros((H, W), np.float32)
    for ti, (kind, a_, b_, la, lb, ang) in enumerate(tapes):
        if kind == 'h':
            w_, h_ = la * S, lb * S
            yy = pt if b_ == 0 else H - pb
            x0, y0 = a_ * S, yy - h_ / 2
        else:
            w_, h_ = la * S, lb * S
            xx = pl if a_ == 0 else W - pr
            x0 = xx - w_ / 2
            y0 = b_ * S if b_ < 200 else H - bc + (b_ - 200) * S
        if kind == 'h':
            tc_, ta_, tl_ = ext.crepe_tape(int(w_), int(h_), 8960 + ti, ext.C('tape'), angle=ang, pad=12)
        else:                                       # a vertical strip: torn ends top / bottom
            tc_, ta_, tl_ = ext.crepe_tape(int(h_), int(w_), 8960 + ti, ext.C('tape'), angle=ang, pad=12)
            tc_, ta_, tl_ = tc_.transpose(1, 0, 2), ta_.T, tl_.T
        hh, ww = ta_.shape
        X0, Y0 = int(round(x0 - 12)), int(round(y0 - 12))
        sy0, sx0 = max(0, -Y0), max(0, -X0)
        sy1, sx1 = min(hh, H - Y0), min(ww, W - X0)
        sl = (slice(Y0 + sy0, Y0 + sy1), slice(X0 + sx0, X0 + sx1))
        aa = ta_[sy0:sy1, sx0:sx1]
        tcol[sl] = tcol[sl] * (1 - aa[..., None]) + tc_[sy0:sy1, sx0:sx1] * aa[..., None]
        tal[sl] = aa + tal[sl] * (1 - aa)
        tlift[sl] = np.maximum(tlift[sl], tl_[sy0:sy1, sx0:sx1])
    # tape is translucent: paper / concrete read through a little (darker over the concrete)
    over_paper = a
    tcol = tcol * (0.93 + 0.07 * over_paper)[..., None]
    # ---- shadows: paper contact shadow (light top-left -> down-right), tape lift shadow
    s = ext.contact_shadow_alpha(a, contact=(1.2, 2.0, 1.6, 0.42), ambient=(1.5, 5.0, 7.0, 0.16))
    sh = ndi.gaussian_filter(ndi.shift(tal, (2.0, 0.8), order=1), 1.6) * 0.28
    sh += ndi.gaussian_filter(ndi.shift(tal * tlift, (2.5, 1.0), order=1), 2.0) * 0.3
    sh = np.clip(sh, 0, 0.6) * (1 - tal)
    on_paper_sh = sh * a                              # tape shadow on the paper darkens the paper colour
    col = col * (1 - on_paper_sh[..., None] * 0.9)
    s = 1 - (1 - s * (1 - a)) * (1 - sh * (1 - a))
    if flap is not None:
        fcol, fal, fsh = flap
        s = 1 - (1 - s) * (1 - fsh * (1 - a))
        col = col * (1 - fsh[..., None] * 0.85 * a[..., None])
    sa_ = shadow_alpha(s) * (1 - np.maximum(a, tal))
    # composite: paper, tape over it, flap over all
    pm = col * a[..., None]
    A = a
    pm = pm * (1 - tal[..., None]) + tcol * tal[..., None]
    A = tal + A * (1 - tal)
    if flap is not None:
        fcol, fal, fsh = flap
        pm = pm * (1 - fal[..., None]) + fcol * fal[..., None]
        A = fal + A * (1 - fal)
    A_tot = A + sa_ * (1 - A)
    img = ext.export(pm, A_tot)
    return img, (H, W)


def peel_corner(col, a, W, H, rng):
    """Top-right corner lifted: the paper beyond the fold line is gone from the sheet and stands up as a flap (the
    back of the paper, foreshortened toward the fold, lit near the fold), casting a soft shadow down-right."""
    pt, pr = PAPER_INSET[0] * S, PAPER_INSET[3] * S
    C = np.array([W - pr, pt], np.float32)                     # the paper's top-right corner
    A_ = np.array([W - pr - 150 * S, pt], np.float32)          # fold meets the top edge
    B_ = np.array([W - pr, pt + 118 * S], np.float32)          # fold meets the right edge
    Y, X = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (B_ - A_) / np.linalg.norm(B_ - A_)
    nrm = np.array([u[1], -u[0]], np.float32)                  # points toward the corner
    if np.dot(C - A_, nrm) < 0:
        nrm = -nrm
    side = (X - A_[0]) * nrm[0] + (Y - A_[1]) * nrm[1]         # > 0 beyond the fold
    # a little curl: the fold is not a crease, the sheet lifts over ~5pt before it
    keep = np.clip(0.5 - side, 0, 1)
    a2 = a * keep
    curl = smoothstep(-12 * S, 0, side) * keep
    col = col * (1 - 0.10 * curl + 0.06 * smoothstep(-4 * S, -1 * S, side) * keep)[..., None]
    # flap: reflect the corner triangle over the fold, foreshortened (it stands up ~45° toward the viewer)
    k = 0.66
    # point p on the flap comes from q = fold-foot + (p - foot)/k mirrored: q = p + (1 + 1/k) * dist * nrm
    dist = -side                                               # flap lies on the sheet side (side < 0)
    qx = X + (1 + 1 / k) * dist * nrm[0]
    qy = Y + (1 + 1 / k) * dist * nrm[1]
    src_a = ndi.map_coordinates(a, [qy, qx], order=1, cval=0) * (side < 0.5) * (dist > -0.5)
    fal = np.clip(src_a * np.clip((qx - A_[0]) * nrm[0] + (qy - A_[1]) * nrm[1], 0, 1), 0, 1)
    fal = fal * np.clip(dist + 0.5, 0, 1)
    back, _, _ = ext.kraft(W, H, 8990, base_hex='#CFAE80', flute_amp=0.004, flute_period=7.0, fibre_k=0.5)
    dfold = np.clip(dist / (k * np.linalg.norm(C - (A_ + np.dot(C - A_, u) * u)) + 1e-6), 0, 1)
    light = 1.16 - 0.10 * smoothstep(0, 0.05, dfold) + 0.12 * np.exp(-dfold / 0.03) - 0.24 * dfold
    fcol = back * light[..., None]
    # the flap's own shadow on the sheet / concrete: offset down-right, soft
    fsh = ndi.gaussian_filter(ndi.shift(fal, (20, 11), order=1), 8) * 0.62 * (1 - fal)
    # the exposed corner: a soft shadow under the lifted edge
    lift_sh = smoothstep(30 * S, 0, side) * (side > 0) * 0.40 * smoothstep(0, 3, side)
    fsh = 1 - (1 - fsh) * (1 - lift_sh * (1 - fal))
    return col, a2, (fcol * fal[..., None], fal, fsh)


def cover_sheets():
    for corner in (False, True):
        img, (H, W) = cover_paper(corner)
        aid = 'cover-sheet-corner-night' if corner else 'cover-sheet-night'
        insets = (COVER_CAPS[0], 250, COVER_CAPS[1], 250)
        purpose = ('Panel cover for the first open of the day: crinkled masking paper over the whole panel (edge 10–12pt '
                   'inside it), crepe-tape strips bridging onto the concrete, ghosts of earlier sprays, contact shadow. '
                   'Layout = the panel 520×H; BakedSlice(tile: true): the 40pt centre band is tile-safe (vertical '
                   'folds + fine texture only), width fixed 520. Shown at 0ms, swapped for cover-sheet-corner-night as '
                   'the peel starts.')
        if corner:
            purpose = ('The same cover with its free top-right corner peeled up (flap = the back of the paper, lit at '
                       'the fold, soft shadow; bare panel under it). Same geometry / insets as cover-sheet-night. '
                       'Peel 0–160ms (ease .5,0,.9,.4: crossfade in over the first 60ms, scale 0.96→1 from the top-right '
                       'corner), fling 160–320ms (rotate +9°, offset (+150, −240)pt about the bottom-left, fade the '
                       'last 60ms), then the paint fades in 320–520ms.')
        out.save(aid, img, 'slice', purpose, bleed=(0, 0, 0, 0), insets=insets, ground='concrete', tile=True)


# ================================================================ group
TIMING = {}


def bake_all():
    NOTES.clear()
    glyph.load()
    TIMING['flood'] = flood_teal()
    TIMING['floodOrange'] = flood_orange()
    TIMING['drip'] = drip_grow()
    reps, _ = stamp_masks()
    TIMING['stamp'] = dict(nice=[90 + round(130 * i / 4) for i in range(4)], miss=[110 + round(160 * i / 4) for i in range(4)])
    for kind in STAMP:
        stamp_sheet(kind, reps[kind])
    rate_mist()
    TIMING['badge'] = badge_masks()
    cover_sheets()
    TIMING['cell'] = [0, 60, 160]
    TIMING['cover'] = [0, 160, 320, 520]
    for n in NOTES:
        print('   note:', n)
