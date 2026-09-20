import SwiftUI

/// Stage 2: run VNDetectHumanHandPoseRequest against the live mask feed and
/// watch the gesture state machine (arm/disarm, pinch scale, rotate)
/// respond, with no 3D model in the loop yet. Debugging gesture thresholds
/// is much easier against this raw HUD than against a spinning model —
/// you can watch the exact scale ratio and rotation delta numbers instead
/// of eyeballing whether a 3D object "looks right."
struct Stage2HandTrackingView: View {
    @EnvironmentObject var connection: MaskConnectionManager
    @StateObject private var tracker = HandPoseTracker()
    @StateObject private var manipulation = ManipulationController()

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                if let image = connection.cameraStream.latestImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .aspectRatio(4.0/3.0, contentMode: .fit)
                }

                if let snapshot = tracker.lastSnapshot {
                    GeometryReader { proxy in
                        ForEach(Array(snapshot.points.keys), id: \.self) { joint in
                            if let point = snapshot.point(joint) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                    .position(
                                        x: point.x * proxy.size.width,
                                        // Vision's y axis is bottom-up; SwiftUI's is top-down.
                                        y: (1 - point.y) * proxy.size.height
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)

            GroupBox("Gesture State") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(tracker.isHandVisible ? "Hand detected" : "No hand", systemImage: tracker.isHandVisible ? "hand.raised.fill" : "hand.raised.slash")
                    Label(manipulation.isArmed ? "Armed" : "Disarmed", systemImage: manipulation.isArmed ? "lock.open" : "lock")
                    Text(String(format: "Scale: %.2fx", manipulation.effectiveScale))
                    Text(String(format: "Rotation: yaw %.2f rad, pitch %.2f rad", manipulation.rotation.dx, manipulation.rotation.dy))
                }
                .font(.callout.monospaced())
            }
            .padding(.horizontal)

            Button("Reset Gesture State") { manipulation.reset() }
        }
        .padding(.vertical)
        .navigationTitle("Stage 2: Hand Tracking")
        .onAppear {
            manipulation.attach(to: tracker.registry)
            tracker.start(consuming: connection.cameraStream.framePublisher)
        }
        .onDisappear {
            tracker.stop()
        }
    }
}
