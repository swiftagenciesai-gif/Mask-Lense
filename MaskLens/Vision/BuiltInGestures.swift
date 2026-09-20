import CoreGraphics
import Foundation

/// The four default recognizers the app ships with. Each is a small, self
/// contained state machine — none of them know about RealityKit, scaling,
/// or rotation; they only emit named events. See ManipulationController
/// for what those events actually *do* to the model.
///
/// To add a new gesture later (e.g. a two-finger swipe to cycle models):
/// write a new `GestureRecognizer`, register it alongside these in
/// `HandPoseTracker.registerDefaultGestures()`, and bind a handler to its
/// event name wherever you want to react to it. Nothing here needs to
/// change.
enum BuiltInGestures {

    /// Detects the thumb tip / index tip pinch distance shrinking and
    /// growing, and turns it into a scale ratio.
    ///
    /// Ratio-based, not absolute distance: `pinchChanged` reports
    /// `currentDistance / distanceAtPinchStart`, so the consumer multiplies
    /// its *existing* scale by that ratio. Reporting a ratio (rather than,
    /// say, raw thumb-index distance) is what makes "locks in place when
    /// released, doesn't drift" possible downstream — see
    /// ManipulationController.committedScale, which is exactly this
    /// recognizer's `pinchCommitted` value baked into a running total and
    /// then never touched again until the next pinch starts.
    final class PinchRecognizer: GestureRecognizer {
        let id = "builtin.pinch"

        private let pinchEngageThreshold: CGFloat = 0.06   // normalized distance to start a pinch
        private let pinchDisengageThreshold: CGFloat = 0.09 // hysteresis so it doesn't chatter at the edge

        func process(_ snapshot: HandSnapshot, context: inout GestureRecognitionContext) -> [GestureEvent] {
            guard
                let thumb = snapshot.point(.thumbTip),
                let index = snapshot.point(.indexTip)
            else {
                if (context.storage["pinching"] as? Bool) == true {
                    context.storage["pinching"] = false
                    // Hand tracking dropped mid-pinch (common on a streamed,
                    // compressed feed — see HandPoseTracker's caveats).
                    // Commit whatever ratio we last measured rather than
                    // silently discarding the gesture the user was mid-way
                    // through; better than snapping back with no explanation.
                    let lastRatio = (context.storage["lastRatio"] as? Double) ?? 1.0
                    return [GestureEvent(name: GestureRegistry.WellKnown.pinchCommitted, value: .scalar(lastRatio), timestamp: snapshot.timestamp)]
                }
                return []
            }

            let distance = hypot(thumb.x - index.x, thumb.y - index.y)
            let isPinching = (context.storage["pinching"] as? Bool) ?? false

            if !isPinching, distance <= pinchEngageThreshold {
                context.storage["pinching"] = true
                context.storage["startDistance"] = distance
                return []
            }

            if isPinching {
                let startDistance = (context.storage["startDistance"] as? CGFloat) ?? distance
                if distance >= pinchDisengageThreshold {
                    context.storage["pinching"] = false
                    let ratio = Double(distance / max(startDistance, 0.001))
                    return [GestureEvent(name: GestureRegistry.WellKnown.pinchCommitted, value: .scalar(ratio), timestamp: snapshot.timestamp)]
                } else {
                    let ratio = Double(distance / max(startDistance, 0.001))
                    context.storage["lastRatio"] = ratio
                    return [GestureEvent(name: GestureRegistry.WellKnown.pinchChanged, value: .scalar(ratio), timestamp: snapshot.timestamp)]
                }
            }

            return []
        }
    }

    /// Open palm → armed, fist → disarmed. Uses average fingertip distance
    /// from the wrist, normalized by wrist-to-middle-MCP distance (a rough
    /// per-hand, per-distance-from-camera scale reference so the threshold
    /// doesn't depend on how close the hand is to the mask's camera).
    ///
    /// Edge-triggered with a short debounce (3 consecutive matching frames)
    /// so a single noisy frame from the streamed video doesn't cause a
    /// spurious arm/disarm — see the top-level README's hand-tracking
    /// accuracy caveats for why that noise is a real, not hypothetical,
    /// concern on a compressed WiFi video feed versus a locally captured one.
    final class ArmDisarmRecognizer: GestureRecognizer {
        let id = "builtin.armDisarm"

        private let openThreshold: CGFloat = 1.4
        private let fistThreshold: CGFloat = 0.85
        private let debounceFrames = 3

        func process(_ snapshot: HandSnapshot, context: inout GestureRecognitionContext) -> [GestureEvent] {
            guard
                let wrist = snapshot.point(.wrist),
                let middleMCP = snapshot.point(.middleMCP)
            else {
                context.storage["openStreak"] = 0
                context.storage["fistStreak"] = 0
                return []
            }

            let tips: [HandJoint] = [.indexTip, .middleTip, .ringTip, .littleTip]
            let tipDistances = tips.compactMap { joint -> CGFloat? in
                guard let point = snapshot.point(joint) else { return nil }
                return hypot(point.x - wrist.x, point.y - wrist.y)
            }
            guard tipDistances.count >= 3 else { return [] }

            let palmReference = max(hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y), 0.001)
            let averageSpread = (tipDistances.reduce(0, +) / CGFloat(tipDistances.count)) / palmReference

            var openStreak = (context.storage["openStreak"] as? Int) ?? 0
            var fistStreak = (context.storage["fistStreak"] as? Int) ?? 0
            let isArmed = (context.storage["armed"] as? Bool) ?? false

            if averageSpread >= openThreshold {
                openStreak += 1
                fistStreak = 0
            } else if averageSpread <= fistThreshold {
                fistStreak += 1
                openStreak = 0
            } else {
                openStreak = 0
                fistStreak = 0
            }
            context.storage["openStreak"] = openStreak
            context.storage["fistStreak"] = fistStreak

            if openStreak >= debounceFrames, !isArmed {
                context.storage["armed"] = true
                return [GestureEvent(name: GestureRegistry.WellKnown.armed, value: .none, timestamp: snapshot.timestamp)]
            }
            if fistStreak >= debounceFrames, isArmed {
                context.storage["armed"] = false
                return [GestureEvent(name: GestureRegistry.WellKnown.disarmed, value: .none, timestamp: snapshot.timestamp)]
            }
            return []
        }
    }

    /// Frame-to-frame wrist position delta in normalized (0-1) Vision
    /// coordinates. Purely a detector — whether that delta should currently
    /// *do* anything (i.e. whether the hand is armed) is a policy decision
    /// left to whoever binds a handler to `rotateDelta`, deliberately kept
    /// out of this recognizer.
    final class HandPositionRotateRecognizer: GestureRecognizer {
        let id = "builtin.rotate"

        func process(_ snapshot: HandSnapshot, context: inout GestureRecognitionContext) -> [GestureEvent] {
            defer { context.previousSnapshot = snapshot }

            guard
                let previous = context.previousSnapshot,
                let currentWrist = snapshot.point(.wrist),
                let previousWrist = previous.point(.wrist)
            else {
                return []
            }

            let dx = Double(currentWrist.x - previousWrist.x)
            let dy = Double(currentWrist.y - previousWrist.y)

            // Ignore sub-pixel jitter from JPEG re-encode noise rather than
            // feeding it straight into rotation, or the model visibly
            // trembles even when the hand is held still.
            guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return [] }

            return [GestureEvent(name: GestureRegistry.WellKnown.rotateDelta, value: .delta(dx: dx, dy: dy), timestamp: snapshot.timestamp)]
        }
    }
}
