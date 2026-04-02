import Foundation

public struct ClaudeConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let model: String
    public let apiKey: String

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        model: String,
        apiKey: String
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }
}

public typealias AnthropicTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public struct ClaudeClient: MeetingNotesModeling, Sendable {
    private static let requestTimeoutSeconds: TimeInterval = 300
    private static let maxTokens = 4_096

    private let configuration: ClaudeConfiguration
    private let transport: AnthropicTransport

    public init(
        configuration: ClaudeConfiguration,
        transport: @escaping AnthropicTransport = ClaudeClient.liveTransport
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func draft(transcript: String, request: MeetingWorkflowRequest) async throws -> DraftNote {
        let output: ClaudeDraftOutput = try await complete(
            systemPrompt: """
            You write informative, professional meeting minutes.
            Only use information grounded in the transcript.
            Keep decisions separate from open questions.
            Only assign an owner when explicitly stated or strongly inferable.
            Respond with one JSON object using the requested schema and no extra text.
            """,
            userPrompt: """
            Meeting title: \(request.meetingTitle)
            Meeting mode: \(request.meetingMode)
            Language: \(request.language)
            Transcript:
            \(transcript)
            """,
            responseFormat: .meetingNote,
            responseType: ClaudeDraftOutput.self
        )

        return draftNote(from: output, request: request)
    }

    public func judge(transcript: String, draft: DraftNote) async throws -> JudgeDecision {
        let output: ClaudeJudgeOutput = try await complete(
            systemPrompt: """
            Judge the meeting note against this rubric:
            1) no unsupported claims,
            2) decisions and open questions are clearly separated,
            3) action items include owners only when explicit or strongly inferable,
            4) tone is professional and concise,
            5) uncertainty is labeled rather than guessed.
            Approve only when the note is safe to auto-save.
            Respond with one JSON object using the requested schema and no extra text.
            """,
            userPrompt: """
            Transcript:
            \(transcript)

            Candidate note:
            \(draftPayload(from: draft))
            """,
            responseFormat: .judgeDecision,
            responseType: ClaudeJudgeOutput.self
        )

        return JudgeDecision(
            approved: output.approved,
            confidence: output.confidence,
            feedback: JudgeFeedback(
                reason: output.reason,
                missingRequirements: output.missingRequirements
            )
        )
    }

    public func revise(draft: DraftNote, feedback: JudgeFeedback, request: MeetingWorkflowRequest) async throws -> DraftNote {
        let output: ClaudeDraftOutput = try await complete(
            systemPrompt: """
            Revise the meeting note so it passes the review rubric.
            Do not invent facts.
            Keep tone professional and concise.
            Respond with one JSON object using the requested schema and no extra text.
            """,
            userPrompt: """
            Meeting title: \(request.meetingTitle)
            Meeting mode: \(request.meetingMode)
            Language: \(request.language)
            Existing note draft:
            \(draftPayload(from: draft))
            Judge feedback:
            \(feedbackPayload(from: feedback))
            """,
            responseFormat: .meetingNote,
            responseType: ClaudeDraftOutput.self
        )

        return draftNote(from: output, request: request)
    }

    private func complete<Response: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        responseFormat: ClaudeOutputFormat,
        responseType: Response.Type
    ) async throws -> Response {
        let url = configuration.baseURL.appending(path: "v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessagesRequest(
                model: configuration.model,
                maxTokens: Self.maxTokens,
                system: systemPrompt,
                messages: [
                    ClaudeInputMessage(role: "user", content: userPrompt)
                ],
                outputConfig: ClaudeOutputConfig(format: responseFormat)
            )
        )

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError where error.code == .timedOut {
            throw VoiceRaftCoreError.anthropicRequestTimedOut
        }

        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VoiceRaftCoreError.anthropicRequestFailed(statusCode: response.statusCode, body: body)
        }

        let envelope: ClaudeMessagesResponse
        do {
            envelope = try JSONDecoder().decode(ClaudeMessagesResponse.self, from: data)
        } catch {
            throw VoiceRaftCoreError.invalidAnthropicResponse("Could not decode Anthropic response envelope.")
        }
        guard
            let content = envelope.content.first(where: { $0.type == "text" })?.text,
            let json = extractJSONObject(from: content),
            let jsonData = json.data(using: .utf8)
        else {
            throw VoiceRaftCoreError.invalidAnthropicResponse("Anthropic did not return structured JSON text.")
        }

        do {
            return try JSONDecoder().decode(responseType, from: jsonData)
        } catch {
            throw VoiceRaftCoreError.invalidAnthropicResponse("Could not decode model output as JSON.")
        }
    }

    private func draftNote(from output: ClaudeDraftOutput, request: MeetingWorkflowRequest) -> DraftNote {
        DraftNote(
            frontmatter: Frontmatter(
                title: request.meetingTitle,
                date: request.startedAt,
                meetingMode: request.meetingMode,
                language: request.language,
                status: .final,
                tags: ["meeting", request.meetingMode]
            ),
            sections: MeetingNoteSections(
                summary: output.summary,
                keyDiscussionPoints: output.keyDiscussionPoints,
                decisions: output.decisions,
                actionItems: output.actionItems.map {
                    ActionItem(task: $0.task, owner: $0.owner, due: $0.due)
                },
                openQuestionsOrRisks: output.openQuestionsOrRisks,
                followUp: output.followUp
            )
        )
    }

    private func draftPayload(from draft: DraftNote) -> String {
        let payload = ClaudeDraftOutput(
            summary: draft.sections.summary,
            keyDiscussionPoints: draft.sections.keyDiscussionPoints,
            decisions: draft.sections.decisions,
            actionItems: draft.sections.actionItems.map {
                ClaudeActionItemOutput(task: $0.task, owner: $0.owner, due: $0.due)
            },
            openQuestionsOrRisks: draft.sections.openQuestionsOrRisks,
            followUp: draft.sections.followUp
        )
        return encodeJSON(payload)
    }

    private func feedbackPayload(from feedback: JudgeFeedback) -> String {
        encodeJSON(
            ClaudeJudgeFeedbackOutput(
                reason: feedback.reason,
                missingRequirements: feedback.missingRequirements
            )
        )
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func extractJSONObject(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        let unwrapped = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if unwrapped.first == "{", unwrapped.last == "}" {
            return unwrapped
        }

        guard let start = unwrapped.firstIndex(of: "{"), let end = unwrapped.lastIndex(of: "}") else {
            return nil
        }
        return String(unwrapped[start...end])
    }

    public static func liveTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceRaftCoreError.invalidAnthropicResponse("The response was not HTTP.")
        }
        return (data, httpResponse)
    }
}

private struct ClaudeMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeInputMessage]
    let outputConfig: ClaudeOutputConfig

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case outputConfig = "output_config"
    }
}

private struct ClaudeInputMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeOutputConfig: Encodable {
    let format: ClaudeOutputFormat
}

private struct ClaudeOutputFormat: Encodable, Sendable {
    let type = "json_schema"
    let schema: ClaudeJSONSchema

    static let meetingNote = ClaudeOutputFormat(
        schema: .meetingNote
    )

    static let judgeDecision = ClaudeOutputFormat(
        schema: .judgeDecision
    )
}

private struct ClaudeMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
}

private struct ClaudeJSONSchema: Encodable, Sendable {
    let type = "object"
    let properties: [String: ClaudeSchemaProperty]
    let required: [String]
    let additionalProperties = false

    static let meetingNote = ClaudeJSONSchema(
        properties: [
            "summary": .string,
            "key_discussion_points": .stringArray,
            "decisions": .stringArray,
            "action_items": .actionItemArray,
            "open_questions_or_risks": .stringArray,
            "follow_up": .stringArray,
        ],
        required: [
            "summary",
            "key_discussion_points",
            "decisions",
            "action_items",
            "open_questions_or_risks",
            "follow_up",
        ]
    )

    static let judgeDecision = ClaudeJSONSchema(
        properties: [
            "approved": .boolean,
            "confidence": .number,
            "reason": .string,
            "missing_requirements": .stringArray,
        ],
        required: [
            "approved",
            "confidence",
            "reason",
            "missing_requirements",
        ]
    )
}

private final class ClaudeSchemaProperty: Encodable, @unchecked Sendable {
    let type: String?
    let unionType: [String]?
    let items: ClaudeSchemaProperty?
    let properties: [String: ClaudeSchemaProperty]?
    let required: [String]?
    let additionalProperties: Bool?

    static let string = ClaudeSchemaProperty(type: "string")
    static let number = ClaudeSchemaProperty(type: "number")
    static let boolean = ClaudeSchemaProperty(type: "boolean")
    static let stringArray = ClaudeSchemaProperty(type: "array", items: .string)
    static let actionItemArray = ClaudeSchemaProperty(
        type: "array",
        items: ClaudeSchemaProperty(
            type: "object",
            properties: [
                "task": .string,
                "owner": ClaudeSchemaProperty(type: ["string", "null"]),
                "due": ClaudeSchemaProperty(type: ["string", "null"]),
            ],
            required: ["task", "owner", "due"],
            additionalProperties: false
        )
    )

    init(
        type: String? = nil,
        items: ClaudeSchemaProperty? = nil,
        properties: [String: ClaudeSchemaProperty]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil
    ) {
        self.type = type
        self.unionType = nil
        self.items = items
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    init(
        type: [String],
        items: ClaudeSchemaProperty? = nil,
        properties: [String: ClaudeSchemaProperty]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil
    ) {
        self.type = nil
        self.unionType = type
        self.items = items
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ClaudeDynamicCodingKey.self)
        if let type {
            try container.encode(type, forKey: ClaudeDynamicCodingKey("type"))
        } else if let unionType {
            try container.encode(unionType, forKey: ClaudeDynamicCodingKey("type"))
        }
        try container.encodeIfPresent(items, forKey: ClaudeDynamicCodingKey("items"))
        try container.encodeIfPresent(properties, forKey: ClaudeDynamicCodingKey("properties"))
        try container.encodeIfPresent(required, forKey: ClaudeDynamicCodingKey("required"))
        try container.encodeIfPresent(additionalProperties, forKey: ClaudeDynamicCodingKey("additionalProperties"))
    }
}

private struct ClaudeDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct ClaudeActionItemOutput: Codable, Equatable {
    let task: String
    let owner: String?
    let due: String?
}

private struct ClaudeDraftOutput: Codable, Equatable {
    let summary: String

    enum CodingKeys: String, CodingKey {
        case summary
        case keyDiscussionPoints = "key_discussion_points"
        case decisions
        case actionItems = "action_items"
        case openQuestionsOrRisks = "open_questions_or_risks"
        case followUp = "follow_up"
    }

    let keyDiscussionPoints: [String]
    let decisions: [String]
    let actionItems: [ClaudeActionItemOutput]
    let openQuestionsOrRisks: [String]
    let followUp: [String]
}

private struct ClaudeJudgeOutput: Codable, Equatable {
    let approved: Bool
    let confidence: Double
    let reason: String

    enum CodingKeys: String, CodingKey {
        case approved
        case confidence
        case reason
        case missingRequirements = "missing_requirements"
    }

    let missingRequirements: [String]
}

private struct ClaudeJudgeFeedbackOutput: Codable {
    enum CodingKeys: String, CodingKey {
        case reason
        case missingRequirements = "missing_requirements"
    }

    let reason: String
    let missingRequirements: [String]
}
