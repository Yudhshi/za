import AppKit
import ImageIO
import SwiftUI

// MARK: - 焼いた材質(Resources/Material)

/// scripts/material/ が焼いた素材の目録(Resources/Material/manifest.json)。
/// 寸法はすべて pt(PNG は 2 倍)。bleed = 配置の枠の外へはみ出す量(飛沫・接地影・回転の余白)
struct MaterialManifest: Decodable {
    struct Asset: Decodable {
        let file: String
        /// tile / slice / sprite
        let kind: String
        /// 画像全体(bleed を含む)の pt
        let size: [CGFloat]
        let bleed: [CGFloat]?
        /// 九宮格の端(画像の縁から測る。上・左・下・右)
        let insets: [CGFloat]?
        let anchor: [CGFloat]?
        /// 組み絵の中での置き場所(壁画带の人:帯の左上からの pt)
        let origin: [CGFloat]?
        /// 模板字の精灵:画像の上端から基線まで / 大文字の高さ
        let baseline: CGFloat?
        let capHeight: CGFloat?
    }

    struct GlyphSet: Decodable {
        let file: String
        let pt: CGFloat
        /// 基線の上 / 下(どの字の切り抜きもこの高さ)
        let lineHeight: [CGFloat]
        let glyphs: [String: Glyph]
    }

    struct Glyph: Decodable {
        /// 図集の中の px(x, y, w, h)
        let rect: [CGFloat]
        /// 送り幅(字間込み)
        let advance: CGFloat
        /// 筆の位置から切り抜きの左端まで
        let bearing: CGFloat
    }

    let version: Int
    let scale: CGFloat
    let assets: [String: Asset]
    let glyphs: [String: GlyphSet]?
    let words: [String: String]?
}

extension MaterialManifest.Asset {
    var width: CGFloat { size.count > 0 ? size[0] : 0 }
    var height: CGFloat { size.count > 1 ? size[1] : 0 }

    var bleedInsets: EdgeInsets { Self.edges(bleed) }
    var capInsets: EdgeInsets { Self.edges(insets) }

    /// 配置の枠(bleed を除いた大きさ)
    var layoutSize: CGSize {
        let b = bleedInsets
        return CGSize(width: width - b.leading - b.trailing, height: height - b.top - b.bottom)
    }

    private static func edges(_ values: [CGFloat]?) -> EdgeInsets {
        guard let v = values, v.count == 4 else { return EdgeInsets() }
        return EdgeInsets(top: v[0], leading: v[1], bottom: v[2], trailing: v[3])
    }
}

/// 素材の読み込みと記憶。見つからないときは nil(画面は素材なしでも文字だけで成り立つように作る)
@MainActor
enum Material {
    static let manifest: MaterialManifest? = {
        guard let url = BundledResource.url("Material/manifest.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MaterialManifest.self, from: data)
    }()

    private static var images: [String: NSImage] = [:]
    private static var atlases: [String: CGImage] = [:]
    private static var glyphImages: [String: NSImage] = [:]

    static var scale: CGFloat { manifest?.scale ?? 2 }

    static func asset(_ id: String) -> MaterialManifest.Asset? {
        guard let manifest else { return nil }
        if let asset = manifest.assets[id] { return asset }
        if let alias = manifest.words?[id] { return manifest.assets[alias] }
        return nil
    }

    static func has(_ id: String) -> Bool { asset(id) != nil }

    /// 画像(大きさは pt にそろえてある)
    static func image(_ id: String) -> NSImage? {
        if let cached = images[id] { return cached }
        guard let asset = asset(id), let cg = cgImage(asset.file) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: asset.width, height: asset.height))
        images[id] = image
        return image
    }

    static func glyphSet(_ set: String) -> MaterialManifest.GlyphSet? {
        manifest?.glyphs?[set]
    }

    /// 模板字 1 字の切り抜き
    static func glyph(_ set: String, _ character: Character) -> (image: NSImage, glyph: MaterialManifest.Glyph)? {
        guard let info = glyphSet(set), let glyph = info.glyphs[String(character)], glyph.rect.count == 4 else { return nil }
        let key = "\(set)/\(character)"
        if let cached = glyphImages[key] { return (cached, glyph) }
        let atlas: CGImage
        if let cached = atlases[set] {
            atlas = cached
        } else {
            guard let loaded = cgImage(info.file) else { return nil }
            atlases[set] = loaded
            atlas = loaded
        }
        let r = glyph.rect
        guard let cropped = atlas.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3])) else { return nil }
        let image = NSImage(cgImage: cropped, size: NSSize(width: r[2] / scale, height: r[3] / scale))
        glyphImages[key] = image
        return (image, glyph)
    }

    private static func cgImage(_ file: String) -> CGImage? {
        guard let url = BundledResource.url("Material/\(file)"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - 置き方

/// 精灵をそのままの大きさで置く。配置の枠は bleed を除いた大きさで、飛沫は枠の外にはみ出す
struct MaterialSprite: View {
    let id: String
    /// 1 以外で拡大縮小(神兽を卡の高さに合わせるなど)
    var scale: CGFloat = 1

    var body: some View {
        if let asset = Material.asset(id), let image = Material.image(id) {
            let b = asset.bleedInsets
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: asset.width * scale, height: asset.height * scale)
                .padding(EdgeInsets(top: -b.top * scale, leading: -b.leading * scale,
                                    bottom: -b.bottom * scale, trailing: -b.trailing * scale))
                .accessibilityHidden(true)
        }
    }

    /// 配置の枠の高さを指定して置く
    static func height(_ id: String, _ height: CGFloat) -> MaterialSprite {
        let base = Material.asset(id)?.layoutSize.height ?? height
        return MaterialSprite(id: id, scale: base > 0 ? height / base : 1)
    }
}

/// 九宮格の喷块・遮块。背景として使う(.background { MaterialSlice(id: ...) })。
/// 枠いっぱいに伸ばし、bleed の分だけ外へはみ出す。素材がなければ fallback の色で塗る
struct MaterialSlice: View {
    let id: String
    var fallback: Color = .clear

    var body: some View {
        if let asset = Material.asset(id), let image = Material.image(id) {
            let b = asset.bleedInsets
            Image(nsImage: image)
                .resizable(capInsets: asset.capInsets, resizingMode: .stretch)
                .interpolation(.high)
                .padding(EdgeInsets(top: -b.top, leading: -b.leading, bottom: -b.bottom, trailing: -b.trailing))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Rectangle().fill(fallback)
        }
    }
}

/// 平铺の材質(混凝土)。枠いっぱいに敷く
struct MaterialTile: View {
    let id: String
    var fallback: Color = Palette.surface

    var body: some View {
        if let image = Material.image(id) {
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Rectangle().fill(fallback)
        }
    }
}

extension View {
    /// 九宮格の素材を背景に敷く
    func material(_ id: String, fallback: Color = .clear) -> some View {
        background { MaterialSlice(id: id, fallback: fallback) }
    }
}

// MARK: - 模板字(精灵を 1 字ずつ並べる)

/// 大数字・時計の数字・20/20 を、焼いた模板字の図集から 1 字ずつ組む。
/// 基線は firstTextBaseline に出すので、HStack(alignment: .firstTextBaseline) で本物の文字と並べられる。
/// 図集がないときは Archivo の本物の文字で代える
struct StencilText: View {
    let text: String
    /// 図集の名前(big-teal / big-black / timer-black)
    let set: String
    /// 図集の字を拡大縮小して使う(通关の 20/20 は big-black を 0.45 倍など)
    var scale: CGFloat = 1
    /// 図集がないときの代わり
    var fallbackSize: CGFloat = 132
    var fallbackColor: Color = Palette.teal

    var body: some View {
        if let info = Material.glyphSet(set), text.allSatisfy({ info.glyphs[String($0)] != nil }) {
            let ascent = (info.lineHeight.first ?? info.pt) * scale
            let descent = (info.lineHeight.count > 1 ? info.lineHeight[1] : 0) * scale
            let layout = Self.layout(text, set: set, scale: scale)
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.items.enumerated()), id: \.offset) { _, item in
                    Image(nsImage: item.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: item.image.size.width * scale, height: item.image.size.height * scale)
                        .offset(x: item.x)
                }
            }
            .frame(width: layout.width, height: ascent + descent, alignment: .topLeading)
            .alignmentGuide(.firstTextBaseline) { _ in ascent }
            .alignmentGuide(.lastTextBaseline) { _ in ascent }
            .accessibilityElement()
            .accessibilityLabel(text)
        } else {
            Text(text)
                .font(Typeface.archivo(fallbackSize * scale, weight: 900, width: 104, tnum: true))
                .tracking(fallbackSize * scale * 0.02)
                .foregroundStyle(fallbackColor)
        }
    }

    private struct Item {
        let image: NSImage
        let x: CGFloat
    }

    private static func layout(_ text: String, set: String, scale: CGFloat) -> (items: [Item], width: CGFloat) {
        var pen: CGFloat = 0
        var items: [Item] = []
        var right: CGFloat = 0
        for character in text {
            guard let hit = Material.glyph(set, character) else { continue }
            items.append(Item(image: hit.image, x: pen + hit.glyph.bearing * scale))
            right = max(right, pen + hit.glyph.advance * scale)
            pen += hit.glyph.advance * scale
        }
        return (items, right)
    }
}

/// 一語まるごと焼いた模板字(NEXT / NOW / TOMORROW / TUESDAY / NICE! など)。
/// 配置の枠は大文字の箱、基線は firstTextBaseline。素材がなければ Archivo の本物の文字
struct StencilWord: View {
    /// 素材の名前(shout-next-teal-night など)
    let id: String
    /// 素材がないときの文字と書体
    let fallback: String
    var fallbackSize: CGFloat = 21
    var fallbackColor: Color = Palette.teal

    var body: some View {
        if let asset = Material.asset(id), Material.image(id) != nil {
            let b = asset.bleedInsets
            // 配置の枠の上端から基線まで
            let baseline = (asset.baseline ?? asset.height - b.bottom) - b.top
            MaterialSprite(id: id)
                .alignmentGuide(.firstTextBaseline) { _ in baseline }
                .alignmentGuide(.lastTextBaseline) { _ in baseline }
                .accessibilityElement()
                .accessibilityLabel(fallback)
        } else {
            Text(fallback)
                .font(Typeface.archivo(fallbackSize, weight: 900, width: 125))
                .tracking(fallbackSize * 0.02)
                .foregroundStyle(fallbackColor)
        }
    }
}
