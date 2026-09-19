import SwiftUI
import RealityKit

/// Renders the reconstructed `.usdz` and applies the same gesture-derived
/// transform (`ManipulationController`) that also drives the mask display
/// feedback in Stage 5 — both consumers read the same published state so
/// they can't drift out of sync with each other.
struct ModelViewerView: View {
    let modelURL: URL
    @ObservedObject var manipulation: ManipulationController

    // Deliberately typed as the base `Entity`, not `ModelEntity`: a usdz
    // loaded this way is not guaranteed to be a single top-level
    // ModelEntity (PhotogrammetrySession output in particular tends to
    // come back as a plain Entity wrapping one or more child
    // ModelEntities). Transform properties (scale/orientation) needed
    // here live on `Entity` itself, so there's no need to downcast.
    @State private var modelEntity: Entity?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            RealityView { content in
                do {
                    let entity = try await Entity(contentsOf: modelURL)
                    entity.generateCollisionShapes(recursive: true)
                    modelEntity = entity
                    content.add(entity)

                    // Basic three-point-ish lighting so the model doesn't
                    // render flat black — PhotogrammetrySession output has
                    // no baked lighting of its own.
                    let light = DirectionalLight()
                    light.light.intensity = 4000
                    light.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
                    content.add(light)
                } catch {
                    loadError = error.localizedDescription
                }
            } update: { content in
                guard let modelEntity else { return }
                let scale = Float(manipulation.effectiveScale)
                modelEntity.scale = SIMD3<Float>(repeating: scale)

                let yaw = simd_quatf(angle: Float(manipulation.rotation.dx), axis: [0, 1, 0])
                let pitch = simd_quatf(angle: Float(-manipulation.rotation.dy), axis: [1, 0, 0])
                modelEntity.orientation = yaw * pitch
            }

            if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Couldn't load model: \(loadError)")
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
