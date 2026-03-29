from __future__ import annotations

from pydantic import BaseModel, Field

from voiceraft_sidecar.markdown import build_markdown
from voiceraft_sidecar.models import (
    ActionItem,
    Frontmatter,
    MeetingNoteSections,
    ProcessingRequest,
    WorkflowResult,
)


class ProcessingRequestModel(BaseModel):
    session_id: str
    audio_path: str
    meeting_title: str
    meeting_mode: str
    language: str
    started_at: str
    ended_at: str

    def to_domain(self) -> ProcessingRequest:
        return ProcessingRequest(
            session_id=self.session_id,
            audio_path=self.audio_path,
            meeting_title=self.meeting_title,
            meeting_mode=self.meeting_mode,
            language=self.language,
            started_at=self.started_at,
            ended_at=self.ended_at,
        )


class ActionItemModel(BaseModel):
    task: str
    owner: str | None = None
    due: str | None = None

    @classmethod
    def from_domain(cls, item: ActionItem) -> "ActionItemModel":
        return cls(task=item.task, owner=item.owner, due=item.due)


class FrontmatterModel(BaseModel):
    title: str
    date: str
    meeting_mode: str
    language: str
    status: str
    tags: list[str] = Field(default_factory=list)

    @classmethod
    def from_domain(cls, frontmatter: Frontmatter) -> "FrontmatterModel":
        return cls(
            title=frontmatter.title,
            date=frontmatter.date,
            meeting_mode=frontmatter.meeting_mode,
            language=frontmatter.language,
            status=frontmatter.status,
            tags=list(frontmatter.tags),
        )


class MeetingNoteSectionsModel(BaseModel):
    summary: str
    key_discussion_points: list[str]
    decisions: list[str]
    action_items: list[ActionItemModel]
    open_questions_or_risks: list[str]
    follow_up: list[str]

    @classmethod
    def from_domain(cls, sections: MeetingNoteSections) -> "MeetingNoteSectionsModel":
        return cls(
            summary=sections.summary,
            key_discussion_points=list(sections.key_discussion_points),
            decisions=list(sections.decisions),
            action_items=[ActionItemModel.from_domain(item) for item in sections.action_items],
            open_questions_or_risks=list(sections.open_questions_or_risks),
            follow_up=list(sections.follow_up),
        )


class WorkflowResultModel(BaseModel):
    status: str
    confidence: float
    judge_summary: str
    frontmatter: FrontmatterModel
    sections: MeetingNoteSectionsModel
    markdown: str

    @classmethod
    def from_domain(cls, result: WorkflowResult) -> "WorkflowResultModel":
        return cls(
            status=result.status,
            confidence=result.confidence,
            judge_summary=result.judge_summary,
            frontmatter=FrontmatterModel.from_domain(result.frontmatter),
            sections=MeetingNoteSectionsModel.from_domain(result.sections),
            markdown=build_markdown(result),
        )
