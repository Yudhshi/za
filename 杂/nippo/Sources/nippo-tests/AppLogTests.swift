import Foundation
import NippoCore

func runAppLogTests() {
    T.run("AppLog appends lines to nippo.log under configured root") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nippo-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        AppLog.shared.configure(root: root)
        AppLog.shared.log("test", "一行目")
        AppLog.shared.log("test", "二行目")
        AppLog.shared.flush()
        let text = try String(contentsOf: root.appendingPathComponent("nippo.log"),
                              encoding: .utf8)
        T.expect(text.contains("一行目") && text.contains("二行目"), "both lines present")
        T.expect(text.contains("[test]"), "category tag present")
    }
}
