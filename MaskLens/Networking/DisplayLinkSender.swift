import Foundation
import Network

/// Sends rendered frames / simple state packets to the mask's display
/// ESP32 over UDP on the local network.
///
/// UDP, not TCP: this link only ever wants the *latest* frame. If a packet
/// is dropped there is no value in retransmitting it — by the time a
/// retransmit arrived the model view has already moved on. TCP's
/// head-of-line blocking would actually make the display feel laggier than
/// just accepting occasional lost frames, which is invisible on a display
/// this size anyway.
///
/// Wire format (see Firmware/display-esp32/display_esp32.ino for the
/// matching parser):
///   byte 0:       packet type  (0x01 = bitmap, 0x02 = text state)
///   bitmap:  byte 1-2 width (u16 LE), byte 3-4 height (u16 LE),
///            remaining bytes = 1-bpp row-major bitmap, LSB-first per byte
///            (XBM bit order — matches u8g2's drawXBM on the firmware side)
///   text:    remaining bytes = UTF-8 string, firmware truncates to fit
final class DisplayLinkSender {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.masklens.displaylink")

    private var minSendInterval: TimeInterval = 1.0 / 8.0
    private var lastSendDate: Date = .distantPast

    func configure(fps: Double) {
        minSendInterval = 1.0 / max(1, fps)
    }

    func connect(host: String, port: UInt16 = 4210) {
        disconnect()
        let params = NWParameters.udp
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 4210,
            using: params
        )
        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    /// `bitmap` must already be packed 1-bpp, row-major, LSB-first
    /// (XBM order), and exactly `ceil(width/8) * height` bytes — see
    /// MaskFrameRenderer.
    func sendBitmap(_ bitmap: Data, width: Int, height: Int) {
        guard shouldSend() else { return }
        var payload = Data([0x01])
        payload.append(UInt8(width & 0xFF))
        payload.append(UInt8((width >> 8) & 0xFF))
        payload.append(UInt8(height & 0xFF))
        payload.append(UInt8((height >> 8) & 0xFF))
        payload.append(bitmap)
        send(payload)
    }

    func sendState(_ text: String) {
        guard shouldSend() else { return }
        var payload = Data([0x02])
        payload.append(Data(text.prefix(64).utf8))
        send(payload)
    }

    private func shouldSend() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastSendDate) >= minSendInterval else { return false }
        lastSendDate = now
        return true
    }

    private func send(_ payload: Data) {
        connection?.send(content: payload, completion: .contentProcessed { _ in })
    }
}
