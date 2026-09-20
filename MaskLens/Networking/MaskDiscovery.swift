import Foundation
import Network

/// Finds the mask's two ESP32 boards on the local network via Bonjour/mDNS.
///
/// Reality check: mDNS on consumer WiFi routers is hit-or-miss. Guest
/// networks and a lot of mesh routers (many eero/Orbi/Google Wifi setups)
/// block multicast between "bands" or isolate clients from each other
/// entirely, which breaks Bonjour outright even though both devices are on
/// the same SSID. That's why `AppSettings.useManualHosts` exists — typing
/// in the IP the ESP32 prints over serial on first boot is the reliable
/// fallback, not an afterthought. Don't assume discovery will "just work"
/// on every network the builder tries.
final class MaskDiscovery: ObservableObject {
    struct DiscoveredHost: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String
        let port: UInt16
    }

    @Published private(set) var cameraHosts: [DiscoveredHost] = []
    @Published private(set) var displayHosts: [DiscoveredHost] = []

    private var cameraBrowser: NWBrowser?
    private var displayBrowser: NWBrowser?

    func start() {
        cameraBrowser = makeBrowser(for: AppSettings.cameraServiceType) { [weak self] hosts in
            self?.cameraHosts = hosts
        }
        displayBrowser = makeBrowser(for: AppSettings.displayServiceType) { [weak self] hosts in
            self?.displayHosts = hosts
        }
    }

    func stop() {
        cameraBrowser?.cancel()
        displayBrowser?.cancel()
        cameraBrowser = nil
        displayBrowser = nil
    }

    private func makeBrowser(
        for serviceType: String,
        onUpdate: @escaping ([DiscoveredHost]) -> Void
    ) -> NWBrowser {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

        browser.browseResultsChangedHandler = { results, _ in
            var hosts: [DiscoveredHost] = []
            let group = DispatchGroup()

            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                group.enter()
                let connection = NWConnection(to: result.endpoint, using: .tcp)
                connection.stateUpdateHandler = { state in
                    if case .ready = state {
                        if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint {
                            hosts.append(DiscoveredHost(name: name, host: "\(host)", port: port.rawValue))
                        }
                        connection.cancel()
                        group.leave()
                    } else if case .failed = state {
                        connection.cancel()
                        group.leave()
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }

            group.notify(queue: .main) {
                onUpdate(hosts)
            }
        }

        browser.start(queue: .main)
        return browser
    }
}
