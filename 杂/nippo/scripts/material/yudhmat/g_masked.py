"""Tape-masked blocks (遮): tab chip, frames, rating / option blocks, tags, bands, plates, checkbox, redaction bars.
Recipes: merge2/english/eng_bake.py (mpaint / paint_rect / paint_frame / cover) and merge2/today/todaybake.py
(checkbox, row bar)."""
import numpy as np
from PIL import Image, ImageDraw

from . import ext, out
from .bake import hexrgb, lin
from .g_concrete import ground_hex
from .g_paint import border_fade, canvas, interior

S = 2
WHITE_CARD = '#F4F3EE'


def block(aid, w, h, color, seed, purpose, caps=(8, 8, 8, 8), bleed=(2, 2, 2, 2), ground=None, on_card=False,
          edge=False, frame_sw=None, quiet_k=0.8, kind='concrete', sprite=False, **kw):
    """One masked block / frame as a transparent 9-slice (or a fixed-size sprite).  kind = the substrate whose relief
    shows through the film (concrete; kraft for the posture popup); ground = what the alpha is solved against."""
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, kind, quiet=interior(r, min(w, h) * 0.18, quiet_k))
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
    label = 'white card' if g == WHITE_CARD else ('concrete' if ground is None else g)
    if sprite:
        out.save(aid, ext.export(L.col, L.A, g), 'sprite', purpose, bleed=bleed, ground=label)
    else:
        out.save(aid, ext.export(L.col, L.A, g), 'slice', purpose, bleed=bleed,
                 insets=tuple(b + c for b, c in zip(bleed, caps)), ground=label)


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


def redact(aid='redact-black-night', w=220, h=30, tilt=0.0, seed=4640, purpose=None, bleed=(6, 6, 12, 10)):
    """eng_bake.cover: a stroke of black sprayed through a hand-cut stencil — slanted knife ends, hairline overcuts,
    overspray mostly below.  tilt (deg, CSS sense) is baked: the sprite's layout rect is the un-tilted box."""
    W, H, r = canvas(w, h, bleed)
    rng = np.random.default_rng(seed)
    L = ext.Layer(W, H, seed + 1, 'concrete', quiet=interior(r, min(6, h * 0.3), 0.6))
    x0, y0, x1, y1 = r
    sl = min(8, h * 0.5) * S
    pts = [(x0, y0 + rng.normal(0, .8)), (x0 + (x1 - x0) * 0.45, y0 + rng.normal(0, .9)), (x1, y0 + rng.normal(0, .8)),
           (x1 - sl, y1 + rng.normal(0, .8)), (x0 + (x1 - x0) * 0.55, y1 + rng.normal(0, .9)), (x0 + rng.normal(0, .6), y1)]
    m = ext.rough_polygon(W, H, pts, rng, jitter=1.1)
    ss = 4
    img = Image.new('L', (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    ax, ay = pts[2]
    d.line([(ax * ss, (ay + 0.6) * ss), ((ax + 9) * ss, (ay + 0.1) * ss)], fill=255, width=int(1.5 * ss))
    bx, by = pts[5]
    d.line([((bx + 0.6) * ss, by * ss), ((bx + 0.2) * ss, (by + min(7, h)) * ss)], fill=255, width=int(1.4 * ss))
    m = np.maximum(m, np.asarray(img.resize((W, H), Image.LANCZOS), np.float32) / 255)
    if tilt:
        m = ext.rotate_mask(m, tilt, (x0 + x1) / 2, (y0 + y1) / 2)
    L.spray(m, 'black', seed + 2, side=73, side_min=0.12, box=r, passes=3 if h > 20 else 2, angle=rng.uniform(-7, -2),
            sheet_pad=6, k=5.2, droplets=0.6, reach=9, spits=0, sheen=0.03, relief=0.6, under=(1, 1))
    border_fade(L, 5)
    img = ext.export(L.col, L.A, WHITE_CARD)
    if tilt:
        out.save(aid, img, 'sprite', purpose, bleed=bleed, ground='white card')
    else:
        out.save(aid, img, 'slice',
                 purpose or ('Hidden-meaning redaction bar (English 04): black sprayed through a hand-cut stencil, '
                             'slanted knife end right, overcuts; stretch horizontally.'),
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
    block('band-black-night', 272, 32, 'black', 4561,
          'Review-history band on the 308pt word card (inner width 272): black masked strip 272×32pt holding the ten '
          '20pt rating cells (rate-20-*, gap 4).',
          caps=(8, 10, 8, 10), on_card=True, cov=0.993, thin=0.0, noise=0.005, ridge=0, relief=0.35)
    block('plate-black-night', 170, 200, 'black', 4571,
          'Black masked plate on the white card: session board (4×5 cells), streak / 本轮 / B1 tags (stretches '
          'down to 24pt tall).', caps=(8, 8, 8, 8), on_card=True, cov=0.993, thin=0.0, noise=0.005, ridge=0,
          relief=0.35)
    block('input-frame-night', 272, 52, 'black', 4581,
          'Dictation input on the 308pt card (inner 272): 2pt black masked frame 272×52pt on the white card; letters '
          'in 20×32 cells inside.', caps=(10, 10, 10, 10),
          on_card=True, frame_sw=2, cov=0.95, thin=0.12, ridge=0.02)
    block('frame-black-night', 48, 24, 'black', 4591,
          'Outline tag on the white card (名词 / 听力 / B2): 1.8pt black masked frame.', caps=(6, 6, 6, 6),
          on_card=True, frame_sw=1.8, cov=0.95, thin=0.12, ridge=0.02)
    checkbox()
    row_bar()
    redact()
    v121()


def v121():
    """V4 §3: blocks at their real sizes, on the ground they actually sit on."""
    card = dict(on_card=True, cov=0.993, thin=0.0, noise=0.005, ridge=0, relief=0.35)
    block('chip-black-card', 100, 30, 'black', 4701,
          'Black masked chip on the white card 100×30pt (StreakPlate 连续 N 天, 本轮 plate): white live text.',
          caps=(8, 10, 8, 10), **card)
    block('tag-black-card', 56, 22, 'black', 4706,
          'Black masked tag on the white card 56×22pt (B1 / 考点词 / 听写 / 词典 / 本轮): white live text.',
          caps=(6, 7, 6, 7), **card)
    block('tag-orange-card', 56, 22, 'orange', 4708,
          'Orange masked tag on the white card 56×22pt (NEW next to B1): black live text. Same height as '
          'tag-black-card / frame-black-*.', caps=(6, 7, 6, 7), on_card=True, thin=0.06, ridge=0.04)
    block('chip-black-kraft', 100, 32, 'black', 4711,
          'Black masked chip on kraft 100×32pt (posture 90° / 已站 32 分钟): white live text.', caps=(8, 10, 8, 10),
          kind='kraft', ground='kraft', cov=0.99, thin=0.0, noise=0.006, ridge=0, relief=0.45)
    block('tag-orange-kraft', 100, 32, 'orange', 4716,
          'Orange masked tag on kraft 100×32pt (目标 30 分钟 / 47 分钟): black live text.', caps=(8, 10, 8, 10),
          kind='kraft', ground='kraft', thin=0.08, ridge=0.04)
    block('frame-white-kraft', 135, 50, 'white', 4719,
          'Posture popup secondary button on KRAFT 135×50pt (15 分钟后 / 再站 10 分钟 / 结束拉伸): 2pt white masked '
          'frame, live black text.', caps=(10, 10, 10, 10), frame_sw=2, kind='kraft', ground='kraft', cov=0.92,
          thin=0.16, ridge=0.02)
    block('tag-orange-square-night', 38, 38, 'orange', 4721,
          'Power key armed (footer): orange masked square 38×38pt on the concrete; the black stencil power icon is '
          'live on top.', caps=(9, 9, 9, 9), thin=0.08, ridge=0.04)
    block('frame-black-long-night', 140, 22, 'black', 4726,
          'Long outline tag on the white card 140×22pt (明天 18 个复习 …): 1.8pt black masked frame, live text.',
          caps=(6, 8, 6, 8), on_card=True, frame_sw=1.8, cov=0.95, thin=0.12, ridge=0.02)
    for name, colr, sd in (('slate', 'slate', 4731), ('teal', 'teal', 4736), ('grey', 'grey', 4741)):
        block(f'block-{name}-option-night', 233, 56, colr, sd,
              {'slate': 'Quiz option at rest 233×56pt (考点词 4 选 1): slate masked block on the concrete, white text.',
               'teal': 'Quiz option chosen / correct 233×56pt: teal masked block, black text (+ stencil ✓).',
               'grey': 'Quiz option wrong pick 233×56pt: meeting-grey masked block, black struck text + ✕.'}[name],
              caps=(12, 14, 12, 14), thin=0.12, ridge=0.04)
    for name, colr, sd in (('slate', 'slate', 4746), ('teal', 'teal', 4751)):
        block(f'block-{name}-rate-night', 112, 52, colr, sd,
              {'slate': 'Rating button at rest 112×52pt (忘了 / 模糊 / 记住了 / 太简单): slate masked block, always '
                        'grey until pressed.',
               'teal': 'Rating button pressed 112×52pt: teal masked block, black text.'}[name],
              caps=(12, 12, 12, 12), thin=0.12, ridge=0.04)
    block('row-hover-night', 472, 40, 'white', 4756,
          'Row hover 472×40pt (schedule / list / task rows): a very faint wash of white masked paint on the concrete '
          '(hard tape edge, thin patches) — the only hover plate; never a flat rectangle.', caps=(10, 14, 10, 14),
          cov=0.013, thin=0.35, thin_sigma=7, ridge=0.0, relief=0.2, noise=0.003, jitter=0.9, rough=0.12)
    block('row-hover-title-night', 472, 24, 'white', 14764,
          'Title-line hover plate 472×24pt (single-line full-width targets: the hero title row, section caption rows): '
          'the same very faint white masked wash on the concrete as row-hover-night (hard tape edge, thin patches).',
          caps=(7, 14, 7, 14),
          cov=0.013, thin=0.35, thin_sigma=6, ridge=0.0, relief=0.2, noise=0.003, jitter=0.9, rough=0.12)
    block('tab-chip-wide-night', 96, 32, 'white', 14504,
          'Selected tab, WIDE 96×32pt (labels like 「学习中 120」): the same white masked chip as tab-chip-night, '
          'baked at its real width (rough edge, thin patches); black live text.',
          cov=0.95, thin=0.28, ridge=0.03, jitter=1.0, rough=0.10, thin_sigma=6)
    block('row-hover-small-night', 120, 24, 'white', 4757,
          'Small hover plate 120×24pt (the 「任务 N」 line, other short single-line targets): the same very faint '
          'white masked wash as row-hover-night.', caps=(7, 10, 7, 10),
          cov=0.013, thin=0.35, thin_sigma=5, ridge=0.0, relief=0.2, noise=0.003, jitter=0.9, rough=0.12)
    block('input-frame-concrete-night', 472, 150, 'white', 4758,
          'Task editor field on the concrete 472×150pt: 2pt white masked frame (rough edge, thin patches), live text '
          'inside; nothing else is drawn for the field.', caps=(12, 12, 12, 12), frame_sw=2, cov=0.9, thin=0.18,
          ridge=0.02)
    block('input-frame-small-night', 64, 26, 'white', 4759,
          'Small input on the concrete 64×26pt (work-time field 9:30): 1.5pt white masked frame, live mono text.',
          caps=(7, 8, 7, 8), frame_sw=1.5, cov=0.9, thin=0.14, ridge=0.02)
    block('mark-teal-card', 80, 20, 'teal', 4761,
          'Word highlight inside the example sentence on the white card 80×20pt: teal masked with the 1pt black '
          'paint edge; black text. insets 6pt (stretch to the word).', caps=(4, 4, 4, 4), bleed=(2, 2, 2, 2),
          on_card=True, edge=True, thin=0.06, ridge=0.04)
    block('letter-orange-card', 20, 32, 'orange', 4766,
          'Dictation: one WRONG letter cell 20×32pt on the white card — orange masked, black 26pt letter on it.',
          bleed=(2, 2, 2, 2), on_card=True, sprite=True, thin=0.06, ridge=0.04, jitter=0.45)
    block('letter-teal-card', 20, 32, 'teal', 4771,
          'Dictation: one letter of the correct spelling 20×32pt on the white card — teal masked with the 1pt black '
          'paint edge, black 26pt letter.', bleed=(3, 3, 3, 3), on_card=True, edge=True, sprite=True, thin=0.05,
          ridge=0.04, jitter=0.45)
    redact('redact-black-1-night', 134, 35, -1.6, 4776,
           'Redaction bar 1 of 2 (English card, hidden meaning): black sprayed through a hand-cut stencil, slanted '
           'knife end, overcuts; tilt −1.6° BAKED (do not rotate). Layout rect = the un-tilted 134×35pt box.',
           bleed=(8, 6, 12, 10))
    card_rule()
    block('band-black-wide-night', 432, 32, 'black', 4796,
          'Review-history band on the wide white card (list / dictionary result): black masked strip 432×32pt.',
          caps=(8, 10, 8, 10), **card)
    block('input-frame-wide-night', 432, 52, 'black', 4801,
          'Dictionary search field on the wide white card: 2pt black masked frame 432×52pt, live text inside.',
          caps=(10, 10, 10, 10), on_card=True, frame_sw=2, cov=0.95, thin=0.12, ridge=0.02)
    block('swatch-black-card', 20, 20, 'black', 4806,
          'Mini black masked plate 20×20pt on the white card: the dark ground for a 14pt rating swatch (rate-14-*) '
          'inside a rating / legend button.', caps=(5, 5, 5, 5), **card)
    redact('redact-black-2-night', 226, 15, 0.8, 4781,
           'Redaction bar 2 of 2: thin black sprayed bar; tilt +0.8° BAKED (do not rotate). Layout rect = the '
           'un-tilted 226×15pt box.', bleed=(7, 6, 10, 10))


def card_rule():
    """Dashed fold line pressed into the white card (V4 §1 rule 1: no vector dividers): kraftbake.score_line on the
    white paint film — groove a shade darker, the lit lip just below it; dash lengths wander."""
    w, h, b = 272, 2, 1
    W, H = w * S, (h + 2 * b) * S
    B = lin(hexrgb(WHITE_CARD))
    col = np.empty((H, W, 3), np.float32)
    col[:] = B
    col, _ = ext.score_line(col, np.zeros((H, W), np.float32), 3, W - 3, H / 2, 4791, dash=12, gap=7, dark=0.34)
    out.save('card-rule', ext.overlay(col, WHITE_CARD), 'slice',
             'Dashed fold line on the white card (section divider, card mode): a pressed crease, not a drawn rule. '
             'Layout 272×2pt (inner width of the 308pt card); stretch ≤ ±20 % or BakedSlice(tile: true) for the wide '
             'card (432–436pt).',
             bleed=(b, 0, b, 0), insets=(b, 3, b, 3), ground='white card')
