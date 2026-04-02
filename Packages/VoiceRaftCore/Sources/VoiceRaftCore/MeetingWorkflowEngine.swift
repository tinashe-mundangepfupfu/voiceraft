import Foundation

public struct MeetingWorkflowEngine: Sendable {
    private let transcriptService: any TranscriptService
    private let modelClient: any MeetingNotesModeling
    private let markdownRenderer: any MarkdownRendering
    private let maxRevisions: Int

    public init(
        transcriptService: any TranscriptService,
        modelClient: any MeetingNotesModeling,
        markdownRenderer: any MarkdownRendering = MarkdownRenderer(),
        maxRevisions: Int = 2
    ) {
        self.transcriptService = transcriptService
        self.modelClient = modelClient
        self.markdownRenderer = markdownRenderer
        self.maxRevisions = maxRevisions
    }

    public func process(request: MeetingWorkflowRequest) async throws -> MeetingWorkflowResult {
        let transcript = try await transcriptService.transcribe(audioURL: request.audioURL, language: request.language)
        var draft = try await modelClient.draft(transcript: transcript, request: request)
        var decision = try await modelClient.judge(transcript: transcript, draft: draft)
        var revisionCount = 0

        while !decision.approved, revisionCount < maxRevisions {
            draft = try await modelClient.revise(draft: draft, feedback: decision.feedback, request: request)
            revisionCount += 1
            decision = try await modelClient.judge(transcript: transcript, draft: draft)
        }

        let status: MeetingWorkflowStatus = decision.approved ? .final : .needsReview
        let frontmatter = draft.frontmatter.withStatus(status)
        let pendingResult = MeetingWorkflowResult(
            status: status,
            confidence: decision.confidence,
            judgeSummary: decision.feedback.reason,
            frontmatter: frontmatter,
            sections: draft.sections,
            markdown: "",
            revisionCount: revisionCount
        )

        return MeetingWorkflowResult(
            status: status,
            confidence: decision.confidence,
            judgeSummary: decision.feedback.reason,
            frontmatter: frontmatter,
            sections: draft.sections,
            markdown: markdownRenderer.render(result: pendingResult),
            revisionCount: revisionCount
        )
    }
}
