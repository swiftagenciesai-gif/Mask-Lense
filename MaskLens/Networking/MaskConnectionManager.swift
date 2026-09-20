import Foundation
import Combine

/// Top-level connection state for the mask, shared across the whole app via
/// `.environmentObject`. Owns the discovery, camera stream, and display
/// link objects so screens don't each stand up their own.
@MainActor
final class MaskConnectionManager: ObservableObject {
    let discovery = MaskDiscovery()
    let cameraStream = CameraStreamReceiver()
    let displayLink = DisplayLinkSender()

    @Published var isDisplayFeedbackEnabled = false

    private var cancellables = Set<AnyCancellable>()

    func startDiscovery() {
        discovery.start()
    }

    func stopDiscovery() {
        discovery.stop()
    }

    func connectCamera(settings: AppSettings) {
        let host: String
        if settings.useManualHosts {
            host = settings.manualCameraHost
        } else if let discovered = discovery.cameraHosts.first {
            host = discovered.host
        } else {
            host = settings.manualCameraHost
        }
        cameraStream.connect(host: host)
    }

    func connectDisplay(settings: AppSettings) {
        let host: String
        if settings.useManualHosts {
            host = settings.manualDisplayHost
        } else if let discovered = discovery.displayHosts.first {
            host = discovered.host
        } else {
            host = settings.manualDisplayHost
        }
        displayLink.configure(fps: settings.displayFeedbackFPS)
        displayLink.connect(host: host)
    }

    func disconnectAll() {
        cameraStream.disconnect()
        displayLink.disconnect()
    }
}
