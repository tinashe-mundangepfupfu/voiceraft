from __future__ import annotations

from typing import Protocol

from fastapi import FastAPI

from voiceraft_sidecar.api_models import ProcessingRequestModel, WorkflowResultModel
from voiceraft_sidecar.models import ProcessingRequest, WorkflowResult


class Processor(Protocol):
    def process(self, request: ProcessingRequest) -> WorkflowResult: ...


def create_app(processor: Processor) -> FastAPI:
    app = FastAPI(title="VoiceRaft Sidecar", version="0.1.0")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/process", response_model=WorkflowResultModel)
    def process(request: ProcessingRequestModel) -> WorkflowResultModel:
        result = processor.process(request.to_domain())
        return WorkflowResultModel.from_domain(result)

    return app
