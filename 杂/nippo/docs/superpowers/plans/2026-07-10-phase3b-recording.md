# 三期 B:双轨录音 → 本地转写 → 議事録 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**依赖:三期 A(Meet 字幕)必须已合入**——本期复用其 `TranscriptService`(transcript_line 表)、`MinutesBuilder`、日报素材接入、菜单「議事録を作成」。录音只是**另一种转写来源**:采集→转写→写入同一个 transcript_line 表(session=录音会话),之后的纪要/日报/チェックリスト全走 A 的既有管线。

**Goal:** 用户点「録音を開始」→ **必须勾选确认门**「参加者に録音を伝え、会社の規定を確認しました」才开始 → ScreenCaptureKit 抓系统音(相手)+ AVAudioEngine 抓麦克风(自分)双轨分存 `recordings/YYYY/MM/` → 停止后 SpeechAnalyzer(回退 SFSpeechRecognizer)本地转写两轨 → 按时间轴合并成「自分/相手」标记的行写入 transcript_line → 复用 A 的「議事録を作成」。零上传,仅生成纪要时把文字给 Claude。

**红线(与打刻/自动化同级):**
1. **未勾选确认门不录音**——代码层面 `guard consented` 挡死,无任何绕过路径。
2. 录音中菜单栏图标变红 + 屏幕常驻「🔴 録音中 MM:SS」浮标(提醒用户自己;应用无法向会议对方广播)。
3. 录音、转写全程不出本机(SpeechAnalyzer/SFSpeechRecognizer 本地);仅纪要文字发 Claude。

**Architecture:** 纯逻辑(`RecordingConsent`/`RecordingSession` 路径与状态、`TranscriptMerger` 双轨时间轴合并)进 NippoCore(TDD);采集(`AudioRecorder`:AVAudioEngine+SCStream)、转写(`LocalTranscriber`:SpeechAnalyzer/SFSpeechRecognizer)、确认门窗、录音浮标进 NippoApp(编译通过 + 真机手动验证)。

**环境事实(勿再验证):** 无 Xcode,测试=`swift run nippo-tests`(A 合入后基线≈88;计数不同按差值顺延 Expected 并在 concerns 说明);分支 phase-1;打包 `./build-app.sh`;**绝不启动 GUI**;手动验证跳过并汇报;shell 用 `set -o pipefail`;提交末尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`;**改既有文件前先 Read**,锚点找不到报 BLOCKED。机器 M4 Pro / macOS 26.5。**AVAudioEngine/ScreenCaptureKit/Speech(SpeechAnalyzer)是系统框架,无外部依赖;SpeechAnalyzer 为 macOS 26 新 API——按 SDK 校验签名,不符则最小改并在 concerns 说明,保证 SFSpeechRecognizer 回退可编译。**

---

### Task 1: RecordingSession + RecordingConsent(路径与状态,纯逻辑)

**Files:**
- Create: `Sources/NippoCore/Recording/RecordingSession.swift`
- Create: `Sources/nippo-tests/RecordingTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(最后一个 run 调用后追加 `runRecordingTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/RecordingTests.swift`:

```swift
import Foundation
import NippoCore

func runRecordingTests() {
    T.run("session id and dual-track file paths under recordings/yyyy/MM") {
        let root = URL(fileURLWithPath: "/tmp/nippo-rec-root")
        let s = RecordingSession(root: root, title: "定例MTG",
                                 startedAt: tokyoDate(2026, 7, 10, 14, 30),
                                 calendar: tokyoCalendar)
        T.expect(s.sessionID.hasPrefix("2026-07-10-"), "dated session id")
        T.expect(s.sessionID.contains("定例MTG"), "title in id")
        T.expect(s.micURL.path.contains("recordings/2026/07/"), "mic under yyyy/MM")
        T.expect(s.micURL.lastPathComponent.hasSuffix("-mic.caf"), "mic suffix")
        T.expect(s.systemURL.lastPathComponent.hasSuffix("-system.caf"), "system suffix")
    }

    T.run("consent gate blocks until explicitly granted, resets per session") {
        var consent = RecordingConsent()
        T.expectEqual(consent.canRecord, false, "blocked by default")
        consent.grant()
        T.expectEqual(consent.canRecord, true, "granted")
        consent.reset()
        T.expectEqual(consent.canRecord, false, "reset re-blocks")
    }

    T.run("duration label formats mm:ss and h:mm:ss") {
        T.expectEqual(RecordingSession.durationLabel(65), "01:05")
        T.expectEqual(RecordingSession.durationLabel(3661), "1:01:01")
        T.expectEqual(RecordingSession.durationLabel(0), "00:00")
    }
}
```

`main.swift` 追加 `runRecordingTests()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `set -o pipefail; swift run nippo-tests`
Expected: `cannot find 'RecordingSession' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Recording/RecordingSession.swift`:

```swift
import Foundation

/// 録音セッションの識別子とファイルパス(自分=マイク / 相手=システム音)。
public struct RecordingSession {
    public let sessionID: String
    public let micURL: URL
    public let systemURL: URL

    public init(root: URL, title: String, startedAt: Date = Date(),
                calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                        from: startedAt)
        let safeTitle = title.isEmpty ? "会議" : title
            .replacingOccurrences(of: "/", with: "・")
            .replacingOccurrences(of: " ", with: "")
        self.sessionID = String(format: "%04d-%02d-%02d-%02d%02d-%@",
                                c.year!, c.month!, c.day!, c.hour!, c.minute!, safeTitle)
        let dir = root
            .appendingPathComponent("recordings")
            .appendingPathComponent(String(format: "%04d", c.year!))
            .appendingPathComponent(String(format: "%02d", c.month!))
        self.micURL = dir.appendingPathComponent("\(sessionID)-mic.caf")
        self.systemURL = dir.appendingPathComponent("\(sessionID)-system.caf")
    }

    public static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}

/// 録音同意ゲート。明示的に grant されるまで録音を許可しない(赤線)。
public struct RecordingConsent {
    private var granted = false
    public init() {}
    public var canRecord: Bool { granted }
    public mutating func grant() { granted = true }
    public mutating func reset() { granted = false }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `set -o pipefail; swift run nippo-tests`
Expected: 基线 +3(如基线 88 → `PASS: 91 tests`)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: recording session paths and consent gate (pure logic)"
```

---

### Task 2: TranscriptMerger(双轨时间轴合并,纯逻辑)

**Files:**
- Create: `Sources/NippoCore/Recording/TranscriptMerger.swift`
- Create: `Sources/nippo-tests/TranscriptMergerTests.swift`
- Modify: `Sources/nippo-tests/main.swift`(追加 `runTranscriptMergerTests()`)

- [ ] **Step 1: 写失败测试**

`Sources/nippo-tests/TranscriptMergerTests.swift`:

```swift
import Foundation
import NippoCore

func runTranscriptMergerTests() {
    T.run("merges two tracks into time-ordered speaker-tagged lines") {
        let mic = [
            TranscriptMerger.Segment(start: 1.0, text: "資料を共有します"),
            TranscriptMerger.Segment(start: 5.0, text: "はい、そうですね"),
        ]
        let sys = [
            TranscriptMerger.Segment(start: 3.0, text: "ありがとうございます"),
            TranscriptMerger.Segment(start: 7.0, text: "では次に進みましょう"),
        ]
        let lines = TranscriptMerger.merge(mic: mic, system: sys,
                                           selfLabel: "自分", otherLabel: "相手")
        T.expectEqual(lines.count, 4)
        T.expectEqual(lines[0].speaker, "自分")
        T.expectEqual(lines[0].text, "資料を共有します")
        T.expectEqual(lines[1].speaker, "相手")   // 3.0 秒
        T.expectEqual(lines[2].speaker, "自分")   // 5.0 秒
        T.expectEqual(lines[3].text, "では次に進みましょう")
    }

    T.run("empty tracks yield empty, single track preserved") {
        T.expectEqual(TranscriptMerger.merge(mic: [], system: [],
                                             selfLabel: "自分", otherLabel: "相手").count, 0)
        let only = TranscriptMerger.merge(
            mic: [.init(start: 2.0, text: "一人で話す")],
            system: [], selfLabel: "自分", otherLabel: "相手")
        T.expectEqual(only.count, 1)
        T.expectEqual(only[0].speaker, "自分")
    }
}
```

`main.swift` 追加 `runTranscriptMergerTests()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `set -o pipefail; swift run nippo-tests`
Expected: `cannot find 'TranscriptMerger' in scope`

- [ ] **Step 3: 实现**

`Sources/NippoCore/Recording/TranscriptMerger.swift`:

```swift
import Foundation

/// 2 トラック(マイク=自分 / システム音=相手)の転写セグメントを
/// 開始時刻順にマージし、話者ラベル付きの行にする。
public enum TranscriptMerger {
    public struct Segment: Equatable {
        public let start: TimeInterval   // 録音開始からの秒
        public let text: String
        public init(start: TimeInterval, text: String) {
            self.start = start
            self.text = text
        }
    }

    public struct Line: Equatable {
        public let start: TimeInterval
        public let speaker: String
        public let text: String
    }

    public static func merge(mic: [Segment], system: [Segment],
                             selfLabel: String, otherLabel: String) -> [Line] {
        let a = mic.map { Line(start: $0.start, speaker: selfLabel, text: $0.text) }
        let b = system.map { Line(start: $0.start, speaker: otherLabel, text: $0.text) }
        return (a + b)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
    }
}
```

- [ ] **Step 4: 跑测试确认通过 + Commit**

Run: `set -o pipefail; swift run nippo-tests`
Expected: 基线 +2

```bash
git add -A && git commit -m "feat: dual-track transcript merger (pure logic)"
```

---

### Task 3: 设置 + Info.plist 麦克风权限说明

**Files:**
- Modify: `Sources/NippoCore/Settings/AppSettings.swift`(recordingLocale + selfLabel/otherLabel)
- Modify: `Sources/nippo-tests/SettingsTests.swift`(断言)
- Modify: `Resources/Info.plist`(NSMicrophoneUsageDescription)

- [ ] **Step 1: 设置 TDD**

`SettingsTests.swift`「defaults and roundtrip」末尾追加:

```swift
        T.expectEqual(s.recordingLocale, "ja-JP")
        T.expectEqual(s.selfLabel, "自分")
        T.expectEqual(s.otherLabel, "相手")
        s.selfLabel = "Yudi"
        T.expectEqual(AppSettings(defaults: d).selfLabel, "Yudi")
```

确认失败后 `AppSettings.swift`(captionServerPort 之后)追加:

```swift
    /// 会議録音の転写ロケール・話者ラベル
    public var recordingLocale: String {
        get { d.string(forKey: "recordingLocale") ?? "ja-JP" }
        set { d.set(newValue, forKey: "recordingLocale"); objectWillChange.send() }
    }
    public var selfLabel: String {
        get { d.string(forKey: "selfLabel") ?? "自分" }
        set { d.set(newValue, forKey: "selfLabel"); objectWillChange.send() }
    }
    public var otherLabel: String {
        get { d.string(forKey: "otherLabel") ?? "相手" }
        set { d.set(newValue, forKey: "otherLabel"); objectWillChange.send() }
    }
```

- [ ] **Step 2: Info.plist**

`Resources/Info.plist`,在 `NSCalendarsFullAccessUsageDescription` 的 key/string 对之后追加:

```xml
    <key>NSMicrophoneUsageDescription</key>
    <string>会議の自分の発言を録音し、ローカルで文字起こしして議事録を作成するために使用します。</string>
```

(屏幕录制はキー不要;SCStream 初回使用時にシステムが許可を求める)

- [ ] **Step 3: 测试 + 构建 + Commit**

Run: `set -o pipefail; swift run nippo-tests && swift build --target NippoApp`
Expected: 基线不变(断言增加),编译通过

```bash
git add -A && git commit -m "feat: recording locale/labels settings and microphone usage description"
```

---

### Task 4: AudioRecorder(双轨采集,系统胶水)

**Files:**
- Create: `Sources/NippoApp/AudioRecorder.swift`

**采集属系统交互,无单元测试;编译通过 + Task 7 手动验证。API 按 SDK 校验,不符最小改并在 concerns 说明。**

- [ ] **Step 1: 实现**

`Sources/NippoApp/AudioRecorder.swift`:

```swift
import AVFoundation
import Foundation
import ScreenCaptureKit
import NippoCore

/// 自分=マイク(AVAudioEngine)/ 相手=システム音(ScreenCaptureKit)を
/// 2 トラックに分けて録る。API は SDK に合わせて最小限に調整すること。
@MainActor
final class AudioRecorder: NSObject {
    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var stream: SCStream?
    private(set) var isRecording = false

    /// マイク権限を要求(初回のみプロンプト)
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            default: cont.resume(returning: false)
            }
        }
    }

    func start(session: RecordingSession) async throws {
        guard !isRecording else { return }
        try FileManager.default.createDirectory(
            at: session.micURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // --- 自分: マイク ---
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        let mic = try AVAudioFile(forWriting: session.micURL,
                                  settings: micFormat.settings)
        micFile = mic
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) {
            [weak self] buffer, _ in
            try? self?.micFile?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()

        // --- 相手: システム音(ScreenCaptureKit の音声のみ) ---
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            AppLog.shared.log("record", "no display for system audio")
            isRecording = true   // マイクのみで続行
            return
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // 自分のアプリ音は除外
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "nippo.sysaudio"))
        try await stream.startCapture()
        self.stream = stream
        isRecording = true
        AppLog.shared.log("record", "started \(session.sessionID)")
    }

    func stop() async {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil
        try? await stream?.stopCapture()
        stream = nil
        systemFile = nil
        isRecording = false
        AppLog.shared.log("record", "stopped")
    }

    private func writeSystem(_ sampleBuffer: CMSampleBuffer, session: RecordingSession) {
        // 初回サンプルでフォーマット確定 → ファイル生成
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
        else { return }
        if systemFile == nil {
            let format = AVAudioFormat(streamDescription: asbd)!
            systemFile = try? AVAudioFile(forWriting: session.systemURL,
                                          settings: format.settings)
        }
        if let pcm = sampleBuffer.toPCMBuffer() {
            try? systemFile?.write(from: pcm)
        }
    }

    // stop 後に相手トラック用の session 参照を保持
    var currentSession: RecordingSession?
}

extension AudioRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio else { return }
        Task { @MainActor [weak self] in
            guard let self, let session = self.currentSession else { return }
            self.writeSystem(sampleBuffer, session: session)
        }
    }
}

extension CMSampleBuffer {
    /// システム音の CMSampleBuffer を AVAudioPCMBuffer に変換(概略・SDK に合わせ調整)
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        pcm.frameLength = frames
        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return pcm
    }
}
```

**注意**:`start(session:)` 前需 `currentSession = session`。若 SCStream/AVAudioFile 某 API 签名不符,最小改并在 concerns 记录;系统音失败时保证麦克风单轨仍工作。

- [ ] **Step 2: 编译确认 + Commit**

Run: `set -o pipefail; swift build --target NippoApp`
Expected: `Build complete!`(如个别 API 签名不符,按 SDK 修正后再编;记录偏离)

```bash
git add -A && git commit -m "feat: dual-track audio recorder (mic + system audio)"
```

---

### Task 5: LocalTranscriber(SpeechAnalyzer,回退 SFSpeechRecognizer)

**Files:**
- Create: `Sources/NippoApp/LocalTranscriber.swift`

**转写属系统交互,编译通过 + 手动验证。SpeechAnalyzer 为 macOS 26 新 API,按 SDK 校验;保证 SFSpeechRecognizer 回退可编译。**

- [ ] **Step 1: 实现**

`Sources/NippoApp/LocalTranscriber.swift`:

```swift
import Foundation
import Speech
import NippoCore

/// 音声ファイルをローカルで文字起こし(セグメント=開始秒+テキスト)。
/// 優先 SpeechAnalyzer(macOS 26)、フォールバック SFSpeechRecognizer。
enum LocalTranscriber {
    static func transcribe(url: URL, locale: String) async -> [TranscriptMerger.Segment] {
        // まず SpeechAnalyzer を試す(API は SDK に合わせて調整すること)。
        // 署名不明・未対応時は SFSpeechRecognizer に落ちる。
        if let viaAnalyzer = try? await transcribeWithAnalyzer(url: url, locale: locale) {
            return viaAnalyzer
        }
        return (try? await transcribeWithRecognizer(url: url, locale: locale)) ?? []
    }

    /// macOS 26 SpeechAnalyzer。SDK に存在しない/署名が違う場合はこの実装を
    /// 埋めるか、throw させて下の SFSpeechRecognizer に委ねる。
    static func transcribeWithAnalyzer(url: URL, locale: String) async throws
        -> [TranscriptMerger.Segment] {
        // TODO(手動): macOS 26 の Speech フレームワークの SpeechAnalyzer /
        // SpeechTranscriber を用いて実装。API 確定まではフォールバックに委ねるため throw。
        throw CocoaError(.featureUnsupported)
    }

    /// 既知の SFSpeechRecognizer によるファイル転写(全編一括・タイムスタンプ付き)
    static func transcribeWithRecognizer(url: URL, locale: String) async throws
        -> [TranscriptMerger.Segment] {
        let granted = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard granted,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.isAvailable else { return [] }
        recognizer.supportsOnDeviceRecognition = true

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true   // ローカルのみ・外部送信しない
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error { cont.resume(throwing: error); return }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments.map {
                    TranscriptMerger.Segment(start: $0.timestamp, text: $0.substring)
                }
                // セグメント粒度が細かすぎるので発話単位にまとめる
                cont.resume(returning: LocalTranscriber.coalesce(segments))
            }
        }
    }

    /// 短いセグメントを 2 秒ギャップ or 句点でまとめて発話単位に
    static func coalesce(_ segs: [TranscriptMerger.Segment]) -> [TranscriptMerger.Segment] {
        var out: [TranscriptMerger.Segment] = []
        for seg in segs {
            if var last = out.last,
               seg.start - (last.start) < 60,   // 粗い結合(手動調整可)
               !last.text.hasSuffix("。") {
                last = .init(start: last.start, text: last.text + seg.text)
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }
}
```

- [ ] **Step 2: 编译确认 + Commit**

Run: `set -o pipefail; swift build --target NippoApp`
Expected: `Build complete!`

```bash
git add -A && git commit -m "feat: local transcriber (SFSpeechRecognizer, SpeechAnalyzer stub)"
```

---

### Task 6: 确认门窗 + 录音浮标 + coordinator + 菜单

**Files:**
- Create: `Sources/NippoApp/RecordingViews.swift`
- Create: `Sources/NippoApp/AppCoordinator+Recording.swift`
- Modify: `Sources/NippoApp/AppCoordinator.swift`(属性)
- Modify: `Sources/NippoApp/MenuContentView.swift`(録音区块)
- Modify: `Sources/NippoApp/SettingsView.swift`(话者标签)

**先 Read 各既有文件。**

- [ ] **Step 1: 确认门窗 + 浮标**

`Sources/NippoApp/RecordingViews.swift`:

```swift
import AppKit
import SwiftUI
import NippoCore

/// 録音前の必須確認ダイアログ。チェックを入れないと「録音を開始」は押せない(赤線)。
@MainActor
final class RecordingConsentController {
    private var window: NSWindow?
    private let onStart: (String) -> Void   // 会議タイトル

    init(onStart: @escaping (String) -> Void) { self.onStart = onStart }

    func show(defaultTitle: String) {
        if window != nil { return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "会議を録音"
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: ConsentView(
            defaultTitle: defaultTitle,
            onStart: { [weak self] title in self?.onStart(title); self?.close() },
            onCancel: { [weak self] in self?.close() }))
        win.center(); win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
    private func close() { window?.close(); window = nil }
}

private struct ConsentView: View {
    let defaultTitle: String
    let onStart: (String) -> Void
    let onCancel: () -> Void
    @State private var title: String
    @State private var agreed = false

    init(defaultTitle: String, onStart: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.defaultTitle = defaultTitle
        self.onStart = onStart
        self.onCancel = onCancel
        _title = State(initialValue: defaultTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("会議を録音します").font(.headline)
            TextField("会議名", text: $title).textFieldStyle(.roundedBorder)
            Toggle(isOn: $agreed) {
                Text("参加者に録音を伝え、会社の規定を確認しました")
            }
            Text("録音・文字起こしはこの Mac 内だけで行われます。議事録の作成時のみ、文字が Claude に送られます。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("キャンセル") { onCancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("録音を開始") { onStart(title) }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(!agreed)   // 赤線:同意なしは押せない
            }
        }
        .padding(16)
    }
}

/// 録音中の常駐フローティング表示「🔴 録音中 MM:SS」。
@MainActor
final class RecordingIndicatorController {
    private var panel: NSPanel?
    func show(elapsed: @escaping () -> Int, onStop: @escaping () -> Void) {
        if panel != nil { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
                        styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: IndicatorView(elapsed: elapsed, onStop: onStop))
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 200,
                                     y: screen.visibleFrame.maxY - 64))
        }
        p.orderFront(nil)
        panel = p
    }
    func hide() { panel?.close(); panel = nil }
}

private struct IndicatorView: View {
    let elapsed: () -> Int
    let onStop: () -> Void
    @State private var label = "00:00"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text("録音中 \(label)").font(.callout.monospacedDigit())
            Button { onStop() } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .onReceive(timer) { _ in label = RecordingSession.durationLabel(elapsed()) }
    }
}
```

- [ ] **Step 2: coordinator 属性 + 扩展**

`AppCoordinator.swift` 属性区追加:

```swift
    @Published var isRecording = false
    private var recorder: AudioRecorder?
    private var recordingSession: RecordingSession?
    private var recordingStart: Date?
    private lazy var consentController = RecordingConsentController { [weak self] title in
        self?.beginRecording(title: title)
    }
    private let recordingIndicator = RecordingIndicatorController()
```

`Sources/NippoApp/AppCoordinator+Recording.swift`:

```swift
import AppKit
import Foundation
import NippoCore

extension AppCoordinator {
    /// メニューから:確認ダイアログを出す(まだ録音は始めない)
    func requestStartRecording() {
        let title = NextEventPolicy.currentOrNext(events: todayEvents, now: Date())?.title
            ?? "会議"
        consentController.show(defaultTitle: title)
    }

    /// 確認ダイアログの「録音を開始」から呼ばれる(= 同意済み)
    func beginRecording(title: String) {
        guard !isRecording else { return }
        let root = URL(fileURLWithPath: settings.reportsRoot)
        let session = RecordingSession(root: root, title: title)
        let recorder = AudioRecorder()
        recorder.currentSession = session
        recordingSession = session
        recordingStart = Date()

        Task { @MainActor in
            guard await recorder.requestMicPermission() else {
                statusMessage = "マイク権限がありません(システム設定で許可)"
                return
            }
            do {
                try await recorder.start(session: session)
                self.recorder = recorder
                self.isRecording = true
                self.recordingIndicator.show(
                    elapsed: { [weak self] in
                        Int(Date().timeIntervalSince(self?.recordingStart ?? Date()))
                    },
                    onStop: { [weak self] in self?.stopRecording() })
                AppLog.shared.log("record", "consented + started \(session.sessionID)")
            } catch {
                statusMessage = "録音の開始に失敗: \(error.localizedDescription)"
            }
        }
    }

    func stopRecording() {
        guard isRecording, let recorder, let session = recordingSession else { return }
        isRecording = false
        recordingIndicator.hide()
        statusMessage = "録音を停止、文字起こし中…"
        Task { @MainActor in
            await recorder.stop()
            self.recorder = nil
            // 2 トラックをローカル転写 → 時刻マージ → transcript_line へ(A の管線に合流)
            let locale = settings.recordingLocale
            let mic = await LocalTranscriber.transcribe(url: session.micURL, locale: locale)
            let sys = await LocalTranscriber.transcribe(url: session.systemURL, locale: locale)
            let lines = TranscriptMerger.merge(mic: mic, system: sys,
                                               selfLabel: settings.selfLabel,
                                               otherLabel: settings.otherLabel)
            for line in lines {
                let at = (self.recordingStart ?? Date()).addingTimeInterval(line.start)
                try? self.transcriptService.append(session: session.sessionID,
                                                    speaker: line.speaker,
                                                    text: line.text, at: at)
            }
            self.activeMeetingSession = session.sessionID
            self.activeMeetingLineCount = lines.count
            self.statusMessage = lines.isEmpty
                ? "文字起こし結果が空でした" : "文字起こし完了。「議事録を作成」できます"
            AppLog.shared.log("record", "transcribed \(lines.count) lines")
        }
    }
}
```

(`activeMeetingSession`/`activeMeetingLineCount`/`transcriptService` 是 A 期已有属性——录音结果直接接进 A 的「議事録を作成」。)

- [ ] **Step 3: 菜单 + 设置**

`MenuContentView.swift` 的 `minutesSection`(A 期新增)之前插入 `recordingSection`:

```swift
    @ViewBuilder
    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("mic.fill", "会議の録音")
            if coordinator.isRecording {
                Button {
                    coordinator.stopRecording()
                } label: {
                    Label("録音を停止して文字起こし", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
            } else {
                Button {
                    coordinator.requestStartRecording()
                } label: {
                    Label("録音を開始(要確認)", systemImage: "record.circle")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .sectionSurface()
    }
```

并在 `normalContent` 的 VStack 里 `minutesSection` 之前加入 `recordingSection`。

`SettingsView.swift`「会議の字幕」Section 之后追加:

```swift
            Section("会議の録音") {
                TextField("自分のラベル", text: binding(\.selfLabel))
                TextField("相手のラベル", text: binding(\.otherLabel))
                TextField("文字起こしロケール", text: binding(\.recordingLocale))
                Text("録音のたびに確認ダイアログが出ます(参加者への周知は必須)。録音と文字起こしはローカルのみ。")
                    .font(.caption).foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: 测试 + 打包 + Commit**

Run: `set -o pipefail; swift run nippo-tests && ./build-app.sh`
Expected: 基线 tests 全绿,`Built: dist/Nippo.app`

```bash
git add -A && git commit -m "feat: recording consent gate, indicator, coordinator wiring, menu"
```

- [ ] **Step 5: 手动验证清单(跳过并汇报)**

1. 菜单「録音を開始(要確認)」→ 弹确认框;**不勾选时「録音を開始」按钮禁用**(红线);勾选后可点
2. 首次弹麦克风权限、首次弹屏幕录制权限 → 允许
3. 录音中屏幕右上出现「🔴 録音中 MM:SS」浮标,可点停止
4. 停止 → recordings/2026/07/ 下有 `-mic.caf` 和 `-system.caf` 两个文件
5. 文字起こし完成后菜单「会議の字幕」区块显示行数 →「議事録を作成」生成含自分/相手标记的纪要
6. 生成的纪要进当天日报素材、TODO 进チェックリスト(复用 A 管线)

---

### Task 7: README + 规格

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「使い方」列表末尾追加**

```markdown
- 会議の録音(オンライン/対面): メニューの「録音を開始」→ 確認ダイアログ(参加者周知が必須)
  → 自分(マイク)と相手(システム音)を 2 トラックで録音 → 停止でローカル文字起こし
  → 「議事録を作成」。録音・文字起こしはこの Mac 内だけ。字幕ルートと同じ議事録に合流
```

- [ ] **Step 2: 确认 + Commit**

Run: `set -o pipefail; swift run nippo-tests`
Expected: 全绿

```bash
git add -A && git commit -m "docs: meeting recording usage"
```

---

## 后续(不在本计划内)

- SpeechAnalyzer(macOS 26)実装で SFSpeechRecognizer を置き換え(精度・話者・句読点向上)
- 録音の一時停止/再開、長時間録音のチャンク転写
- 「初めて聞いた言葉」ログ(転写×用語集)
- 録音セッションと日历事件の自動関連付け
