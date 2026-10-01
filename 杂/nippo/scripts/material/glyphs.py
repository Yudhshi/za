#!/usr/bin/env python3
"""Stencil glyph atlas (Chromium mode).

Renders every stencil glyph the app needs with Archivo 900 (width axis per row) into ONE white-on-black atlas at
@2x pixels: src/glyphs/atlas.png + src/glyphs/atlas.json.  Same method as merge2/tex/glyphs.py (one glyph per
cell, every cell of a row shares the same line box, so the baseline is a constant per row).

The atlas is committed, so `make.py` never needs Chromium.  Re-run this only when a row / glyph is added:

    YUDH_RENDER=/path/to/render.sh python3 scripts/material/glyphs.py

YUDH_RENDER is a script `render.sh <html> <png> <w> <h>` that screenshots a page at device scale 2 (the design
scratchpad's render.sh swaps the Google Fonts <link> for a local copy).  Without it we call a headless Chromium
directly (CHROMIUM=/path/to/chrome or `chromium` on PATH); the page then loads Archivo from Google Fonts.
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'src', 'glyphs')

# (row prefix, size pt, wdth axis %, glyphs) — sizes are tokens.json type.* sizes
ROWS = [
    ('big', 132, 104, '0123456789:/'),         # bigNumber: hero countdown, 20/20
    ('n56', 56, 104, '0123456789/'),           # English 20/20 (stage clear)
    ('tm', 40, 104, '0123456789:'),            # posture popup timer 12:30
    ('day', 31, 125, 'MONDAYTUESWHRFI'),       # shoutDay: header weekday
    ('sm', 21, 125, 'NEXTOWMRDAYSUHFI'),       # shoutSmall: NEXT / NOW / TOMORROW / small weekday
    ('st', 32, 125, 'NICE!MS'),                # stamp letters
]


def page():
    cells, html, y = {}, [], 0
    for name, size, wd, chars in ROWS:
        cw, ch = int(size * 1.6), int(size * 1.25)
        for i, c in enumerate(dict.fromkeys(chars)):
            x = i * cw
            cells[f'{name}:{c}'] = [x, y, cw, ch, size, wd]
            html.append(f'<div style="position:absolute;left:{x}px;top:{y}px;width:{cw}px;height:{ch}px;'
                        f'font:900 {size}px/{ch}px Archivo;font-stretch:{wd}%;color:#fff;padding-left:{int(size * .12)}px">'
                        f'{c}</div>')
        y += ch
    W = max(c[0] + c[2] for c in cells.values()) + 10
    doc = ('<!doctype html><meta charset="utf-8"><link rel="stylesheet" '
           'href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,900">'
           f'<body style="margin:0;background:#000;width:{W}px;height:{y}px;position:relative">' + ''.join(html) + '</body>')
    return doc, cells, W, y


def render(html_path, png_path, w, h):
    rs = os.environ.get('YUDH_RENDER')
    if rs:
        subprocess.run([rs, html_path, png_path, str(w), str(h)], check=True, stdout=subprocess.DEVNULL)
        return
    chrome = os.environ.get('CHROMIUM') or shutil.which('chromium') or shutil.which('google-chrome')
    if not chrome:
        sys.exit('no renderer: set YUDH_RENDER=<render.sh> or CHROMIUM=<headless chrome>')
    subprocess.run([chrome, '--headless', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
                    '--force-device-scale-factor=2', '--virtual-time-budget=10000', f'--window-size={w},{h}',
                    f'--screenshot={png_path}', 'file://' + html_path], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    os.makedirs(OUT, exist_ok=True)
    doc, cells, W, H = page()
    hp = os.path.join(OUT, '_atlas.html')
    open(hp, 'w').write(doc)
    png = os.path.join(OUT, 'atlas.png')
    render(hp, png, W, H)
    os.remove(hp)
    # keep only the luminance (white glyphs on black) — smaller and exactly what bake.stencil_word reads
    from PIL import Image
    Image.open(png).convert('L').save(png, optimize=True)
    rows = {name: dict(size=size, wdth=wd, glyphs=''.join(dict.fromkeys(chars))) for name, size, wd, chars in ROWS}
    json.dump(dict(cells=cells, rows=rows, font='Archivo 900', scale=2), open(os.path.join(OUT, 'atlas.json'), 'w'),
              indent=0)
    print('atlas', W, H, len(cells))


if __name__ == '__main__':
    main()
