import XCTest
@testable import VoiceRaftCore

final class AnthropicModelsServiceTests: XCTestCase {
    func testListModelsFollowsPaginationAndSortsClaudeIDs() async throws {
        let requests = RequestRecorder()
        let transport = StubHTTPTransport { request in
            requests.append(request)

            if request.url?.query == nil {
                return (
                    Data(
                        """
                        {
                          "data": [
                            { "id": "claude-3-7-sonnet-20250219" },
                            { "id": "claude-3-5-haiku-20241022" }
                          ],
                          "has_more": true,
                          "last_id": "claude-3-5-haiku-20241022"
                        }
                        """.utf8
                    ),
                    HTTPURLResponse(
                        url: URL(string: "https://api.anthropic.com/v1/models")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }

            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.anthropic.com/v1/models?after_id=claude-3-5-haiku-20241022"
            )
            return (
                Data(
                    """
                    {
                      "data": [
                        { "id": "claude-4-opus-20260301" }
                      ],
                      "has_more": false,
                      "last_id": "claude-4-opus-20260301"
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/v1/models?after_id=claude-3-5-haiku-20241022")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let service = AnthropicModelsService(
            apiKey: "test-anthropic-key",
            transport: transport.send
        )

        let models = try await service.listModels()

        XCTAssertEqual(models, [
            "claude-3-5-haiku-20241022",
            "claude-3-7-sonnet-20250219",
            "claude-4-opus-20260301",
        ])
        XCTAssertEqual(requests.values.count, 2)
        XCTAssertEqual(requests.values.first?.url?.absoluteString, "https://api.anthropic.com/v1/models")
    }

    func testListModelsFiltersToClaudePrefixedIDs() async throws {
        let transport = StubHTTPTransport { request in
            (
                Data(
                    """
                    {
                      "data": [
                        { "id": "claude-3-7-sonnet-20250219" },
                        { "id": "text-embedding-3-large" },
                        { "id": "claude-3-5-haiku-20241022" }
                      ],
                      "has_more": false,
                      "last_id": "claude-3-5-haiku-20241022"
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let service = AnthropicModelsService(
            apiKey: "test-anthropic-key",
            transport: transport.send
        )

        let models = try await service.listModels()

        XCTAssertEqual(models, [
            "claude-3-5-haiku-20241022",
            "claude-3-7-sonnet-20250219",
        ])
    }

    func testListModelsMapsTimeoutToTypedError() async {
        let transport = StubHTTPTransport { _ in
            throw URLError(.timedOut)
        }
        let service = AnthropicModelsService(
            apiKey: "test-anthropic-key",
            transport: transport.send
        )

        await XCTAssertThrowsErrorAsync(
            try await service.listModels()
        ) { error in
            XCTAssertEqual(error as? VoiceRaftCoreError, .anthropicModelDiscoveryTimedOut)
        }
    }
}
