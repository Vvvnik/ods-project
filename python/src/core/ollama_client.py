from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import ollama


@dataclass(frozen=True)
class OllamaClient:
    host: str

    def _client(self) -> Any:
        return ollama.Client(host=self.host)

    def generate(self, prompt: str, model: str, temperature: float = 0.2) -> str:
        client = self._client()
        resp = client.generate(
            model=model,
            prompt=prompt,
            stream=False,
            options={"temperature": temperature},
        )
        return str(resp.get("response", "")).strip()
