import Foundation

/// A gesture the registry can evaluate against each incoming hand pose.
/// Detection and action are deliberately decoupled: a recognizer only ever
/// emits named `GestureEvent`s, it never knows what those events *do*.
protocol GestureRecognizer: AnyObject {
    /// Stable identifier, used as the key for this recognizer's scratch
    /// state. Must be unique across all registered recognizers.
    var id: String { get }

    func process(_ snapshot: HandSnapshot, context: inout GestureRecognitionContext) -> [GestureEvent]
}

/// Extensible hand-gesture pipeline: a list of `GestureRecognizer`s that
/// turn hand poses into named events, and a list of listeners bound to
/// event names that turn events into app behavior.
///
/// Both sides are open for extension without modifying this class or
/// `HandPoseTracker`: drop in a new `GestureRecognizer` for a new gesture,
/// or call `onEvent(name:)` for a new action bound to an existing gesture.
/// Nothing here special-cases pinch/palm/fist/rotate — those are just the
/// four recognizers registered by default in `BuiltInGestures.swift`.
final class GestureRegistry {
    /// Names emitted by the recognizers in BuiltInGestures.swift. Purely
    /// documentation/convenience — `onEvent` takes any `String`.
    enum WellKnown {
        static let armed = "hand.armed"
        static let disarmed = "hand.disarmed"
        static let pinchChanged = "pinch.changed"
        static let pinchCommitted = "pinch.committed"
        static let rotateDelta = "rotate.delta"
    }

    private var recognizers: [GestureRecognizer] = []
    private var contexts: [String: GestureRecognitionContext] = [:]
    private var listeners: [String: [(GestureEvent) -> Void]] = [:]

    func register(_ recognizer: GestureRecognizer) {
        recognizers.append(recognizer)
        contexts[recognizer.id] = GestureRecognitionContext()
    }

    func unregister(id: String) {
        recognizers.removeAll { $0.id == id }
        contexts.removeValue(forKey: id)
    }

    /// Bind a handler to an event name. Multiple handlers may share a name;
    /// they all fire, in registration order. Pass `"*"` to observe every
    /// event regardless of name (useful for debug HUDs / logging).
    func onEvent(_ name: String, handler: @escaping (GestureEvent) -> Void) {
        listeners[name, default: []].append(handler)
    }

    func removeAllListeners() {
        listeners.removeAll()
    }

    /// Fires an event directly to bound listeners, bypassing recognizer
    /// evaluation entirely. Recognizers use this indirectly via `process`;
    /// it's also handy on its own for injecting synthetic events — a
    /// debug UI simulating a gesture without a camera, or a unit test
    /// exercising `ManipulationController` without needing a fake
    /// `HandSnapshot` for every recognizer.
    func dispatch(_ event: GestureEvent) {
        listeners[event.name]?.forEach { $0(event) }
        listeners["*"]?.forEach { $0(event) }
    }

    func process(_ snapshot: HandSnapshot) {
        for recognizer in recognizers {
            var context = contexts[recognizer.id] ?? GestureRecognitionContext()
            let events = recognizer.process(snapshot, context: &context)
            context.previousSnapshot = snapshot
            contexts[recognizer.id] = context

            events.forEach(dispatch)
        }
    }

    /// No hand detected this frame. Recognizers that track continuous
    /// state (e.g. an in-progress pinch) need a chance to reset rather than
    /// silently freezing on stale state, so this is routed through the
    /// same recognizers via a nil-point snapshot rather than skipped.
    func processNoHand(timestamp: TimeInterval) {
        let empty = HandSnapshot(timestamp: timestamp, points: [:], confidences: [:])
        process(empty)
    }
}
