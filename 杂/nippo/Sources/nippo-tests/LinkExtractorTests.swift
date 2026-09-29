import Foundation
import NippoCore

func runLinkExtractorTests() {
    T.run("finds Meet link inside notes text") {
        let url = MeetingLinkExtractor.extract(from: [
            nil,
            "会議室A",
            "参加方法: ビデオ通話のリンク: https://meet.google.com/abc-defg-hij\nメモ: 資料は esa",
        ])
        T.expectEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    T.run("finds Zoom link on subdomain, strips trailing punctuation") {
        let url = MeetingLinkExtractor.extract(from: [
            "詳細は https://us02web.zoom.us/j/1234567890?pwd=xyz."])
        T.expectEqual(url?.absoluteString, "https://us02web.zoom.us/j/1234567890?pwd=xyz")
    }

    T.run("finds Teams link and respects candidate priority order") {
        let url = MeetingLinkExtractor.extract(from: [
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting",
            "https://meet.google.com/should-not-win",
        ])
        T.expect(url?.host == "teams.microsoft.com", "URL field wins, got \(String(describing: url))")
    }

    T.run("ignores non-meeting URLs and empty input") {
        T.expectEqual(MeetingLinkExtractor.extract(from: [
            "資料: https://example.com/docs と https://github.com/x/y"]), nil)
        T.expectEqual(MeetingLinkExtractor.extract(from: [nil, "", "場所: 会議室B"]), nil)
    }

    T.run("full-width punctuation and kana never absorbed into the URL") {
        T.expectEqual(MeetingLinkExtractor.extract(from: [
            "参加リンク:(https://meet.google.com/abc-defg-hij)"])?.absoluteString,
            "https://meet.google.com/abc-defg-hij")
        T.expectEqual(MeetingLinkExtractor.extract(from: [
            "リンクは https://meet.google.com/abc-defg-hij」です"])?.absoluteString,
            "https://meet.google.com/abc-defg-hij")
    }

    T.run("unwraps Outlook SafeLinks before matching") {
        let wrapped = "https://nam12.safelinks.protection.outlook.com/ap/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F19%253ameeting&data=05%7C02%7Cx"
        let url = MeetingLinkExtractor.extract(from: [wrapped])
        T.expect(url?.host == "teams.microsoft.com",
                 "unwrapped host, got \(String(describing: url))")
    }

    T.run("prefers the longest URL within the same field (keeps pwd token)") {
        let url = MeetingLinkExtractor.extract(from: [
            "参加: https://zoom.us/j/123 詳細: https://us02web.zoom.us/j/1234567890?pwd=secret"])
        T.expect(url?.absoluteString.contains("pwd=secret") == true,
                 "pwd link wins, got \(String(describing: url))")
    }

    T.run("does not match lookalike host") {
        T.expectEqual(MeetingLinkExtractor.extract(from: [
            "https://fakemeet.google.com.evil.example/x https://notzoom.us.example/y"]), nil)
    }
}
