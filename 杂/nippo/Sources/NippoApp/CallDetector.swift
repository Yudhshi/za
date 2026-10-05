import CoreAudio
import CoreMediaIO
import Foundation

/// いま通話中か:どこかのアプリがマイクから入力している、またはカメラが動いている。
/// 日历に無い会議(臨時の Meet・Slack のハドル・Zoom)や、予定より延びた会議もこれで分かる。
/// 音や映像は読まない(「使われているか」だけ)。権限も要らない
enum CallDetector {
    /// いまマイク・カメラを使っているもの(マイクはアプリの bundle id、カメラは "camera")。空なら通話していない。
    /// ログに残して、一日中マイクを開けっぱなしのアプリで提醒が止まったときに原因が分かるようにする
    static func activeSources() -> [String] {
        microphoneUsers() + (cameraInUse() ? ["camera"] : [])
    }

    // MARK: マイク

    /// 入力を動かしているプロセス(自分は除く)の bundle id。プロセスごとに見るので、
    /// AirPods のように入出力が 1 台の機器で音楽を聴いているだけ、を通話と取り違えない(macOS 14.2+)
    static func microphoneUsers() -> [String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else {
            return []
        }
        let me = getpid()
        return processes
            .filter { flag($0, kAudioProcessPropertyIsRunningInput) && pid(of: $0) != me }
            .map { bundleID(of: $0) ?? "pid \(pid(of: $0))" }
    }

    /// プロセスの bundle id(Core Audio が返す CFString は呼んだ側が手放す)
    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let unmanaged = value else { return nil }
        let id = unmanaged.takeRetainedValue() as String
        return id.isEmpty ? nil : id
    }

    private static func pid(of process: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr else { return -1 }
        return pid
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    // MARK: カメラ

    /// 内蔵・外付け・iPhone のカメラのどれかが、どこかのアプリで動いているか
    static func cameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else {
            return false
        }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var value: UInt32 = 0
            var valueUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &running, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &valueUsed, &value)
            return status == noErr && value != 0
        }
    }
}
