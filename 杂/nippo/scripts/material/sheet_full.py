"""Full review sheet: assembled mockups (tiles + 9-slices stretched to real sizes + sprites + glyph runs, composed the
way SwiftUI will), every asset at 1×, and 100 % (@2x) crops.  Live text is drawn with a stand-in font."""
import numpy as np
from PIL import Image, ImageDraw

from sheet import BG, font, nine, over, rrect_mask, scaled, tile_fill

INK = (22, 22, 21)
WHITE = (244, 243, 238)
DIM = (171, 175, 178)
TEAL = (18, 233, 211)
CJK = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'


class Board:
    """A 2x canvas in pt coordinates."""

    def __init__(self, mm, w, h, bg=BG):
        self.m, self.w, self.h = mm, w, h
        self.c = np.zeros((int(h * 2), int(w * 2), 3), np.float32)
        self.c[:] = np.array(bg, np.float32) / 255

    def e(self, aid):
        return self.m.m['assets'][aid]

    def slice(self, aid, x, y, w, h):
        e = self.e(aid)
        bt, bl, bb, br = e['bleed']
        W, H = w + bl + br, h + bt + bb
        img = self.m.img(aid)
        if e['kind'] == 'slice':
            img = nine(img, e['insets'], int(round(W * 2)), int(round(H * 2)))
        over(self.c, img, (x - bl) * 2, (y - bt) * 2)

    def sprite(self, aid, x, y, scale=1.0):
        """layout-rect top-left at (x, y)."""
        e = self.e(aid)
        bt, bl = e['bleed'][0], e['bleed'][1]
        over(self.c, scaled(self.m.img(aid), scale), (x - bl * scale) * 2, (y - bt * scale) * 2)

    def anchored(self, aid, x, y, scale=1.0):
        e = self.e(aid)
        if 'anchor' in e:
            ax, ay = e['anchor']
        else:                      # centre of the layout rect
            bt, bl, bb, br = e['bleed']
            ax, ay = bl + (e['size'][0] - bl - br) / 2, bt + (e['size'][1] - bt - bb) / 2
        over(self.c, scaled(self.m.img(aid), scale), (x - ax * scale) * 2, (y - ay * scale) * 2)

    def word(self, aid, x, baseline, scale=1.0):
        e = self.e(aid)
        over(self.c, scaled(self.m.img(aid), scale), (x - e['bleed'][1] * scale) * 2, (baseline - e['baseline'] * scale) * 2)
        return x + (e['size'][0] - e['bleed'][1] - e['bleed'][3]) * scale

    def glyphs(self, sid, s, x, baseline, scale=1.0):
        g = self.m.m['glyphs'][sid]
        atlas = self.m.img(sid)
        asc = g['lineHeight'][0]
        pen = x
        for ch in s:
            gl = g['glyphs'][ch]
            rx, ry, rw, rh = gl['rect']
            piece = scaled(atlas[ry:ry + rh, rx:rx + rw], scale)
            over(self.c, piece, (pen + gl['bearing'] * scale) * 2, (baseline - asc * scale) * 2)
            pen += gl['advance'] * scale
        return pen

    def text(self, x, y, s, size, fill=WHITE, path=CJK, anchor='la'):
        im = Image.fromarray((np.clip(self.c, 0, 1) * 255 + 0.5).astype(np.uint8))
        f = font_path(path, int(size * 2))
        ImageDraw.Draw(im).text((x * 2, y * 2), s, font=f, fill=fill, anchor=anchor)
        self.c = np.asarray(im, np.float32) / 255

    def panel(self, x, y, w, h, header=56, frame='panel-frame-night'):
        """Concrete slab: quiet tile everywhere, texture tile in the header band and the 18pt edge band (feathered),
        clipped to the 20pt rounded rect, then the frame slice."""
        quiet, tex = self.m.img('concrete-quiet-night'), self.m.img('concrete-night')
        X0, Y0, X1, Y1 = int(x * 2), int(y * 2), int((x + w) * 2), int((y + h) * 2)
        rr = rrect_mask(X1 - X0, Y1 - Y0, 40)
        tile_fill(self.c, quiet, X0, Y0, X1, Y1, mask=rr)
        zone = np.zeros((Y1 - Y0, X1 - X0), np.float32)
        zone[:header * 2] = 1
        e = 36
        zone[:, :e] = 1
        zone[:, -e:] = 1
        zone[-e:] = 1
        from scipy import ndimage as ndi
        zone = ndi.gaussian_filter(zone, 8) * rr
        tile_fill(self.c, tex, X0, Y0, X1, Y1, mask=zone)
        self.slice(frame, x, y, w, h)

    def kraft(self, x, y, w, h):
        self.slice('kraft-sheet-night', x, y, w, h)

    def img(self, scale=1):
        a = (np.clip(self.c, 0, 1) * 255 + 0.5).astype(np.uint8)
        im = Image.fromarray(a)
        if scale != 2:
            im = im.resize((int(im.width * scale / 2), int(im.height * scale / 2)), Image.LANCZOS)
        return im


_FP = {}


def font_path(p, size):
    from PIL import ImageFont
    k = (p, size)
    if k not in _FP:
        _FP[k] = ImageFont.truetype(p, size)
    return _FP[k]


def board_cells(b, x, y, states, now=None):
    names = dict(e='cell-empty-night', p='cell-past-night', g='cell-meeting-night', gp='cell-meeting-past-night',
                 t='cell-teal-night', d='cell-teal-dots-night')
    xs = []
    cx = x
    for i, st in enumerate(states.split(',')):
        b.sprite(names[st], cx, y)
        xs.append(cx)
        cx += 10.5 + 2 + (3 if (i + 1) % 4 == 0 else 0)
    if now is not None:
        i = int(now)
        nx = xs[i] + 12.5 * (now - i) - 1
        b.sprite('now-notch-night', nx, y)
    for h in range(10):
        lx = x + h * 53 - (0 if h == 0 else 2.5)
        b.text(lx, y + 26, str(9 + h), 12, DIM, '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
               anchor='la' if h == 0 else ('ra' if h == 9 else 'ma'))


# ---------------------------------------------------------------- mockups
def today_calm(m):
    b = Board(m, 560, 700)
    b.panel(20, 20, 520, 660)
    x0 = 44
    end = b.word('day-tuesday-white-night', x0, 20 + 22 + 31)
    b.text(end + 52, 20 + 33, '已工作', 12, DIM)
    b.text(end + 92, 20 + 28, '4:00', 20, WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.slice('tab-chip-night', 20 + 520 - 24 - 132, 20 + 26, 58, 32)
    b.text(20 + 520 - 24 - 132 + 14, 20 + 33, '今日', 14, INK)
    b.text(20 + 520 - 24 - 60, 20 + 33, '英语 12', 14, DIM)
    hx, hy, hw, hh = x0, 92, 472, 230
    b.slice('hero-calm-night', hx, hy, hw, hh)
    e = b.e('creature-tue-grey')
    ix, iy, ix1, iy1 = e['ink']            # [x0, y0, x1, y1] in the layout rect
    iw, ih = ix1 - ix, iy1 - iy
    sc = hh * 0.74 / ih
    cx = hx + hw - 10 - (ix + iw) * sc
    cy = hy + hh - 8 - (iy + ih) * sc
    b.sprite('creature-tue-grey', cx, cy, sc)
    end = b.word('shout-next-teal-night', hx + 20, hy + 16 + 18)
    b.text(end + 14, hy + 16, '16:30–17:00', 17, WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.text(hx + 20, hy + 48, '1on1', 20, WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    end = b.glyphs('big-teal', '90', hx + 20, hy + 186)
    b.text(end + 14, hy + 166, '分钟后', 20, TEAL)
    b.sprite('cell-teal-night', hx + 20, hy + 196)
    b.sprite('cell-teal-night', hx + 32.5, hy + 196)
    b.text(hx + 52, hy + 198, '30 分钟', 13, WHITE)
    b.slice('concrete-seam-night', 20, 344, 520, 12)
    board_cells(b, x0, 372, 'p,p,p,p,gp,gp,p,p,p,p,p,p,p,p,p,p,p,p,p,p,gp,gp,gp,gp,e,e,e,e,e,e,g,g,e,e,e,e', now=24.0)
    rows = [('10:00', '朝会', False), ('14:00', 'デザインレビュー（gen2 ナビゲーション）', False), ('16:30', '1on1', True)]
    for i, (t, s, sel) in enumerate(rows):
        y = 430 + i * 40
        if sel:
            b.slice('bar-teal-night', 20 + 18, y + 4, 6, 24)
        b.text(x0 + 20, y + 8, t, 15, TEAL if sel else WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')
        b.text(x0 + 80, y + 8, s, 15, WHITE)
    b.text(x0 + 6, 556, '任务 2', 12, DIM)
    b.sprite('checkbox-night', x0 + 6, 580)
    b.text(x0 + 34, 579, '事例公開', 15, WHITE)
    b.sprite('checkbox-checked-night', x0 + 6, 612)
    b.text(x0 + 34, 611, 'Ph2 - navigate', 15, WHITE)
    b.text(x0 + 4, 648, '已坐 47 分钟', 14, WHITE)
    b.slice('tag-orange-night', x0 + 100, 645, 56, 24)
    b.text(x0 + 108, 650, '到点了', 13, INK)
    return b


def today_event(m):
    b = Board(m, 560, 600)
    b.panel(20, 20, 520, 560)
    hx, hy, hw, hh = 44, 60, 472, 236
    # drips first so their root tucks under the slab edge
    for k, (dx, n) in enumerate(((60, 5), (300, 3), (440, 4))):
        a = b.e(f'drip-teal-{n}')['anchor']
        b.anchored(f'drip-teal-{n}', hx + dx, hy + hh - 1)
    b.slice('hero-event-night', hx, hy, hw, hh)
    end = b.word('shout-next-black-night', hx + 20, hy + 16 + 18)
    b.text(end + 14, hy + 16, '14:00–15:00', 17, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.text(hx + 20, hy + 48, 'デザインレビュー（gen2 ナビゲーション）', 20, INK)
    end = b.glyphs('big-black', '04', hx + 20, hy + 190)
    b.text(end + 14, hy + 170, '分钟后', 20, INK)
    for i in range(4):
        b.sprite('cell-black-night', hx + 20 + 12.5 * i, hy + 200)
    b.text(hx + 76, hy + 202, '60 分钟', 13, INK)
    b.slice('button-orange-ringed-night', hx + hw - 20 - 120, hy + 120, 120, 50)
    b.text(hx + hw - 20 - 60, hy + 145, '加入会议', 17, INK, anchor='mm')
    board_cells(b, 44, 340, 'p,p,p,p,gp,gp,p,p,p,p,p,p,p,p,p,p,p,p,p,p,t,t,t,t,e,e,e,e,e,e,g,g,e,e,e,e', now=20.0)
    # hero 00 (orange) + tomorrow (03) below
    zx, zy = 44, 400
    b.slice('hero-zero-night', zx, zy, 472, 150)
    b.word('shout-now-black-night', zx + 20, zy + 34)
    b.glyphs('big-black', '00', zx + 20, zy + 128, 0.62)
    b.text(zx + 130, zy + 108, '分钟后', 20, INK)
    return b


def tomorrow(m):
    b = Board(m, 560, 280)
    b.panel(20, 20, 520, 250)
    hx, hy, hw, hh = 44, 40, 472, 190
    b.slice('hero-calm-night', hx, hy, hw, hh)
    e = b.e('creature-wed-grey')
    ix, iy, ix1, iy1 = e['ink']            # [x0, y0, x1, y1] in the layout rect
    iw, ih = ix1 - ix, iy1 - iy
    sc = hh * 0.76 / ih
    b.sprite('creature-wed-grey', hx + hw - 10 - (ix + iw) * sc, hy + hh - 8 - (iy + ih) * sc, sc)
    end = b.word('shout-tomorrow-teal-night', hx + 20, hy + 34)
    b.word('dayshout-wednesday-white-night', end + 10, hy + 34)
    b.text(hx + 20, hy + 46, '朝会', 20, WHITE)
    b.glyphs('big-teal', '10:00', hx + 20, hy + 150, 80 / 132)
    b.sprite('cell-outline-night', hx + 20, hy + 158)
    b.sprite('cell-outline-night', hx + 32.5, hy + 158)
    b.text(hx + 52, hy + 160, '30 分钟 · 到 10:30', 13, WHITE)
    return b


def english(m):
    b = Board(m, 560, 700)
    b.panel(20, 20, 520, 660)
    x0 = 44
    b.word('day-tuesday-white-night', x0, 73)
    b.slice('tab-chip-night', x0, 92, 62, 32)
    b.text(x0 + 12, 99, '单词 8', 14, INK)
    b.text(x0 + 82, 99, '考点词 4    语料    词典', 14, DIM)
    cx, cy, cw, ch = x0, 140, 330, 330
    b.anchored('drip-white-3', cx + 40, cy + ch - 1)
    b.anchored('drip-white-5', cx + 270, cy + ch - 1)
    b.slice('card-white-night', cx, cy, cw, ch)
    b.slice('plate-black-night', cx + 18, cy + 18, 40, 24)
    b.text(cx + 27, cy + 22, 'B1', 13, WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.slice('tag-orange-night', cx + 66, cy + 18, 58, 24)
    b.text(cx + 74, cy + 22, 'NEW', 13, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.slice('frame-black-night', cx + 132, cy + 18, 48, 24)
    b.text(cx + 141, cy + 22, '名词', 13, INK)
    b.text(cx + 18, cy + 50, 'storey', 60, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.text(cx + 18, cy + 132, '复习记录', 12, (42, 41, 38))
    b.slice('band-black-night', cx + 18, cy + 152, 294, 34)
    states = ['good', 'fuzzy', 'good', 'good', 'forgot', 'current', 'empty', 'empty', 'empty', 'empty']
    for i, st in enumerate(states):
        b.sprite(f'rate-18-{st}', cx + 26 + i * 27.5, cy + 160)
    b.text(cx + 18, cy + 214, '释义', 13, (42, 41, 38))
    b.slice('redact-black-night', cx + 60, cy + 204, 134, 35)
    b.slice('redact-black-night', cx + 18, cy + 256, 270, 15)
    # stamp slot + session board on concrete
    b.anchored('stamp-nice-night', 386 + 88, 140 + 50)
    b.text(386, 252, '本轮', 12, DIM)
    b.text(486, 252, '13/20', 13, WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf')
    seq = ['good', 'good', 'easy', 'fuzzy', 'good', 'forgot', 'good', 'good', 'easy', 'good', 'fuzzy', 'good', 'current',
           'empty', 'empty', 'empty', 'empty', 'empty', 'empty', 'empty']
    for i, st in enumerate(seq):
        r, c = divmod(i, 4)
        b.sprite(f'rate-24-{st}', 386 + c * 30, 272 + r * 30)
    # rating buttons
    for i, (lab, key, st) in enumerate((('忘了', '1', 'forgot'), ('模糊', '2', 'fuzzy'), ('记住了', '3', 'good'), ('太简单', '4', 'easy'))):
        x = x0 + i * 120
        b.slice('block-teal-night' if i == 2 else 'block-slate-night', x, 500, 112, 52)
        b.sprite(f'rate-14-{st}', x + 12, 519)
        b.text(x + 34, 516, f'{key}  {lab}', 15, INK if i == 2 else WHITE)
    b.text(x0, 574, '这一张 storey → 记住了', 12.5, DIM)
    b.text(x0 + 4, 640, '已坐 47 分钟', 14, WHITE)
    b.slice('tag-orange-night', x0 + 100, 637, 56, 24)
    b.text(x0 + 108, 642, '到点了', 13, INK)
    return b


def english2(m):
    """06b options + MISS, 07 input + secondary, 08 badge + 20/20."""
    b = Board(m, 560, 760)
    b.panel(20, 20, 520, 720)
    x0 = 44
    b.anchored('stamp-miss-night', 386 + 88, 40 + 50)
    opts = [('block-teal-night', '1  book', '正确答案 ✓', INK), ('block-slate-night', '2  refund', '', WHITE),
            ('block-grey-night', '3  cancel', '你的选择 ✕', INK), ('block-slate-night', '4  deliver', '', WHITE)]
    for i, (aid, s, note, colr) in enumerate(opts):
        r, c = divmod(i, 2)
        x, y = x0 + c * 240, 150 + r * 64
        b.slice(aid, x, y, 233, 54)
        b.text(x + 16, y + 15, s, 20, colr, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
        if note:
            b.text(x + 140, y + 19, note, 12, colr)
    # 07: input frame on a card + secondary / primary buttons
    b.slice('card-white-night', x0, 300, 330, 120)
    b.anchored('button-play-orange-night', x0 + 44, 340)
    b.text(x0 + 76, 328, '播放', 20, INK)
    b.slice('input-frame-night', x0 + 18, 362, 294, 46)
    b.text(x0 + 30, 372, 'i n s u r e n c e', 20, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
    b.slice('frame-white-night', x0, 440, 120, 50)
    b.text(x0 + 60, 465, '加入错词本', 16, WHITE, anchor='mm')
    b.slice('button-orange-night', x0 + 472 - 92, 440, 92, 50)
    b.text(x0 + 472 - 46, 465, '下一个', 16, INK, anchor='mm')
    # 08 badge
    cx, cy = x0, 510
    b.slice('card-white-night', cx, cy, 472, 200)
    b.slice('plate-black-night', cx + 18, cy + 18, 54, 26)
    b.text(cx + 28, cy + 22, '本轮', 13, WHITE)
    b.slice('tag-teal-night', cx + 80, cy + 18, 86, 26)
    b.text(cx + 92, cy + 23, 'CLEAR', 13, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.glyphs('count-black', '20/20', cx + 18, cy + 102)
    b.text(cx + 18, cy + 120, '全部完成，地盘喷满了', 14, (42, 41, 38))
    b.slice('badge-plate-night', cx + 300, cy + 60, 142, 105)
    b.anchored('creature-tue-teal', cx + 300 + 71, cy + 60 + 52.5)
    return b


def posture(m):
    b = Board(m, 820, 580)
    # popup 10 (standing): kraft 360 x 484
    px, py = 30, 40
    b.kraft(px, py, 360, 484)
    b.slice('tape-handle-night', px + 180 - 58, py - 11, 116, 26)
    b.text(px + 180, py + 2, 'STRETCH', 12, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', anchor='mm')
    b.text(px + 22, py + 44, '站立中', 14, INK)
    b.glyphs('timer-black', '12:30', px + 81, py + 66)
    b.sprite('pose-shoulder-rolls', px + 22, py + 80, 132 / 240)
    b.text(px + 168, py + 104, '第 2 步 / 共 3 步', 13, (62, 47, 28))
    b.text(px + 168, py + 126, '转肩', 30, INK)
    b.text(px + 168, py + 172, '10 次 · 前后各半', 15, INK)
    b.slice('kraft-score', px + 22, py + 222, 316, 8)
    fx, fy = px + 22, py + 238
    b.sprite('frieze-ground', fx, fy)
    for step, st in (('shoulder-blades', 'done'), ('shoulder-rolls', 'current'), ('chin-tuck', 'future')):
        aid = f'frieze-{step}-{st}'
        b.sprite(aid, fx + b.e(aid)['origin'][0], fy)
    b.text(px + 70, py + 356, '✓ 夹肩胛骨', 13, (62, 47, 28), anchor='mm')
    b.text(px + 180, py + 356, '转肩', 13, INK, anchor='mm')
    b.text(px + 290, py + 356, '收下巴', 13, (62, 47, 28), anchor='mm')
    b.anchored('drip-teal-2', px + 22 + 120, py + 412 + 49)
    b.slice('button-teal-night', px + 22, py + 412, 169, 50)
    b.text(px + 22 + 84, py + 437, '下一步', 17, INK, anchor='mm')
    b.slice('frame-white-night', px + 203, py + 412, 135, 50)
    b.text(px + 203 + 67, py + 437, '结束拉伸', 17, WHITE, anchor='mm')
    # popup 09 (stand up) with the weekday ghost
    qx, qy = 430, 40
    b.kraft(qx, qy, 360, 384)
    gh = b.m.img('kraft-ghost-tue')
    from sheet import over as _over
    clip = np.zeros_like(gh)
    clip[...] = gh
    h_avail = int((384 - 84) * 2)
    _over(b.c, clip[:h_avail], qx * 2, (qy + 84) * 2)
    b.slice('tape-handle-night', qx + 180 - 62, qy - 11, 124, 26)
    b.text(qx + 180, qy + 2, 'STAND UP', 12, INK, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', anchor='mm')
    b.sprite('pose-stand-up', qx + 22, qy + 30, 132 / 240)
    b.text(qx + 168, qy + 47, '站起来\n了吗？', 30, INK)
    b.text(qx + 168, qy + 127, '已经坐了 47 分钟', 13, (62, 47, 28))
    b.slice('kraft-score', qx + 22, qy + 172, 316, 8)
    b.sprite('pose-shoulder-blades', qx + 22, qy + 190, 100 / 240)
    b.text(qx + 138, qy + 207, '夹肩胛骨 · 1 分钟', 15, INK)
    b.slice('plate-black-night', qx + 138, qy + 241, 54, 32)
    b.text(qx + 150, qy + 248, '90°', 15, WHITE, '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
    b.slice('tag-orange-night', qx + 202, qy + 241, 76, 32)
    b.text(qx + 212, qy + 249, '47 分钟', 14, INK)
    b.slice('button-teal-night', qx + 22, qy + 312, 169, 50)
    b.text(qx + 22 + 84, qy + 337, '站起来了', 17, INK, anchor='mm')
    b.slice('frame-white-night', qx + 203, qy + 312, 135, 50)
    b.text(qx + 203 + 67, qy + 337, '15 分钟后', 17, WHITE, anchor='mm')
    return b


def stretch(m):
    """9-slices at several real sizes on concrete: proves the cap insets."""
    b = Board(m, 1200, 640)
    b.panel(10, 10, 1180, 620, header=0, frame='panel-frame-night')
    lab = DIM
    y = 40
    for i, (w, h) in enumerate(((472, 230), (472, 170), (472, 280))):
        x = 40 + i * 0
    b.slice('hero-calm-night', 40, 40, 472, 230)
    b.text(40, 276, 'hero-calm 472×230', 12, lab)
    b.slice('hero-calm-night', 560, 40, 472, 170)
    b.text(560, 216, 'hero-calm 472×170', 12, lab)
    b.slice('hero-event-night', 40, 310, 472, 280)
    b.text(40, 596, 'hero-event 472×280', 12, lab)
    b.slice('card-white-night', 560, 250, 330, 300)
    b.text(560, 556, 'card-white 330×300', 12, lab)
    xs = 920
    for j, (aid, w, h) in enumerate((('button-orange-night', 120, 50), ('button-orange-night', 92, 50),
                                     ('button-orange-night', 169, 50), ('frame-white-night', 120, 50),
                                     ('block-slate-night', 233, 54), ('block-teal-night', 112, 52))):
        yy = 250 + j * 62
        b.slice(aid, xs, yy, w, h)
        b.text(xs, yy + h + 1, f'{aid.replace("-night", "")} {w}×{h}', 10, lab)
    return b


def card_tall(m):
    b = Board(m, 420, 460)
    b.panel(10, 10, 400, 440, header=0)
    b.slice('card-white-night', 40, 40, 330, 380)
    b.text(40, 425, 'card-white 330×380', 12, DIM)
    return b


# ---------------------------------------------------------------- every asset at 1x
def grid(m, width=2400):
    pad, lab = 14, 13
    items = list(m.m['assets'].items()) + [(k, None) for k in m.m['glyphs']]
    tiles = []
    for aid, e in items:
        im = m.img(aid)
        im1 = scaled(im, 0.5)
        tiles.append((aid, im1))
    x, y, rowh = pad, pad + 40, 0
    pos = []
    for aid, im in tiles:
        w, h = im.shape[1], im.shape[0] + lab + 4
        w = max(w, len(aid) * 6 + 4)
        if x + w > width - pad:
            x, y = pad, y + rowh + pad
            rowh = 0
        pos.append((aid, im, x, y))
        x += w + pad
        rowh = max(rowh, h)
    H = y + rowh + pad
    c = np.zeros((H, width, 3), np.float32)
    c[:] = np.array(BG) / 255
    grounds = {'concrete': (41, 44, 47), 'black slab': (27, 28, 29), 'black plate': (25, 25, 24),
               'white card': (244, 243, 238), 'kraft': (196, 156, 105), 'teal paint': (18, 233, 211)}
    for aid, im, x, y in pos:
        e = m.m['assets'].get(aid, {})
        g = e.get('ground')
        if g is None and aid in m.m['glyphs']:
            g = {'big-teal': 'black slab', 'big-black': 'teal paint', 'timer-black': 'kraft', 'count-black': 'white card'}.get(aid)
        if g in grounds:
            c[y + lab + 4:y + lab + 4 + im.shape[0], x:x + im.shape[1]] = np.array(grounds[g]) / 255
        over(c, im, x, y + lab + 4)
    pil = Image.fromarray((c * 255 + 0.5).astype(np.uint8))
    d = ImageDraw.Draw(pil)
    d.text((pad, 10), f'EVERY ASSET AT 1×  ·  {len(pos)} images  ·  each on its manifest ground (concrete / black slab / white card / kraft / teal), sheet #161719', font=font(20, True), fill=(236, 235, 230))
    for aid, im, x, y in pos:
        d.text((x, y), aid, font=font(10), fill=(170, 174, 178))
    return pil


def build(path, m):
    boards = [('TODAY · calm 01b (panel 520×660: tiles + frame, hero-calm 472×230, creature, NEXT, 90, board, rows)', today_calm(m)),
              ('TODAY · event 01 (hero-event 472×236 + drips + ringed button) · hero-zero 472×150', today_event(m)),
              ('ENGLISH · 04/05 (card 330×330, tags, band + 18pt cells, redaction, NICE!, 24pt board, rating blocks)', english(m)),
              ('ENGLISH · 06b options + MISS · 07 input / buttons · 08 badge + 20/20', english2(m)),
              ('TOMORROW · 03 (hero-calm 472×190, TOMORROW WEDNESDAY, 10:00 at 80pt, Baku)', tomorrow(m)),
              ('POSTURE · popup 10 (kraft 360×484, tape, timer, 混天绫, frieze) · popup 09 (kraft 360×384 + TUE ghost)', posture(m)),
              ('STRETCH TESTS · 9-slices at real sizes', stretch(m)), ('card 330×380', card_tall(m))]
    W = 2400
    ims = [(t, b.img(1)) for t, b in boards]
    # 100 % crops from the 2x boards
    crops = [('100% · calm hero: numerals + creature', boards[0][1].img(2).crop((88, 170, 88 + 980, 170 + 480))),
             ('100% · event hero edge, drips, ringed button', boards[1][1].img(2).crop((560, 200, 560 + 520, 200 + 460))),
             ('100% · card, band cells, redaction, NICE!, board', boards[2][1].img(2).crop((80, 270, 80 + 1000, 270 + 660))),
             ('100% · kraft: timer, 混天绫, frieze, buttons', boards[5][1].img(2).crop((60, 80, 60 + 740, 80 + 1000))),
             ('100% · badge + 20/20 + options', boards[3][1].img(2).crop((80, 1040, 80 + 980, 1040 + 400)))]
    g = grid(m, W)
    # layout: mockups in rows (wrap at W), then crops, then grid
    rows, cur, cw = [], [], 0
    for t, im in ims:
        if cw + im.width + 30 > W and cur:
            rows.append(cur)
            cur, cw = [], 0
        cur.append((t, im))
        cw += im.width + 30
    rows.append(cur)
    crow, cur, cw = [], [], 0
    for t, im in crops:
        if cw + im.width + 30 > W and cur:
            crow.append(cur)
            cur, cw = [], 0
        cur.append((t, im))
        cw += im.width + 30
    crow.append(cur)
    H = 70 + sum(max(im.height for _, im in r) + 50 for r in rows) + 50 + sum(max(im.height for _, im in r) + 50 for r in crow) + g.height
    out = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(out)
    d.text((24, 18), 'YUDH v12 · Resources/Material · night · contact sheet (1× = 1px per pt; crops at 100% = @2x)',
           font=font(26, True), fill=(236, 235, 230))
    y = 70
    for r in rows:
        x = 24
        for t, im in r:
            d.text((x, y), t, font=font(13), fill=(190, 194, 198))
            out.paste(im, (x, y + 22))
            x += im.width + 30
        y += max(im.height for _, im in r) + 50
    y += 20
    for r in crow:
        x = 24
        for t, im in r:
            d.text((x, y), t, font=font(13), fill=(190, 194, 198))
            out.paste(im, (x, y + 22))
            x += im.width + 30
        y += max(im.height for _, im in r) + 50
    out.paste(g, (0, y))
    out.save(path, optimize=True)
    # also keep the pieces next to the sheet for close inspection
    import os
    wd = os.path.join(os.path.dirname(os.path.abspath(path)), '_sheet')
    os.makedirs(wd, exist_ok=True)
    for i, (t, b) in enumerate(boards):
        b.img(2).save(os.path.join(wd, f'board{i}@2x.png'))
    print('sheet', out.size, path)
