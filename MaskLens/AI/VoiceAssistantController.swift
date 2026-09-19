import Foundation
import Speech
import AVFoundation

/// Hands-free voice Q&A: on-device speech-to-text (Speech framework) →
/// Claude API (text) → spoken answer (AVSpeechSynthesizer).
///
/// **This is push-to-talk, not always-listening.** A real wake-word /
/// trigger-phrase mode would mean running `SFSpeechRecognizer` continuously
/// in the background, which is a meaningful, continuous battery and
/// privacy cost (the mic stays hot and audio keeps getting transcribed
/// whether or not anyone is actually talking to the assistant) on top of
/// everything else already draining the phone (video receipt, Vision hand
/// tracking, WiFi). Wiring a UI button (or a hardware gesture — e.g. a
/// dedicated "fist held for 1s" action registered through the same
/// GestureRegistry used for the 3D model) to `startListening()` /
/// `stopListeningAndSubmit()` gets the same "hands-free once you've
/// started talking" feel without paying that always-on cost. If you do
/// want a real wake word later, look at Apple's `SFSpeechRecognizer`
/// continuous mode or a dedicated small on-device wake-word model — don't
/// just leave this class's recognizer running permanently, it will not
/// treat your battery kindly.
@MainActor
final class VoiceAssistantController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var lastAnswer: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func requestAuthorization() async -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
        guard speechStatus == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startListening() throws {
        guard state != .listening else { return }
        guard let recognizer, recognizer.isAvailable else {
            state = .error("Speech recognizer unavailable (no network for server-side fallback, or an unsupported locale).")
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.teardownAudio()
                    self.state = .idle
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening
    }

    /// Stop capturing, finalize the transcript, and immediately send it to
    /// Claude. Speaks the reply when it comes back.
    func stopListeningAndSubmit(client: ClaudeAPIClient) {
        guard state == .listening else { return }
        recognitionRequest?.endAudio()
        teardownAudio()

        let question = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            state = .idle
            return
        }

        state = .thinking
        Task {
            do {
                let answer = try await client.ask(
                    question,
                    systemPrompt: "You are a concise voice assistant speaking through a wearable device's speaker. Answer in 2-3 short spoken sentences unless the user clearly asked for more detail."
                )
                self.lastAnswer = answer
                self.speak(answer)
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func cancelListening() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        teardownAudio()
        state = .idle
    }

    private func teardownAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func speak(_ text: String) {
        state = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
    }
}

extension VoiceAssistantController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.state = .idle }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.state = .idle }
    }
}
