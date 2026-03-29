import Foundation

enum MeetingMode: String, Codable, CaseIterable {
    case room
    case online

    var menuTitle: String {
        switch self {
        case .room:
            "Start Room Meeting"
        case .online:
            "Start Online Meeting"
        }
    }
}

struct MeetingSession: Sendable {
    let id: String
    let title: String
    let mode: MeetingMode
    let startedAt: Date
}

enum CoordinatorState {
    case idle
    case recording(MeetingSession, URL)
    case processing(MeetingSession, URL)

    var isBusy: Bool {
        switch self {
        case .idle:
            false
        case .recording, .processing:
            true
        }
    }

    var statusItemTitle: String {
        switch self {
        case .idle:
            "VoiceRaft"
        case .recording:
            "VoiceRaft REC"
        case .processing:
            "VoiceRaft ..."
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "Idle"
        case let .recording(session, _):
            "Recording \(session.title)"
        case let .processing(session, _):
            "Processing \(session.title)"
        }
    }
}

struct ProcessingRequestPayload: Codable {
    let sessionID: String
    let audioPath: String
    let meetingTitle: String
    let meetingMode: String
    let language: String
    let startedAt: String
    let endedAt: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case audioPath = "audio_path"
        case meetingTitle = "meeting_title"
        case meetingMode = "meeting_mode"
        case language
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct WorkflowResponsePayload: Codable {
    struct Frontmatter: Codable {
        let title: String
        let date: String
        let meetingMode: String
        let language: String
        let status: String
        let tags: [String]

        enum CodingKeys: String, CodingKey {
            case title
            case date
            case meetingMode = "meeting_mode"
            case language
            case status
            case tags
        }
    }

    struct ActionItem: Codable {
        let task: String
        let owner: String?
        let due: String?
    }

    struct Sections: Codable {
        let summary: String
        let keyDiscussionPoints: [String]
        let decisions: [String]
        let actionItems: [ActionItem]
        let openQuestionsOrRisks: [String]
        let followUp: [String]

        enum CodingKeys: String, CodingKey {
            case summary
            case keyDiscussionPoints = "key_discussion_points"
            case decisions
            case actionItems = "action_items"
            case openQuestionsOrRisks = "open_questions_or_risks"
            case followUp = "follow_up"
        }
    }

    let status: String
    let confidence: Double
    let judgeSummary: String
    let frontmatter: Frontmatter
    let sections: Sections
    let markdown: String

    enum CodingKeys: String, CodingKey {
        case status
        case confidence
        case judgeSummary = "judge_summary"
        case frontmatter
        case sections
        case markdown
    }
}
