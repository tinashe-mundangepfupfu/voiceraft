import XCTest
@testable import VoiceRaftCore

final class MeetingWorkflowEngineTests: XCTestCase {
    func testProcessReturnsFinalWhenJudgeApprovesInitialDraft() async throws {
        let transcriptService = StubTranscriptService(transcript: "Alice confirmed the launch is on schedule.")
        let modelClient = StubMeetingNotesModelClient(
            drafts: [Fixtures.draftNote()],
            decisions: [Fixtures.approvedDecision()]
        )
        let engine = MeetingWorkflowEngine(
            transcriptService: transcriptService,
            modelClient: modelClient,
            maxRevisions: 2
        )

        let result = try await engine.process(request: Fixtures.request())

        XCTAssertEqual(result.status, .final)
        XCTAssertEqual(result.revisionCount, 0)
        XCTAssertEqual(transcriptService.callCount, 1)
        XCTAssertEqual(modelClient.draftCallCount, 1)
        XCTAssertEqual(modelClient.judgeCallCount, 1)
        XCTAssertEqual(modelClient.reviseCallCount, 0)
        XCTAssertEqual(result.sections.summary, "The team aligned on launch readiness.")
        XCTAssertTrue(result.markdown.contains("## Summary"))
    }

    func testProcessRevisesUntilJudgeApproves() async throws {
        let transcriptService = StubTranscriptService(transcript: "The team debated support timing.")
        let modelClient = StubMeetingNotesModelClient(
            drafts: [Fixtures.draftNote(summary: "Initial draft.")],
            decisions: [
                Fixtures.rejectedDecision(),
                Fixtures.approvedDecision(reason: "Revision fixed the separation problem."),
            ],
            revisions: [
                Fixtures.draftNote(summary: "Revised draft.")
            ]
        )
        let engine = MeetingWorkflowEngine(
            transcriptService: transcriptService,
            modelClient: modelClient,
            maxRevisions: 2
        )

        let result = try await engine.process(request: Fixtures.request())

        XCTAssertEqual(result.status, .final)
        XCTAssertEqual(result.revisionCount, 1)
        XCTAssertEqual(modelClient.judgeCallCount, 2)
        XCTAssertEqual(modelClient.reviseCallCount, 1)
        XCTAssertEqual(result.sections.summary, "Revised draft.")
    }

    func testProcessReturnsNeedsReviewAfterRetryLimit() async throws {
        let transcriptService = StubTranscriptService(transcript: "The team left open ownership questions.")
        let modelClient = StubMeetingNotesModelClient(
            drafts: [Fixtures.draftNote(summary: "Draft with unsupported claims.")],
            decisions: [
                Fixtures.rejectedDecision(reason: "Missing uncertainty labels."),
                Fixtures.rejectedDecision(reason: "Still mixes assumptions with facts."),
                Fixtures.rejectedDecision(reason: "Retry limit reached."),
            ],
            revisions: [
                Fixtures.draftNote(summary: "Revision one."),
                Fixtures.draftNote(summary: "Revision two."),
            ]
        )
        let engine = MeetingWorkflowEngine(
            transcriptService: transcriptService,
            modelClient: modelClient,
            maxRevisions: 2
        )

        let result = try await engine.process(request: Fixtures.request())

        XCTAssertEqual(result.status, .needsReview)
        XCTAssertEqual(result.revisionCount, 2)
        XCTAssertEqual(modelClient.judgeCallCount, 3)
        XCTAssertEqual(modelClient.reviseCallCount, 2)
        XCTAssertEqual(result.frontmatter.status, .needsReview)
        XCTAssertTrue(result.markdown.contains("> Review recommended: Retry limit reached."))
    }
}
