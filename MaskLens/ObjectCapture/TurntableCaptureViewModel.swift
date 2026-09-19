import Foundation
import UIKit
import SwiftUI

/// Guides the user through capturing a turntable photo set from the mask's
/// camera feed, then hands the resulting folder of JPEGs to
/// `PhotogrammetryCoordinator`.
///
/// Capture is manual-shutter, not automatic: the mask's camera has no
/// motion sensor we're reading, and this app doesn't try to detect "the
/// object rotated enough" from image content alone. The user physically
/// rotates the object a bit, taps Capture, repeats. That's more tedious
/// than Apple's own ObjectCaptureView (which watches ARKit motion and
/// nudges you in real time), and it's a direct consequence of the camera
/// living in the mask rather than the phone — see
/// PhotogrammetryCoordinator.swift for the full explanation of that
/// tradeoff.
@MainActor
final class TurntableCaptureViewModel: ObservableObject {
    struct CapturedShot: Identifiable {
        let id = UUID()
        let image: UIImage
        let fileURL: URL
    }

    @Published private(set) var shots: [CapturedShot] = []
    @Published var targetShotCount = 32

    let workingDirectory: URL

    var isReadyToReconstruct: Bool { shots.count >= 12 } // fewer than this and PhotogrammetrySession reliably fails to find enough overlap

    init() {
        workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaskLensCapture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    func captureCurrentFrame(from image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        let index = shots.count
        let fileURL = workingDirectory.appendingPathComponent(String(format: "frame_%03d.jpg", index))
        do {
            try data.write(to: fileURL)
            shots.append(CapturedShot(image: image, fileURL: fileURL))
        } catch {
            print("TurntableCaptureViewModel: failed to write frame: \(error)")
        }
    }

    func removeShot(_ shot: CapturedShot) {
        try? FileManager.default.removeItem(at: shot.fileURL)
        shots.removeAll { $0.id == shot.id }
    }

    func reset() {
        for shot in shots {
            try? FileManager.default.removeItem(at: shot.fileURL)
        }
        shots.removeAll()
    }

    /// Guidance string shown in the capture UI. Deliberately simple —
    /// real coverage/blur analysis is exactly the piece Apple's
    /// ObjectCaptureSession provides "for free" against local camera input
    /// and that this app cannot replicate without a lot more image
    /// analysis of its own (out of scope here; see README's stretch goals).
    var guidanceText: String {
        if shots.isEmpty {
            return "Center the object in the mask's camera view, then tap Capture."
        } else if shots.count < 12 {
            return "Rotate the object a little and capture again. \(shots.count)/\(targetShotCount) shots — need at least 12 to attempt reconstruction."
        } else if shots.count < targetShotCount {
            return "Keep going — \(shots.count)/\(targetShotCount) shots. Aim for full 360° coverage with some overlap between shots."
        } else {
            return "\(shots.count) shots captured. You can reconstruct now, or keep adding shots from angles you're missing (top/bottom especially)."
        }
    }
}
