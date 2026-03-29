import unittest

from voiceraft_sidecar.markdown import build_markdown
from voiceraft_sidecar.models import ActionItem, Frontmatter, MeetingNoteSections, WorkflowResult


class BuildMarkdownTests(unittest.TestCase):
    def test_renders_frontmatter_sections_and_warning_for_review_notes(self) -> None:
        result = WorkflowResult(
            status="needs-review",
            confidence=0.42,
            judge_summary="The summary is solid, but one action owner is missing.",
            frontmatter=Frontmatter(
                title="Weekly Product Sync",
                date="2026-03-29T10:00:00Z",
                meeting_mode="online",
                language="en",
                status="needs-review",
                tags=["meeting", "product"],
            ),
            sections=MeetingNoteSections(
                summary="The team aligned on the April launch scope and risks.",
                key_discussion_points=[
                    "Reviewed launch blockers for onboarding.",
                    "Agreed to postpone template customization until May.",
                ],
                decisions=[
                    "Ship onboarding analytics in the April release.",
                ],
                action_items=[
                    ActionItem(task="Finalize onboarding copy", owner="Sam", due="2026-03-31"),
                ],
                open_questions_or_risks=[
                    "Support workload may spike during launch week.",
                ],
                follow_up=[
                    "Check analytics instrumentation in the next sync.",
                ],
            ),
        )

        markdown = build_markdown(result)

        self.assertIn("title: Weekly Product Sync", markdown)
        self.assertIn("status: needs-review", markdown)
        self.assertIn("> Review recommended: The summary is solid", markdown)
        self.assertIn("## Summary", markdown)
        self.assertIn("- Finalize onboarding copy", markdown)
        self.assertIn("Owner: Sam", markdown)


if __name__ == "__main__":
    unittest.main()
