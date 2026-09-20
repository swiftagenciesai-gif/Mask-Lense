import SwiftUI

/// Stage 1: prove the mask's camera ESP32 can stream video to the phone
/// reliably before building anything on top of it. If this stage isn't
/// solid — steady FPS, no long stalls, reconnects cleanly after the ESP32
/// reboots or WiFi hiccups — every later stage will be harder to debug,
/// because you won't know if a problem is "my code" or "the video feed
/// dropped a frame."
struct Stage1VideoView: View {
    @EnvironmentObject var connection: MaskConnectionManager
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if let image = connection.cameraStream.latestImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .aspectRatio(4.0/3.0, contentMode: .fit)
                        .overlay(Text("No frames yet").foregroundStyle(.white))
                }
            }
            .padding(.horizontal)

            Text(stateText)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)

            if !connection.discovery.cameraHosts.isEmpty {
                List(connection.discovery.cameraHosts) { host in
                    Button {
                        connection.cameraStream.connect(host: host.host)
                    } label: {
                        HStack {
                            Text(host.name)
                            Spacer()
                            Text(host.host).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            HStack {
                Button("Connect") {
                    connection.connectCamera(settings: settings)
                }
                .buttonStyle(.borderedProminent)

                Button("Disconnect") {
                    connection.cameraStream.disconnect()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical)
        .navigationTitle("Stage 1: Video")
    }

    private var stateText: String {
        switch connection.cameraStream.state {
        case .idle: "Idle"
        case .connecting: "Connecting…"
        case .streaming(let fps): String(format: "Streaming — %.1f fps", fps)
        case .failed(let message): "Error: \(message)"
        }
    }
}
