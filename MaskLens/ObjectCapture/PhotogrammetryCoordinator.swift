import RealityKit
import Foundation

/// Wraps RealityKit's `PhotogrammetrySession` — the low-level "give me a
/// folder of images, get back a model" API — rather than the higher-level
/// `ObjectCaptureSession`/`ObjectCaptureView` Apple showcases in its own
/// demos.
///
/// This is a deliberate, load-bearing choice, not an oversight:
/// `ObjectCaptureSession` owns its own `AVCaptureSession` against the
/// phone's *local* camera and Apple does not expose a way to feed it
/// externally-sourced frames. Since this app's whole premise is that the
/// camera lives in the mask, not the phone, `ObjectCaptureSession` is not
/// usable here at all. `PhotogrammetrySession` is the one part of the
/// Object Capture stack that's decoupled from camera hardware — it just
/// wants a directory of JPEGs (optionally with per-image depth/gravity/pose
/// hints, none of which we have) — so that's what this app is built on.
///
/// The real cost of that choice: `ObjectCaptureSession` also gives you,
/// for free, live coverage tracking, blur/lighting feedback per shot, and
/// automatic object segmentation (especially valuable on LiDAR devices,
/// where it uses depth to mask the object from the background). None of
/// that exists here. `TurntableCaptureViewModel` reimplements a much
/// cruder version (shot count target + manual review of thumbnails) and
/// `PhotogrammetrySession` gets plain, unmasked, unposed JPEGs and has to
/// figure out geometry from feature matching alone. On a device with no
/// LiDAR to begin with, that's already the harder path; combined with no
/// masking, expect noticeably worse results than Apple's own marketing
/// demos on featureless, reflective, transparent, or very thin objects —
/// matte objects with visible texture/pattern all over their surface do
/// best.
actor PhotogrammetryCoordinator {
    enum Stage: Equatable {
        case idle
        case processing(fraction: Double)
        case complete(modelURL: URL)
        case failed(String)
    }

    private(set) var stage: Stage = .idle
    private var stageContinuation: AsyncStream<Stage>.Continuation?

    /// Observe this to drive UI; a plain `AsyncStream` keeps this actor
    /// from needing `@MainActor` while still giving SwiftUI something to
    /// await/iterate over.
    func stageUpdates() -> AsyncStream<Stage> {
        AsyncStream { continuation in
            self.stageContinuation = continuation
            continuation.yield(stage)
        }
    }

    /// `imagesFolder` should contain nothing but the captured JPEGs (no
    /// subfolders, no other file types) — PhotogrammetrySession is picky
    /// about that. `detail` defaults to `.reduced`: on iOS (as opposed to
    /// macOS), Apple's documented guidance is that only the lighter detail
    /// levels are practical given on-device memory limits, and `.reduced`
    /// is what most iPhone Object Capture sample code actually ships with.
    /// Processing time is genuinely long — expect low-to-mid single-digit
    /// minutes for ~30-40 images even at `.reduced` on an iPhone 17-class
    /// chip, and it will use a meaningful chunk of the battery you already
    /// spent capturing the photos. There's no way to make this fast; the
    /// honest move is to make the UI clearly show progress and let the
    /// phone sit still and plugged in while it works, not to promise speed
    /// it can't deliver.
    func reconstruct(imagesFolder: URL, outputURL: URL, detail: PhotogrammetrySession.Request.Detail = .reduced) async {
        guard PhotogrammetrySession.isSupported else {
            update(.failed("Object Capture is not supported on this device (needs an A12 Bionic chip or newer, which every iPhone since the XS qualifies for)."))
            return
        }

        var configuration = PhotogrammetrySession.Configuration()
        // We have no ARKit pose/gravity metadata for these frames (they
        // came from the mask's camera, not ARKit), so we can't claim any
        // particular capture ordering was followed.
        configuration.sampleOrdering = .unordered
        configuration.featureSensitivity = .normal
        configuration.isObjectMaskingEnabled = false

        do {
            let session = try PhotogrammetrySession(input: imagesFolder, configuration: configuration)
            let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: detail)

            update(.processing(fraction: 0))

            try session.process(requests: [request])

            for try await output in session.outputs {
                switch output {
                case .requestProgress(_, let fraction):
                    update(.processing(fraction: fraction))
                case .requestComplete(_, let result):
                    if case let .modelFile(url) = result {
                        update(.complete(modelURL: url))
                    }
                case .requestError(_, let error):
                    update(.failed(error.localizedDescription))
                case .processingCancelled:
                    update(.failed("Reconstruction cancelled."))
                case .invalidSample(let id, let reason):
                    // Non-fatal — log and keep going; PhotogrammetrySession
                    // drops individual bad frames on its own.
                    print("PhotogrammetryCoordinator: dropped sample \(id): \(reason)")
                default:
                    break
                }
            }
        } catch {
            update(.failed(error.localizedDescription))
        }
    }

    private func update(_ newStage: Stage) {
        stage = newStage
        stageContinuation?.yield(newStage)
    }
}
