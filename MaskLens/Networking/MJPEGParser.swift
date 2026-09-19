import Foundation

/// Incrementally parses a `multipart/x-mixed-replace` MJPEG HTTP stream —
/// the format the standard ESP32-CAM "CameraWebServer" Arduino example
/// serves at `/stream`. Fed raw bytes as they arrive over the network;
/// emits complete JPEG frames as it finds them.
///
/// This is a pragmatic parser, not a general MIME parser: it looks for the
/// boundary marker and a `Content-Length` header, and if `Content-Length`
/// is missing it falls back to scanning for JPEG SOI/EOI markers
/// (0xFFD8 ... 0xFFD9). The ESP32-CAM firmware in Firmware/camera-esp32cam
/// always sends Content-Length, so the fallback is a safety net for other
/// MJPEG sources, not the primary path.
final class MJPEGParser {
    private var buffer = Data()
    private let boundaryToken = "--".data(using: .ascii)!

    /// Feed raw bytes from the connection. Returns any complete JPEG frames
    /// found in this call (usually zero or one, occasionally more if the
    /// network delivered several frames in one read).
    func feed(_ data: Data) -> [Data] {
        buffer.append(data)
        var frames: [Data] = []

        while true {
            guard let headerEnd = range(of: "\r\n\r\n".data(using: .ascii)!, in: buffer) else {
                break
            }
            let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
            guard let headerString = String(data: headerData, encoding: .ascii) else {
                // Unparseable header — drop up to end of this attempted header and keep going.
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
                continue
            }

            guard let contentLength = contentLength(from: headerString) else {
                // No length yet available for this part; wait for more data,
                // unless the buffer is growing unreasonably (malformed
                // stream) in which case bail out to avoid unbounded memory use.
                if buffer.count > 8 * 1024 * 1024 {
                    buffer.removeAll()
                }
                break
            }

            let frameStart = headerEnd.upperBound
            let frameEnd = buffer.index(frameStart, offsetBy: contentLength, limitedBy: buffer.endIndex)
            guard let frameEnd else { break } // frame not fully received yet

            frames.append(buffer.subdata(in: frameStart..<frameEnd))
            buffer.removeSubrange(buffer.startIndex..<frameEnd)
        }

        return frames
    }

    func reset() {
        buffer.removeAll()
    }

    private func contentLength(from header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private func range(of pattern: Data, in data: Data) -> Range<Data.Index>? {
        guard !pattern.isEmpty, data.count >= pattern.count else { return nil }
        var index = data.startIndex
        let lastPossible = data.index(data.endIndex, offsetBy: -pattern.count)
        while index <= lastPossible {
            if data[index..<data.index(index, offsetBy: pattern.count)] == pattern {
                return index..<data.index(index, offsetBy: pattern.count)
            }
            index = data.index(after: index)
        }
        return nil
    }
}
