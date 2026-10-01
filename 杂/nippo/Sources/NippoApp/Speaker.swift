import AVFoundation

/// 英語の読み上げ(macOS 内蔵の音声)。IELTS に合わせて英国英語の声を優先し、
/// 高品質版(「拡張」「プレミアム」)を入れてあればそちらを使う
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestVoice()

    func say(_ text: String, slow: Bool = false) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = slow ? 0.34 : AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 日课の拉伸の読み上げ(中文の声。少しゆっくり)
    func guide(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = guideVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    private lazy var guideVoice: AVSpeechSynthesisVoice? = Self.bestVoice(languages: ["zh-CN", "zh-TW", "zh-HK"])

    private static func bestVoice(languages: [String]) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.identifier.contains("eloquence") && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        for language in languages {
            if let best = voices.filter({ $0.language == language }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
                return best
            }
        }
        return AVSpeechSynthesisVoice(language: languages.first ?? "zh-CN")
    }

    /// 声の名前(画面の注記用。英語の声が無ければ nil)
    var voiceName: String? { voice?.name }

    /// 品質の高い順(同じ品質なら英国英語の定番 Daniel)。機械的な Eloquence 系とおもしろ音声は使わない
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.identifier.contains("eloquence") && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            v.quality.rawValue * 10 + (v.name == "Daniel" ? 1 : 0)
        }
        for language in ["en-GB", "en-US", "en-AU", "en-IE"] {
            if let best = voices.filter({ $0.language == language }).max(by: { rank($0) < rank($1) }) {
                return best
            }
        }
        return AVSpeechSynthesisVoice(language: "en-GB")
    }
}
