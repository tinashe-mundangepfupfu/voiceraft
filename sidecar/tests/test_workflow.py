import unittest

from voiceraft_sidecar.models import (
    ActionItem,
    DraftNote,
    Frontmatter,
    JudgeDecision,
    JudgeFeedback,
    MeetingNoteSections,
    ProcessingRequest,
)
from voiceraft_sidecar.workflow import MeetingWorkflowRunner


class FakeTranscriber:
    def transcribe(self, audio_path: str, language: str) -> str:
        return "Sam will finalize onboarding copy before Tuesday."


class FakeDraftGenerator:
    def __init__(self) -> None:
        self.revision_feedback: list[str] = []

    def draft(self, transcript: str, request: ProcessingRequest) -> DraftNote:
        if not self.revision_feedback:
            action_items = [ActionItem(task="Finalize onboarding copy", owner=None, due=None)]
        else:
            action_items = [ActionItem(task="Finalize onboarding copy", owner="Sam", due=None)]

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
                summary="The team reviewed launch readiness.",
                key_discussion_points=["Discussed onboarding copy readiness."],
                decisions=["Proceed with launch preparation."],
                action_items=action_items,
                open_questions_or_risks=["Copy review timing remains tight."],
                follow_up=["Confirm final copy in the next sync."],
            ),
        )

    def revise(self, draft: DraftNote, feedback: JudgeFeedback, request: ProcessingRequest) -> DraftNote:
        self.revision_feedback.append(feedback.reason)
        return self.draft("ignored", request)


class FakeJudge:
    def __init__(self) -> None:
        self.calls = 0

    def evaluate(self, transcript: str, draft: DraftNote) -> JudgeDecision:
        self.calls += 1
        if self.calls == 1:
            return JudgeDecision(
                approved=False,
                confidence=0.45,
                feedback=JudgeFeedback(
                    reason="Owner missing for an explicit action item.",
                    missing_requirements=["Action items should include explicit owners when available."],
                ),
            )

        return JudgeDecision(
            approved=True,
            confidence=0.92,
            feedback=JudgeFeedback(reason="Looks good.", missing_requirements=[]),
        )


class MeetingWorkflowRunnerTests(unittest.TestCase):
    def test_revises_once_then_returns_final_result(self) -> None:
        request = ProcessingRequest(
            session_id="session-1",
            audio_path="/tmp/example.wav",
            meeting_title="Weekly Product Sync",
            meeting_mode="online",
            language="en",
            started_at="2026-03-29T10:00:00Z",
            ended_at="2026-03-29T10:30:00Z",
        )
        drafter = FakeDraftGenerator()
        judge = FakeJudge()
        runner = MeetingWorkflowRunner(
            transcriber=FakeTranscriber(),
            drafter=drafter,
            judge=judge,
            max_revisions=2,
        )

        result = runner.run(request)

        self.assertEqual(result.status, "final")
        self.assertEqual(result.frontmatter.status, "final")
        self.assertEqual(result.sections.action_items[0].owner, "Sam")
        self.assertEqual(result.revision_count, 1)
        self.assertEqual(judge.calls, 2)
        self.assertEqual(drafter.revision_feedback, ["Owner missing for an explicit action item."])

    def test_marks_result_for_review_after_revision_budget_is_exhausted(self) -> None:
        class AlwaysRejectJudge:
            def evaluate(self, transcript: str, draft: DraftNote) -> JudgeDecision:
                return JudgeDecision(
                    approved=False,
                    confidence=0.31,
                    feedback=JudgeFeedback(
                        reason="Still too vague about risk ownership.",
                        missing_requirements=["Clarify the owner for launch risk mitigation."],
                    ),
                )

        request = ProcessingRequest(
            session_id="session-2",
            audio_path="/tmp/example.wav",
            meeting_title="Launch Risk Review",
            meeting_mode="room",
            language="en",
            started_at="2026-03-29T11:00:00Z",
            ended_at="2026-03-29T11:30:00Z",
        )
        runner = MeetingWorkflowRunner(
            transcriber=FakeTranscriber(),
            drafter=FakeDraftGenerator(),
            judge=AlwaysRejectJudge(),
            max_revisions=2,
        )

        result = runner.run(request)

        self.assertEqual(result.status, "needs-review")
        self.assertEqual(result.frontmatter.status, "needs-review")
        self.assertEqual(result.revision_count, 2)
        self.assertEqual(result.judge_summary, "Still too vague about risk ownership.")


if __name__ == "__main__":
    unittest.main()
