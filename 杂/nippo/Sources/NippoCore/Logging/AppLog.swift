import Foundation

/// 追記型の軽量ログ。<reportsRoot>/nippo.log に書き、1MB 超で .old へ退避。
/// 「なぜ通知・生成が走らなかったか」を事後に追えるようにする(可観測性)。
public final class AppLog {
    public static let shared = AppLog()

    private let queue = DispatchQueue(label: "nippo.applog")
    private var root: URL?

    private init() {}

    public func configure(root: URL) {
        queue.sync { self.root = root }
    }

    public func log(_ category: String, _ message: String) {
        queue.async { [weak self] in
            guard let self, let root = self.root else { return }
            let url = root.appendingPathComponent("nippo.log")
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let line = "[\(f.string(from: Date()))] [\(category)] \(message)\n"
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int,
               size > 1_000_000 {
                let old = root.appendingPathComponent("nippo.log.old")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// テスト用:書き込みキューを排水する
    public func flush() {
        queue.sync {}
    }
}
