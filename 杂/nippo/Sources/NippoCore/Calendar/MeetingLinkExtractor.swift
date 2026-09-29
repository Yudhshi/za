import Foundation

/// カレンダーイベントの URL・場所・メモから会議リンク(Meet/Zoom/Teams/Webex)を抽出する。
public enum MeetingLinkExtractor {
    /// 会議サービスのホスト(サブドメイン込みで一致判定)
    static let meetingHosts = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
    ]

    /// URL 文字を RFC 3986 の ASCII に限定する(括弧・引用符は除外)。
    /// 日本語のメモでは URL 直後に全角括弧・かな が続くことが多く、
    /// 否定文字クラス方式だとそれらを URL に取り込んでリンクを壊してしまう。
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https://[A-Za-z0-9\-._~:/?#@!$&*+,;=%]+"#,
        options: [.caseInsensitive])

    /// Outlook (Microsoft Defender) SafeLinks を元の URL に戻す。
    /// 会議リンクが safelinks.protection.outlook.com/?url=<encoded> に包まれると
    /// ホスト照合が全滅するため、走査前に必ず解包する。入れ子対応・上限付き。
    private static let safeLinksRegex = try! NSRegularExpression(
        pattern: #"https://[\S]+\.safelinks\.protection\.outlook\.com/[\S]*?url=([^&\s]+)"#,
        options: [.caseInsensitive])

    static func unwrapSafeLinks(_ text: String) -> String {
        var result = text
        var guardCount = 0
        while guardCount < 32 {
            guardCount += 1
            let range = NSRange(result.startIndex..., in: result)
            guard let m = safeLinksRegex.firstMatch(in: result, range: range),
                  m.numberOfRanges > 1,
                  let full = Range(m.range(at: 0), in: result),
                  let cap = Range(m.range(at: 1), in: result),
                  let decoded = String(result[cap]).removingPercentEncoding,
                  !decoded.isEmpty else { break }
            let before = result
            result.replaceSubrange(full, with: decoded)
            if result == before { break }   // 進捗なしなら打ち切り
        }
        return result
    }

    /// 候補文字列を順に走査し、会議リンクを返す。
    /// 候補の順序 = 優先度(呼び出し側は URL → 場所 → メモ の順で渡す)。
    /// 同一候補内に複数リンクがある場合は最長の URL を採用する
    /// (裸のリンクより ?pwd= 付きの完全なリンクを優先するため)。
    public static func extract(from candidates: [String?]) -> URL? {
        for candidate in candidates {
            guard let raw = candidate, !raw.isEmpty else { continue }
            let text = unwrapSafeLinks(raw)
            var best: URL?
            let range = NSRange(text.startIndex..., in: text)
            for match in urlRegex.matches(in: text, range: range) {
                guard let r = Range(match.range, in: text) else { continue }
                // 文末の句読点を除去("…参加: https://zoom.us/j/123." のような場合)
                var urlString = String(text[r])
                while let last = urlString.last, ".,;。、".contains(last) {
                    urlString.removeLast()
                }
                guard let url = URL(string: urlString),
                      let host = url.host?.lowercased() else { continue }
                guard meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
                else { continue }
                if best == nil || urlString.count > (best?.absoluteString.count ?? 0) {
                    best = url
                }
            }
            if let best { return best }
        }
        return nil
    }
}
