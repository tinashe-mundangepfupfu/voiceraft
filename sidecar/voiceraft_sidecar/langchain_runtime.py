from __future__ import annotations

import json

from langchain_core.prompts import ChatPromptTemplate
from langchain_openai import ChatOpenAI

from voiceraft_sidecar.config import LMStudioConfig
from voiceraft_sidecar.models import (
    ActionItem,
    DraftNote,
    Frontmatter,
    JudgeDecision,
    JudgeFeedback,
    MeetingNoteSections,
    ProcessingRequest,
)
from voiceraft_sidecar.structured_models import DraftNoteOutput, JudgeDecisionOutput


def create_chat_model(config: LMStudioConfig) -> ChatOpenAI:
    return ChatOpenAI(
        model=config.model,
        base_url=config.base_url,
        api_key=config.api_key,
        temperature=config.temperature,
        max_retries=1,
    )


class LangChainMeetingDrafter:
    def __init__(self, llm: ChatOpenAI, structured_method: str = "json_mode") -> None:
        self._draft_chain = (
            ChatPromptTemplate.from_messages(
                [
                    (
                        "system",
                        "You write informative, professional meeting minutes. "
                        "Only use information grounded in the transcript. "
                        "Keep decisions separate from open questions. "
                        "Only assign an owner when explicitly stated or strongly inferable.",
                    ),
                    (
                        "user",
                        "Meeting title: {meeting_title}\n"
                        "Meeting mode: {meeting_mode}\n"
                        "Language: {language}\n"
                        "Transcript:\n{transcript}",
                    ),
                ]
            )
            | llm.with_structured_output(DraftNoteOutput, method=structured_method)
        )
        self._revise_chain = (
            ChatPromptTemplate.from_messages(
                [
                    (
                        "system",
                        "Revise the meeting note so it passes the review rubric. "
                        "Do not invent facts. Keep tone professional and concise.",
                    ),
                    (
                        "user",
                        "Meeting title: {meeting_title}\n"
                        "Meeting mode: {meeting_mode}\n"
                        "Language: {language}\n"
                        "Existing note draft:\n{draft_json}\n"
                        "Judge feedback:\n{feedback_json}",
                    ),
                ]
            )
            | llm.with_structured_output(DraftNoteOutput, method=structured_method)
        )

    def draft(self, transcript: str, request: ProcessingRequest) -> DraftNote:
        output = self._draft_chain.invoke(
            {
                "meeting_title": request.meeting_title,
                "meeting_mode": request.meeting_mode,
                "language": request.language,
                "transcript": transcript,
            }
        )
        return _draft_output_to_domain(output, request)

    def revise(self, draft: DraftNote, feedback: JudgeFeedback, request: ProcessingRequest) -> DraftNote:
        output = self._revise_chain.invoke(
            {
                "meeting_title": request.meeting_title,
                "meeting_mode": request.meeting_mode,
                "language": request.language,
                "draft_json": json.dumps(_draft_to_payload(draft), indent=2),
                "feedback_json": json.dumps(
                    {
                        "reason": feedback.reason,
                        "missing_requirements": list(feedback.missing_requirements),
                    },
                    indent=2,
                ),
            }
        )
        return _draft_output_to_domain(output, request)


class LangChainMeetingJudge:
    def __init__(self, llm: ChatOpenAI, structured_method: str = "json_mode") -> None:
        self._judge_chain = (
            ChatPromptTemplate.from_messages(
                [
                    (
                        "system",
                        "Judge the meeting note against this rubric: "
                        "1) no unsupported claims, "
                        "2) decisions and open questions are clearly separated, "
                        "3) action items include owners only when explicit or strongly inferable, "
                        "4) tone is professional and concise, "
                        "5) uncertainty is labeled rather than guessed. "
                        "Approve only when the note is safe to auto-save.",
                    ),
                    (
                        "user",
                        "Transcript:\n{transcript}\n\n"
                        "Candidate note:\n{draft_json}",
                    ),
                ]
            )
            | llm.with_structured_output(JudgeDecisionOutput, method=structured_method)
        )

    def evaluate(self, transcript: str, draft: DraftNote) -> JudgeDecision:
        output = self._judge_chain.invoke(
            {
                "transcript": transcript,
                "draft_json": json.dumps(_draft_to_payload(draft), indent=2),
            }
        )
        return JudgeDecision(
            approved=output.approved,
            confidence=output.confidence,
            feedback=JudgeFeedback(
                reason=output.reason,
                missing_requirements=list(output.missing_requirements),
            ),
        )


def _draft_output_to_domain(output: DraftNoteOutput, request: ProcessingRequest) -> DraftNote:
    return DraftNote(
        frontmatter=Frontmatter(
            title=request.meeting_title,
            date=request.started_at,
            meeting_mode=request.meeting_mode,
            language=request.language,
            status="final",
            tags=["meeting", request.meeting_mode],
        ),
        sections=MeetingNoteSections(
            summary=output.summary,
            key_discussion_points=list(output.key_discussion_points),
            decisions=list(output.decisions),
            action_items=[
                ActionItem(task=item.task, owner=item.owner, due=item.due)
                for item in output.action_items
            ],
            open_questions_or_risks=list(output.open_questions_or_risks),
            follow_up=list(output.follow_up),
        ),
    )


def _draft_to_payload(draft: DraftNote) -> dict[str, object]:
    return {
        "title": draft.frontmatter.title,
        "summary": draft.sections.summary,
        "key_discussion_points": list(draft.sections.key_discussion_points),
        "decisions": list(draft.sections.decisions),
        "action_items": [
            {
                "task": item.task,
                "owner": item.owner,
                "due": item.due,
            }
            for item in draft.sections.action_items
        ],
        "open_questions_or_risks": list(draft.sections.open_questions_or_risks),
        "follow_up": list(draft.sections.follow_up),
    }
