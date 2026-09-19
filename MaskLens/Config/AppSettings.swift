import Foundation
import Combine

/// Central, observable settings object. Everything here is either
/// user-editable in SettingsView or a documented default — nothing is
/// hardcoded elsewhere in the app.
@MainActor
final class AppSettings: ObservableObject {
    // MARK: Claude API

    @Published var claudeAPIKey: String {
        didSet { APIKeyStore.save(claudeAPIKey) }
    }

    /// Update if Anthropic ships a newer model id. Sonnet is the pick here:
    /// vision-capable, cheaper than Opus, faster than either for the
    /// "point mask, get an answer back in under a couple seconds" UX this
    /// app wants. Swap to claude-opus-5 if you want higher-effort answers
    /// and don't mind paying more / waiting longer per request.
    @Published var claudeModel: String = "claude-sonnet-5"

    @Published var claudeMaxOutputTokens: Int = 1024

    // MARK: Mask network config

    /// Bonjour service types the two boards advertise. See
    /// Firmware/README.md — the sketches there advertise exactly these.
    static let cameraServiceType = "_masklens-cam._tcp"
    static let displayServiceType = "_masklens-disp._tcp"

    /// Manual IP fallback, for the (common) case where mDNS discovery is
    /// flaky on a given router. Persisted in UserDefaults since it's not
    /// secret.
    @Published var manualCameraHost: String {
        didSet { UserDefaults.standard.set(manualCameraHost, forKey: Keys.cameraHost) }
    }
    @Published var manualDisplayHost: String {
        didSet { UserDefaults.standard.set(manualDisplayHost, forKey: Keys.displayHost) }
    }
    @Published var useManualHosts: Bool {
        didSet { UserDefaults.standard.set(useManualHosts, forKey: Keys.useManual) }
    }

    /// How often we push a display frame to the OLED mask, in frames per
    /// second. Kept low deliberately — see MaskFrameRenderer.swift for why
    /// pushing every RealityKit frame would be both wasteful and pointless
    /// given the panel's size.
    @Published var displayFeedbackFPS: Double = 8

    private enum Keys {
        static let cameraHost = "manualCameraHost"
        static let displayHost = "manualDisplayHost"
        static let useManual = "useManualHosts"
    }

    init() {
        self.claudeAPIKey = APIKeyStore.load() ?? ""
        self.manualCameraHost = UserDefaults.standard.string(forKey: Keys.cameraHost) ?? "192.168.4.1"
        self.manualDisplayHost = UserDefaults.standard.string(forKey: Keys.displayHost) ?? "192.168.4.2"
        self.useManualHosts = UserDefaults.standard.bool(forKey: Keys.useManual)
    }

    var hasAPIKey: Bool { !claudeAPIKey.trimmingCharacters(in: .whitespaces).isEmpty }
}
