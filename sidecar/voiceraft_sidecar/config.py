from __future__ import annotations

from dataclasses import dataclass
from os import environ
from typing import Mapping


@dataclass(slots=True)
class ServerConfig:
    host: str = "127.0.0.1"
    port: int = 8765


@dataclass(slots=True)
class LMStudioConfig:
    base_url: str = "http://127.0.0.1:1234/v1"
    model: str = "qwen2.5-7b-instruct"
    api_key: str = "lm-studio"
    temperature: float = 0.0


@dataclass(slots=True)
class WhisperConfig:
    model: str = "small.en"
    device: str = "auto"
    compute_type: str = "int8"


@dataclass(slots=True)
class SidecarConfig:
    server: ServerConfig
    lm_studio: LMStudioConfig
    whisper: WhisperConfig
    max_revisions: int = 2


def load_config(env: Mapping[str, str] | None = None) -> SidecarConfig:
    values = dict(environ if env is None else env)
    return SidecarConfig(
        server=ServerConfig(
            host=values.get("VOICERAFT_HOST", "127.0.0.1"),
            port=int(values.get("VOICERAFT_PORT", "8765")),
        ),
        lm_studio=LMStudioConfig(
            base_url=values.get("VOICERAFT_LM_STUDIO_BASE_URL", "http://127.0.0.1:1234/v1"),
            model=values.get("VOICERAFT_LM_STUDIO_MODEL", "qwen2.5-7b-instruct"),
            api_key=values.get("VOICERAFT_LM_STUDIO_API_KEY", "lm-studio"),
            temperature=float(values.get("VOICERAFT_LM_STUDIO_TEMPERATURE", "0.0")),
        ),
        whisper=WhisperConfig(
            model=values.get("VOICERAFT_WHISPER_MODEL", "small.en"),
            device=values.get("VOICERAFT_WHISPER_DEVICE", "auto"),
            compute_type=values.get("VOICERAFT_WHISPER_COMPUTE_TYPE", "int8"),
        ),
        max_revisions=int(values.get("VOICERAFT_MAX_REVISIONS", "2")),
    )
