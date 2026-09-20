import SwiftUI

/// Stage 5: close the loop by sending the current manipulation state (from
/// the same gesture pipeline as Stages 2/3) to the mask's OLED as a small
/// monochrome HUD. See MaskFrameRenderer.swift for why this sends a status
/// HUD rather than a mirrored 3D render — the panel is simply too small
/// and low-res for the latter to be worth the bandwidth/battery.
struct Stage5DisplayFeedbackView: View {
    @EnvironmentObject var connection: MaskConnectionManager
    @EnvironmentObject var settings: AppSettings
    @StateObject private var manipulation = ManipulationController()
    @StateObject private var handTracker = HandPoseTracker()

    @State private var isSending = false
    @State private var previewImage: UIImage?
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 256, height: 128)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray))
                    .accessibilityLabel("Preview of what's being sent to the mask display")
            } else {
                Text("Not sending yet").foregroundStyle(.secondary)
            }

            Text("This is exactly what's being sent to the OLED, scaled up 2x for visibility on the phone screen (the real panel is 128×64, viewed through a small loupe lens close to the eye).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Toggle("Send to Mask Display", isOn: $isSending)
                .padding(.horizontal)
                .onChange(of: isSending) { _, newValue in
                    if newValue {
                        connection.connectDisplay(settings: settings)
                        startTimer()
                    } else {
                        stopTimer()
                        connection.displayLink.disconnect()
                    }
                }
        }
        .padding(.vertical)
        .navigationTitle("Stage 5: Display Feedback")
        .onAppear {
            manipulation.attach(to: handTracker.registry)
            handTracker.start(consuming: connection.cameraStream.framePublisher)
        }
        .onDisappear {
            handTracker.stop()
            stopTimer()
            connection.displayLink.disconnect()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / max(1, settings.displayFeedbackFPS), repeats: true) { _ in
            Task { @MainActor in
                let image = MaskFrameRenderer.renderHUDImage(
                    isArmed: manipulation.isArmed,
                    scale: manipulation.effectiveScale,
                    yawRadians: manipulation.rotation.dx
                )
                previewImage = image
                let bitmap = MaskFrameRenderer.pack1bpp(image)
                connection.displayLink.sendBitmap(bitmap, width: MaskFrameRenderer.width, height: MaskFrameRenderer.height)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
