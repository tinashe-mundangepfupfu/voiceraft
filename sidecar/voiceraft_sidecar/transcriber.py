from __future__ import annotations

from faster_whisper import WhisperModel

from voiceraft_sidecar.config import WhisperConfig


class FasterWhisperTranscriber:
    def __init__(self, config: WhisperConfig) -> None:
        self._config = config
        self._model: WhisperModel | None = None

    def transcribe(self, audio_path: str, language: str) -> str:
        model = self._ensure_model()
        segments, _info = model.transcribe(
            audio_path,
            language=language,
            beam_size=5,
            vad_filter=True,
        )
        text = " ".join(segment.text.strip() for segment in segments if segment.text.strip())
        normalized = " ".join(text.split())
        if not normalized:
            raise ValueError("Transcription produced no usable text.")
        return normalized

    def _ensure_model(self) -> WhisperModel:
        if self._model is None:
            self._model = WhisperModel(
                self._config.model,
                device=self._config.device,
                compute_type=self._config.compute_type,
            )
        return self._model
