import AppKit
import ImageIO
import NippoCore
import SwiftUI

// MARK: - 同梱リソースの場所

/// .app の Contents/Resources を探す。開発中(swift run、.app の外)だけリポジトリの Resources/ も見る
/// (.app で素材が欠けていたら、構建機の上でも欠けたまま見えるように)
enum BundledResource {
    static func url(_ relative: String) -> URL? {
        let fm = FileManager.default
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent(relative)
            if fm.fileExists(atPath: url.path) { return url }
        }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        // Sources/NippoApp/Baked.swift → ../../Resources
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repo.appendingPathComponent("Resources").appendingPathComponent(relative)
        return fm.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - 焼いた材質(Resources/Material)

/// scripts/material/ が焼いた素材の目録(Resources/Material/manifest.json)。
/// 寸法はすべて pt(PNG は 2 倍)。bleed = 配置の枠の外へはみ出す量(飛沫・接地影・回転の余白)
struct BakedManifest: Decodable {
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
        /// 神兽:墨の外接矩形(配置の枠の座標:x0, y0, x1, y1)と、帯ごとのいちばん左の墨の x
        let ink: [CGFloat]?
        let contour: [CGFloat?]?
        /// 動きの帯:枚数・長さ・各枚の始まり(長さが不揃いの帯だけ)、漫开の起点にした大数字の箱(卡の pt:x, y, w, h)
        let frames: Int?
        let durationMs: Double?
        let frameStartsMs: [Double]?
        let numeralBox: [CGFloat]?
        /// 遮罩の帯(8bit の灰色・1×。白 = 漆がある)。luminanceToAlpha して使う
        let mask: Bool?
        /// 章の垂れの箱(配置の枠の pt:x, y, w, h)。喷く間は遮罩で 0、揭がしてから伸ばす
        let dripBox: [CGFloat]?
    }

    struct GlyphSet: Decodable {
        let file: String
        let pt: CGFloat
        /// 基線の上 / 下(どの字の切り抜きもこの高さ)
        let lineHeight: [CGFloat]
        /// 切り抜きの上端から大文字の上端まで / 大文字の高さ(字身の箱)
        let capTop: CGFloat?
        let capHeight: CGFloat?
        let glyphs: [String: Glyph]
    }

    struct Glyph: Decodable {
        /// 図集の中の px(x, y, w, h)
        let rect: [CGFloat]
        /// 送り幅(字間込み)
        let advance: CGFloat
        /// 筆の位置から切り抜きの左端まで
        let bearing: CGFloat
        /// 筆の位置から墨の右端まで(飛沫を除く)。最後の字の後ろの空きを数えないため
        let inkRight: CGFloat?
    }

    let version: Int
    let scale: CGFloat
    let assets: [String: Asset]
    let glyphs: [String: GlyphSet]?
}

extension BakedManifest.Asset {
    var width: CGFloat { size.count > 0 ? size[0] : 0 }
    var height: CGFloat { size.count > 1 ? size[1] : 0 }

    var bleedInsets: EdgeInsets { Self.edges(bleed) }
    var capInsets: EdgeInsets { Self.edges(insets) }

    /// 配置の枠(bleed を除いた大きさ)
    var layoutSize: CGSize {
        let b = bleedInsets
        return CGSize(width: width - b.leading - b.trailing, height: height - b.top - b.bottom)
    }

    /// 神兽の置き方を決める形(墨の外接矩形と左の輪郭)。無ければ配置の枠ぜんぶが墨とみなす
    var creatureArt: CreatureFit.Art? {
        let box = layoutSize
        guard box.width > 0, box.height > 0 else { return nil }
        let inkRect: CGRect
        if let i = ink, i.count == 4 {
            inkRect = CGRect(x: i[0], y: i[1], width: i[2] - i[0], height: i[3] - i[1])
        } else {
            inkRect = CGRect(origin: .zero, size: box)
        }
        let profile = contour ?? Array(repeating: CGFloat(0), count: 8)
        return CreatureFit.Art(box: box, ink: inkRect, contour: profile)
    }

    private static func edges(_ values: [CGFloat]?) -> EdgeInsets {
        guard let v = values, v.count == 4 else { return EdgeInsets() }
        return EdgeInsets(top: v[0], leading: v[1], bottom: v[2], trailing: v[3])
    }
}

/// 素材の読み込みと記憶。見つからない・読めないときは nil(画面は素材なしでも文字と単色で成り立つ)。
/// 解いた画像は NSCache に置き(画素数で数える)、曜日で入れ替わる神兽などが溜まり続けないようにする
@MainActor
enum Baked {
    static let manifest: BakedManifest? = {
        guard let url = BundledResource.url("Material/manifest.json") else {
            AppLog.shared.log("material", "manifest.json not found")
            return nil
        }
        do {
            return try JSONDecoder().decode(BakedManifest.self, from: Data(contentsOf: url))
        } catch {
            AppLog.shared.log("material", "manifest.json unreadable: \(error)")
            return nil
        }
    }()

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    /// 読めなかった素材(毎回ファイルを探しに行かない)
    private static var missing: Set<String> = []

    static var scale: CGFloat { manifest?.scale ?? 2 }

    static func asset(_ id: String) -> BakedManifest.Asset? {
        manifest?.assets[id]
    }

    /// 画像が本当に読めるか(目録にあるだけでは true にしない)
    static func has(_ id: String) -> Bool { image(id) != nil }

    /// 並べた候補のうち、読める最初の素材(専用の素材 → 汎用の素材の順に書く)
    static func first(_ ids: [String]) -> String? {
        ids.first { has($0) }
    }

    /// 動きの帯が目録にそろっているか(1 枚目の frames を見るだけで、絵は解かない)
    static func hasFrames(_ prefix: String, count: Int) -> Bool {
        (asset("\(prefix)0")?.frames ?? 0) >= count || (0..<count).allSatisfy { asset("\(prefix)\($0)") != nil }
    }

    /// 動きの帯を先に解いておく(動き出した最初のコマで止まらないように)。1 枚ずつ間を空けて解く
    static func preload(_ prefix: String, count: Int) {
        Task { @MainActor in
            for index in 0..<count {
                _ = image("\(prefix)\(index)")
                await Task.yield()
            }
        }
    }

    /// 画像(大きさは pt にそろえてある)
    static func image(_ id: String) -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard !missing.contains(id) else { return nil }
        guard let asset = asset(id), let cg = cgImage(asset.file) else {
            missing.insert(id)
            if manifest != nil { AppLog.shared.log("material", "missing \(id)") }
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: asset.width, height: asset.height))
        cache.setObject(image, forKey: id as NSString, cost: cg.width * cg.height * 4)
        return image
    }

    /// 動きの帯(prefix0 … prefix(count-1))。1 枚でも欠けていれば nil(動かさず最後の絵だけ見せる)
    static func frames(_ prefix: String, count: Int) -> [NSImage]? {
        guard count > 0 else { return nil }
        var result: [NSImage] = []
        for index in 0..<count {
            guard let image = image("\(prefix)\(index)") else { return nil }
            result.append(image)
        }
        return result
    }

    static func glyphSet(_ set: String) -> BakedManifest.GlyphSet? {
        manifest?.glyphs?[set]
    }

    /// 模板字 1 字の切り抜き
    static func glyph(_ set: String, _ character: Character) -> (image: NSImage, glyph: BakedManifest.Glyph)? {
        guard let info = glyphSet(set), let glyph = info.glyphs[String(character)], glyph.rect.count == 4 else { return nil }
        let key = "glyph:\(set)/\(character)"
        if let cached = cache.object(forKey: key as NSString) { return (cached, glyph) }
        guard !missing.contains(key) else { return nil }
        let atlasKey = "atlas:\(set)"
        guard let atlas = atlasImage(info.file, key: atlasKey),
              let cropped = atlas.cropping(to: CGRect(x: glyph.rect[0], y: glyph.rect[1],
                                                      width: glyph.rect[2], height: glyph.rect[3])) else {
            missing.insert(key)
            return nil
        }
        let image = NSImage(cgImage: cropped, size: NSSize(width: glyph.rect[2] / scale, height: glyph.rect[3] / scale))
        cache.setObject(image, forKey: key as NSString, cost: cropped.width * cropped.height * 4)
        return (image, glyph)
    }

    /// 図集は切り抜くためだけに読む(切り抜いたあとは手放してよい)
    private static func atlasImage(_ file: String, key: String) -> CGImage? {
        if let cached = cache.object(forKey: key as NSString),
           let cg = cached.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        guard let cg = cgImage(file) else { return nil }
        let holder = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(holder, forKey: key as NSString, cost: cg.width * cg.height * 4)
        return cg
    }

    private static func cgImage(_ file: String) -> CGImage? {
        guard let url = BundledResource.url("Material/\(file)"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

// MARK: - 置き方

/// 精灵をそのままの大きさで置く。配置の枠は bleed を除いた大きさで、飛沫は枠の外にはみ出す
struct BakedSprite: View {
    let id: String
    /// 1 以外で拡大縮小(なるべく 0.85〜1.15 の間で。外れるなら表示の大きさで焼き直す)
    var scale: CGFloat = 1

    var body: some View {
        if let asset = Baked.asset(id), let image = Baked.image(id) {
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
    static func height(_ id: String, _ height: CGFloat) -> BakedSprite {
        let base = Baked.asset(id)?.layoutSize.height ?? height
        return BakedSprite(id: id, scale: base > 0 ? height / base : 1)
    }
}

/// 九宮格の喷块・遮块。背景として使う(.baked(id) か .background { BakedSlice(id: ...) })。
/// 枠いっぱいに伸ばし、bleed の分だけ外へはみ出す。tile = 端と中央を伸ばさず敷き詰める(長い帯の地肌が流れない)。
/// 素材がなければ fallback の色で塗る
struct BakedSlice: View {
    let id: String
    var fallback: Color = .clear
    var tile = false

    var body: some View {
        if let asset = Baked.asset(id), let image = Baked.image(id) {
            let b = asset.bleedInsets
            Image(nsImage: image)
                .resizable(capInsets: asset.capInsets, resizingMode: tile ? .tile : .stretch)
                .interpolation(.high)
                .padding(EdgeInsets(top: -b.top, leading: -b.leading, bottom: -b.bottom, trailing: -b.trailing))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Rectangle().fill(fallback)
                .allowsHitTesting(false)
        }
    }
}

/// 平铺の材質(混凝土)。枠いっぱいに敷く
struct BakedTile: View {
    let id: String
    var fallback: Color = Palette.surface

    var body: some View {
        if let image = Baked.image(id) {
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Rectangle().fill(fallback)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// 九宮格の素材を背景に敷く
    func baked(_ id: String, fallback: Color = .clear, tile: Bool = false) -> some View {
        background { BakedSlice(id: id, fallback: fallback, tile: tile) }
    }
}

// MARK: - 模板字(精灵を 1 字ずつ並べる)

/// 大数字・時刻・20/20・坐站の時計を、焼いた模板字の図集から 1 字ずつ組む。
/// 配置の枠は字身(大文字の箱):幅 = 送り幅の合計、高さ = capHeight。飛沫は枠の外へはみ出す。
/// 基線 = 枠の下端なので、HStack(alignment: .firstTextBaseline) で本物の文字と並べられる。
/// 図集がない・1 字でも切り抜けないときは Archivo の本物の文字で代える
struct StencilText: View {
    let text: String
    /// 図集の名前(big-teal / big-black / mid-teal / mid-black / count-black / timer-black)
    let set: String
    /// 図集の字を拡大縮小して使う(なるべく 1 のまま。大きさの違う図集を選ぶ)
    var scale: CGFloat = 1
    /// 図集がないときの代わり
    var fallbackSize: CGFloat = 132
    var fallbackColor: Color = Palette.teal

    var body: some View {
        if let info = Baked.glyphSet(set), let layout = Self.layout(text, set: set, scale: scale) {
            let ascent = info.lineHeight.first ?? info.pt
            let capTop = (info.capTop ?? 0) * scale
            let capHeight = (info.capHeight ?? ascent - (info.capTop ?? 0)) * scale
            // 字身の箱の下端 = 基線(切り抜きの上端から ascent 下)
            let baseline = ascent * scale - capTop
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.items.enumerated()), id: \.offset) { _, item in
                    Image(nsImage: item.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: item.image.size.width * scale, height: item.image.size.height * scale)
                        .offset(x: item.x, y: -capTop)
                }
            }
            .frame(width: layout.width, height: capHeight, alignment: .topLeading)
            .alignmentGuide(.firstTextBaseline) { _ in baseline }
            .alignmentGuide(.lastTextBaseline) { _ in baseline }
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

    /// 1 字でも切り抜けなければ nil(全部本物の文字にする。混ぜない)
    private static func layout(_ text: String, set: String, scale: CGFloat) -> (items: [Item], width: CGFloat)? {
        guard !text.isEmpty else { return nil }
        var pen: CGFloat = 0
        var items: [Item] = []
        var right: CGFloat = 0
        for character in text {
            guard let hit = Baked.glyph(set, character) else { return nil }
            items.append(Item(image: hit.image, x: pen + hit.glyph.bearing * scale))
            // 幅は最後の字の墨の右端まで(送り幅の余りは単位との間に入れない)
            right = pen + (hit.glyph.inkRight ?? hit.glyph.advance) * scale
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
    /// 長い語(WEDNESDAY)を枠に収めるときの縮小
    var scale: CGFloat = 1

    var body: some View {
        if let asset = Baked.asset(id), Baked.has(id) {
            let b = asset.bleedInsets
            // 配置の枠の上端から基線まで
            let baseline = ((asset.baseline ?? asset.height - b.bottom) - b.top) * scale
            BakedSprite(id: id, scale: scale)
                .alignmentGuide(.firstTextBaseline) { _ in baseline }
                .alignmentGuide(.lastTextBaseline) { _ in baseline }
                .accessibilityElement()
                .accessibilityLabel(fallback)
        } else {
            Text(fallback)
                .font(Typeface.archivo(fallbackSize * scale, weight: 900, width: 125))
                .tracking(fallbackSize * scale * 0.02)
                .foregroundStyle(fallbackColor)
        }
    }
}

// MARK: - 曜日の神兽(主角卡の第二の模板)

/// 主角卡の中で神兽と重ねたくない枠(文字・大数字・格・ボタン)を集める
struct CreatureAvoidKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// この枠には神兽を近づけない(9pt 以上離す)
    func creatureAvoid() -> some View {
        anchorPreference(key: CreatureAvoidKey.self, value: .bounds) { [$0] }
    }

    /// 卡の後ろ(喷块の上・文字の下)に神兽を喷く。enabled = 静のときだけ。
    /// 大きさと位置は CreatureFit(墨の高さ = 卡の 0.76 から、avoid と 9pt 離れるまで 0.44 まで縮める。入らなければ出さない)
    func creatureLayer(_ id: String, enabled: Bool) -> some View {
        backgroundPreferenceValue(CreatureAvoidKey.self) { anchors in
            GeometryReader { geo in
                if enabled, let placed = CreatureTier.place(id, card: geo.size, avoid: anchors.map { geo[$0] }) {
                    BakedSprite(id: placed.id, scale: placed.fit.scale)
                        .position(x: placed.fit.origin.x + placed.art.box.width * placed.fit.scale / 2,
                                  y: placed.fit.origin.y + placed.art.box.height * placed.fit.scale / 2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 神兽は大・中・小の 3 段に焼いてある(墨の高さ ≈ 180 / 145 / 114pt)。どの段も 0.85〜1.15 倍の間でしか伸び縮みさせず、
/// 大きい段から順に、卡の 0.76 の高さを目指して文字・数字と 9pt 離れるところを探す。卡の 0.44 より小さくなるなら出さない
@MainActor
enum CreatureTier {
    struct Placed {
        let id: String
        let art: CreatureFit.Art
        let fit: CreatureFit.Placement
    }

    static func place(_ base: String, card: CGSize, avoid: [CGRect]) -> Placed? {
        guard card.height > 0 else { return nil }
        for id in [base, "\(base)-m", "\(base)-s"] {
            guard let asset = Baked.asset(id), let art = asset.creatureArt, art.ink.height > 0, Baked.has(id) else { continue }
            let target = min(0.76, art.ink.height * 1.15 / card.height)
            let minimum = max(0.44, art.ink.height * 0.85 / card.height)
            guard minimum <= target,
                  let fit = CreatureFit.place(art: art, card: card, avoid: avoid, target: target, minimum: minimum) else { continue }
            return Placed(id: id, art: art, fit: fit)
        }
        return nil
    }
}

// MARK: - 動き(焼いた帯を 1 回だけ流す)

/// trigger が変わったら durationMs かけて 0 → 1 を 1 回だけ流し、中身に進み具合を渡す。
/// 最初に出たときと「減らす動き」のときは 1(最後の絵)。動いていないときは時計を止める
struct MotionPlayer<Trigger: Equatable, Content: View>: View {
    let trigger: Trigger
    let durationMs: Double
    /// 出たときにも 1 回流す(毎日最初に開いたときの遮盖纸など)
    var playOnAppear = false
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: startedAt == nil)) { context in
            content(progress(at: context.date))
        }
        .onAppear {
            if playOnAppear && !reduceMotion { startedAt = Date() }
        }
        .onChange(of: trigger) {
            startedAt = reduceMotion ? nil : Date()
        }
        .task(id: startedAt) {
            guard startedAt != nil else { return }
            // 途中で次が始まった(task が取り消された)ときは、新しい始まりを消さない
            do {
                try await Task.sleep(for: .milliseconds(Int(durationMs) + 20))
            } catch {
                return
            }
            startedAt = nil
        }
    }

    private func progress(at date: Date) -> Double {
        guard let startedAt else { return 1 }
        return min(1, max(0, date.timeIntervalSince(startedAt) * 1000 / durationMs))
    }
}

/// 帯の中の 1 枚(進み具合 0…1 → prefix0 … prefix(count-1))。遮罩にも精灵にも使える。
/// 素材の配置の枠いっぱいに伸ばし、bleed の分だけはみ出す(遮罩は卡と同じ枠で使う)
struct BakedFrame: View {
    let prefix: String
    let count: Int
    let progress: Double

    var body: some View {
        let id = "\(prefix)\(Self.index(prefix: prefix, count: count, progress: progress))"
        if let asset = Baked.asset(id), let image = Baked.image(id) {
            let b = asset.bleedInsets
            Group {
                if asset.mask == true {
                    // 灰色の遮罩:明るさをそのまま不透明度に
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .luminanceToAlpha()
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                }
            }
            .padding(EdgeInsets(top: -b.top, leading: -b.leading, bottom: -b.bottom, trailing: -b.trailing))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            // 帯が無いときは全面(遮罩に使っても中身を消さない)
            Rectangle()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 進み具合 → 何枚目か。1 枚目の素材に frameStartsMs があれば(長さ不揃いの帯)それに従う
    static func index(prefix: String, count: Int, progress: Double) -> Int {
        guard count > 0 else { return 0 }
        if let first = Baked.asset("\(prefix)0"), let starts = first.frameStartsMs, starts.count == count,
           let total = first.durationMs, total > 0 {
            let t = progress * total
            return starts.lastIndex { $0 <= t } ?? 0
        }
        return min(count - 1, max(0, Int(progress * Double(count))))
    }
}

/// 区間 [start, end](ms)の中の進み具合 0…1(区間の外は 0 か 1)。動きの段取りを書くため
func motionPhase(_ progress: Double, totalMs: Double, from start: Double, to end: Double) -> Double {
    let t = progress * totalMs
    guard end > start else { return t >= end ? 1 : 0 }
    return min(1, max(0, (t - start) / (end - start)))
}
