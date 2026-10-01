#!/usr/bin/env python3
"""Swift のコードが使う素材 id が manifest.json にあるかを調べる(素材を焼き直したら / 画面を書き換えたら)。

    python3 scripts/material/check_ids.py

文字列そのままの id は全部、補間のある id("pose-\\(name)" など)は既知の値で展開して調べる。
見つからない id があれば一覧を出して 1 で終わる(素材が無くても画面は単色と本物の文字で動くが、見た目は落ちる)。
"""
import glob
import itertools
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'Sources', 'NippoApp')
MANIFEST = os.path.join(ROOT, 'Resources', 'Material', 'manifest.json')

PREFIXES = ('concrete-', 'panel-', 'hero-', 'card-', 'chip-', 'tag-', 'button-', 'strip-', 'redact-', 'frame-',
            'block-', 'row-', 'mark-', 'letter-', 'rate-', 'shout-', 'dayshout-', 'day-', 'dot-', 'pose-',
            'stamp-', 'regmark-', 'cover-', 'flood-', 'drip-', 'badge-', 'cell-', 'now-', 'creature-',
            'kraft-', 'tape-', 'frieze-', 'band-', 'plate-', 'input-', 'bar-', 'checkbox-')

# 補間に入りうる値(足りなければここに足す)
VALUES = {
    'day': ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'],
    'weekday': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'],
    'pose': ['stretch', 'walk', 'chest-doorway', 'belly-breathing', 'shoulder-blades', 'shoulder-rolls',
             'neck-side', 'chin-tuck', 'sit-down', 'stand-up'],
    'mark': ['easy', 'good', 'fuzzy', 'forgot', 'empty', 'current'],
    'cell': ['empty', 'past', 'meeting', 'meeting-past', 'teal', 'teal-dots', 'black', 'black-dots', 'outline'],
}


def main():
    manifest = json.load(open(MANIFEST))
    ids = set(manifest['assets']) | set(manifest.get('glyphs', {}))
    literal, patterns = set(), set()
    for path in glob.glob(os.path.join(SRC, '*.swift')):
        text = re.sub(r'//[^\n]*', '', open(path, encoding='utf-8').read())
        for s in re.findall(r'"((?:[^"\\]|\\.)*)"', text):
            if not s.startswith(PREFIXES) or ' ' in s:
                continue
            (patterns if '\\(' in s else literal).add(s)
        # 動きの帯:Baked.frames("prefix", count: n) / BakedFrame(prefix: "prefix", count: n)
        for prefix, count in re.findall(r'(?:frames\(|prefix:\s*)"([^"]+)",\s*count:\s*(\d+)', text):
            literal.update(f'{prefix}{i}' for i in range(int(count)))
    missing = sorted(s for s in literal if s not in ids and not s.endswith('-'))
    print(f'{len(literal)} literal ids, {len(patterns)} interpolated patterns, {len(ids)} assets in the manifest')
    for p in sorted(patterns):
        print('  pattern', p)
    if missing:
        print('MISSING:')
        for m in missing:
            print('  ', m)
        sys.exit(1)


if __name__ == '__main__':
    main()
