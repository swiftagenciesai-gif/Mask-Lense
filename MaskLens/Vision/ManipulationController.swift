import Foundation
import CoreGraphics
import Combine

/// Turns generic gesture events into the specific manipulation state the
/// rendered model (Stage 3) and the mask display feedback (Stage 5) both
/// read from. This is the "policy" layer described in
/// BuiltInGestures.swift and GestureRegistry.swift: it's the only place
/// that knows arm/disarm gates rotation, or that a committed pinch means
/// "bake this into the running scale and stop touching it."
@MainActor
final class ManipulationController: ObservableObject {
    @Published private(set) var isArmed = false

    /// The committed scale factor. This is the only scale value anything
    /// downstream should treat as "current" once a pinch has ended —
    /// intentionally there is no decay, spring-back, or continued update
    /// after `pinchCommitted` fires, which is what makes it not drift.
    @Published private(set) var scale: Double = 1.0

    /// Non-nil only while a pinch is actively in progress; a live preview
    /// value for the UI to render smoothly without mutating `scale` until
    /// the gesture actually commits.
    @Published private(set) var livePinchScale: Double?

    /// Accumulated rotation, in radians, as (yaw, pitch). Only advances
    /// while armed.
    @Published private(set) var rotation = CGVector(dx: 0, dy: 0)

    var effectiveScale: Double { livePinchScale ?? scale }

    private let minScale = 0.2
    private let maxScale = 5.0
    private let rotationSensitivity = 3.5 // radians per normalized-coordinate unit of wrist travel

    private var subscriptions: [String] = []

    func attach(to registry: GestureRegistry) {
        registry.onEvent(GestureRegistry.WellKnown.armed) { [weak self] _ in
            self?.isArmed = true
        }
        registry.onEvent(GestureRegistry.WellKnown.disarmed) { [weak self] _ in
            self?.isArmed = false
        }
        registry.onEvent(GestureRegistry.WellKnown.pinchChanged) { [weak self] event in
            guard let self, case let .scalar(ratio) = event.value else { return }
            self.livePinchScale = self.clamp(self.scale * ratio)
        }
        registry.onEvent(GestureRegistry.WellKnown.pinchCommitted) { [weak self] event in
            guard let self, case let .scalar(ratio) = event.value else { return }
            self.scale = self.clamp(self.scale * ratio)
            self.livePinchScale = nil
        }
        registry.onEvent(GestureRegistry.WellKnown.rotateDelta) { [weak self] event in
            guard let self, self.isArmed, case let .delta(dx, dy) = event.value else { return }
            self.rotation.dx += dx * self.rotationSensitivity
            self.rotation.dy += dy * self.rotationSensitivity
        }
    }

    func reset() {
        isArmed = false
        scale = 1.0
        livePinchScale = nil
        rotation = .zero
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, minScale), maxScale)
    }
}
