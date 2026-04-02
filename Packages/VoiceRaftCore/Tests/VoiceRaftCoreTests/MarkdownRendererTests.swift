import XCTest
@testable import VoiceRaftCore

final class MarkdownRendererTests: XCTestCase {
    func testRenderMatchesCurrentSectionLayout() {
        let draft = Fixtures.draftNote()
        let result = MeetingWorkflowResult(
            status: .final,
            confidence: 0.93,
            judgeSummary: "Looks good.",
            frontmatter: draft.frontmatter,
            sections: draft.sections,
            markdown: "",
            revisionCount: 0
        )

        let markdown = MarkdownRenderer().render(result: result)

        XCTAssertEqual(
            markdown,
            """
            ---
            title: Weekly Sync
            date: 2026-03-31T09:00:00Z
            meeting_mode: room
            language: en
            status: final
            tags: [meeting, room]
            ---

            ## Summary
            The team aligned on launch readiness.

            ## Key Discussion Points
            - Reviewed launch checklist.

            ## Decisions
            - Launch remains on schedule.

            ## Action Items
            - Send final checklist (Owner: Alice, Due: 2026-04-01)

            ## Open Questions / Risks
            - Need confirmation from support.

            ## Follow-Up
            - Review status tomorrow.
            """
        )
    }

    func testRenderIncludesNeedsReviewBanner() {
        let draft = Fixtures.draftNote()
        let result = MeetingWorkflowResult(
            status: .needsReview,
            confidence: 0.42,
            judgeSummary: "Needs clearer uncertainty labeling.",
            frontmatter: Frontmatter(
                title: draft.frontmatter.title,
                date: draft.frontmatter.date,
                meetingMode: draft.frontmatter.meetingMode,
                language: draft.frontmatter.language,
                status: .needsReview,
                tags: draft.frontmatter.tags
            ),
            sections: draft.sections,
            markdown: "",
            revisionCount: 2
        )

        let markdown = MarkdownRenderer().render(result: result)

        XCTAssertTrue(markdown.contains("> Review recommended: Needs clearer uncertainty labeling."))
        XCTAssertTrue(markdown.contains("status: needs-review"))
    }
}
