import Foundation

/// 単語(IELTS アプリの分層詞池)。id は詞池の id(「b1-0807」など)
public struct VocabWord: Decodable, Equatable, Sendable {
    public let id: String
    public let w: String
    public let ph: String?
    public let pos: String?
    public let zh: String
    public let ex: String?
    public let lv: String

    public init(id: String, w: String, ph: String? = nil, pos: String? = nil, zh: String,
                ex: String? = nil, lv: String) {
        self.id = id
        self.w = w
        self.ph = ph
        self.pos = pos
        self.zh = zh
        self.ex = ex
        self.lv = lv
    }
}

/// 同義替換(刘洪波 考点词真经)。w が考点词、syn が真題での言い換え
public struct ParaphraseEntry: Decodable, Equatable, Sendable {
    public let w: String
    public let pos: String?
    public let zh: String?
    public let syn: [String]
    /// "listening" | "reading"
    public let skill: String

    public init(w: String, pos: String? = nil, zh: String? = nil, syn: [String], skill: String) {
        self.w = w
        self.pos = pos
        self.zh = zh
        self.syn = syn
        self.skill = skill
    }
}

/// 聴写の語(王陆 语料库)。set は原書の小節名(「特别名词」など)
public struct DictationWord: Decodable, Equatable, Sendable {
    public let w: String
    public let ipa: String?
    public let zh: String?
    public let set: String

    public init(w: String, ipa: String? = nil, zh: String? = nil, set: String) {
        self.w = w
        self.ipa = ipa
        self.zh = zh
        self.set = set
    }
}

/// 辞書を引いた結果
public struct DictHit: Equatable, Sendable {
    public let word: String
    public let ipa: String
    public let zh: String
}

/// 英語タブの素材一式。scripts/import-english.mjs が IELTS アプリから作った JSON を読む。
/// ファイルが無いモードは空のまま(画面で取り込み方を案内する)
public struct EnglishLibrary: Sendable {
    public var vocab: [VocabWord]
    public var paraphrases: [ParaphraseEntry]
    public var dictation: [DictationWord]
    /// ECDICT の抜粋 { 小文字の語: [音標, 釈義] }
    public var dictionary: [String: [String]]

    public init(vocab: [VocabWord] = [], paraphrases: [ParaphraseEntry] = [],
                dictation: [DictationWord] = [], dictionary: [String: [String]] = [:]) {
        self.vocab = vocab
        self.paraphrases = paraphrases
        self.dictation = dictation
        self.dictionary = dictionary
    }

    public var isEmpty: Bool {
        vocab.isEmpty && paraphrases.isEmpty && dictation.isEmpty && dictionary.isEmpty
    }

    /// dir の vocab.json・paraphrase.json・dictation.json・dict.json を読む(壊れた/無いファイルは空)
    public static func load(from dir: URL) -> EnglishLibrary {
        func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return EnglishLibrary(
            vocab: read("vocab.json", as: [VocabWord].self) ?? [],
            paraphrases: read("paraphrase.json", as: [ParaphraseEntry].self) ?? [],
            dictation: read("dictation.json", as: [DictationWord].self) ?? [],
            dictionary: read("dict.json", as: [String: [String]].self) ?? [:])
    }

    /// 辞書を引く。見つからなければ語形変化(-s / -es / -ies / -ed / -ing など)を外して引き直す
    public func lookup(_ query: String) -> DictHit? {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty else { return nil }
        if let entry = dictionary[word], entry.count >= 2 {
            return DictHit(word: word, ipa: entry[0], zh: entry[1])
        }
        // 語形変化を外した候補のうち、辞書にある最も長いもの(cares → care であって car ではない)
        let hits = Self.baseForms(of: word).filter { (dictionary[$0]?.count ?? 0) >= 2 }
        guard let best = hits.max(by: { $0.count < $1.count }), let entry = dictionary[best] else { return nil }
        return DictHit(word: best, ipa: entry[0], zh: entry[1])
    }

    /// 語形変化を外した候補(辞書に無い形も含む。引けた最初のものを使う)
    static func baseForms(of word: String) -> [String] {
        var forms: [String] = []
        func strip(_ suffix: String, add: String = "") {
            guard word.hasSuffix(suffix), word.count > suffix.count + 1 else { return }
            forms.append(String(word.dropLast(suffix.count)) + add)
        }
        strip("ies", add: "y")
        strip("ied", add: "y")
        strip("es")
        strip("s")
        strip("ing")
        strip("ing", add: "e")
        strip("ed")
        strip("ed", add: "e")
        strip("d")
        strip("er")
        strip("est")
        strip("ly")
        // running → run, stopped → stop(子音の重なり)
        for suffix in ["ing", "ed"] where word.hasSuffix(suffix) {
            let stem = word.dropLast(suffix.count)
            if stem.count >= 3, let last = stem.last, stem.dropLast().last == last {
                forms.append(String(stem.dropLast()))
            }
        }
        return forms
    }
}
