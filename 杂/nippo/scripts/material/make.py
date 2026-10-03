#!/usr/bin/env python3
"""Yudh v12 「Stencil Turf」 production material pipeline (night version).

    python3 scripts/material/make.py                 # bake everything; manifest.json is rebuilt from scratch
    python3 scripts/material/make.py --only concrete stencil   # some groups; their entries are MERGED into the
                                                     # existing manifest (other groups' entries are kept as they are)
    python3 scripts/material/make.py --sheet /path/material-sheet.png   # + review contact sheet (not in the repo)

Deterministic: every random draw is seeded; same inputs + same numpy/scipy/Pillow -> same pixels.
Needs numpy, scipy, Pillow; pyoxipng is optional (smaller files).  No Chromium: glyphs come from the committed
src/glyphs/atlas.png (re-render it with glyphs.py when glyphs are added).
"""
import argparse
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from yudhmat import out  # noqa: E402

GROUPS = ['concrete', 'paint', 'masked', 'stencil', 'drips', 'cells', 'creatures', 'poses', 'kraft', 'motion']

# ids no group bakes any more: dropped from the manifest and their PNGs deleted, also on an --only run of any group
RETIRED = {'concrete-quiet-night', 'pose-standing', 'pose-stand-up-s', 'pose-sit-down-s',
           'shout-tomorrow-black-night'} | \
          {f'rate-18-{s}' for s in ('easy', 'good', 'fuzzy', 'forgot', 'empty', 'current')} | \
          {f'drip-black-{n}' for n in range(1, 7)}


def run(group):
    mod = __import__(f'yudhmat.g_{group}', fromlist=['bake_all'])
    return mod.bake_all()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', nargs='*')
    ap.add_argument('--sheet')
    ap.add_argument('--no-optimise', action='store_true')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()
    out.OPTIMISE = not a.no_optimise
    out.RETIRED.update(RETIRED)
    groups = a.only or GROUPS
    seen = set()
    for g in groups:
        t = time.time()
        run(g)
        print(f"{g:10s} {time.time() - t:6.1f}s  total {out.total_bytes() / 1e6:.2f} MB", flush=True)
        if a.verbose:
            for k, (n, mode) in sorted(out.LOG.items()):
                if k not in seen:
                    print(f"   {k:40s} {n // 1024:5d} KB  {mode}")
                    seen.add(k)
    m = out.write_manifest(merge=bool(a.only), drop=out.RETIRED)
    n = len(m['assets']) + len(m['glyphs'])
    print(f'{n} images, {out.total_bytes() / 1e6:.2f} MB')
    if a.sheet:
        import sheet
        sheet.build(a.sheet)


if __name__ == '__main__':
    main()
