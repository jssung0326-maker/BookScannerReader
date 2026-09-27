import Foundation
import Combine
import AVFoundation

final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private struct Segment {
        let pageIndex: Int
        let text: String
    }

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentSentence = ""
    @Published private(set) var currentPageIndex: Int?
    @Published private(set) var currentSentenceNumber = 0
    @Published private(set) var totalSentences = 0
    @Published var rate: Float = 0.48

    private let synthesizer = AVSpeechSynthesizer()
    private var segments: [Segment] = []
    private var segmentIndex = 0
    private var manualStop = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isActive: Bool {
        isSpeaking || isPaused || !currentSentence.isEmpty
    }

    var progress: Double {
        guard totalSentences > 0 else { return 0 }
        return Double(min(max(currentSentenceNumber, 0), totalSentences)) / Double(totalSentences)
    }

    func speakPage(_ text: String, pageIndex: Int, language: String? = nil) {
        let built = sentenceSegments(text: text, pageIndex: pageIndex)
        start(built, forcedLanguage: language)
    }

    /// 현재 페이지부터 마지막 페이지까지 문장 단위로 이어 읽습니다.
    func speakPages(_ pageTexts: [String], from startPage: Int) {
        guard !pageTexts.isEmpty else { return }
        let safeStart = min(max(startPage, 0), pageTexts.count - 1)
        var built: [Segment] = []
        for index in safeStart..<pageTexts.count {
            built.append(contentsOf: sentenceSegments(text: pageTexts[index], pageIndex: index))
        }
        start(built, forcedLanguage: nil)
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        if synthesizer.pauseSpeaking(at: .word) {
            DispatchQueue.main.async {
                self.isPaused = true
                self.isSpeaking = false
            }
        }
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        if synthesizer.continueSpeaking() {
            DispatchQueue.main.async {
                self.isPaused = false
                self.isSpeaking = true
            }
        }
    }

    func stop() {
        manualStop = true
        synthesizer.stopSpeaking(at: .immediate)
        resetState()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !manualStop else {
            manualStop = false
            return
        }
        segmentIndex += 1
        if segmentIndex < segments.count {
            speakCurrentSegment()
        } else {
            resetState()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // stop()/새 읽기 시작 시 상태는 호출 측에서 정리합니다.
        // 이전 utterance의 비동기 cancel 콜백이 새 큐를 지우지 않도록 여기서는 별도 초기화하지 않습니다.
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = true
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = false
            self.isSpeaking = true
        }
    }

    private func start(_ newSegments: [Segment], forcedLanguage: String?) {
        let usable = newSegments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return }

        manualStop = true
        synthesizer.stopSpeaking(at: .immediate)
        manualStop = false

        segments = usable
        segmentIndex = 0
        totalSentences = usable.count
        currentSentenceNumber = 0
        currentSentence = ""
        currentPageIndex = usable.first?.pageIndex
        speakCurrentSegment(forcedLanguage: forcedLanguage)
    }

    private func speakCurrentSegment(forcedLanguage: String? = nil) {
        guard segments.indices.contains(segmentIndex) else {
            resetState()
            return
        }

        let segment = segments[segmentIndex]
        let utterance = AVSpeechUtterance(string: segment.text)
        let language = forcedLanguage ?? preferredLanguage(for: segment.text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)

        DispatchQueue.main.async {
            self.currentSentence = segment.text
            self.currentPageIndex = segment.pageIndex
            self.currentSentenceNumber = self.segmentIndex + 1
            self.isPaused = false
            self.isSpeaking = true
        }
        synthesizer.speak(utterance)
    }

    private func resetState() {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.currentSentence = ""
            self.currentPageIndex = nil
            self.currentSentenceNumber = 0
            self.totalSentences = 0
            self.segments = []
            self.segmentIndex = 0
        }
    }

    private func sentenceSegments(text: String, pageIndex: Int) -> [Segment] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [Segment] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex..<trimmed.endIndex, options: .bySentences) { substring, _, _, _ in
            guard let substring else { return }
            let sentence = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                result.append(Segment(pageIndex: pageIndex, text: sentence))
            }
        }

        if result.isEmpty {
            result.append(Segment(pageIndex: pageIndex, text: trimmed))
        }
        return result
    }

    private func preferredLanguage(for text: String) -> String {
        if text.range(of: "[가-힣]", options: .regularExpression) != nil {
            return "ko-KR"
        }
        return "en-US"
    }
}
