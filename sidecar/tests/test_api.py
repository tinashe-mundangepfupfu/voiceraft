import unittest

from fastapi.testclient import TestClient

from voiceraft_sidecar.app import create_app
from voiceraft_sidecar.models import ActionItem, Frontmatter, MeetingNoteSections, ProcessingRequest, WorkflowResult


class StubProcessor:
    def process(self, request: ProcessingRequest) -> WorkflowResult:
        return WorkflowResult(
            status="final",
            confidence=0.94,
            judge_summary="Ready to save.",
            frontmatter=Frontmatter(
                title=request.meeting_title,
                date=request.started_at,
                meeting_mode=request.meeting_mode,
                language=request.language,
                status="final",
                tags=["meeting", "voiceraft"],
            ),
            sections=MeetingNoteSections(
                summary="The team confirmed sprint priorities.",
                key_discussion_points=["Reviewed scope and blockers."],
                decisions=["Keep the onboarding cutover date unchanged."],
                action_items=[ActionItem(task="Confirm QA sign-off", owner="Lee", due=None)],
                open_questions_or_risks=["Support readiness needs another check."],
                follow_up=["Revisit launch readiness on Thursday."],
            ),
        )


class CreateAppTests(unittest.TestCase):
    def test_process_endpoint_returns_contract_with_markdown(self) -> None:
        client = TestClient(create_app(processor=StubProcessor()))

        response = client.post(
            "/process",
            json={
                "session_id": "session-1",
                "audio_path": "/tmp/example.wav",
                "meeting_title": "Sprint Sync",
                "meeting_mode": "online",
                "language": "en",
                "started_at": "2026-03-29T10:00:00Z",
                "ended_at": "2026-03-29T10:30:00Z",
            },
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["status"], "final")
        self.assertEqual(payload["frontmatter"]["title"], "Sprint Sync")
        self.assertIn("## Summary", payload["markdown"])
        self.assertEqual(payload["sections"]["action_items"][0]["owner"], "Lee")


if __name__ == "__main__":
    unittest.main()
