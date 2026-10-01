"""Tape-masked blocks (遮): tab chip, frames, rating / option blocks, tags, bands, plates, checkbox, redaction bars.
Recipes: merge2/english/eng_bake.py (mpaint / paint_rect / paint_frame / cover) and merge2/today/todaybake.py
(checkbox, row bar)."""
import numpy as np
from PIL import Image, ImageDraw

from . import ext, out
from .g_concrete import ground_hex
from .g_paint import border_fade, canvas, interior

S = 2
WHITE_CARD = '#F4F3EE'


def block(aid, w, h, color, seed, purpose, caps=(8, 8, 8, 8), bleed=(2, 2, 2, 2), ground=None, on_card=False,
          edge=False, frame_sw=None, quiet_k=0.8, **kw):
    """One masked block / frame as a transparent 9-slice."""
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, min(w, h) * 0.18, quiet_k))
    x0, y0, x1, y1 = r
    if edge:          # small marks on the white card carry a 1pt black paint edge
        m = ext.knife_rect(W, H, x0 - 2, y0 - 2, x1 + 2, y1 + 2, rng, 0.55)
        L.mpaint(m, 'black', rng, cov=0.995, ridge=0, noise=0.004, relief=0.3)
    if frame_sw:
        m = ext.rough_frame(W, H, x0, y0, x1, y1, frame_sw * S, rng)
    else:
        m = ext.knife_rect(W, H, x0, y0, x1, y1, rng, kw.pop('jitter', 0.55))
    L.mpaint(m, color, rng, **kw)
    border_fade(L, 3)
    g = ground or (WHITE_CARD if on_card else ground_hex())
    out.save(aid, ext.export(L.col, L.A, g), 'slice', purpose, bleed=bleed,
             insets=tuple(b + c for b, c in zip(bleed, caps)),
             ground='white card' if g == WHITE_CARD else ('concrete' if ground is None else g))


def checkbox():
    s = 17
    bleed = (2, 2, 2, 2)
    W, H, r = canvas(s, s, bleed)
    rng = np.random.default_rng(4610)
    L = ext.Layer(W, H, 4611, 'concrete')
    L.masked(ext.knife_frame(W, H, *r, 4.2, rng), 'pale', 4612, coverage=0.9, ridge=0.03, thin=0.08)
    border_fade(L, 2)
    out.save('checkbox-night', ext.export(L.col, L.A, ground_hex()), 'sprite',
             'Task checkbox, empty: hand-cut 2pt frame of pale masked paint, corners not perfect (17pt).',
             bleed=bleed, ground='concrete')
    bleed = (6, 6, 6, 6)
    W, H, r = canvas(s, s, bleed)
    rng = np.random.default_rng(4620)
    L = ext.Layer(W, H, 4621, 'concrete')
    L.spray(ext.knife_rect(W, H, *r, rng, 0.6), 'teal', 4622, passes=2, angle=rng.uniform(-8, 8), sheet_pad=5,
            k=2.8, droplets=0.10, reach=5, spits=0, sheen=0.04)
    border_fade(L, 4)
    out.save('checkbox-checked-night', ext.export(L.col, L.A, ground_hex()), 'sprite',
             'Task checkbox, checked: small teal spray block (17pt); the stencil ✓ is a live Shape in black on top.',
             bleed=bleed, ground='concrete')


def row_bar():
    w, h = 6, 24
    bleed = (2, 2, 2, 2)
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(4630)
    L = ext.Layer(W, H, 4631, 'concrete')
    L.masked(ext.knife_rect(W, H, *r, rng, 0.6), 'teal', 4632, coverage=0.97, ridge=0.06, thin=0.06)
    border_fade(L, 2)
    out.save('bar-teal-night', ext.export(L.col, L.A, ground_hex()), 'slice',
             'Selected schedule row: 6pt teal masked bar (stretch vertically only).', bleed=bleed,
             insets=(bleed[0] + 5, bleed[1] + 2, bleed[2] + 5, bleed[3] + 2), ground='concrete')


def redact():
    """eng_bake.cover: a stroke of black sprayed through a hand-cut stencil — slanted knife ends, hairline overcuts,
    overspray mostly below.  Stretched horizontally (and down to ~15pt tall) for the two redaction bars."""
    w, h = 220, 30
    bleed = (6, 6, 12, 10)
    W, H, r = canvas(w, h, bleed)
    seed = 4640
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, 6, 0.6))
    x0, y0, x1, y1 = r
    sl = 8 * S
    pts = [(x0, y0 + rng.normal(0, .8)), (x0 + (x1 - x0) * 0.45, y0 + rng.normal(0, .9)), (x1, y0 + rng.normal(0, .8)),
           (x1 - sl, y1 + rng.normal(0, .8)), (x0 + (x1 - x0) * 0.55, y1 + rng.normal(0, .9)), (x0 + rng.normal(0, .6), y1)]
    m = ext.rough_polygon(W, H, pts, rng, jitter=1.1)
    ss = 4
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    ax, ay = pts[2]
    d.line([(ax * ss, (ay + 0.6) * ss), ((ax + 9) * ss, (ay + 0.1) * ss)], fill=255, width=int(1.5 * ss))
    bx, by = pts[5]
    d.line([((bx + 0.6) * ss, by * ss), ((bx + 0.2) * ss, (by + 7) * ss)], fill=255, width=int(1.4 * ss))
    m = np.maximum(m, np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255)
    L.spray(m, 'black', seed + 2, side=73, side_min=0.12, box=r, passes=3, angle=rng.uniform(-7, -2), sheet_pad=6,
            k=5.2, droplets=0.6, reach=9, spits=0, sheen=0.03, relief=0.6, under=(1, 1))
    border_fade(L, 5)
    out.save('redact-black-night', ext.export(L.col, L.A, WHITE_CARD), 'slice',
             'Hidden-meaning redaction bar (English 04): black sprayed through a hand-cut stencil, slanted knife end '
             'right, overcuts; stretch horizontally (two bars: ~134×35pt and ~226×15pt, tilt −1.6° / +0.8° in the view).',
             bleed=bleed, insets=(bleed[0] + 6, bleed[1] + 12, bleed[2] + 6, bleed[3] + 22), ground='white card')


def bake_all():
    block('tab-chip-night', 64, 32, 'white', 4501,
          'Selected tab (今日 / 英语 12, 单词 / 考点词 …): white masked chip, rough edge, thin patches; idle tabs have no frame.',
          cov=0.95, thin=0.28, ridge=0.03, jitter=1.0, rough=0.10, thin_sigma=6)
    block('frame-white-night', 135, 50, 'white', 4511,
          'Secondary button: 2pt white masked frame (concrete and kraft), live label.', caps=(10, 10, 10, 10),
          frame_sw=2, cov=0.9, thin=0.18, ridge=0.02)
    block('block-slate-night', 160, 54, 'slate', 4521,
          'Rating / option button at rest: slate masked block + live text (rating 112×52, options 233×54).',
          caps=(10, 10, 10, 10), thin=0.12, ridge=0.04)
    block('block-grey-night', 160, 54, 'grey', 4531,
          'Wrong pick / forgot: meeting-grey masked block (+ live strikethrough and ✕).', caps=(10, 10, 10, 10),
          thin=0.12, ridge=0.04)
    block('block-teal-night', 160, 54, 'teal', 4541,
          'Selected / correct option, pressed rating: teal masked block, black text.', caps=(10, 10, 10, 10),
          thin=0.12, ridge=0.04)
    block('tag-orange-night', 56, 24, 'orange', 4551,
          'Small orange masked tag (到点了 in the footer, NEW, 47 分钟), black text.', caps=(6, 7, 6, 7),
          thin=0.08, ridge=0.04)
    block('tag-teal-night', 88, 24, 'teal', 4556,
          'Small teal masked tag on the white card (CLEAR), with the 1pt black paint edge; black text.',
          caps=(6, 7, 6, 7), bleed=(3, 3, 3, 3), on_card=True, edge=True, thin=0.06, ridge=0.04)
    block('band-black-night', 352, 34, 'black', 4561,
          'Review-history band on the word card: black masked strip holding the 18pt rating cells.',
          caps=(8, 10, 8, 10), on_card=True, cov=0.993, thin=0.0, noise=0.005, ridge=0, relief=0.35)
    block('plate-black-night', 170, 200, 'black', 4571,
          'Black masked plate on the white card: session board (4×5 cells), streak / 本轮 / B1 tags (stretches '
          'down to 24pt tall).', caps=(8, 8, 8, 8), on_card=True, cov=0.993, thin=0.0, noise=0.005, ridge=0,
          relief=0.35)
    block('input-frame-night', 350, 46, 'black', 4581,
          'Dictation input: 2pt black masked frame on the white card, live text inside.', caps=(10, 10, 10, 10),
          on_card=True, frame_sw=2, cov=0.95, thin=0.12, ridge=0.02)
    block('frame-black-night', 48, 24, 'black', 4591,
          'Outline tag on the white card (名词 / 听力 / B2): 1.8pt black masked frame.', caps=(6, 6, 6, 6),
          on_card=True, frame_sw=1.8, cov=0.95, thin=0.12, ridge=0.02)
    checkbox()
    row_bar()
    redact()
