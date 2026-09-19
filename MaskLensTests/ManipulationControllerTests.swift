import XCTest
@testable import MaskLens

@MainActor
final class ManipulationControllerTests: XCTestCase {

    func testPinchCommitLocksScaleWithoutDrift() {
        let registry = GestureRegistry()
        let controller = ManipulationController()
        controller.attach(to: registry)

        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.pinchChanged, value: .scalar(1.5), timestamp: 0))
        XCTAssertEqual(controller.effectiveScale, 1.5, accuracy: 0.0001, "Live preview should track the in-progress ratio")
        XCTAssertEqual(controller.scale, 1.0, "Committed scale must not move until the pinch actually commits")

        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.pinchCommitted, value: .scalar(1.5), timestamp: 1))
        XCTAssertEqual(controller.scale, 1.5, accuracy: 0.0001)
        XCTAssertNil(controller.livePinchScale, "livePinchScale must clear on commit so nothing keeps nudging it")

        // Simulate many more frames of "nothing happening" — scale must stay put.
        for _ in 0..<10 {
            registry.dispatch(GestureEvent(name: "noop", value: .none, timestamp: 2))
        }
        XCTAssertEqual(controller.scale, 1.5, accuracy: 0.0001, "Scale must not drift after commit")
    }

    func testRotationOnlyAppliesWhileArmed() {
        let registry = GestureRegistry()
        let controller = ManipulationController()
        controller.attach(to: registry)

        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.rotateDelta, value: .delta(dx: 0.1, dy: 0), timestamp: 0))
        XCTAssertEqual(controller.rotation.dx, 0, "Rotation must be gated by armed state")

        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.armed, value: .none, timestamp: 1))
        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.rotateDelta, value: .delta(dx: 0.1, dy: 0), timestamp: 2))
        XCTAssertGreaterThan(controller.rotation.dx, 0, "Rotation should apply once armed")

        let armedRotation = controller.rotation.dx
        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.disarmed, value: .none, timestamp: 3))
        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.rotateDelta, value: .delta(dx: 0.1, dy: 0), timestamp: 4))
        XCTAssertEqual(controller.rotation.dx, armedRotation, "Rotation must freeze again once disarmed")
    }

    func testScaleClampsToConfiguredRange() {
        let registry = GestureRegistry()
        let controller = ManipulationController()
        controller.attach(to: registry)

        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.pinchCommitted, value: .scalar(1000), timestamp: 0))
        XCTAssertLessThanOrEqual(controller.scale, 5.0)

        registry.dispatch(GestureEvent(name: GestureRegistry.WellKnown.pinchCommitted, value: .scalar(0.0001), timestamp: 1))
        XCTAssertGreaterThanOrEqual(controller.scale, 0.2)
    }
}
