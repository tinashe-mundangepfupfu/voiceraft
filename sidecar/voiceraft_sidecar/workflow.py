from __future__ import annotations

from dataclasses import replace
from typing import Protocol

from voiceraft_sidecar.models import DraftNote, JudgeDecision, ProcessingRequest, WorkflowResult


class Transcriber(Protocol):
    def transcribe(self, audio_path: str, language: str) -> str: ...


class Drafter(Protocol):
    def draft(self, transcript: str, request: ProcessingRequest) -> DraftNote: ...

    def revise(self, draft: DraftNote, feedback, request: ProcessingRequest) -> DraftNote: ...


class Judge(Protocol):
    def evaluate(self, transcript: str, draft: DraftNote) -> JudgeDecision: ...


class MeetingWorkflowRunner:
    def __init__(self, transcriber: Transcriber, drafter: Drafter, judge: Judge, max_revisions: int = 2) -> None:
        self._transcriber = transcriber
        self._drafter = drafter
        self._judge = judge
        self._max_revisions = max_revisions

    def run(self, request: ProcessingRequest) -> WorkflowResult:
        transcript = self._transcriber.transcribe(request.audio_path, request.language)
        draft = self._drafter.draft(transcript, request)
        revision_count = 0
        decision = self._judge.evaluate(transcript, draft)

        while not decision.approved and revision_count < self._max_revisions:
            draft = self._drafter.revise(draft, decision.feedback, request)
            revision_count += 1
            decision = self._judge.evaluate(transcript, draft)

        status = "final" if decision.approved else "needs-review"
        frontmatter = replace(draft.frontmatter, status=status)
        return WorkflowResult(
            status=status,
            confidence=decision.confidence,
            judge_summary=decision.feedback.reason,
            frontmatter=frontmatter,
            sections=draft.sections,
            revision_count=revision_count,
        )
