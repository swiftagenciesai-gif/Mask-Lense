import SwiftUI

/// The turntable capture screen: live preview from the mask's camera, a
/// shutter button, and a thumbnail strip of what's captured so far.
struct TurntableCaptureView: View {
    @ObservedObject var cameraStream: CameraStreamReceiver
    @ObservedObject var viewModel: TurntableCaptureViewModel
    var onReconstruct: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if let image = cameraStream.latestImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.8))
                        .overlay(Text("No camera feed").foregroundStyle(.white))
                        .aspectRatio(4.0/3.0, contentMode: .fit)
                }
            }
            .padding(.horizontal)

            Text(viewModel.guidanceText)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                if let image = cameraStream.latestImage {
                    viewModel.captureCurrentFrame(from: image)
                }
            } label: {
                Label("Capture Shot", systemImage: "camera.aperture")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(cameraStream.latestImage == nil)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.shots) { shot in
                        Image(uiImage: shot.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    viewModel.removeShot(shot)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 4, y: -4)
                            }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 72)

            HStack {
                Button("Reset", role: .destructive) { viewModel.reset() }
                Spacer()
                Button {
                    onReconstruct()
                } label: {
                    Text("Build 3D Model (\(viewModel.shots.count) shots)")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isReadyToReconstruct)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Turntable Capture")
    }
}
