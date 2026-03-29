from __future__ import annotations

from voiceraft_sidecar.models import ActionItem, WorkflowResult


def _render_frontmatter(result: WorkflowResult) -> list[str]:
    tags = ", ".join(result.frontmatter.tags)
    return [
        "---",
        f"title: {result.frontmatter.title}",
        f"date: {result.frontmatter.date}",
        f"meeting_mode: {result.frontmatter.meeting_mode}",
        f"language: {result.frontmatter.language}",
        f"status: {result.frontmatter.status}",
        f"tags: [{tags}]",
        "---",
        "",
    ]


def _render_bullets(items: list[str]) -> list[str]:
    if not items:
        return ["- None"]
    return [f"- {item}" for item in items]


def _render_action_items(items: list[ActionItem]) -> list[str]:
    if not items:
        return ["- None"]

    lines: list[str] = []
    for item in items:
        detail = [f"Owner: {item.owner or 'Unassigned'}"]
        if item.due:
            detail.append(f"Due: {item.due}")
        lines.append(f"- {item.task} ({', '.join(detail)})")
    return lines


def build_markdown(result: WorkflowResult) -> str:
    sections = result.sections
    lines = _render_frontmatter(result)

    if result.status == "needs-review":
        lines.extend(
            [
                f"> Review recommended: {result.judge_summary}",
                "",
            ]
        )

    lines.extend(
        [
            "## Summary",
            sections.summary,
            "",
            "## Key Discussion Points",
            *_render_bullets(sections.key_discussion_points),
            "",
            "## Decisions",
            *_render_bullets(sections.decisions),
            "",
            "## Action Items",
            *_render_action_items(sections.action_items),
            "",
            "## Open Questions / Risks",
            *_render_bullets(sections.open_questions_or_risks),
            "",
            "## Follow-Up",
            *_render_bullets(sections.follow_up),
            "",
        ]
    )
    return "\n".join(lines)
