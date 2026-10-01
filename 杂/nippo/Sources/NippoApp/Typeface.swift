import AppKit
import CoreText
import SwiftUI

// MARK: - 同梱リソースの場所

/// .app の Contents/Resources → 開発中(swift run)はリポジトリの Resources/ の順に探す
enum BundledResource {
    static func url(_ relative: String) -> URL? {
        let fm = FileManager.default
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent(relative)
            if fm.fileExists(atPath: url.path) { return url }
        }
        // Sources/NippoApp/Typeface.swift → ../../Resources
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repo.appendingPathComponent("Resources").appendingPathComponent(relative)
        return fm.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - 字体(Archivo / JetBrains Mono を同梱。中文・日文はシステムの PingFang のまま)

/// 欧文と数字の書体。可変フォントの wght / wdth 軸を直接指定する(SwiftUI の .width() はカスタム書体に効かないため)。
/// 中文・日文は Archivo に含まれないので CoreText が PingFang に落とす(斜体・幅変更はしない)
enum Typeface {
    private static let archivoFile = "Fonts/Archivo[wdth,wght].ttf"
    private static let monoFile = "Fonts/JetBrainsMono[wght].ttf"

    private static let archivoBase: CTFontDescriptor? = descriptor(archivoFile)
    private static let monoBase: CTFontDescriptor? = descriptor(monoFile)

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        guard let url = BundledResource.url(file),
              let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        return list.first
    }

    // OpenType の軸タグ(4 文字を 32bit に詰めたもの)
    private static let wghtTag = 0x7767_6874  // 'wght'
    private static let wdthTag = 0x7764_7468  // 'wdth'

    private static func make(_ base: CTFontDescriptor, size: CGFloat, axes: [Int: CGFloat], tnum: Bool, italic: Bool) -> CTFont {
        var attributes: [CFString: Any] = [
            kCTFontVariationAttribute: Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) }),
        ]
        if tnum {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1] as [CFString: Any],
            ]
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
        guard let base = archivoBase else {
            var font = Font.system(size: size, weight: fallbackWeight(weight))
            if width >= 112 { font = font.width(.expanded) } else if width <= 90 { font = font.width(.condensed) }
            if tnum { font = font.monospacedDigit() }
            return italic ? font.italic() : font
        }
        return Font(make(base, size: size, axes: [wghtTag: weight, wdthTag: width], tnum: tnum, italic: italic))
    }

    /// JetBrains Mono。weight 100–800
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        guard let base = monoBase else {
            return .system(size: size, weight: fallbackWeight(weight), design: .monospaced)
        }
        return Font(make(base, size: size, axes: [wghtTag: weight], tnum: false, italic: false))
    }

    /// 中文・日文(PingFang)。斜体・幅の変更はしない
    static func cjk(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
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

/// 画面で使う文字の役割。大きな模板字(大数字・喊声・曜日・章)は素材の精灵で組むので、ここにあるのは本物の文字だけ
enum TypeRole {
    /// 14:00–15:00、3:12(Archivo 900 / wdth 108 / 等幅数字)
    static let time = Typeface.archivo(17, weight: 900, width: 108, tnum: true)
    /// 単語(storey)
    static let word = Typeface.archivo(68, weight: 800, width: 100)
    /// 考点词(reserve)
    static let quizWord = Typeface.archivo(56, weight: 800, width: 100)
    /// /ˈstɔːri/
    static let ipa = Typeface.archivo(17, weight: 500, width: 100)
    /// 例文(欧文のみ・斜体)
    static let example = Typeface.archivo(16, weight: 500, width: 100, italic: true)
    /// 聴写の入力欄
    static let input = Typeface.archivo(20, weight: 600, width: 100)
    /// 坐站小窓のつまみ(STAND UP / STRETCH / SIT DOWN)
    static let tape = Typeface.archivo(12, weight: 800, width: 112)
    /// 盤面の時刻 9 … 18
    static let boardLabel = Typeface.mono(12, weight: 400)
    static let boardLabelNow = Typeface.mono(12, weight: 700)
    /// 回数・時刻・キーの説明(12/20、⌘Z)
    static let count = Typeface.mono(12, weight: 700)
    static let keycap = Typeface.mono(12, weight: 700)

    /// 站起来了吗？
    static let titleZh = Typeface.cjk(30, weight: .black)
    /// 主角カードの会議名(日本語・中文)
    static let cardTitle = Typeface.cjk(20, weight: .bold)
    /// 楼层
    static let definition = Typeface.cjk(32, weight: .black)
    /// 加入会议 / 显示释义
    static let button = Typeface.cjk(17, weight: .black)
    /// 予定の行・タスク
    static let body = Typeface.cjk(15, weight: .medium)
    /// 補足(已结束・ヒント)
    static let caption = Typeface.cjk(12.5, weight: .semibold)
    /// 区切りの一行(任务 2)
    static let sectionCaption = Typeface.cjk(12, weight: .semibold)
    /// タブ
    static let tab = Typeface.cjk(14, weight: .bold)
}
