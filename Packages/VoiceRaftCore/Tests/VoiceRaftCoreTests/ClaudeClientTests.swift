import XCTest
@testable import VoiceRaftCore

final class ClaudeClientTests: XCTestCase {
    func testDraftBuildsAnthropicMessagesRequest() async throws {
        let requests = RequestRecorder()
        let transport = StubHTTPTransport { request in
            requests.append(request)
            return (
                Data(
                    """
                    {
                      "content": [
                        {
                          "type": "text",
                          "text": "{\\"summary\\":\\"The team aligned on launch readiness.\\",\\"key_discussion_points\\":[\\"Reviewed launch checklist.\\"],\\"decisions\\":[\\"Launch remains on schedule.\\"],\\"action_items\\":[{\\"task\\":\\"Send final checklist\\",\\"owner\\":\\"Alice\\",\\"due\\":\\"2026-04-01\\"}],\\"open_questions_or_risks\\":[\\"Need confirmation from support.\\"],\\"follow_up\\":[\\"Review status tomorrow.\\"]}"
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/v1/messages")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = ClaudeClient(
            configuration: Fixtures.claudeConfiguration(),
            transport: transport.send
        )

        let draft = try await client.draft(
            transcript: "Alice confirmed the launch is on schedule.",
            request: Fixtures.request()
        )

        let request = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-3-7-sonnet-20250219")
        XCTAssertEqual(json["max_tokens"] as? Int, 4_096)
        XCTAssertNotNil(json["system"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")

        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")

        XCTAssertEqual(draft.sections.summary, "The team aligned on launch readiness.")
    }

    func testJudgeBuildsAnthropicMessagesRequest() async throws {
        let requests = RequestRecorder()
        let transport = StubHTTPTransport { request in
            requests.append(request)
            return (
                Data(
                    """
                    {
                      "content": [
                        {
                          "type": "text",
                          "text": "{\\"approved\\":true,\\"confidence\\":0.94,\\"reason\\":\\"The note is grounded and safe to save.\\",\\"missing_requirements\\":[]}"
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/v1/messages")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = ClaudeClient(
            configuration: Fixtures.claudeConfiguration(),
            transport: transport.send
        )

        let decision = try await client.judge(
            transcript: "Transcript",
            draft: Fixtures.draftNote()
        )

        let request = try XCTUnwrap(requests.values.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-anthropic-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-3-7-sonnet-20250219")
        XCTAssertEqual(json["max_tokens"] as? Int, 4_096)
        XCTAssertNotNil(json["system"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")

        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")

        XCTAssertTrue(decision.approved)
    }

    func testDraftMapsTimeoutToTypedError() async {
        let transport = StubHTTPTransport { _ in
            throw URLError(.timedOut)
        }
        let client = ClaudeClient(
            configuration: Fixtures.claudeConfiguration(),
            transport: transport.send
        )

        await XCTAssertThrowsErrorAsync(
            try await client.draft(
                transcript: "Transcript",
                request: Fixtures.request()
            )
        ) { error in
            XCTAssertEqual(error as? VoiceRaftCoreError, .anthropicRequestTimedOut)
        }
    }

    func testDraftRejectsMissingStructuredJSON() async {
        let transport = StubHTTPTransport { _ in
            (
                Data(
                    """
                    {
                      "content": [
                        {
                          "type": "tool_use",
                          "id": "toolu_123"
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/v1/messages")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = ClaudeClient(
            configuration: Fixtures.claudeConfiguration(),
            transport: transport.send
        )

        await XCTAssertThrowsErrorAsync(
            try await client.draft(
                transcript: "Transcript",
                request: Fixtures.request()
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceRaftCoreError,
                .invalidAnthropicResponse("Anthropic did not return structured JSON text.")
            )
        }
    }

    func testDraftMapsMalformedEnvelopeToTypedError() async {
        let transport = StubHTTPTransport { _ in
            (
                Data(
                    """
                    {
                      "content": "not-an-array"
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/v1/messages")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = ClaudeClient(
            configuration: Fixtures.claudeConfiguration(),
            transport: transport.send
        )

        await XCTAssertThrowsErrorAsync(
            try await client.draft(
                transcript: "Transcript",
                request: Fixtures.request()
            )
        ) { error in
            XCTAssertEqual(
                error as? VoiceRaftCoreError,
                .invalidAnthropicResponse("Could not decode Anthropic response envelope.")
            )
        }
    }
}
