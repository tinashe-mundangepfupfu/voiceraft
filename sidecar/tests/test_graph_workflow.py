import unittest

from voiceraft_sidecar.graph_workflow import LangGraphMeetingProcessor
from voiceraft_sidecar.models import (
    ActionItem,
    DraftNote,
    Frontmatter,
    JudgeDecision,
    JudgeFeedback,
    MeetingNoteSections,
    ProcessingRequest,
)


class FakeTranscriber:
    def transcribe(self, audio_path: str, language: str) -> str:
        return "Lee will confirm QA sign-off and the team will keep the cutover date."


class FakeDrafter:
    def __init__(self) -> None:
        self.revisions = 0

    def draft(self, transcript: str, request: ProcessingRequest) -> DraftNote:
        return DraftNote(
            frontmatter=Frontmatter(
                title=request.meeting_title,
                date=request.started_at,
                meeting_mode=request.meeting_mode,
                language=request.language,
                status="final",
                tags=["meeting"],
            ),
            sections=MeetingNoteSections(
                summary="The team confirmed the launch remains on track.",
                key_discussion_points=["Reviewed QA and cutover readiness."],
                decisions=["Keep the current cutover date."],
                action_items=[
                    ActionItem(
                        task="Confirm QA sign-off",
                        owner="Lee" if self.revisions else None,
                        due=None,
                    )
                ],
                open_questions_or_risks=["Support readiness still needs a final check."],
                follow_up=["Confirm launch checklist completion on Thursday."],
            ),
        )

    def revise(self, draft: DraftNote, feedback: JudgeFeedback, request: ProcessingRequest) -> DraftNote:
        self.revisions += 1
        return self.draft("ignored", request)


class FakeJudge:
    def __init__(self) -> None:
        self.calls = 0

    def evaluate(self, transcript: str, draft: DraftNote) -> JudgeDecision:
        self.calls += 1
        if self.calls == 1:
            return JudgeDecision(
                approved=False,
                confidence=0.5,
                feedback=JudgeFeedback(
                    reason="The explicit QA owner must be named in the action items.",
                    missing_requirements=["Carry explicit owners into action items."],
                ),
            )

        return JudgeDecision(
            approved=True,
            confidence=0.96,
            feedback=JudgeFeedback(reason="Approved.", missing_requirements=[]),
        )


class LangGraphMeetingProcessorTests(unittest.TestCase):
    def test_process_runs_transcribe_draft_judge_and_revision_loop(self) -> None:
        processor = LangGraphMeetingProcessor(
            transcriber=FakeTranscriber(),
            drafter=FakeDrafter(),
            judge=FakeJudge(),
            max_revisions=2,
        )
        request = ProcessingRequest(
            session_id="session-graph-1",
            audio_path="/tmp/example.wav",
            meeting_title="Launch Readiness Review",
            meeting_mode="online",
            language="en",
            started_at="2026-03-29T14:00:00Z",
            ended_at="2026-03-29T14:30:00Z",
        )

        result = processor.process(request)

        self.assertEqual(result.status, "final")
        self.assertEqual(result.revision_count, 1)
        self.assertEqual(result.sections.action_items[0].owner, "Lee")
        self.assertEqual(result.judge_summary, "Approved.")


if __name__ == "__main__":
    unittest.main()
