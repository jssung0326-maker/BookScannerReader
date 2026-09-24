import Foundation
import Combine
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "ko-KR", rate: Float = 0.48) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func pause() {
        if synthesizer.pauseSpeaking(at: .word) {
            isSpeaking = false
        }
    }

    func resume() {
        if synthesizer.continueSpeaking() {
            isSpeaking = true
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}
