import Foundation
import UIKit
import CoreVideo
import Combine

/// Connects to the mask's camera ESP32 and republishes its MJPEG stream as
/// decoded `CVPixelBuffer`s ready for `Vision`, plus `UIImage`s for on-screen
/// preview.
///
/// Stream source is `http://<camera-ip>/stream`, matching the firmware in
/// Firmware/camera-esp32cam. This is the app's Stage 1 dependency — nothing
/// else (hand tracking, Object Capture, the AI vision button) has anything
/// to work with until this is reliably producing frames.
@MainActor
final class CameraStreamReceiver: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case streaming(fps: Double)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestImage: UIImage?
    @Published private(set) var latestPixelBuffer: CVPixelBuffer?

    /// Fires once per decoded frame. Used by HandPoseTracker and the Object
    /// Capture flow instead of observing `latestPixelBuffer`, so consumers
    /// don't miss frames or process the same one twice due to SwiftUI's
    /// publish coalescing.
    let framePublisher = PassthroughSubject<CVPixelBuffer, Never>()

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let parser = MJPEGParser()

    private var frameTimestamps: [Date] = []

    func connect(host: String, port: UInt16 = 80, path: String = "/stream") {
        disconnect()
        state = .connecting

        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            state = .failed("Invalid camera URL")
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.dataTask(with: url)
        self.task = task
        task.resume()
    }

    func disconnect() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        parser.reset()
        state = .idle
    }

    fileprivate func handleIncoming(_ data: Data) {
        let frames = parser.feed(data)
        for frameData in frames {
            handle(frame: frameData)
        }
    }

    private func handle(frame data: Data) {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        latestImage = image

        if let pixelBuffer = Self.pixelBuffer(from: cgImage) {
            latestPixelBuffer = pixelBuffer
            framePublisher.send(pixelBuffer)
        }

        recordFrameForFPS()
    }

    private func recordFrameForFPS() {
        let now = Date()
        frameTimestamps.append(now)
        frameTimestamps.removeAll { now.timeIntervalSince($0) > 2 }
        let fps = Double(frameTimestamps.count) / 2.0
        state = .streaming(fps: fps)
    }

    private static func pixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

extension CameraStreamReceiver: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            self.handleIncoming(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor in
            self.state = .failed(error.localizedDescription)
        }
    }
}
