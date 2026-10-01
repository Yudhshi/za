# scripts/material — v12.1「Stencil Turf」材质管线（夜间版）

把设计稿（`directions/merge2`：`V3.md`、`FIXES.md`、`system/tokens.json` 和各画面的烘焙脚本）里验证过的材质配方，烘焙成 App 用的 @2x PNG：
`Resources/Material/*.png` + `Resources/Material/manifest.json`。SwiftUI 只负责摆放、九宫格拉伸、裁切和淡入；文字、图标永远是真的。

```bash
python3 scripts/material/make.py                      # 全部重烘（约 3 分钟，4 核）
python3 scripts/material/make.py --only stencil -v    # 只烘某几组：它们的条目合并进现有 manifest（其他组的条目原样保留），-v 打印每张的大小和编码
python3 scripts/material/sheet.py /tmp/material-sheet.png   # 审查用的拼版（不进仓库）：拼好的画面 + 每张 1× + 100% 局部
```

## 依赖

- Python ≥ 3.9，`numpy`、`scipy`、`Pillow`（`pip install numpy scipy pillow`）
- 可选：`pyoxipng`（`pip install pyoxipng`）——有它 PNG 会再小 10–20%，没有也能跑
- **不需要 Chromium**：模板字形图集已经渲染好并提交在 `src/glyphs/atlas.png`（+ `atlas.json`）

## 两种模式

1. **平常（无 Chromium）**：`make.py` 只读 `src/` 里提交好的东西——字形图集 PNG 和矢量 SVG（神兽、剪影、壁画带都只有 M/L/Z 多边形，由 `yudhmat/svg.py` 自己栅格化，结果与设计稿用 Chromium 栅格化的蒙版逐像素一致）。
2. **重做字形图集（需要 Chromium + Archivo 字体）**：只有加字号或加字母时才需要。
   ```bash
   YUDH_RENDER=/path/to/render.sh python3 scripts/material/glyphs.py      # render.sh <html> <png> <w> <h>，设备像素比 2
   CHROMIUM=/path/to/headless_shell python3 scripts/material/glyphs.py    # 或者直接给一个无头 Chrome（字体走 Google Fonts）
   ```
   设计用的 `render.sh` 会把 Google Fonts 的 `<link>` 换成本地字体（Archivo 900，wdth 轴）。行表在 `glyphs.py` 的 `ROWS`：
   `big` 132pt / `mid` 80pt / `n56` 56pt / `tm` 40pt（wdth 104）、`day` 31pt / `sm` 21pt / `st` 32pt（wdth 125）。
   新字只加在行尾、新行只加在表尾，已有格子的位置和像素不变；`-` 格里排的是 en dash（–），数字组里的「—」用它。

## 确定性

每一次喷、遮、垂滴、纤维都有自己的种子；同样的输入 + 同版本的 numpy / scipy / Pillow 得到同样的像素。调色板量化（k-means）也是固定种子。

## 结构

| 文件 | 内容 |
| --- | --- |
| `make.py` | 入口：按组烘焙、写 manifest |
| `yudhmat/bake.py` | 设计的共享烘焙库 `merge2/tex/bake.py` 原样复制（只去掉了导入时的副作用；字形图集由 `glyph.py` 注入） |
| `yudhmat/ext.py` | 设计各画面脚本里的扩展（todaybake / eng_bake / kraftbake / popups 的函数原样搬来）+ 透明图层 `Layer`、导出 `export()`、可平铺混凝土 `concrete_tile()` |
| `yudhmat/glyph.py` | 从图集取模板字（YudhStencil 桥位，`R`、`I` 的例外同设计） |
| `yudhmat/svg.py` | SVG 多边形栅格化（even-odd，4× 超采样） |
| `yudhmat/out.py` | 写 PNG（k-means 调色板 + oxipng，误差不够小就保留真彩）、manifest |
| `yudhmat/g_*.py` | 各组：`concrete`（平铺 + 面板边框）、`paint`（喷块九宫格）、`masked`（遮块九宫格）、`stencil`（字形组 / 喊声 / 星期 / 章）、`drips`、`cells`、`creatures`、`poses`（剪影 + 埃及壁画带）、`kraft`（牛皮纸 + 胶带） |
| `sheet.py`, `sheet_full.py` | 审查拼版（按 SwiftUI 的方式合成：sRGB 空间 alpha over + 九宫格拉伸） |
| `src/` | 提交的源：字形图集、神兽 7 张、剪影 11 张（`shoulder-rolls-sash.svg` = 哪吒混天绫版，App 的「转肩」用它）、壁画带 |

## 怎么用这些图（给 SwiftUI）

- **manifest.json**（schema v1）：`assets[id]` = `file`、`kind`（`tile` / `slice` / `sprite`）、`size`（pt，整张图）、`bleed`（pt，图超出布局框的部分：飞沫、投影、旋转余量）、`insets`（仅 slice，pt，从**图像边缘**量，≥ bleed）、可选 `anchor`、单词精灵图的 `baseline` / `capHeight`、`purpose`、`ground`（烘焙时对着的地面）。
  神兽 `creature-*-grey`：`ink` = 模板墨迹外接框 `[x0, y0, x1, y1]`，`contour` = 32 个数：布局框自上而下等分成 32 条横带，每条里最左的墨迹 x（没有墨迹为 null）；都是布局框坐标、pt、不含飞沫。垂滴 `drip-*`：`length` = 锚点以下垂多长（pt）。另有 `origin`（壁画带）、`feetY` 等说明性字段。v12.1 起没有 `words` 别名表。
- **glyphs[set]**：一组一张图集，所有格子同高；`lineHeight = [ascent, descent]`（pt，基线在格子顶下 ascent 处），`capTop`（格子顶到大写顶，pt）、`capHeight`（大写顶到基线，pt；capTop + capHeight = ascent），每个字 `rect`（px）、`advance`（pt，含字距）、`bearing`（pt，格子左边相对笔位置，负数 = 左边的飞沫）。拼「04」：笔位置从 x 开始，每个字画在 `pen + bearing`，然后 `pen += advance`；布局框 = 宽 Σadvance × 高 capHeight，图向上 / 下溢出。
- **布局框 = 图像减去 bleed**。九宫格的拉伸只发生在 insets 之内；v12.1 每张都按真实显示尺寸烘焙（主角卡 472×270 / 短卡 472×150、白卡 308×380 / 472×340 / 472×160、选项 233×56、评分 112×52、剪影 132 / 96pt …），九宫格拉伸 ≤ ±20 %，精灵按 1× 用。
- **透明的喷 / 遮**：颜色是漆本身的颜色；alpha 是覆盖率按「在 manifest `ground` 上做 sRGB 空间 over 合成时亮度与线性光烘焙一致」重解过的（Core Animation 在 gamma 空间混合）。所以薄处、飞沫、渗边在混凝土 / 黑漆 / 牛皮纸上看起来和设计稿一致，换底色时色相也不会跑。
- **面板**（裁成 20pt 圆角矩形）：`concrete-night`（512pt 安静平铺，整块面板都铺它，520×900 上看不出重复）→ `concrete-edge-night`（左右各 18pt 的浇筑纹理 + 向内羽化，`BakedSlice(tile: true)` 铺满整块面板，竖向 512pt 周期）→ `concrete-band-night`（520×60，盘面格子行后面）→ `concrete-seam-night`（整条 520pt、不周期、两端消失，只放在区块之间的空隙里）→ 最上面 `panel-frame-night`（520×760 名义高度；投影在 bleed 里，崩角处画成阴影里的空缺）。`concrete-quiet-night` 现在多余，只为旧代码保留。
- **牛皮纸小窗**：`kraft-sheet-night`（宽固定 360pt，只竖向拉伸）→ 当天的 `kraft-ghost-<day>`（只在 09 / 11，铺在 (0, 84)）→ 剪影 / 模板字 / 按钮 → `tape-handle-night` 横跨上沿，文字是真的。
- **动档**：`hero-event-night` / `hero-zero-night` 下沿挂 ≤ 3 条 `drip-<色>-n`（锚点 = 离开漆面的顶点中点，压进卡里 1pt）；静档不挂。

## 体积

静态素材约 4.6 MB / 210 多个文件（连动效组全部 ≲ 8 MB）。大头是四张主角卡（各 ~160–300 KB）、三张白卡、牛皮纸板（~260 KB）、混凝土平铺（~150 KB）和七张残影。
编码：先试 64→256 色的 k-means 调色板（预乘 RGBA，透明索引精确），模糊后误差 < 0.3/255（均值）且 < 2.5/255（99.9%）才用，否则真彩；最后过 oxipng。

## 已量过的数

- 混凝土细节（亮度相对局部均值的 p1 / p99）：`concrete-night`（v12.1 安静底）约 −2.6 / +2.6 %，没有 σ > 90px 的斑块；纹理带（边缘、盘面带）用 v12 的纹理配方，去掉了大斑块和冷暖漂移。
- 牛皮纸：内部按 popups.py 文字下的做法压平（amount 0.55），#3E2F1C 12pt 次要字在内容区任意一行对最暗 5 % 像素 ≥ 4.59:1；残影在 09 / 11 的文字区下减薄 92 %，那里 ≥ 4.94:1。
- 同一台机器上重跑，PNG 逐字节相同。
