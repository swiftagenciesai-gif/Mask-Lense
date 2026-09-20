import CoreGraphics
import Foundation

/// A hand-relevant subset of a single `VNHumanHandPoseObservation`, already
/// converted to plain values so the rest of the gesture pipeline doesn't
/// need to import Vision or think about `VNRecognizedPoint` confidence at
/// every call site — that's handled once, here, in HandPoseTracker.
struct HandSnapshot {
    let timestamp: TimeInterval
    /// Vision image coordinates: (0,0) bottom-left, (1,1) top-right.
    let points: [HandJoint: CGPoint]
    let confidences: [HandJoint: Float]

    func point(_ joint: HandJoint, minConfidence: Float = 0.3) -> CGPoint? {
        guard let confidence = confidences[joint], confidence >= minConfidence else { return nil }
        return points[joint]
    }
}

enum HandJoint: Hashable, CaseIterable {
    case wrist
    case thumbTip, thumbIP
    case indexTip, indexPIP, indexMCP
    case middleTip, middlePIP, middleMCP
    case ringTip, ringMCP
    case littleTip, littleMCP
}

/// A recognized gesture moment, published by name so new recognizers and
/// new action bindings can both be added without touching a shared enum.
/// `GestureRegistry.wellKnown` documents the names the built-in recognizers
/// emit, but nothing enforces using only those — that's the point.
struct GestureEvent {
    let name: String
    let value: GestureValue
    let timestamp: TimeInterval
}

enum GestureValue {
    case none
    case scalar(Double)
    case point(CGPoint)
    case delta(dx: Double, dy: Double)
}

/// Per-recognizer scratch space, kept by the registry and handed back on
/// every call so recognizers can be simple value-ish types instead of each
/// managing their own mutable singleton state.
struct GestureRecognitionContext {
    var previousSnapshot: HandSnapshot?
    var storage: [String: Any] = [:]
}
