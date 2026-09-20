import SwiftUI

/// Stage 4: the Claude-backed features, built against whatever the camera
/// stream (Stage 1) is currently showing. Deliberately independent of
/// Stages 2/3 — you can test vision ID and voice Q&A against a live mask
/// feed without hand tracking or Object Capture working at all.
struct Stage4AIView: View {
    @EnvironmentObject var connection: MaskConnectionManager
    @EnvironmentObject var settings: AppSettings
    @StateObject private var visionService = VisionIdentificationService()
    @StateObject private var voiceAssistant = VoiceAssistantController()

    var body: some View {
        Form {
            if !settings.hasAPIKey {
                Section {
                    Label("No Claude API key set — add one in Settings before using this stage.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Vision Identification") {
                if let image = connection.cameraStream.latestImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Button {
                    identifyCurrentFrame()
                } label: {
                    Label("What am I looking at?", systemImage: "eye")
                }
                .disabled(!settings.hasAPIKey || connection.cameraStream.latestImage == nil || visionService.state == .requesting)

                switch visionService.state {
                case .idle: EmptyView()
                case .requesting: ProgressView("Asking Claude…")
                case .result(let text): Text(text)
                case .failed(let message): Text(message).foregroundStyle(.red)
                }
            }

            Section {
                Text(voiceStateText).foregroundStyle(.secondary)
                if !voiceAssistant.transcript.isEmpty {
                    Text("\"\(voiceAssistant.transcript)\"").italic()
                }
                if !voiceAssistant.lastAnswer.isEmpty {
                    Text(voiceAssistant.lastAnswer)
                }

                Button {
                    Task { await toggleListening() }
                } label: {
                    Label(voiceAssistant.state == .listening ? "Stop & Ask" : "Hold to Ask (tap to start/stop)", systemImage: voiceAssistant.state == .listening ? "stop.circle.fill" : "mic.circle")
                }
                .disabled(!settings.hasAPIKey)
            } header: {
                Text("Voice Assistant")
            } footer: {
                Text("Push-to-talk by design — see VoiceAssistantController.swift for why an always-listening wake word is a much bigger battery/privacy cost than it looks like at first.")
            }
        }
        .navigationTitle("Stage 4: Claude AI")
    }

    private var voiceStateText: String {
        switch voiceAssistant.state {
        case .idle: "Tap to start listening"
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking…"
        case .error(let message): "Error: \(message)"
        }
    }

    private func identifyCurrentFrame() {
        guard let image = connection.cameraStream.latestImage else { return }
        let client = ClaudeAPIClient(apiKey: settings.claudeAPIKey, model: settings.claudeModel, maxTokens: settings.claudeMaxOutputTokens)
        Task { await visionService.identify(image: image, client: client) }
    }

    private func toggleListening() async {
        let client = ClaudeAPIClient(apiKey: settings.claudeAPIKey, model: settings.claudeModel, maxTokens: settings.claudeMaxOutputTokens)
        if voiceAssistant.state == .listening {
            voiceAssistant.stopListeningAndSubmit(client: client)
        } else {
            guard await voiceAssistant.requestAuthorization() else { return }
            try? voiceAssistant.startListening()
        }
    }
}
