import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connection: MaskConnectionManager
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false

    var body: some View {
        Form {
            Section {
                if showAPIKey {
                    TextField("sk-ant-...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("sk-ant-...", text: $apiKeyInput)
                }
                Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                Button("Save Key") {
                    settings.claudeAPIKey = apiKeyInput
                }
                .disabled(apiKeyInput.isEmpty)
                if settings.hasAPIKey {
                    Button("Clear Saved Key", role: .destructive) {
                        settings.claudeAPIKey = ""
                        apiKeyInput = ""
                    }
                }
            } header: {
                Text("Claude API Key")
            } footer: {
                Text("Stored in the iOS Keychain, never in source or UserDefaults. Every vision identification and voice question sends a request to the Claude API — this is a paid API, so usage adds up. See the README for typical per-request costs.")
            }

            Section {
                Picker("Model", selection: $settings.claudeModel) {
                    Text("claude-sonnet-5 (recommended)").tag("claude-sonnet-5")
                    Text("claude-opus-5 (higher quality, slower, pricier)").tag("claude-opus-5")
                    Text("claude-haiku-4-5-20251001 (fastest, cheapest)").tag("claude-haiku-4-5-20251001")
                }
                Stepper("Max output tokens: \(settings.claudeMaxOutputTokens)", value: $settings.claudeMaxOutputTokens, in: 128...4096, step: 128)
            } header: {
                Text("Claude Model")
            }

            Section {
                Toggle("Use manual IP addresses", isOn: $settings.useManualHosts)
                TextField("Camera ESP32 IP", text: $settings.manualCameraHost)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Display ESP32 IP", text: $settings.manualDisplayHost)
                    .keyboardType(.numbersAndPunctuation)
            } header: {
                Text("Mask Network")
            } footer: {
                Text("Bonjour/mDNS discovery is tried automatically, but plenty of routers (guest networks, mesh systems with client isolation) block it silently. If Stage 1 can't find your camera board, flip this on and type the IP shown on the ESP32's serial monitor at boot.")
            }

            Section {
                HStack {
                    Text("Display feedback rate")
                    Spacer()
                    Text("\(Int(settings.displayFeedbackFPS)) fps")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.displayFeedbackFPS, in: 1...15, step: 1)
            } header: {
                Text("Mask Display")
            } footer: {
                Text("This is a status HUD sent to a 128x64 monochrome panel, not a video stream — higher rates mostly just cost battery and WiFi traffic without a visible benefit. 5-8fps is plenty for a rotation/scale indicator to feel responsive.")
            }
        }
        .navigationTitle("Settings")
        .onAppear { apiKeyInput = settings.claudeAPIKey }
    }
}
