#!/usr/bin/env python3
"""Swift のコードが使う素材 id が manifest.json にあるかを調べる(素材を焼き直したら / 画面を書き換えたら)。

    python3 scripts/material/check_ids.py

文字列そのままの id は全部、補間のある id("pose-\\(name)" など)は既知の値(VALUES)で展開して調べる。
展開できない補間は一覧に出す(前方一致の素材は「使っている」とみなす)。どこからも参照されない素材も一覧に出す。
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
            'kraft-', 'tape-', 'frieze-', 'band-', 'plate-', 'input-', 'bar-', 'checkbox-', 'swatch-', 'tab-',
            'big-', 'mid-', 'count-', 'timer-')

# 補間に入りうる値(足りなければここに足す)
VALUES = {
    'day': ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'],
    'weekday': ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'],
    'pose': ['stretch', 'walk', 'chest-doorway', 'belly-breathing', 'shoulder-blades', 'shoulder-rolls',
             'neck-side', 'chin-tuck', 'sit-down', 'stand-up'],
    'mark': ['easy', 'good', 'fuzzy', 'forgot', 'empty', 'current'],
    'cell': ['empty', 'past', 'meeting', 'meeting-past', 'teal', 'teal-dots', 'black', 'black-dots', 'outline'],
}


# 補間の中身(\\(...))を、その式に出てくる名前から VALUES のどれで展開するか
HINTS = [
    (('creature', 'dayKey', 'Myth'), 'day'),
    (('ghost',), 'day'),
    (('name.lowercased', 'day.lowercased', 'weekday'), 'weekday'),
    (('pose', 'name'), 'pose'),
    (('kind.rawValue', 'mark'), 'mark'),
]


def expand(pattern):
    """補間を VALUES で展開する。展開できない補間は None(手で見る)"""
    parts = re.split(r'(\\\([^)]*\)?\)?)', pattern)
    options = []
    for part in parts:
        if not part.startswith('\\('):
            options.append([part])
            continue
        # frieze は 3 つの姿勢だけ、pose-…-s は焼いてある姿勢だけ(無ければ大きい方へ退く)なので展開しない
        if pattern.startswith('frieze-') or pattern.endswith('-s') or any(w in part for w in ('paint', 'state', 'suffix', 'size', '$0', 'index', '?')):
            return None
        key = None
        for words, value in HINTS:
            if any(w in part for w in words):
                key = value
                break
        if key is None:
            return None
        if pattern.startswith('cell-') and key == 'mark':
            key = 'cell'
        options.append(VALUES[key])
    return [''.join(p) for p in itertools.product(*options)]


def main():
    manifest = json.load(open(MANIFEST))
    ids = set(manifest['assets']) | set(manifest.get('glyphs', {}))
    literal, patterns = set(), set()
    for path in glob.glob(os.path.join(SRC, '*.swift')):
        text = re.sub(r'//[^\n]*', '', open(path, encoding='utf-8').read())
        for s in re.findall(r'"((?:[^"\\]|\\.)*)"', text):
            outside = re.sub(r'\\\((?:[^()]|\([^()]*\))*\)', '', s)
            if not s.startswith(PREFIXES) or ' ' in outside:
                continue
            (patterns if '\\(' in s else literal).add(s)
        # 動きの帯:Baked.frames("prefix", count: n) / BakedFrame(prefix: "prefix", count: n)
        for prefix, count in re.findall(r'(?:frames\(|hasFrames\(|prefix:\s*)"([^"]+)",\s*count:\s*(\d+)', text):
            literal.update(f'{prefix}{i}' for i in range(int(count)))
    used = set(literal)
    unchecked = []
    for p in sorted(patterns):
        expanded = expand(p)
        if expanded is None:
            unchecked.append(p)
            # 前方一致で使われていると見なす(未使用の一覧から外すだけ)
            head = p.split('\\(')[0]
            used.update(i for i in ids if i.startswith(head))
        else:
            used.update(expanded)
            literal.update(expanded)
    missing = sorted(s for s in literal if s not in ids and not s.endswith('-'))
    unused = sorted(i for i in ids if i not in used)
    print(f'{len(literal)} ids checked, {len(patterns)} interpolated patterns ({len(unchecked)} not expandable), '
          f'{len(ids)} assets in the manifest')
    for p in unchecked:
        print('  not expanded:', p)
    if unused:
        print('unused (no reference found):')
        for u in unused:
            print('  ', u)
    if missing:
        print('MISSING:')
        for m in missing:
            print('  ', m)
        sys.exit(1)


if __name__ == '__main__':
    main()
