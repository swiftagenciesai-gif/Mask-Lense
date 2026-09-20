import XCTest
import CoreGraphics
@testable import MaskLens

/// These tests exercise the gesture logic against synthetic `HandSnapshot`
/// values — no camera, no Vision framework, no network. That's the whole
/// point of keeping detection (GestureRegistry/BuiltInGestures) decoupled
/// from the video pipeline: the gesture *logic* is fully testable without
/// any hardware, even though the app as a whole obviously needs the mask
/// to do anything useful.
final class GestureRegistryTests: XCTestCase {

    private func snapshot(thumb: CGPoint, index: CGPoint) -> HandSnapshot {
        HandSnapshot(
            timestamp: 0,
            points: [.thumbTip: thumb, .indexTip: index],
            confidences: [.thumbTip: 1, .indexTip: 1]
        )
    }

    func testPinchEmitsChangedThenCommittedWithRatio() {
        let registry = GestureRegistry()
        registry.register(BuiltInGestures.PinchRecognizer())

        var events: [GestureEvent] = []
        registry.onEvent(GestureRegistry.WellKnown.pinchChanged) { events.append($0) }
        registry.onEvent(GestureRegistry.WellKnown.pinchCommitted) { events.append($0) }

        // Start a pinch: thumb and index close together.
        registry.process(snapshot(thumb: CGPoint(x: 0.50, y: 0.50), index: CGPoint(x: 0.53, y: 0.50)))
        XCTAssertTrue(events.isEmpty, "Engaging the pinch shouldn't itself emit an event")

        // Shrink further -> pinchChanged with ratio < 1.
        registry.process(snapshot(thumb: CGPoint(x: 0.50, y: 0.50), index: CGPoint(x: 0.51, y: 0.50)))
        guard case .scalar(let shrinkRatio)? = events.last?.value else {
            return XCTFail("Expected a scalar pinchChanged event")
        }
        XCTAssertEqual(events.last?.name, GestureRegistry.WellKnown.pinchChanged)
        XCTAssertLessThan(shrinkRatio, 1.0)

        // Release: thumb and index move apart past the disengage threshold.
        registry.process(snapshot(thumb: CGPoint(x: 0.30, y: 0.50), index: CGPoint(x: 0.70, y: 0.50)))
        XCTAssertEqual(events.last?.name, GestureRegistry.WellKnown.pinchCommitted)
    }

    func testPinchDoesNotReCommitAfterRelease() {
        let registry = GestureRegistry()
        registry.register(BuiltInGestures.PinchRecognizer())

        var commitCount = 0
        registry.onEvent(GestureRegistry.WellKnown.pinchCommitted) { _ in commitCount += 1 }

        registry.process(snapshot(thumb: CGPoint(x: 0.50, y: 0.50), index: CGPoint(x: 0.53, y: 0.50))) // engage
        registry.process(snapshot(thumb: CGPoint(x: 0.30, y: 0.50), index: CGPoint(x: 0.70, y: 0.50))) // release -> commit
        XCTAssertEqual(commitCount, 1)

        // Holding the hand still (no new pinch) must not emit another commit.
        for _ in 0..<5 {
            registry.process(snapshot(thumb: CGPoint(x: 0.30, y: 0.50), index: CGPoint(x: 0.70, y: 0.50)))
        }
        XCTAssertEqual(commitCount, 1, "Scale must lock after a pinch ends, not keep re-committing")
    }

    func testArmDisarmRequiresDebounceStreak() {
        let registry = GestureRegistry()
        registry.register(BuiltInGestures.ArmDisarmRecognizer())

        var armedCount = 0
        registry.onEvent(GestureRegistry.WellKnown.armed) { _ in armedCount += 1 }

        let openSnapshot = HandSnapshot(
            timestamp: 0,
            points: [
                .wrist: CGPoint(x: 0.5, y: 0.2),
                .middleMCP: CGPoint(x: 0.5, y: 0.3),
                .indexTip: CGPoint(x: 0.4, y: 0.6),
                .middleTip: CGPoint(x: 0.5, y: 0.65),
                .ringTip: CGPoint(x: 0.6, y: 0.6),
                .littleTip: CGPoint(x: 0.65, y: 0.55),
            ],
            confidences: [
                .wrist: 1, .middleMCP: 1, .indexTip: 1, .middleTip: 1, .ringTip: 1, .littleTip: 1,
            ]
        )

        // A single open-palm frame shouldn't be enough (debounce).
        registry.process(openSnapshot)
        XCTAssertEqual(armedCount, 0)

        registry.process(openSnapshot)
        registry.process(openSnapshot)
        XCTAssertEqual(armedCount, 1, "Three consecutive open-palm frames should arm exactly once")

        // Continuing to hold the open palm should not re-arm repeatedly.
        registry.process(openSnapshot)
        XCTAssertEqual(armedCount, 1)
    }
}
