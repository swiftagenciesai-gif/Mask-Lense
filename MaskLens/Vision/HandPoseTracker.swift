import Vision
import CoreVideo
import Combine
import Foundation

/// Runs `VNDetectHumanHandPoseRequest` on each frame from the mask's camera
/// stream and feeds the results into a `GestureRegistry`.
///
/// Honest limitation: this is hand tracking on a *re-streamed, JPEG
/// compressed, WiFi-delivered* video feed, not on frames captured locally
/// by AVFoundation the instant they leave the sensor. Compared to running
/// Vision directly against a live local capture session (the normal iOS
/// use case it's tuned for), expect:
///   - Lower effective frame rate (ESP32-CAM + WiFi realistically gets you
///     ~10-15fps at VGA/SVGA before quality degrades further; see
///     Firmware/README.md), which makes fast hand motion track less
///     smoothly and makes the rotate-by-hand-position gesture feel less
///     responsive than pinch/palm/fist.
///   - Extra motion blur and JPEG block artifacts around fingertips,
///     which is exactly where Vision's confidence scores are most
///     sensitive — expect more frames with a hand present but confidence
///     too low to use, especially in dim light (the ESP32-CAM's small
///     sensor is mediocre in low light to begin with).
///   - Network jitter meaning frames don't arrive at an even cadence, so
///     "per-frame" state machines (like the pinch recognizer) are really
///     "per received frame," which can occasionally skip a fast pinch
///     entirely if two frames arrive close together and Vision processing
///     falls behind.
/// None of this makes hand tracking unusable, but don't expect Apple's own
/// demo-video smoothness — tune the thresholds in BuiltInGestures.swift
/// against your actual mask hardware and lighting, not just the simulator.
@MainActor
final class HandPoseTracker: ObservableObject {
    @Published private(set) var lastSnapshot: HandSnapshot?
    @Published private(set) var isHandVisible = false

    let registry = GestureRegistry()

    private var cancellable: AnyCancellable?
    private let visionQueue = DispatchQueue(label: "com.masklens.vision", qos: .userInitiated)
    private var isProcessing = false

    // `nonisolated`: read by the `nonisolated` `snapshot(from:timestamp:)`
    // below, which runs off the main actor on `visionQueue`. It's a fixed
    // lookup table with no mutable state, so isolation buys nothing here.
    private nonisolated static let jointMap: [(VNHumanHandPoseObservation.JointName, HandJoint)] = [
        (.wrist, .wrist),
        (.thumbTip, .thumbTip), (.thumbIP, .thumbIP),
        (.indexTip, .indexTip), (.indexPIP, .indexPIP), (.indexMCP, .indexMCP),
        (.middleTip, .middleTip), (.middlePIP, .middlePIP), (.middleMCP, .middleMCP),
        (.ringTip, .ringTip), (.ringMCP, .ringMCP),
        (.littleTip, .littleTip), (.littleMCP, .littleMCP),
    ]

    init() {
        registerDefaultGestures()
    }

    func registerDefaultGestures() {
        registry.register(BuiltInGestures.PinchRecognizer())
        registry.register(BuiltInGestures.ArmDisarmRecognizer())
        registry.register(BuiltInGestures.HandPositionRotateRecognizer())
    }

    func start(consuming publisher: PassthroughSubject<CVPixelBuffer, Never>) {
        cancellable = publisher.sink { [weak self] pixelBuffer in
            self?.process(pixelBuffer)
        }
    }

    func stop() {
        cancellable = nil
    }

    /// Drops frames instead of queueing them: if Vision is still busy with
    /// frame N when frame N+1 arrives, processing N+1 late is worse than
    /// just processing N+2 on time. Queueing would make the gesture
    /// pipeline's latency grow unboundedly under load instead of just
    /// losing temporal resolution, which is the better failure mode for an
    /// interactive control scheme.
    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard !isProcessing else { return }
        isProcessing = true

        let timestamp = Date().timeIntervalSince1970

        // CVPixelBuffer predates Swift concurrency and isn't marked
        // Sendable, but Core Video buffers are safe to hand off to another
        // thread as long as nothing mutates them concurrently — which
        // nothing here does, this closure only reads it. `nonisolated(unsafe)`
        // documents that we've verified that rather than silencing a
        // warning blindly.
        nonisolated(unsafe) let pixelBuffer = pixelBuffer

        visionQueue.async { [weak self] in
            guard let self else { return }
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 1

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            var snapshot: HandSnapshot?
            do {
                try handler.perform([request])
                if let observation = request.results?.first {
                    snapshot = Self.snapshot(from: observation, timestamp: timestamp)
                }
            } catch {
                // Vision throws on malformed pixel buffers or unsupported
                // formats; treat it the same as "no hand this frame" rather
                // than crashing the gesture pipeline over one bad frame.
                snapshot = nil
            }

            Task { @MainActor in
                self.isProcessing = false
                if let snapshot {
                    self.lastSnapshot = snapshot
                    self.isHandVisible = true
                    self.registry.process(snapshot)
                } else {
                    self.isHandVisible = false
                    self.registry.processNoHand(timestamp: timestamp)
                }
            }
        }
    }

    // `nonisolated`: this is pure computation over its arguments (no actor
    // state touched) and is called from `visionQueue`'s background closure
    // — without this, it inherits `@MainActor` isolation from the
    // enclosing class and calling it from that background queue without a
    // hop becomes a compile error.
    private nonisolated static func snapshot(from observation: VNHumanHandPoseObservation, timestamp: TimeInterval) -> HandSnapshot? {
        var points: [HandJoint: CGPoint] = [:]
        var confidences: [HandJoint: Float] = [:]

        guard let allPoints = try? observation.recognizedPoints(.all) else { return nil }

        for (visionJoint, ourJoint) in jointMap {
            guard let recognized = allPoints[visionJoint] else { continue }
            points[ourJoint] = CGPoint(x: recognized.location.x, y: recognized.location.y)
            confidences[ourJoint] = recognized.confidence
        }

        guard !points.isEmpty else { return nil }
        return HandSnapshot(timestamp: timestamp, points: points, confidences: confidences)
    }
}
