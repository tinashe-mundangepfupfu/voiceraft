from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal


WorkflowStatus = Literal["final", "needs-review"]
MeetingMode = Literal["room", "online"]


@dataclass(slots=True)
class ActionItem:
    task: str
    owner: str | None
    due: str | None


@dataclass(slots=True)
class MeetingNoteSections:
    summary: str
    key_discussion_points: list[str]
    decisions: list[str]
    action_items: list[ActionItem]
    open_questions_or_risks: list[str]
    follow_up: list[str]


@dataclass(slots=True)
class Frontmatter:
    title: str
    date: str
    meeting_mode: MeetingMode
    language: str
    status: WorkflowStatus
    tags: list[str]


@dataclass(slots=True)
class DraftNote:
    frontmatter: Frontmatter
    sections: MeetingNoteSections


@dataclass(slots=True)
class JudgeFeedback:
    reason: str
    missing_requirements: list[str] = field(default_factory=list)


@dataclass(slots=True)
class JudgeDecision:
    approved: bool
    confidence: float
    feedback: JudgeFeedback


@dataclass(slots=True)
class ProcessingRequest:
    session_id: str
    audio_path: str
    meeting_title: str
    meeting_mode: MeetingMode
    language: str
    started_at: str
    ended_at: str


@dataclass(slots=True)
class WorkflowResult:
    status: WorkflowStatus
    confidence: float
    judge_summary: str
    frontmatter: Frontmatter
    sections: MeetingNoteSections
    revision_count: int = 0
