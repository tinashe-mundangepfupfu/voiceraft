import os
import unittest

from voiceraft_sidecar.config import SidecarConfig, load_config


class LoadConfigTests(unittest.TestCase):
    def test_loads_expected_local_defaults(self) -> None:
        config = load_config({})

        self.assertEqual(config.server.port, 8765)
        self.assertEqual(config.lm_studio.base_url, "http://127.0.0.1:1234/v1")
        self.assertEqual(config.whisper.model, "small.en")
        self.assertEqual(config.max_revisions, 2)

    def test_respects_environment_overrides(self) -> None:
        env = {
            "VOICERAFT_PORT": "9900",
            "VOICERAFT_LM_STUDIO_MODEL": "qwen3-8b",
            "VOICERAFT_WHISPER_MODEL": "medium.en",
        }

        config = load_config(env)

        self.assertEqual(config.server.port, 9900)
        self.assertEqual(config.lm_studio.model, "qwen3-8b")
        self.assertEqual(config.whisper.model, "medium.en")


if __name__ == "__main__":
    unittest.main()
