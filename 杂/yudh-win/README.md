# Yudh for Windows

Mac 版 Yudh（`../nippo`）的 Windows 伴随程序。电脑主要用来打游戏，所以只做这几件事、尽量不占资源：

1. **英语**：单词卡 / 考点词 / 听写，和 Mac 共用同一份进度（同步文件夹里的 `english-events-*.jsonl`）。听写和 Mac 一样用系统语音读（英式优先，没装就用美式并在卡上写明）。
2. **明天的会**：只读 Mac 写的 `agenda.json`，不碰日历。
3. **泡完澡后的日课**：和 Mac 同一套（跟练视频用官方播放器 → 肩颈拉伸 → 躺着做腹式呼吸），按时间自动往下走，没有语音播报；以及站起来时的 3 次腹式呼吸。连续天数和隔天力量按两台设备加起来算（同步文件夹里各自写一个 `habits-<设备名>.json`，读的时候相加）。
4. **坐站提醒**：计划已经定好（坐 30 分钟 → 站 30 分钟循环，不用调），和 Mac 同样的拉伸步骤，每一步到时间自动往下走。全屏游戏时不弹，但**连续玩 60 分钟以上，退出全屏就马上问一次「站起来了吗？」**（手臂前伸、身体前倾的长时间正是斜角肌最容易绷紧的时候）。

格式以 `../nippo/docs/sync-format.md` 为准。

## 结构

```
core/      yudh-core：没有界面的 Rust 库（这里的逻辑全部有测试，在 Linux 上也能跑）
  event    同步事件一行（键按字母序、空字段不写、时间 UTC 毫秒）
  replay   去重 → 排除撤销 → 按 (at, id) 重放 → 卡片 + 答题记录
  srs      SM-2（和 Swift 的 SRSState.applying 同一组用例）
  queue    出题顺序（复习优先 → 当天新词额度）
  english  给界面用的入口：出题、评分、知道了、加词、恢复、撤销、统计
  sync     同步文件夹：只写自己的文件（临时文件 + 替换，内容没变不写）
  library  词表（同步文件夹的 english-library/）
  agenda   明天的会：没有文件 / Mac 还没更新 / 没有会 / 会议列表
  posture  坐站计时与小窗判断（Mac 的 BreakReminder + StretchGuide）
  ritual   日课：视频链接解析与嵌入地址、拉伸每一步的秒数、腹式呼吸节拍与记录
  habits   日课 / 呼吸记录的跨设备合计（只写自己的 habits-<设备名>.json，读时把别的设备加上）
```

没有本地数据库：自己的 `english-events-<设备名>.jsonl` 就是自己的正本，状态每次从所有设备的事件重放出来（几千行，毫秒级）。

## 开发

```
cargo test            # 核心 38 个 + app 1 个
cargo clippy --all-targets -- -D warnings
```

## app（Tauri 2 外壳）

```
app/
  src-tauri/   Rust：托盘、30 秒一次的坐站判定（全屏游戏判定、离开座位判定）、给界面的命令
  ui/          面板 index.html（英语 / 明天 / 设置）、坐站小窗 posture.html、日课 ritual.html
               素材 material/ 和字体 fonts/ 在构建前从 ../../nippo/Resources 复制（不进 git）
  scripts/copy-assets.mjs
```

- 常驻的只有托盘。面板、坐站小窗、日课窗口都是要用时才创建，关掉就销毁；面板关掉时连词表一起释放内存。
- 面板：点托盘图标打开，出现在鼠标所在屏幕的可用区域右下角（任务栏在哪条边都不会挡住），失去焦点就关（选文件夹时除外）。Esc 关闭。
- 默认开机自启（只进托盘）；设置里可以关。重复双击启动时不会再开一个，只会把面板打开。
- 打游戏时完全安静（反作弊对策，默认 AION2：`Aion2.exe` / `Aion2-Win64-Shipping.exe`，设置里可改）：名单里的程序在运行时，
  Yudh 关掉自己所有窗口、不再创建任何窗口，也不再读键鼠空闲和全屏状态，只留托盘图标（提示变成「游戏中，已暂停」）；游戏关掉后自动恢复。
  判断只看进程列表里的程序名（Toolhelp 快照，和任务管理器一样），不打开、不读取游戏进程。
  Yudh 本来就不读写游戏内存、不注入、不装驱动、不挂键鼠钩子、不模拟按键、不截屏。但反作弊的规则不公开，没人能保证；最稳妥的是开游戏前从托盘退出 Yudh。
- 视觉沿用 Mac 夜版烤好的素材：九宫格用 CSS `border-image`（`bleed` 用外扩，`insets` 对应切片），模板字用字形图集。
- 在浏览器里预览界面：`cd app/ui && python3 -m http.server`，打开 `index.html` / `posture.html?prompt=askStand` / `ritual.html`
  （不在 Tauri 里时，`js/mock.js` 提供示例数据）。

## 安装包

GitHub Actions（`.github/workflows/yudh-windows.yml`）在 windows-latest 上 `npm run build`，
产物在运行页面的 Artifacts「Yudh-Windows-setup」（NSIS 安装包，装在当前用户下，不需要管理员权限）。

本地（Windows）：

```
cd app
npm install
npm run dev      # 开发
npm run build    # 安装包：target/release/bundle/nsis/
```

## 第一次使用

1. 安装包没有代码签名，Windows 会弹 SmartScreen「已保护你的电脑」：点「更多信息」→「仍要运行」。只有第一次。
2. 打开面板 → 设置 → 同步文件夹：选和 Mac 设置里同一个文件夹（OneDrive 等）。
3. 这台电脑的名字：默认是计算机名，不要和 Mac 同名。
4. Mac 设置里要打开「把今天和明天的会议写给 Windows」和「把词表复制一份给 Windows」，Windows 才有明天的会和单词。
5. 听写和日课播报用 Windows 自带的语音。设置最下面「语音」会显示这台电脑有没有英式英语和中文语音、没有的话怎么装；没有中文语音时日课只计时不播报（不会用日语的声音去读中文）。
