import Foundation
@testable import VoiceRaftCore

enum Fixtures {
    static func request() -> MeetingWorkflowRequest {
        MeetingWorkflowRequest(
            sessionID: "session-123",
            audioURL: URL(fileURLWithPath: "/tmp/demo.m4a"),
            meetingTitle: "Weekly Sync",
            meetingMode: "room",
            language: "en",
            startedAt: "2026-03-31T09:00:00Z",
            endedAt: "2026-03-31T09:30:00Z"
        )
    }

    static func draftNote(summary: String = "The team aligned on launch readiness.") -> DraftNote {
        DraftNote(
            frontmatter: Frontmatter(
                title: "Weekly Sync",
                date: "2026-03-31T09:00:00Z",
                meetingMode: "room",
                language: "en",
                status: .final,
                tags: ["meeting", "room"]
            ),
            sections: MeetingNoteSections(
                summary: summary,
                keyDiscussionPoints: [
                    "Reviewed launch checklist."
                ],
                decisions: [
                    "Launch remains on schedule."
                ],
                actionItems: [
                    ActionItem(task: "Send final checklist", owner: "Alice", due: "2026-04-01")
                ],
                openQuestionsOrRisks: [
                    "Need confirmation from support."
                ],
                followUp: [
                    "Review status tomorrow."
                ]
            )
        )
    }

    static func approvedDecision(
        confidence: Double = 0.93,
        reason: String = "The note is grounded and safe to save."
    ) -> JudgeDecision {
        JudgeDecision(
            approved: true,
            confidence: confidence,
            feedback: JudgeFeedback(
                reason: reason,
                missingRequirements: []
            )
        )
    }

    static func rejectedDecision(
        confidence: Double = 0.41,
        reason: String = "The note mixes open questions with decisions."
    ) -> JudgeDecision {
        JudgeDecision(
            approved: false,
            confidence: confidence,
            feedback: JudgeFeedback(
                reason: reason,
                missingRequirements: [
                    "Separate tentative follow-ups from confirmed decisions."
                ]
            )
        )
    }
}

final class StubTranscriptService: TranscriptService, @unchecked Sendable {
    private(set) var callCount = 0
    var transcript: String

    init(transcript: String) {
        self.transcript = transcript
    }

    func transcribe(audioURL: URL, language: String) async throws -> String {
        callCount += 1
        return transcript
    }
}

final class StubMeetingNotesModelClient: MeetingNotesModeling, @unchecked Sendable {
    private(set) var draftCallCount = 0
    private(set) var judgeCallCount = 0
    private(set) var reviseCallCount = 0

    private var drafts: [DraftNote]
    private var decisions: [JudgeDecision]
    private var revisions: [DraftNote]

    init(drafts: [DraftNote], decisions: [JudgeDecision], revisions: [DraftNote] = []) {
        self.drafts = drafts
        self.decisions = decisions
        self.revisions = revisions
    }

    func draft(transcript: String, request: MeetingWorkflowRequest) async throws -> DraftNote {
        draftCallCount += 1
        return try popFirst(from: &drafts)
    }

    func judge(transcript: String, draft: DraftNote) async throws -> JudgeDecision {
        judgeCallCount += 1
        return try popFirst(from: &decisions)
    }

    func revise(draft: DraftNote, feedback: JudgeFeedback, request: MeetingWorkflowRequest) async throws -> DraftNote {
        reviseCallCount += 1
        return try popFirst(from: &revisions)
    }

    private func popFirst<T>(from values: inout [T]) throws -> T {
        guard !values.isEmpty else {
            throw NSError(domain: "StubMeetingNotesModelClient", code: 1)
        }
        return values.removeFirst()
    }
}
