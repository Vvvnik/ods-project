from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class HermesClient:
    model: str
    provider: str | None = None
    base_url: str | None = None
    api_key: str | None = None
    hermes_repo_path: str = "/Users/vvv/.hermes/hermes-agent"
    hermes_python_path: str | None = None
    timeout_sec: int = 120
    retry_attempts: int = 2
    skip_memory: bool = False
    skip_context_files: bool = False
    # Hermes MINIMUM_CONTEXT_LENGTH is 64000; optional override (model.context_length).
    context_length: int | None = None
    # None = все toolsets Hermes; [] = без инструментов (рекомендуется для пакетного текста).
    enabled_toolsets: list[str] | None = None
    # False: один AIAgent, история между эпиками; True: новый AIAgent (новая сессия Hermes) на каждый промпт.
    session_toggle: bool = False

    def _resolve_runtime(self) -> tuple[Path, Path]:
        repo = Path(self.hermes_repo_path).expanduser().resolve()
        if not repo.is_dir():
            raise FileNotFoundError(
                f"Hermes SDK repo not found: {repo}. "
                "Set hermes.hermes_repo_path or HERMES_REPO_PATH."
            )
        if self.hermes_python_path:
            py = Path(self.hermes_python_path).expanduser().resolve()
        else:
            prefix_cand = Path(sys.prefix).resolve() / "bin" / "python3"
            if prefix_cand.is_file():
                py = prefix_cand
            else:
                venv = os.environ.get("VIRTUAL_ENV", "").strip()
                if venv:
                    cand = Path(venv).expanduser().resolve() / "bin" / "python3"
                    py = cand if cand.is_file() else Path(sys.executable).resolve()
                else:
                    py = Path(sys.executable).resolve()
        if not py.is_file():
            raise FileNotFoundError(
                f"Hermes runtime python not found: {py}. "
                "Set hermes.hermes_python_path or HERMES_PYTHON_PATH."
            )
        return repo, py

    def generate(
        self,
        *,
        prompt: str,
        model: str | None,
        skills: list[str],
        system_instruction: str | None = None,
    ) -> str:
        results = self.generate_many(
            prompts=[prompt],
            model=model,
            skills=skills,
            system_instruction=system_instruction,
        )
        return results[0]

    def generate_many(
        self,
        *,
        prompts: list[str],
        model: str | None,
        skills: list[str],
        system_instruction: str | None = None,
    ) -> list[str]:
        if not prompts:
            return []
        effective_model = model.strip() if model and model.strip() else self.model
        repo, python_bin = self._resolve_runtime()
        runner = """
import json
import sys
from pathlib import Path

payload = json.loads(sys.stdin.read())
repo = Path(payload["repo"]).resolve()
if str(repo) not in sys.path:
    sys.path.insert(0, str(repo))

_ctx = payload.get("context_length")
if _ctx is not None:
    import hermes_cli.config as _hc_config

    _orig_load = _hc_config.load_config

    def _load_with_context_length():
        cfg = _orig_load()
        if not isinstance(cfg, dict):
            cfg = {}
        m = cfg.get("model")
        if not isinstance(m, dict):
            m = {}
            cfg["model"] = m
        m["context_length"] = int(_ctx)
        return cfg

    _hc_config.load_config = _load_with_context_length

from run_agent import AIAgent
try:
    from agent.skill_commands import build_preloaded_skills_prompt
except Exception:
    build_preloaded_skills_prompt = None

skills = payload.get("skills") or []
parts = []
system_instruction = payload.get("system_instruction")
if system_instruction:
    parts.append(str(system_instruction).strip())
if build_preloaded_skills_prompt and skills:
    skill_prompt, loaded_skills, missing = build_preloaded_skills_prompt(skills)
    if missing and "my/asciidoc" in missing:
        print(json.dumps({"ok": False, "error": "Missing required Hermes skill: my/asciidoc"}))
        raise SystemExit(2)
    if missing:
        parts.append("[SYSTEM: Optional Hermes skills not found: " + ", ".join(missing) + "]")
    if loaded_skills and skill_prompt.strip():
        parts.append(skill_prompt.strip())
elif skills:
    parts.append("Use preloaded skills with priority: " + ", ".join(skills))

ephemeral_prompt = "\\n\\n".join([p for p in parts if p]) or None

_agent_kw = dict(
    model=payload["model"],
    provider=payload.get("provider"),
    base_url=payload.get("base_url"),
    api_key=payload.get("api_key"),
    quiet_mode=True,
    skip_memory=bool(payload.get("skip_memory", False)),
    skip_context_files=bool(payload.get("skip_context_files", False)),
    ephemeral_system_prompt=ephemeral_prompt,
)
if "enabled_toolsets" in payload:
    _agent_kw["enabled_toolsets"] = payload["enabled_toolsets"]
_session_toggle = bool(payload.get("session_toggle", False))
texts = []
last_sid = None
if _session_toggle:
    # Отдельный чат на каждый эпик: новый AIAgent → новый session_id и лог.
    for prompt in payload["prompts"]:
        agent = AIAgent(**_agent_kw)
        result = agent.run_conversation(prompt, conversation_history=None)
        raw = result.get("final_response")
        texts.append("" if raw is None else str(raw).strip())
        last_sid = getattr(agent, "session_id", None)
else:
    agent = AIAgent(**_agent_kw)
    # Цепочка run_conversation: общий контекст API; один session_*.json на весь батч.
    history = None
    for prompt in payload["prompts"]:
        result = agent.run_conversation(prompt, conversation_history=history)
        raw = result.get("final_response")
        texts.append("" if raw is None else str(raw).strip())
        history = result.get("messages")
    last_sid = getattr(agent, "session_id", None)
print(json.dumps({"ok": True, "texts": texts, "session_id": last_sid}))
"""

        payload = {
            "repo": str(repo),
            "prompts": prompts,
            "model": effective_model,
            "provider": self.provider,
            "base_url": self.base_url,
            "api_key": self.api_key or os.environ.get("HERMES_API_KEY"),
            "skills": skills,
            "system_instruction": system_instruction,
            "skip_memory": self.skip_memory,
            "skip_context_files": self.skip_context_files,
            "context_length": self.context_length,
            "session_toggle": self.session_toggle,
        }
        if self.enabled_toolsets is not None:
            payload["enabled_toolsets"] = self.enabled_toolsets

        last_error: Exception | None = None
        for attempt in range(1, max(1, self.retry_attempts) + 1):
            try:
                completed = subprocess.run(
                    [str(python_bin), "-c", runner],
                    input=json.dumps(payload),
                    capture_output=True,
                    text=True,
                    timeout=self.timeout_sec,
                )
                lines = [ln.strip() for ln in (completed.stdout or "").splitlines() if ln.strip()]
                data = None
                if lines:
                    try:
                        data = json.loads(lines[-1])
                    except json.JSONDecodeError:
                        data = None

                if completed.returncode != 0:
                    stderr = (completed.stderr or "").strip()
                    stdout = (completed.stdout or "").strip()
                    details = stderr
                    if stdout:
                        details = (details + "\n" + stdout).strip() if details else stdout
                    raise RuntimeError(details or f"exit_code={completed.returncode}")

                if not isinstance(data, dict):
                    raise ValueError("Hermes SDK produced non-JSON stdout")
                if not data.get("ok"):
                    raise RuntimeError(str(data.get("error") or "Unknown Hermes SDK error"))
                texts_raw = data.get("texts")
                if not isinstance(texts_raw, list):
                    raise ValueError("Hermes SDK returned invalid response list")
                texts = [str(x).strip() for x in texts_raw]
                if len(texts) != len(prompts):
                    raise ValueError("Hermes SDK returned wrong number of responses")
                if any(not t for t in texts):
                    raise ValueError("Hermes SDK returned empty response")
                sid = data.get("session_id")
                if sid:
                    print(
                        f"Hermes session: {sid} → ~/.hermes/sessions/session_{sid}.json",
                        file=sys.stderr,
                        flush=True,
                    )
                return texts
            except Exception as exc:  # pragma: no cover - runtime/env dependent path
                last_error = exc
                if attempt >= max(1, self.retry_attempts):
                    break
                time.sleep(min(1.5 * attempt, 5.0))

        raise RuntimeError(f"Hermes SDK call failed: {last_error}")
