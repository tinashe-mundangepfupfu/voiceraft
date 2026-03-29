from __future__ import annotations

import uvicorn

from voiceraft_sidecar.config import load_config
from voiceraft_sidecar.factory import create_default_app


def main() -> None:
    config = load_config()
    app = create_default_app(config)
    uvicorn.run(app, host=config.server.host, port=config.server.port, log_level="info")


if __name__ == "__main__":
    main()
