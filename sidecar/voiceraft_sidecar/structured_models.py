from __future__ import annotations

from pydantic import BaseModel, Field


class ActionItemOutput(BaseModel):
    task: str = Field(description="Short action item phrasing suitable for professional meeting minutes.")
    owner: str | None = Field(
        default=None,
        description="Explicit owner only when stated or strongly inferable from the transcript.",
    )
    due: str | None = Field(default=None, description="Due date only when clearly grounded in the transcript.")


class DraftNoteOutput(BaseModel):
    summary: str = Field(description="Two to four sentences summarizing the meeting outcome.")
    key_discussion_points: list[str] = Field(description="Important discussion bullets grounded in the transcript.")
    decisions: list[str] = Field(description="Confirmed decisions only, not open questions.")
    action_items: list[ActionItemOutput] = Field(description="Action items with owners only when explicit.")
    open_questions_or_risks: list[str] = Field(description="Outstanding risks, blockers, or unresolved questions.")
    follow_up: list[str] = Field(description="Concrete next follow-up moments or checks.")


class JudgeDecisionOutput(BaseModel):
    approved: bool = Field(description="Whether the note is safe to auto-save as final.")
    confidence: float = Field(ge=0.0, le=1.0, description="Confidence in the judge decision.")
    reason: str = Field(description="One concise explanation for the decision.")
    missing_requirements: list[str] = Field(
        default_factory=list,
        description="Specific rubric issues that should be fixed before the note is final.",
    )
