import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

final class OpenAIClient {
    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func streamChat(
        messages: [ChatMessage],
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        let url: URL = Self.makeAPIURL(from: baseURL, endpoint: "chat/completions")
        let body: ChatCompletionRequest = ChatCompletionRequest(
            model: model,
            messages: messages,
            stream: true
        )
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 30)

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setAuthorizationHeaderIfNeeded(on: &request)
        request.httpBody = try encoder.encode(body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse: HTTPURLResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody: String = try await Self.readErrorBody(from: bytes)
            throw OpenAIClientError.httpError(
                statusCode: httpResponse.statusCode,
                body: String(responseBody.prefix(500))
            )
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }

            let payload: String = String(line.dropFirst("data: ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { continue }
            guard payload != "[DONE]" else { return }

            let data: Data = Data(payload.utf8)
            let chunk: ChatCompletionStreamChunk
            do {
                chunk = try decoder.decode(ChatCompletionStreamChunk.self, from: data)
            } catch {
                if let apiError: APIErrorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                    throw OpenAIClientError.apiError(message: apiError.error.message)
                }
                continue
            }
            guard let content: String = chunk.choices.first?.delta?.content, !content.isEmpty else {
                continue
            }

            await MainActor.run {
                onDelta(content)
            }
        }
    }

    func listModels() async throws -> [String] {
        let url: URL = Self.makeAPIURL(from: baseURL, endpoint: "models")
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 30)

        request.httpMethod = "GET"
        setAuthorizationHeaderIfNeeded(on: &request)

        let (data, response): (Data, URLResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse: HTTPURLResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody: String = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIClientError.httpError(
                statusCode: httpResponse.statusCode,
                body: String(responseBody.prefix(500))
            )
        }

        let responseBody: ModelListResponse = try decoder.decode(ModelListResponse.self, from: data)
        return Set(responseBody.data.map(\.id)).sorted()
    }

    private func setAuthorizationHeaderIfNeeded(on request: inout URLRequest) {
        guard !apiKey.isEmpty else { return }

        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private static func makeAPIURL(from baseURL: URL, endpoint: String) -> URL {
        var components: URLComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var path: String = components.path
        let normalizedEndpoint: String = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        while path.hasSuffix("/") {
            path.removeLast()
        }

        if path.hasSuffix("/v1") {
            path.append("/\(normalizedEndpoint)")
        } else {
            path.append("/v1/\(normalizedEndpoint)")
        }

        components.path = path
        components.query = nil
        components.fragment = nil

        return components.url ?? baseURL.appendingPathComponent("v1/\(normalizedEndpoint)")
    }

    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var lines: [String] = []

        for try await line in bytes.lines {
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct ChatCompletionStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta?
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct ModelListResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct APIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private enum OpenAIClientError: LocalizedError, CustomStringConvertible {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case apiError(message: String)

    var description: String {
        switch self {
        case .invalidResponse:
            return String(localized: "OpenAI-compatible API returned a non-HTTP response.")
        case let .httpError(statusCode, body):
            return String(
                format: String(localized: "OpenAI-compatible API request failed with status %d: %@"),
                statusCode,
                body
            )
        case let .apiError(message):
            return String(
                format: String(localized: "OpenAI-compatible API stream failed: %@"),
                message
            )
        }
    }

    var errorDescription: String? {
        description
    }
}
