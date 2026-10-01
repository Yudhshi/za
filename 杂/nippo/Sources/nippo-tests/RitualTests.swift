import Foundation
import NippoCore

func runRitualTests() {
    print("Ritual")
    T.run("ritual videos: names, sites, embeds, tracking queries dropped") {
        let videos = Ritual.videos(from: Ritual.defaultVideos)
        T.expectEqual(videos.map(\.title), ["跟练 1", "跟练 2", "跟练 3", "跟练 4"])
        T.expectEqual(videos.map(\.site), [.bilibili, .bilibili, .youtube, .youtube])
        T.expectEqual(videos[0].id, "BV1JW4y1k7F7")
        T.expectEqual(videos[0].embed?.absoluteString,
                      "https://player.bilibili.com/player.html?bvid=BV1JW4y1k7F7&page=1&autoplay=1&danmaku=0&high_quality=1")
        T.expectEqual(videos[3].embed?.absoluteString,
                      "https://www.youtube-nocookie.com/embed/aHlNoTpXf_8?autoplay=1&rel=0&playsinline=1")
        let pasted = Ritual.videos(from: """
        https://www.bilibili.com/video/BV1UL411F7Hk/?spm_id_from=333.1387&vd_source=abc
        晨间 https://youtu.be/SGPBSqxKGAc?t=10
        短 https://www.youtube.com/shorts/abcDEF12345
        随便写的一行

        别处 https://example.com/v/1
        """)
        T.expectEqual(pasted.map(\.title), ["视频 1", "晨间", "短", "别处"], "a line without a URL is skipped")
        T.expectEqual(pasted[0].page.absoluteString, "https://www.bilibili.com/video/BV1UL411F7Hk/",
                      "the vd_source / spm queries are not kept")
        T.expectEqual(pasted[1].id, "SGPBSqxKGAc")
        T.expectEqual(pasted[2].id, "abcDEF12345")
        T.expectEqual(pasted[3].site, .other)
        T.expectEqual(pasted[3].embed, nil, "unknown sites open in the browser")
    }

    T.run("ritual stretches: every step is timed or a short setup, poses fit") {
        let list = BreakReminder.stretches(from: Ritual.defaultStretches)
        T.expectEqual(list.count, 9)
        T.expectEqual(Ritual.duration(of: "右手按住右侧锁骨下方，头向左倒，拉伸右侧颈部，停 20 秒"), 20)
        T.expectEqual(Ritual.duration(of: "微微抬头停 15 秒，再微微低头停 15 秒"), 30, "two holds add up")
        T.expectEqual(Ritual.duration(of: "收下巴，后脑轻轻压向地面，停 5 秒 × 5 次"), 33, "5 × 5 + 4 gaps × 2")
        T.expectEqual(Ritual.duration(of: "挺胸，手臂慢慢往后上方抬，停 30 秒 × 2 次"), 62)
        T.expectEqual(Ritual.duration(of: "四点跪姿，吸气塌腰抬头，呼气拱背低头，慢慢做 8 次"), 32, "4 s a rep")
        T.expectEqual(Ritual.duration(of: "头向右转 45°，低头看右边腋下，停 30 秒"), 30, "degrees are not seconds")
        T.expectEqual(Ritual.duration(of: "走 2 分钟"), 120)
        T.expectEqual(Ritual.duration(of: "仰躺，膝盖弯曲，一只手放肚子上"), nil, "a setup step")
        let untimed = list.flatMap(\.steps).filter { Ritual.duration(of: $0) == nil }
        // 構えの行(腕・体の置き方)だけ秒が無い。アプリでは 10 秒の構えの時間にする
        T.expectEqual(untimed.count, 5, "only setup lines are untimed: \(untimed)")
        T.expectEqual(list.map { BreakReminder.illustration(for: $0) },
                      ["neck-side", "neck-side", "stretch", "stretch", "stretch", "chest-doorway", "stretch",
                       "stretch", "belly-breathing"])
        T.expect(!Ritual.defaultStretches.contains("举过头"), "nothing overhead")
    }

    T.run("breath pacer: 4 in, 6 out, three times") {
        T.expectEqual(BreathPacer.total, 30)
        T.expectEqual(BreathPacer.state(elapsed: 0), BreathPacer.State(breath: 0, inhaling: true, remaining: 4, finished: false))
        T.expectEqual(BreathPacer.state(elapsed: 3.2).remaining, 1)
        T.expectEqual(BreathPacer.state(elapsed: 4), BreathPacer.State(breath: 0, inhaling: false, remaining: 6, finished: false))
        T.expectEqual(BreathPacer.state(elapsed: 10.5), BreathPacer.State(breath: 1, inhaling: true, remaining: 4, finished: false))
        T.expectEqual(BreathPacer.state(elapsed: 29.9).breath, 2)
        T.expect(BreathPacer.state(elapsed: 30).finished, "done after three")
    }

    T.run("breath log: counts per day, streak, keeps 60 days") {
        let cal = tokyoCalendar
        var log: [String: Int] = [:]
        log = BreathLog.recording(log, day: "2026-10-01")
        log = BreathLog.recording(log, day: "2026-10-01")
        log = BreathLog.recording(log, day: "2026-10-02")
        T.expectEqual(log["2026-10-01"], 2)
        T.expectEqual(BreathLog.streak(log, today: tokyoDate(2026, 10, 2, 20, 0), calendar: cal), 2)
        T.expectEqual(BreathLog.streak(log, today: tokyoDate(2026, 10, 3, 8, 0), calendar: cal), 2,
                      "not yet today: count up to yesterday")
        T.expectEqual(BreathLog.streak(log, today: tokyoDate(2026, 10, 5, 8, 0), calendar: cal), 0)
        var long: [String: Int] = [:]
        for day in 1...70 {
            long = BreathLog.recording(long, day: String(format: "2026-%02d-%02d", 7 + (day - 1) / 31, (day - 1) % 31 + 1))
        }
        T.expectEqual(long.count, 60)
        T.expect(long["2026-07-01"] == nil, "the oldest days are dropped")
    }
}
