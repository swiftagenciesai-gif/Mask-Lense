import Foundation
import UIKit

/// Optional stretch feature: after a model reconstructs, send a couple of
/// the source turntable photos (and, ideally, a screenshot of the
/// rendered result) to Claude for a plain-language QA pass.
///
/// Be clear-eyed about what this can and can't do: **Claude's vision API
/// takes images, not 3D geometry** — there is no way to hand it the
/// `.usdz` mesh itself and get back an edited mesh, and nothing here
/// attempts actual hole-filling, decimation, or topology cleanup. What it
/// *can* usefully do is look at your capture photos (and a render of the
/// result, if you pass one) and describe problems in words — "the bottom
/// of the object was never photographed," "this side is reflective and
/// likely has holes in the mesh," "consider recapturing from a lower
/// angle" — which the user can act on by recapturing and re-running
/// `PhotogrammetryCoordinator`. Treat this as a smarter version of "here's
/// some advice," not a mesh repair tool. If this call fails or the API key
/// isn't set, the rest of the Object Capture flow must keep working
/// exactly as before — this is additive, never a blocker.
enum MeshCleanupService {
    static func reviewCapture(shots: [UIImage], renderedPreview: UIImage?, client: ClaudeAPIClient) async -> String? {
        // Keep the request small and cheap: a handful of representative
        // shots is enough for Claude to spot obvious coverage gaps, and
        // sending all 30+ turntable photos would be slow and needlessly
        // expensive for what is explicitly a "nice to have" pass.
        let sample = Array(shots.prefix(6))
        guard let firstImage = sample.first ?? renderedPreview else { return nil }

        let prompt = """
        These are photos from a turntable capture used to reconstruct a 3D model \
        of an object with Apple's PhotogrammetrySession, taken on a phone with no \
        LiDAR (feature-matching only, no depth data). Based on what you can see \
        of coverage, lighting, and surface material, give 2-4 short, specific, \
        actionable suggestions for improving the reconstruction (e.g. missing \
        angles, reflective/transparent surfaces that will confuse feature \
        matching, motion blur, insufficient overlap between shots). Do not \
        describe the object itself — focus only on capture quality.
        """

        do {
            // NOTE: describeImage only takes one image today. Sending the
            // single most representative frame is a scope-conscious
            // starting point for this optional feature; extending
            // ClaudeAPIClient to accept multiple image blocks in one
            // request (the Messages API supports it) is a reasonable next
            // step if this proves useful enough to invest more in.
            return try await client.describeImage(firstImage, prompt: prompt)
        } catch {
            return nil
        }
    }
}
