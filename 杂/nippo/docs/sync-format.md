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

改了设备名之后，新名字的文件会带着这台设备的全部事件重新写一份；旧文件可以删掉（留着也没事，事件按 `id` 去重）。

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

「撤销」只针对刚答的那张卡：产生的 `undo` 事件只指向这台设备在撤销点之后、同一张卡上的事件。撤销后本地也按上面的规则整体重放一次，所以不管中途有没有导入别的设备的事件，结果都和对方重放出来的一致。

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
- 会议：Windows 不读日历，只读 Mac 写出的 `agenda.json`（见下）。

## 会议：`agenda.json`（Mac → Windows，只读）

Windows 不碰日历。Mac 在同步文件夹里写一个 `agenda.json`，内容是**今天和明天**的会议；Windows 只读它，从不写。

```
<同步文件夹>/
  agenda.json            只由 Mac 写（设置里「把今天和明天的会议写给 Windows」可以关掉）
```

- 什么时候写：Mac 每次读日历（打开面板时、每分钟的 tick）之后。**除 `generatedAt` 以外的内容没变就不写**，所以一天里只在会议变动和日期变化时才会改动这个文件。
- 写法同上：先写 `.agenda.json.tmp` 再整体替换。
- 不写参加者。标题、时间、会议链接照写（文件在你自己的同步盘里）。

```json
{
  "days" : [
    {
      "day" : "2026-10-01",
      "events" : []
    },
    {
      "day" : "2026-10-02",
      "events" : [
        {
          "allDay" : false,
          "end" : "2026-10-02T01:15:00Z",
          "id" : "C1A2…",
          "join" : "https://meet.google.com/abc-defg-hij",
          "start" : "2026-10-02T01:00:00Z",
          "title" : "朝会"
        }
      ]
    }
  ],
  "device" : "MacBook",
  "generatedAt" : "2026-10-01T12:00:00Z",
  "timeZone" : "Asia/Tokyo",
  "version" : 1
}
```

| 字段 | 说明 |
|---|---|
| `version` | 现在是 `1`。不认识的版本整个文件不读 |
| `device` | 写这个文件的 Mac 的设备名 |
| `generatedAt` | 内容最后一次变化的时刻（ISO 8601、UTC） |
| `timeZone` | Mac 的时区（IANA 名）。`day` 按这个时区划分 |
| `days[].day` | `yyyy-MM-dd`。今天、明天各一项；没有会议也会列出（`events` 为空 = 确实没会） |
| `events[]` | 按 `start` 升序；同一时刻按 `end`、`title`、`id` |
| `id` | 日历里的事件 id（同一个会议在两次写出之间不变，提醒去重用） |
| `start` `end` | ISO 8601、UTC（读的时候也接受带毫秒的写法） |
| `allDay` | 全天事件（Windows 端一般不提醒、不显示倒计时） |
| `join` | 会议链接（Meet / Zoom / Teams），没有就不写 |

Windows 端的读法：

- 「明天」= Windows 本地日期 + 1 天，在 `days` 里找同一个 `day`。**找不到 = Mac 还没更新**（比如 Mac 一直在睡），显示「Mac 还没同步明天的日程」之类的话，不要显示成「明天没会」。
- 只在打开面板时读一次；文件很小，不用监听。
- 以 Swift 端 `Sources/NippoCore/Calendar/AgendaExport.swift`（`parse`）与 `Sources/nippo-tests/AgendaExportTests.swift` 为准。
