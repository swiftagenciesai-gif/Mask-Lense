import SwiftUI

/// Home screen, deliberately structured around the five build stages from
/// the README rather than around "features." Each stage is independently
/// testable against the real hardware in the order it's meant to be
/// brought up: get video working before you trust hand tracking on top of
/// it, get hand tracking working before you build Object Capture on top of
/// that, and so on. Trying to bring up all five at once against real
/// hardware for the first time is exactly the debugging nightmare the
/// README warns against.
struct StagesHomeView: View {
    @EnvironmentObject var connection: MaskConnectionManager
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        List {
            Section {
                ConnectionStatusRow(
                    label: "Camera (mask)",
                    state: cameraStateDescription
                )
                ConnectionStatusRow(
                    label: "Display (mask)",
                    state: displayStateDescription
                )
            } header: {
                Text("Mask Connection")
            }

            Section {
                NavigationLink {
                    Stage1VideoView()
                } label: {
                    StageRow(number: 1, title: "Video Streaming", subtitle: "Receive live video from the mask's ESP32-CAM")
                }
                NavigationLink {
                    Stage2HandTrackingView()
                } label: {
                    StageRow(number: 2, title: "Hand Tracking", subtitle: "Vision framework gestures on the live stream")
                }
                NavigationLink {
                    Stage3ObjectCaptureView()
                } label: {
                    StageRow(number: 3, title: "Object Capture", subtitle: "Turntable capture → RealityKit 3D model")
                }
                NavigationLink {
                    Stage4AIView()
                } label: {
                    StageRow(number: 4, title: "Claude AI Features", subtitle: "Vision ID + voice Q&A")
                }
                NavigationLink {
                    Stage5DisplayFeedbackView()
                } label: {
                    StageRow(number: 5, title: "Mask Display Feedback", subtitle: "Send model state back to the OLED")
                }
            } header: {
                Text("Build & Test in Order")
            } footer: {
                Text("Each stage only depends on the ones before it. Don't skip ahead against real hardware — Stage 2 hand tracking is much easier to debug once you already trust Stage 1's video feed is solid.")
            }
        }
        .navigationTitle("MaskLens")
        .onAppear { connection.startDiscovery() }
        .onDisappear { connection.stopDiscovery() }
    }

    private var cameraStateDescription: String {
        switch connection.cameraStream.state {
        case .idle: "Not connected"
        case .connecting: "Connecting…"
        case .streaming(let fps): String(format: "Streaming (%.0f fps)", fps)
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var displayStateDescription: String {
        connection.discovery.displayHosts.first?.host ?? (settings.useManualHosts ? settings.manualDisplayHost : "Not discovered")
    }
}

private struct StageRow: View {
    let number: Int
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.tint.opacity(0.15)))
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConnectionStatusRow: View {
    let label: String
    let state: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(state).foregroundStyle(.secondary)
        }
    }
}
