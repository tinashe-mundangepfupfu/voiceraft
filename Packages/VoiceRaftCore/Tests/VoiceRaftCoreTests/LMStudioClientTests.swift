import XCTest
@testable import VoiceRaftCore

final class LMStudioClientTests: XCTestCase {
    func testDraftBuildsChatCompletionsRequestAndDecodesStructuredResponse() async throws {
        let capturedRequest = RequestCapture()
        let transport = StubTransport { request in
            capturedRequest.set(request)
            return (
                Data(
                    """
                    {
                      "choices": [
                        {
                          "message": {
                            "content": "{\\"summary\\":\\"The team aligned on launch readiness.\\",\\"key_discussion_points\\":[\\"Reviewed launch checklist.\\"],\\"decisions\\":[\\"Launch remains on schedule.\\"],\\"action_items\\":[{\\"task\\":\\"Send final checklist\\",\\"owner\\":\\"Alice\\",\\"due\\":\\"2026-04-01\\"}],\\"open_questions_or_risks\\":[\\"Need confirmation from support.\\"],\\"follow_up\\":[\\"Review status tomorrow.\\"]}"
                          }
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = LMStudioClient(
            configuration: LMStudioConfiguration(
                baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                model: "qwen3-8b-deepseek-v3.2-speciale-distill"
            ),
            transport: transport.send
        )

        let draft = try await client.draft(
            transcript: "Alice confirmed the launch is on schedule.",
            request: Fixtures.request()
        )

        let request = capturedRequest.value
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.absoluteString, "http://127.0.0.1:1234/v1/chat/completions")
        XCTAssertEqual(draft.sections.summary, "The team aligned on launch readiness.")
        XCTAssertEqual(draft.sections.actionItems.first?.owner, "Alice")
    }

    func testDraftRequestsStructuredOutputSchema() async throws {
        let capturedRequest = RequestCapture()
        let transport = StubTransport { request in
            capturedRequest.set(request)
            return (
                Data(
                    """
                    {
                      "choices": [
                        {
                          "message": {
                            "content": "{\\"summary\\":\\"The team aligned on launch readiness.\\",\\"key_discussion_points\\":[\\"Reviewed launch checklist.\\"],\\"decisions\\":[\\"Launch remains on schedule.\\"],\\"action_items\\":[{\\"task\\":\\"Send final checklist\\",\\"owner\\":\\"Alice\\",\\"due\\":\\"2026-04-01\\"}],\\"open_questions_or_risks\\":[\\"Need confirmation from support.\\"],\\"follow_up\\":[\\"Review status tomorrow.\\"]}"
                          }
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = LMStudioClient(
            configuration: LMStudioConfiguration(
                baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                model: "qwen3-8b-deepseek-v3.2-speciale-distill"
            ),
            transport: transport.send
        )

        _ = try await client.draft(
            transcript: "Alice confirmed the launch is on schedule.",
            request: Fixtures.request()
        )

        let request = try XCTUnwrap(capturedRequest.value)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let responseFormat = try XCTUnwrap(json["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")

        let schemaEnvelope = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(schemaEnvelope["name"] as? String, "meeting_note")
        XCTAssertEqual(schemaEnvelope["strict"] as? Bool, true)

        let schema = try XCTUnwrap(schemaEnvelope["schema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")

        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertTrue(required.contains("summary"))
        XCTAssertTrue(required.contains("key_discussion_points"))
        XCTAssertTrue(required.contains("decisions"))
        XCTAssertTrue(required.contains("action_items"))
        XCTAssertTrue(required.contains("open_questions_or_risks"))
        XCTAssertTrue(required.contains("follow_up"))
    }

    func testJudgeThrowsTypedErrorWhenModelReturnsInvalidJSON() async {
        let transport = StubTransport { _ in
            (
                Data(
                    """
                    {
                      "choices": [
                        {
                          "message": {
                            "content": "not-json"
                          }
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = LMStudioClient(
            configuration: LMStudioConfiguration(
                baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                model: "qwen3-8b-deepseek-v3.2-speciale-distill"
            ),
            transport: transport.send
        )

        await XCTAssertThrowsErrorAsync(
            try await client.judge(
                transcript: "Transcript",
                draft: Fixtures.draftNote()
            )
        ) { error in
            XCTAssertEqual(error as? VoiceRaftCoreError, .invalidLMStudioResponse("Could not decode model output as JSON."))
        }
    }

    func testDraftExtendsRequestTimeoutForLocalModeling() async throws {
        let capturedRequest = RequestCapture()
        let transport = StubTransport { request in
            capturedRequest.set(request)
            return (
                Data(
                    """
                    {
                      "choices": [
                        {
                          "message": {
                            "content": "{\\"summary\\":\\"Done.\\" ,\\"key_discussion_points\\":[],\\"decisions\\":[],\\"action_items\\":[],\\"open_questions_or_risks\\":[],\\"follow_up\\":[]}"
                          }
                        }
                      ]
                    }
                    """.utf8
                ),
                HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        let client = LMStudioClient(
            configuration: LMStudioConfiguration(
                baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                model: "qwen3-8b-deepseek-v3.2-speciale-distill"
            ),
            transport: transport.send
        )

        _ = try await client.draft(
            transcript: "Transcript",
            request: Fixtures.request()
        )

        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.timeoutInterval, 300, accuracy: 0.1)
    }

    func testDraftSurfacesFriendlyTimeoutError() async {
        let transport = StubTransport { _ in
            throw URLError(.timedOut)
        }
        let client = LMStudioClient(
            configuration: LMStudioConfiguration(
                baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                model: "qwen3-8b-deepseek-v3.2-speciale-distill"
            ),
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
                .invalidLMStudioResponse("LM Studio timed out before it returned a response.")
            )
        }
    }
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URLRequest?

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ request: URLRequest) {
        lock.lock()
        storage = request
        lock.unlock()
    }
}

private struct StubTransport: Sendable {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Sendable,
    _ message: @autoclosure () -> String = "",
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
