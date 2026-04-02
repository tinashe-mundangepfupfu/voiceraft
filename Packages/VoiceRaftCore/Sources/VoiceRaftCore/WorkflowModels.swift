import Foundation

public enum MeetingWorkflowStatus: String, Codable, Sendable, Equatable {
    case final = "final"
    case needsReview = "needs-review"
}

public struct ActionItem: Codable, Equatable, Sendable {
    public let task: String
    public let owner: String?
    public let due: String?

    public init(task: String, owner: String?, due: String?) {
        self.task = task
        self.owner = owner
        self.due = due
    }
}

public struct MeetingNoteSections: Codable, Equatable, Sendable {
    public let summary: String
    public let keyDiscussionPoints: [String]
    public let decisions: [String]
    public let actionItems: [ActionItem]
    public let openQuestionsOrRisks: [String]
    public let followUp: [String]

    public init(
        summary: String,
        keyDiscussionPoints: [String],
        decisions: [String],
        actionItems: [ActionItem],
        openQuestionsOrRisks: [String],
        followUp: [String]
    ) {
        self.summary = summary
        self.keyDiscussionPoints = keyDiscussionPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestionsOrRisks = openQuestionsOrRisks
        self.followUp = followUp
    }
}

public struct Frontmatter: Codable, Equatable, Sendable {
    public let title: String
    public let date: String
    public let meetingMode: String
    public let language: String
    public let status: MeetingWorkflowStatus
    public let tags: [String]

    public init(
        title: String,
        date: String,
        meetingMode: String,
        language: String,
        status: MeetingWorkflowStatus,
        tags: [String]
    ) {
        self.title = title
        self.date = date
        self.meetingMode = meetingMode
        self.language = language
        self.status = status
        self.tags = tags
    }

    func withStatus(_ status: MeetingWorkflowStatus) -> Frontmatter {
        Frontmatter(
            title: title,
            date: date,
            meetingMode: meetingMode,
            language: language,
            status: status,
            tags: tags
        )
    }
}

public struct DraftNote: Codable, Equatable, Sendable {
    public let frontmatter: Frontmatter
    public let sections: MeetingNoteSections

    public init(frontmatter: Frontmatter, sections: MeetingNoteSections) {
        self.frontmatter = frontmatter
        self.sections = sections
    }
}

public struct JudgeFeedback: Codable, Equatable, Sendable {
    public let reason: String
    public let missingRequirements: [String]

    public init(reason: String, missingRequirements: [String]) {
        self.reason = reason
        self.missingRequirements = missingRequirements
    }
}

public struct JudgeDecision: Codable, Equatable, Sendable {
    public let approved: Bool
    public let confidence: Double
    public let feedback: JudgeFeedback

    public init(approved: Bool, confidence: Double, feedback: JudgeFeedback) {
        self.approved = approved
        self.confidence = confidence
        self.feedback = feedback
    }
}

public struct MeetingWorkflowRequest: Equatable, Sendable {
    public let sessionID: String
    public let audioURL: URL
    public let meetingTitle: String
    public let meetingMode: String
    public let language: String
    public let startedAt: String
    public let endedAt: String

    public init(
        sessionID: String,
        audioURL: URL,
        meetingTitle: String,
        meetingMode: String,
        language: String,
        startedAt: String,
        endedAt: String
    ) {
        self.sessionID = sessionID
        self.audioURL = audioURL
        self.meetingTitle = meetingTitle
        self.meetingMode = meetingMode
        self.language = language
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct MeetingWorkflowResult: Equatable, Sendable {
    public let status: MeetingWorkflowStatus
    public let confidence: Double
    public let judgeSummary: String
    public let frontmatter: Frontmatter
    public let sections: MeetingNoteSections
    public let markdown: String
    public let revisionCount: Int

    public init(
        status: MeetingWorkflowStatus,
        confidence: Double,
        judgeSummary: String,
        frontmatter: Frontmatter,
        sections: MeetingNoteSections,
        markdown: String,
        revisionCount: Int
    ) {
        self.status = status
        self.confidence = confidence
        self.judgeSummary = judgeSummary
        self.frontmatter = frontmatter
        self.sections = sections
        self.markdown = markdown
        self.revisionCount = revisionCount
    }
}

public enum VoiceRaftCoreError: Error, LocalizedError, Equatable, Sendable {
    case emptyTranscript
    case speechRecognitionPermissionDenied
    case speechTranscriptionUnavailable(String)
    case transcriptionFailed(String)
    case invalidLMStudioResponse(String)
    case lmStudioRequestFailed(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "Speech transcription produced no usable text."
        case .speechRecognitionPermissionDenied:
            "VoiceRaft needs speech recognition permission to transcribe meetings."
        case let .speechTranscriptionUnavailable(message):
            message
        case let .transcriptionFailed(message):
            "VoiceRaft could not transcribe the recording. \(message)"
        case let .invalidLMStudioResponse(message):
            "VoiceRaft received an invalid LM Studio response. \(message)"
        case let .lmStudioRequestFailed(statusCode, body):
            "LM Studio returned HTTP \(statusCode). \(body)"
        }
    }
}

public protocol TranscriptService: Sendable {
    func transcribe(audioURL: URL, language: String) async throws -> String
}

public protocol MeetingNotesModeling: Sendable {
    func draft(transcript: String, request: MeetingWorkflowRequest) async throws -> DraftNote
    func judge(transcript: String, draft: DraftNote) async throws -> JudgeDecision
    func revise(draft: DraftNote, feedback: JudgeFeedback, request: MeetingWorkflowRequest) async throws -> DraftNote
}

public protocol MarkdownRendering: Sendable {
    func render(result: MeetingWorkflowResult) -> String
}
