import UIKit
import CoreGraphics

/// Renders a tiny monochrome HUD (armed state, scale, yaw indicator) to
/// send to the mask's OLED, rather than trying to mirror the full RealityKit
/// render.
///
/// This is a deliberate simplification, not a shortcut: a 0.96" 128x64
/// monochrome panel viewed through a $10 loupe lens is not going to
/// usefully show a shaded 3D model — at that size and resolution it would
/// read as an indistinct blob, and pushing full RGB frames over WiFi to a
/// display that can't show them anyway would just burn battery on both
/// ends for nothing. A simple armed/disarmed dot, a scale readout, and a
/// rotating tick mark for yaw are things a viewer can actually resolve
/// through a loupe, and they're literally the state the gesture system
/// already tracks — no extra rendering pass over the model needed.
///
/// **Confirm the resolution below against your actual panel.** 128x64 is
/// the common Waveshare/SSD1306-family panel size, but Waveshare sells the
/// 0.96" SSD1312 module in more than one pixel configuration — check the
/// datasheet for the exact unit you bought before wiring this up, and
/// change `width`/`height` (and the firmware's matching buffer size) to
/// match.
enum MaskFrameRenderer {
    static let width = 128
    static let height = 64

    static func renderHUD(isArmed: Bool, scale: Double, yawRadians: Double) -> Data {
        pack1bpp(renderHUDImage(isArmed: isArmed, scale: scale, yawRadians: yawRadians))
    }

    /// Same rendering as `renderHUD`, but returned as a `UIImage` for
    /// on-screen preview (e.g. Stage5DisplayFeedbackView showing exactly
    /// what's being sent to the physical panel).
    static func renderHUDImage(isArmed: Bool, scale: Double, yawRadians: Double) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.setLineWidth(1.5)

            let indicatorRect = CGRect(x: 4, y: 4, width: 10, height: 10)
            if isArmed {
                cg.fillEllipse(in: indicatorRect)
            } else {
                cg.strokeEllipse(in: indicatorRect)
            }

            let text = String(format: "%.1fx", scale) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            text.draw(at: CGPoint(x: 20, y: 1), withAttributes: attrs)

            let center = CGPoint(x: Double(width) - 18, y: Double(height) - 18)
            let radius: CGFloat = 13
            cg.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let tickX = center.x + radius * CGFloat(cos(yawRadians))
            let tickY = center.y + radius * CGFloat(sin(yawRadians))
            cg.move(to: center)
            cg.addLine(to: CGPoint(x: tickX, y: tickY))
            cg.strokePath()
        }

        return image
    }

    /// Packs an image into row-major, MSB-first 1-bpp — the format
    /// `DisplayLinkSender` sends and `Firmware/display-esp32` parses.
    /// Exposed (not `private`) so callers who already have a `UIImage` from
    /// `renderHUDImage` (e.g. for on-screen preview) can pack that same
    /// image instead of re-rendering it via `renderHUD`.
    static func pack1bpp(_ image: UIImage) -> Data {
        guard let cgImage = image.cgImage else { return Data() }
        let w = cgImage.width
        let h = cgImage.height

        var grayscale = [UInt8](repeating: 0, count: w * h)
        guard let context = CGContext(
            data: &grayscale, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Data() }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // LSB-first per byte (bit 0 = leftmost pixel in that byte) — this
        // is XBM bit order, matching what u8g2's drawXBM() expects on the
        // firmware side. Get this backwards and the image renders
        // horizontally bit-reversed in each 8-pixel group, which looks
        // like static rather than an obviously "flipped" image, so it's
        // an easy mismatch to miss — keep this in sync with
        // Firmware/display-esp32/display_esp32.ino's drawBitmapPacket.
        let bytesPerRow = (w + 7) / 8
        var packed = [UInt8](repeating: 0, count: bytesPerRow * h)
        for y in 0..<h {
            for x in 0..<w where grayscale[y * w + x] > 127 {
                let byteIndex = y * bytesPerRow + x / 8
                let bitIndex = x % 8
                packed[byteIndex] |= (1 << bitIndex)
            }
        }
        return Data(packed)
    }
}
