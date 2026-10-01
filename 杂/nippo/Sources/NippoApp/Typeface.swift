import AppKit
import CoreText
import SwiftUI

// MARK: - 字体(Archivo / JetBrains Mono を同梱。中文は PingFang SC、日文は Hiragino Sans)

/// 欧文と数字の書体。可変フォントの wght / wdth 軸を直接指定する(SwiftUI の .width() はカスタム書体に効かないため)。
/// mixed = Archivo の欧文 + 中文 / 日文の級聯(会議名・日程・タスクのような混ざった文字)。中日文は直立・幅そのまま。
/// 同じ引数の字体は 1 回だけ作る(body の中で呼んでも CTFont を作り直さない)
enum Typeface {
    private static let archivoFile = "Fonts/Archivo[wdth,wght].ttf"
    private static let monoFile = "Fonts/JetBrainsMono[wght].ttf"

    private static let archivoBase: CTFontDescriptor? = descriptor(archivoFile)
    private static let monoBase: CTFontDescriptor? = descriptor(monoFile)

    private static let lock = NSLock()
    private static var fonts: [String: Font] = [:]

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        guard let url = BundledResource.url(file),
              let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        return list.first
    }

    private static func memo(_ key: String, _ make: () -> Font) -> Font {
        lock.lock()
        defer { lock.unlock() }
        if let font = fonts[key] { return font }
        let font = make()
        fonts[key] = font
        return font
    }

    // OpenType の軸タグ(4 文字を 32bit に詰めたもの)
    private static let wghtTag = 0x7767_6874  // 'wght'
    private static let wdthTag = 0x7764_7468  // 'wdth'

    private static func make(_ base: CTFontDescriptor, size: CGFloat, axes: [Int: CGFloat], tnum: Bool, italic: Bool,
                             cascade: [CTFontDescriptor] = []) -> CTFont {
        var attributes: [CFString: Any] = [
            kCTFontVariationAttribute: Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) }),
        ]
        if tnum {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1] as [CFString: Any],
            ]
        }
        if !cascade.isEmpty {
            attributes[kCTFontCascadeListAttribute] = cascade
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
        guard italic else { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
        // Archivo の可変版には斜体がないので、例文の斜体は傾きの行列で付ける(欧文だけに使う)
        var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        return CTFontCreateWithFontDescriptor(descriptor, size, &skew)
    }

    /// Archivo。weight 100–900、width 62–125(tokens の type.* と同じ数値)
    static func archivo(_ size: CGFloat, weight: CGFloat = 900, width: CGFloat = 100,
                        tnum: Bool = false, italic: Bool = false) -> Font {
        memo("a|\(size)|\(weight)|\(width)|\(tnum)|\(italic)") {
            guard let base = archivoBase else {
                var font = Font.system(size: size, weight: fallbackWeight(weight))
                if width >= 112 { font = font.width(.expanded) } else if width <= 90 { font = font.width(.condensed) }
                if tnum { font = font.monospacedDigit() }
                return italic ? font.italic() : font
            }
            return Font(make(base, size: size, axes: [wghtTag: weight, wdthTag: width], tnum: tnum, italic: italic))
        }
    }

    /// JetBrains Mono。weight 100–800
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        memo("m|\(size)|\(weight)") {
            guard let base = monoBase else {
                return .system(size: size, weight: fallbackWeight(weight), design: .monospaced)
            }
            return Font(make(base, size: size, axes: [wghtTag: weight], tnum: false, italic: false))
        }
    }

    /// 欧文・数字は Archivo、中文は PingFang SC、日文(仮名を含む)は Hiragino Sans。
    /// 会議名・日程・タスク・ボタンなど、中文と欧文が混ざる本物の文字はこれ。直立・幅 100 のまま
    static func mixed(_ size: CGFloat, weight: CGFloat = 600, japanese: Bool = false) -> Font {
        memo("x|\(size)|\(weight)|\(japanese)") {
            guard let base = archivoBase else {
                return .system(size: size, weight: fallbackWeight(weight))
            }
            let names = japanese ? [hiragino(weight), pingFang(weight)] : [pingFang(weight), hiragino(weight)]
            let cascade = names.map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, 0) }
            return Font(make(base, size: size, axes: [wghtTag: weight, wdthTag: 100], tnum: false, italic: false,
                             cascade: cascade))
        }
    }

    /// 中文だけの短い札(PingFang)。斜体・幅の変更はしない
    static func cjk(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// 文字列に仮名があれば日本語(会議名の漢字を日本の字形で出すため)
    static func isJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return true
            default: return false
            }
        }
    }

    private static func pingFang(_ weight: CGFloat) -> String {
        switch weight {
        case ..<450: return "PingFangSC-Regular"
        case ..<600: return "PingFangSC-Medium"
        default: return "PingFangSC-Semibold"
        }
    }

    private static func hiragino(_ weight: CGFloat) -> String {
        switch weight {
        case ..<450: return "HiraginoSans-W3"
        case ..<600: return "HiraginoSans-W5"
        case ..<750: return "HiraginoSans-W6"
        case ..<850: return "HiraginoSans-W7"
        default: return "HiraginoSans-W8"
        }
    }

    private static func fallbackWeight(_ value: CGFloat) -> Font.Weight {
        switch value {
        case ..<250: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}

// MARK: - 文字の役割(tokens.json の type.*)

/// 画面で使う文字の役割。大きな模板字(大数字・喊声・曜日・章)は素材の精灵で組むので、ここにあるのは本物の文字だけ。
/// 会議名・日程・タスクのように日本語が混ざりうるものは TypeRole.title(for:) / body(for:) と .typesetting(for:) を使う
enum TypeRole {
    /// 14:00–15:00、3:12(Archivo 900 / wdth 108 / 等幅数字)
    static let time = Typeface.archivo(17, weight: 900, width: 108, tnum: true)
    /// 単語(storey)
    static let word = Typeface.archivo(68, weight: 800, width: 100)
    /// 考点词(reserve)
    static let quizWord = Typeface.archivo(56, weight: 800, width: 100)
    /// /ˈstɔːri/(Archivo に IPA が無いので系统字体。字面は Archivo 500 に近い SF)
    static let ipa = Font.system(size: 17, weight: .medium)
    /// 例文(欧文のみ・斜体)
    static let example = Typeface.archivo(16, weight: 500, width: 100, italic: true)
    /// 聴写の入力欄・判定の字
    static let input = Typeface.archivo(20, weight: 600, width: 100)
    static let letter = Typeface.archivo(26, weight: 600, width: 100)
    /// 坐站小窓のつまみ(STAND UP / STRETCH / SIT DOWN)
    static let tape = Typeface.archivo(12, weight: 800, width: 112)
    /// 小さな札の欧文(CLEAR / NEW / B1)
    static let tagLatin = Typeface.archivo(12, weight: 900, width: 112)
    /// 盤面の時刻 9 … 18
    static let boardLabel = Typeface.mono(12, weight: 400)
    static let boardLabelNow = Typeface.mono(12, weight: 700)
    /// 回数・時刻(12/20、12:30)
    static let count = Typeface.mono(12, weight: 700)
    /// キーの説明(⌘Z / Space / ⏎ ⌫ は JetBrains Mono に無いので系统の等幅)
    static let keycap = Font.system(size: 12, weight: .bold, design: .monospaced)

    /// 站起来了吗？
    static let titleZh = Typeface.mixed(30, weight: 900)
    /// 楼层
    static let definition = Typeface.mixed(32, weight: 900)
    /// 加入会议 / 显示释义
    static let button = Typeface.mixed(17, weight: 900)
    /// 中文の本文(日程・タスクは body(for:))
    static let body = Typeface.mixed(15, weight: 500)
    /// 補足(已结束・ヒント)
    static let caption = Typeface.mixed(12.5, weight: 600)
    /// 区切りの一行(任务 2)
    static let sectionCaption = Typeface.mixed(12, weight: 600)
    /// タブ
    static let tab = Typeface.mixed(14, weight: 700)

    /// 中文の見出し(卡の中の短い題)。会議名は title(for:)
    static let cardTitle = Typeface.mixed(20, weight: 700)

    /// 主角卡の会議名(日本語なら Hiragino)
    static func title(for text: String) -> Font {
        Typeface.mixed(20, weight: 700, japanese: Typeface.isJapanese(text))
    }

    /// 日程・タスクの一行(日本語なら Hiragino)
    static func body(for text: String) -> Font {
        Typeface.mixed(15, weight: 500, japanese: Typeface.isJapanese(text))
    }
}

extension View {
    /// 日本語(仮名を含む)なら ja、それ以外は zh-Hans で組む(漢字の字形を言語に合わせる)
    func typesetting(for text: String) -> some View {
        typesettingLanguage(Typeface.isJapanese(text) ? Theme.japanese : Theme.language)
    }
}
