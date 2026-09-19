import SwiftUI
import RealityKit

/// Stage 3: turntable capture from the mask's camera → PhotogrammetrySession
/// reconstruction → RealityKit viewer with the same gesture controls from
/// Stage 2 wired up for real. See PhotogrammetryCoordinator.swift and
/// TurntableCaptureViewModel.swift for the detailed explanation of why this
/// works differently (and less smoothly) than Apple's own ObjectCaptureView
/// demos: no LiDAR, and the camera isn't the phone's own, so the
/// higher-level guided capture API isn't usable at all here.
struct Stage3ObjectCaptureView: View {
    @EnvironmentObject var connection: MaskConnectionManager
    @EnvironmentObject var settings: AppSettings
    @StateObject private var captureViewModel = TurntableCaptureViewModel()
    @StateObject private var manipulation = ManipulationController()
    @StateObject private var handTracker = HandPoseTracker()

    // @State, not a plain `let`: SwiftUI recreates this View struct on
    // every re-render (which happens constantly here, since `progress`
    // updates drive one), and a plain stored property would silently
    // construct a fresh, unrelated actor each time. @State ties a single
    // instance to this view's identity instead. It doesn't matter for the
    // in-flight reconstruction Task itself (it captures the specific actor
    // reference at launch), but it avoids leaking a new orphaned actor
    // instance on every frame.
    @State private var coordinator = PhotogrammetryCoordinator()

    @State private var phase: Phase = .capturing
    @State private var progress: Double = 0
    @State private var modelURL: URL?
    @State private var errorMessage: String?
    @State private var cleanupNote: String?

    enum Phase {
        case capturing
        case reconstructing
        case viewing
    }

    var body: some View {
        Group {
            switch phase {
            case .capturing:
                TurntableCaptureView(cameraStream: connection.cameraStream, viewModel: captureViewModel) {
                    startReconstruction()
                }
            case .reconstructing:
                VStack(spacing: 16) {
                    ProgressView(value: progress)
                        .padding(.horizontal)
                    Text("Reconstructing… \(Int(progress * 100))%")
                    Text("This genuinely takes a while — expect low-to-mid single-digit minutes for a few dozen photos on-device, longer for more shots or a busier/reflective object. Keep the phone plugged in and awake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).padding()
                        Button("Back to Capture") { phase = .capturing }
                    }
                }
                .navigationTitle("Reconstructing")
            case .viewing:
                VStack(spacing: 12) {
                    if let modelURL {
                        ModelViewerView(modelURL: modelURL, manipulation: manipulation)
                            .frame(maxHeight: .infinity)
                    }
                    if let cleanupNote {
                        GroupBox("Capture Quality Notes (Claude)") {
                            Text(cleanupNote).font(.caption)
                        }
                        .padding(.horizontal)
                    }
                    Button("Capture a New Object") {
                        captureViewModel.reset()
                        modelURL = nil
                        cleanupNote = nil
                        phase = .capturing
                    }
                    .padding(.bottom)
                }
                .navigationTitle("Stage 3: Model")
                .onAppear {
                    manipulation.attach(to: handTracker.registry)
                    handTracker.start(consuming: connection.cameraStream.framePublisher)
                }
                .onDisappear { handTracker.stop() }
            }
        }
    }

    private func startReconstruction() {
        phase = .reconstructing
        errorMessage = nil
        let outputURL = captureViewModel.workingDirectory.appendingPathComponent("model.usdz")
        let imagesFolder = captureViewModel.workingDirectory

        Task {
            for await stage in await coordinator.stageUpdates() {
                switch stage {
                case .idle:
                    break
                case .processing(let fraction):
                    progress = fraction
                case .complete(let url):
                    modelURL = url
                    phase = .viewing
                    await runCleanupPassIfConfigured()
                    return
                case .failed(let message):
                    errorMessage = message
                    return
                }
            }
        }

        Task {
            await coordinator.reconstruct(imagesFolder: imagesFolder, outputURL: outputURL)
        }
    }

    private func runCleanupPassIfConfigured() async {
        guard settings.hasAPIKey else { return }
        let client = ClaudeAPIClient(apiKey: settings.claudeAPIKey, model: settings.claudeModel, maxTokens: settings.claudeMaxOutputTokens)
        let images = captureViewModel.shots.map(\.image)
        cleanupNote = await MeshCleanupService.reviewCapture(shots: images, renderedPreview: nil, client: client)
    }
}
