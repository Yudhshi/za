// IELTS アプリ(ielts-dist)の素材を、Yudh の「英語」タブ用の JSON に取り込む。
// 使い方: node scripts/import-english.mjs <ielts-dist のフォルダ>
//   例:  node scripts/import-english.mjs ~/Downloads/ielts-dist-v71
// 出力: Resources/English/{vocab,paraphrase,dictation,dict}.json
//
// 教材から抜き出した語表を含むので、公開リポジトリには載せない(Resources/English/ は .gitignore 済み)。
// build-app.sh がこのフォルダを .app に同梱する。依存パッケージ不要(node だけで動く)。
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const src = process.argv[2] && resolve(process.argv[2].replace(/^~(?=$|\/)/, process.env.HOME ?? "~"));
if (!src || !existsSync(src)) {
  console.error("使い方: node scripts/import-english.mjs <ielts-dist のフォルダ>");
  process.exit(1);
}
const out = join(dirname(fileURLToPath(import.meta.url)), "../Resources/English");
mkdirSync(out, { recursive: true });

/** `window.X = ...` 形式の JS を読み、window に載ったものを返す(dist/ の下にあってもよい) */
function load(rel) {
  const file = [join(src, rel), join(src, "dist", rel)].find(existsSync);
  if (!file) {
    console.warn(`  見つからない: ${rel}(このモードはスキップ)`);
    return {};
  }
  const window = {};
  const ctx = { window, globalThis: window, module: undefined };
  vm.runInNewContext(readFileSync(file, "utf8"), ctx, { filename: file });
  return window;
}

function write(name, data, count) {
  writeFileSync(join(out, name), JSON.stringify(data));
  console.log(`  ${name}: ${count}`);
}

const { DICT_MINI: dict = {} } = load("dict-mini.js");
const lookupZh = (w) => dict[w.toLowerCase()]?.[1];

// 単語:分層詞池。IELTS 4〜5 相当の B1 から始め、B2 → C1 → C2、A2 は最後
{
  const { VOCAB_POOL_NEW: pool = [] } = load("vocab/vocab-pool.js");
  const order = { b1: 0, b2: 1, c1: 2, c2: 3, a2: 4 };
  const vocab = pool
    .filter((v) => v.word && v.meaningZh)
    .map((v, i) => ({ v, i }))
    .sort((a, b) => (order[a.v.level] ?? 9) - (order[b.v.level] ?? 9) || a.i - b.i)
    .map(({ v }) => ({
      id: v.id, w: v.word, ph: v.phonetic || undefined, pos: v.partOfSpeech || undefined,
      zh: v.meaningZh, ex: v.exampleEn || undefined, lv: v.level,
    }));
  if (vocab.length) write("vocab.json", vocab, vocab.length);
}

// 同替:刘洪波 考点词真经。聴力 179 → 阅读 538 の順、原書の重要度(n)順
{
  const { PARAPHRASE_BANK: bank } = load("data/paraphrase-bank.js");
  const entries = (bank?.banks ?? []).flatMap((b) =>
    b.entries
      .map((e, i) => ({ e, i }))
      .sort((x, y) => (x.e.n ?? 1e9) - (y.e.n ?? 1e9) || x.i - y.i)
      .map(({ e }) => ({
        w: e.w, pos: e.pos || undefined, zh: e.zh || lookupZh(e.w) || undefined,
        syn: (e.syn ?? []).filter(Boolean), skill: b.skill,
      }))
      .filter((e) => e.syn.length > 0)
  );
  if (entries.length) write("paraphrase.json", entries, entries.length);
}

// 聴写:王陆 语料库。原書の練習順(3 名詞 → 4 形容詞副詞 → 5 連読吞音 → 11 総合 → 807 場面)。
// 8 章(数字・住所・日付)は表記ゆれの判定が難しいので入れない。同じ語は最初の 1 回だけ
{
  const { WANGLU_CORPUS: corpus } = load("data/wanglu-corpus.js");
  const chapterOrder = [3, 4, 5, 11, 807];
  const seen = new Map();
  for (const ch of chapterOrder) {
    for (const set of (corpus?.sets ?? []).filter((s) => s.chapter === ch)) {
      for (const x of set.words) {
        const w = (x.w ?? "").trim();
        if (!w || /\d/.test(w)) continue;
        const key = w.toLowerCase();
        const prev = seen.get(key);
        if (prev) {
          prev.ipa ??= x.ipa || undefined;
          prev.zh ??= x.zh || undefined;
          continue;
        }
        seen.set(key, { w, ipa: x.ipa || undefined, zh: x.zh || lookupZh(w) || undefined, set: set.label });
      }
    }
  }
  const words = [...seen.values()];
  if (words.length) write("dictation.json", words, words.length);
}

// 辞書:ECDICT(MIT License, github.com/skywind3000/ECDICT)の抜粋 { word: [音標, 釈義] }
if (Object.keys(dict).length) write("dict.json", dict, Object.keys(dict).length);

// 許可表示:ECDICT は MIT(著作権表示と許可文の同梱が条件)。教材由来の語表は個人学習用で再配布しない
writeFileSync(
  join(out, "LICENSES.txt"),
  `dict.json — ECDICT (https://github.com/skywind3000/ECDICT), MIT License
Copyright (c) 2017 skywind3000

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions: The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
WITHOUT WARRANTY OF ANY KIND.

paraphrase.json / dictation.json / vocab.json — 摘自刘洪波《雅思考点词真经》、王陆《雅思王听力真题语料库》与 IELTS app 的分级词池。
仅供个人学习使用，不得再分发（Resources/English/ 与 dist/ 均不进入仓库、不分享）。
`
);
console.log(`→ ${out}`);
