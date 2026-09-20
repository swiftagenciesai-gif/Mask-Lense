import Foundation
import UIKit
import AVFoundation

/// "What am I looking at?" — grabs the current frame from the mask's
/// camera, sends it to Claude's vision endpoint, and speaks the answer.
/// Triggered explicitly (a button, or a recognized trigger phrase from
/// VoiceAssistantController) — never on a timer or continuously, both
/// because Vision framework + Claude cost + battery all argue against
/// polling, and because a running commentary on everything the wearer
/// looks at is not what most people want from this.
@MainActor
final class VisionIdentificationService: ObservableObject {
    enum State: Equatable {
        case idle
        case requesting
        case result(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let speechSynthesizer = AVSpeechSynthesizer()

    func identify(image: UIImage, client: ClaudeAPIClient, speak: Bool = true) async {
        state = .requesting
        do {
            let description = try await client.describeImage(
                image,
                prompt: "Describe what's in this image in one or two concise sentences, as if answering someone wearing a camera who just asked \"what am I looking at?\". Mention the most important/salient object or scene first."
            )
            state = .result(description)
            if speak {
                self.speak(description)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        speechSynthesizer.speak(utterance)
    }
}
