# 英语进度同步格式（Mac ⇄ Windows）

目的：两台机器共享单词 / 考点词 / 听写的复习进度、每日答题数和连续天数，不用服务器，不把 SQLite 放进同步盘。

## 原则

- 每台设备只**追加写自己的一个文件**，从不改别人的文件。
- 状态 = 把所有设备的「出来事」按时间顺序重放。两边重放同一组事件，得到同一份状态。
- 传输交给任何会搬文件的东西：OneDrive、iCloud Drive、Dropbox 都行。Mac 端在设置里选文件夹，Windows 指到同一个文件夹。

## 文件

```
<同步文件夹>/
  english-events-<设备名>.jsonl     每台设备一个，只由该设备写
```

设备名只保留字母、数字、`-`、`_`，其余替换成 `-`，首尾的 `-` 去掉（`Mac Book (Yudh)` → `english-events-Mac-Book--Yudh.jsonl`）。

写文件时先写到同目录的临时文件（`.english-events-X.jsonl.tmp`）再整体替换，避免读到半截。内容没变就不要重写（免得同步盘反复上传）。

## 一行一个事件（JSON）

```json
{"at":"2026-10-01T01:00:05.000Z","card":"vocab:b1-0807","device":"MacBook","id":"3f2c…","kind":"vocab","op":"rate","rating":"good"}
```

| 字段 | 说明 |
|---|---|
| `id` | 全局唯一（UUID 小写）。去重靠它 |
| `device` | 产生这个事件的设备名 |
| `at` | ISO 8601、UTC、带毫秒。**顺序只看这个值**（同时刻再按 `id` 字符串排序） |
| `op` | `rate` / `known` / `add` / `restore` / `undo` / `snapshot` / `log` |
| `card` | 卡片 id：`vocab:<词表id>`、`dict:<单词>`、`para:<listening|reading>:<词>`、`spell:<小写单词>` |
| `kind` | `vocab` / `para` / `spell` |
| `rating` | `rate` 用：`again` / `hard` / `good` / `easy` |
| `target` | `undo` 用：被取消的事件 id |
| `interval` `ease` `reps` `lapses` `due` `known` `firstSeen` | `snapshot` 用：卡片的完整状态 |
| `day` `result` | `log` 用：历史的答题记录（`day` 是 `yyyy-MM-dd`，`result` 同 rating 或 `known`） |

不认识的行（坏 JSON、未知 `op`）跳过。空字段不写。

`snapshot` 和 `log` 只在 Mac 端第一次升级到带同步的版本时产生一次（把同步之前的历史写成事件，`device` 为 `history`），Windows 端不需要产生它们，但必须能重放。

## 重放规则

1. 收集所有文件的所有事件，按 `id` 去重。
2. 找出所有 `undo` 的 `target`，把这些事件排除；`undo` 本身也不参与重放。
3. 其余按 `(at, id)` 升序，清空本地卡片和日志后依次应用：

- `snapshot`：用字段直接写入卡片状态（若缺 `due`/`firstSeen`，用 `at` 的日期）。
- `log`：写一条日志（`day`, `kind`, `result`, `at`）。
- `rate`：取卡片（不存在则新建：interval 0、ease 2.5、reps 0、lapses 0、known false、firstSeen = `at` 的日期），应用 SM-2 评分（规则见下），`due` = `at` 的日期 + interval 天；写一条日志 `result = rating`，`day` = `at` 的日期。
- `known`：取或新建卡片，`known = true`；写一条日志 `result = known`。
- `add`：不存在才新建（due = firstSeen = `at` 的日期）。
- `restore`：存在则 `known = false`，`due` = `at` 的日期。

「日期」按本机时区取 `yyyy-MM-dd`（两台机器都在东京时区就一致）。

## SM-2 评分（NippoCore `SRSState.applying`）

新卡 interval 0、ease 2.5、reps 0、lapses 0。`round` 为四舍五入到整数；下面的 reps 指评分**之前**的值。

- `again`：interval = 0；reps = 0；lapses + 1；ease = max(1.3, ease − 0.2)
- `hard`：interval = max(interval + 1, round(max(interval, 1) × 1.2))；ease = max(1.3, ease − 0.15)；reps + 1
- `good`：reps 为 0 → interval 1；reps 为 1 → max(3, round(interval × ease))；否则 max(1, round(interval × ease))；reps + 1（ease 不变）
- `easy`：reps 为 0 → interval 4；否则 max(1, round(interval × ease × 1.3))；ease + 0.15；reps + 1

以 Swift 端 `Sources/NippoCore/English/EnglishDrill.swift` 与 `Sources/nippo-tests/EnglishTests.swift` 为准；Windows 实现请跑同一组用例（good 连续三次：1 → 3 → 8；之后 hard → 10、ease 2.35；again → 0、reps 0、lapses 1；新卡 easy → 4、新卡 hard → 1；ease 最低 1.3）。

## 统计

- 今日答题数 = 日志里 `day` 等于今天的行数（`known` 也算一题）。
- 连续天数 = 从今天（今天还没答就从昨天）往前数日志里连续有记录的天数。
- 今天的新词配额 = 当天 `firstSeen` 等于今天且 id 不以 `dict:` 开头的卡片数。

## Windows 端的建议（电脑主要用来打游戏，要省资源）

- 不常驻轮询：打开面板时和每 5 分钟读一次文件夹；文件很小（几千行）。
- 不要用文件系统监听常驻钩子；不要开后台服务。
- 只写自己的文件；本地用 SQLite 或一个 JSON 文件存重放结果都可以。
- 会议：Windows 不读日历，只读 Mac 写出的 `agenda.json`（待实现，见 README 的计划）。
