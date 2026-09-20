import Foundation
import UIKit

/// Thin wrapper around the Claude Messages API (`POST /v1/messages`).
///
/// **Every call here costs money and hits the network on every single
/// invocation** — there is no caching or batching, because vision
/// identification and voice Q&A are both inherently "fresh input each
/// time." If you wire the trigger phrase in VoiceAssistantController to
/// something that fires often, or leave vision identification on a tight
/// polling loop instead of a manual/explicit trigger, costs scale with
/// however often that fires. See the top-level README's cost section
/// before you build an "always-on" mode around this.
final class ClaudeAPIClient {
    struct APIError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let session: URLSession

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    init(apiKey: String, model: String, maxTokens: Int, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.session = session
    }

    /// Sends a single image + text prompt (vision identification / "what
    /// am I looking at" flow). Downscales before sending — there is no
    /// reason to ship a full-resolution ESP32-CAM frame for a description
    /// task, and every extra KB is extra latency and (marginally) extra
    /// cost.
    func describeImage(_ image: UIImage, prompt: String) async throws -> String {
        guard let base64 = Self.jpegBase64(image, maxDimension: 1024) else {
            throw APIError(message: "Could not encode image for upload.")
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64,
                            ],
                        ],
                        ["type": "text", "text": prompt],
                    ],
                ]
            ],
        ]

        return try await send(body: body)
    }

    /// Text-only turn for the voice assistant loop.
    func ask(_ question: String, systemPrompt: String? = nil) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": question]
            ],
        ]
        if let systemPrompt {
            body["system"] = systemPrompt
        }
        return try await send(body: body)
    }

    private func send(body: [String: Any]) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError(message: "No Claude API key set. Add one in Settings.")
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "No HTTP response from Claude API.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError(message: "Claude API error: \(message)")
        }

        return try Self.extractText(from: data)
    }

    private static func extractText(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
        guard !text.isEmpty else {
            throw APIError(message: "Claude API returned no text content.")
        }
        return text
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
    }

    private static func jpegBase64(_ image: UIImage, maxDimension: CGFloat) -> String? {
        let scaleFactor = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }

        return resized.jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }
}
