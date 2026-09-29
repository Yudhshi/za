import Foundation
import NippoCore

func runTaskOutlineTests() {
    func render(_ lines: [TaskOutline.Line?]) -> [String] {
        lines.map { $0.map { "\($0.depth):\($0.text)" } ?? "---" }
    }

    T.run("the user's example: tab-indented bullets become children, blank line separates tasks") {
        let memo = "事例公開\n\nPh2 - navigate\n\t- 電話\n\t- gen1 と gen2 の違い\n"
        T.expectEqual(render(TaskOutline.parse(memo)),
                      ["0:事例公開", "---", "0:Ph2 - navigate", "1:電話", "1:gen1 と gen2 の違い"])
    }

    T.run("spaces, full-width space and bullets without indent") {
        let memo = "A\n    - four spaces\n  two spaces\n\u{3000}全角\n- no indent bullet\n\t\t- deeper\n・中黒"
        T.expectEqual(render(TaskOutline.parse(memo)),
                      ["0:A", "1:four spaces", "1:two spaces", "1:全角", "1:no indent bullet",
                       "2:deeper", "1:中黒"])
    }

    T.run("blank lines collapse; leading/trailing blanks and empty bullets dropped") {
        T.expectEqual(render(TaskOutline.parse("\n\nA\n\n\n\nB\n- \n\n")), ["0:A", "---", "0:B"])
        T.expectEqual(render(TaskOutline.parse("")), [])
    }
}
