from __future__ import annotations

from voiceraft_sidecar.app import create_app
from voiceraft_sidecar.config import SidecarConfig, load_config
from voiceraft_sidecar.graph_workflow import LangGraphMeetingProcessor
from voiceraft_sidecar.langchain_runtime import (
    LangChainMeetingDrafter,
    LangChainMeetingJudge,
    create_chat_model,
)
from voiceraft_sidecar.transcriber import FasterWhisperTranscriber


def build_processor(config: SidecarConfig | None = None) -> LangGraphMeetingProcessor:
    resolved = config or load_config()
    llm = create_chat_model(resolved.lm_studio)
    return LangGraphMeetingProcessor(
        transcriber=FasterWhisperTranscriber(resolved.whisper),
        drafter=LangChainMeetingDrafter(llm),
        judge=LangChainMeetingJudge(llm),
        max_revisions=resolved.max_revisions,
    )


def create_default_app(config: SidecarConfig | None = None):
    resolved = config or load_config()
    return create_app(processor=build_processor(resolved))
