import Foundation

public struct AnthropicModelsService: Sendable {
    private static let requestTimeoutSeconds: TimeInterval = 60

    private let baseURL: URL
    private let apiKey: String
    private let transport: AnthropicTransport

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        apiKey: String,
        transport: @escaping AnthropicTransport = ClaudeClient.liveTransport
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.transport = transport
    }

    public func listModels() async throws -> [String] {
        var afterID: String?
        var collectedModelIDs: [String] = []

        while true {
            var components = URLComponents(url: baseURL.appending(path: "v1/models"), resolvingAgainstBaseURL: false)
            if let afterID {
                components?.queryItems = [URLQueryItem(name: "after_id", value: afterID)]
            }

            guard let url = components?.url else {
                throw VoiceRaftCoreError.invalidAnthropicResponse("Could not build the Anthropic models URL.")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = Self.requestTimeoutSeconds
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await transport(request)
            } catch let error as URLError where error.code == .timedOut {
                throw VoiceRaftCoreError.anthropicModelDiscoveryTimedOut
            }

            guard (200..<300).contains(response.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw VoiceRaftCoreError.anthropicRequestFailed(statusCode: response.statusCode, body: body)
            }

            let page: AnthropicModelsPage
            do {
                page = try JSONDecoder().decode(AnthropicModelsPage.self, from: data)
            } catch {
                throw VoiceRaftCoreError.invalidAnthropicResponse("Could not decode Anthropic models response.")
            }
            collectedModelIDs.append(contentsOf: page.data.map(\.id))

            guard page.hasMore else {
                break
            }

            guard let lastID = page.lastID else {
                throw VoiceRaftCoreError.invalidAnthropicResponse("Anthropic model pagination ended without a cursor.")
            }
            afterID = lastID
        }

        return collectedModelIDs
            .filter { $0.hasPrefix("claude-") }
            .sorted()
    }
}

private struct AnthropicModelsPage: Decodable {
    struct ModelSummary: Decodable {
        let id: String
    }

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case lastID = "last_id"
    }

    let data: [ModelSummary]
    let hasMore: Bool
    let lastID: String?
}
