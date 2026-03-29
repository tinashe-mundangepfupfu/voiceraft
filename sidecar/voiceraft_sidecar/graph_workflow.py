from __future__ import annotations

from dataclasses import replace
from typing import TypedDict

from langgraph.graph import END, START, StateGraph

from voiceraft_sidecar.models import DraftNote, JudgeDecision, ProcessingRequest, WorkflowResult
from voiceraft_sidecar.workflow import Drafter, Judge, Transcriber


class WorkflowState(TypedDict, total=False):
    request: ProcessingRequest
    transcript: str
    draft: DraftNote
    decision: JudgeDecision
    revision_count: int


class LangGraphMeetingProcessor:
    def __init__(self, transcriber: Transcriber, drafter: Drafter, judge: Judge, max_revisions: int = 2) -> None:
        self._transcriber = transcriber
        self._drafter = drafter
        self._judge = judge
        self._max_revisions = max_revisions
        self._graph = self._build_graph()

    def process(self, request: ProcessingRequest) -> WorkflowResult:
        state = self._graph.invoke({"request": request, "revision_count": 0})
        decision = state["decision"]
        draft = state["draft"]
        revision_count = state["revision_count"]
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

    def _build_graph(self):
        graph = StateGraph(WorkflowState)
        graph.add_node("transcribe", self._transcribe)
        graph.add_node("draft", self._draft)
        graph.add_node("judge", self._judge_draft)
        graph.add_node("revise", self._revise)
        graph.add_edge(START, "transcribe")
        graph.add_edge("transcribe", "draft")
        graph.add_edge("draft", "judge")
        graph.add_conditional_edges("judge", self._next_step, {"revise": "revise", "finish": END})
        graph.add_edge("revise", "judge")
        return graph.compile()

    def _transcribe(self, state: WorkflowState) -> WorkflowState:
        request = state["request"]
        transcript = self._transcriber.transcribe(request.audio_path, request.language)
        return {"transcript": transcript}

    def _draft(self, state: WorkflowState) -> WorkflowState:
        return {
            "draft": self._drafter.draft(state["transcript"], state["request"]),
        }

    def _judge_draft(self, state: WorkflowState) -> WorkflowState:
        return {
            "decision": self._judge.evaluate(state["transcript"], state["draft"]),
        }

    def _revise(self, state: WorkflowState) -> WorkflowState:
        revised = self._drafter.revise(state["draft"], state["decision"].feedback, state["request"])
        return {
            "draft": revised,
            "revision_count": state["revision_count"] + 1,
        }

    def _next_step(self, state: WorkflowState) -> str:
        if state["decision"].approved:
            return "finish"
        if state["revision_count"] >= self._max_revisions:
            return "finish"
        return "revise"
