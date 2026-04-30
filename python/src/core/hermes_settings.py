from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

import yaml

_ENV_PATTERN = re.compile(r"\$\{([^}:]+)(?::-([^}]*))?\}")

PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _expand_env_in_obj(obj: Any) -> Any:
    def expand_str(s: str) -> str:
        def repl(m: re.Match[str]) -> str:
            key = m.group(1)
            default = m.group(2)
            if default is not None:
                return os.environ.get(key, default)
            return os.environ.get(key, "")

        return _ENV_PATTERN.sub(repl, s)

    if isinstance(obj, str):
        return expand_str(obj)
    if isinstance(obj, dict):
        return {k: _expand_env_in_obj(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_expand_env_in_obj(v) for v in obj]
    return obj


def load_hermes_settings(config_path: str | None = None) -> dict[str, Any]:
    raw_path = (config_path or os.environ.get("HERMES_CONFIG", "")).strip()
    cfg = Path(raw_path) if raw_path else (PACKAGE_ROOT / "config.hermes.yaml")
    if not cfg.is_absolute():
        cfg = (PACKAGE_ROOT / cfg).resolve()
    else:
        cfg = cfg.resolve()

    if not cfg.is_file():
        raise FileNotFoundError(cfg)
    with cfg.open("r", encoding="utf-8") as fh:
        settings = yaml.safe_load(fh) or {}
    if not isinstance(settings, dict):
        raise ValueError(f"Invalid YAML root in {cfg}")
    settings = _expand_env_in_obj(settings)
    settings["_config_path"] = str(cfg)
    return settings


def get_workspace_root(settings: dict[str, Any]) -> Path:
    ws_rel = str(settings.get("workspace", "..")).strip() or ".."
    cfg = Path(str(settings["_config_path"])).resolve()
    return (cfg.parent / ws_rel).resolve()


def resolve_path(settings: dict[str, Any], path_value: str) -> Path:
    p = Path(str(path_value).strip())
    if p.is_absolute():
        return p.resolve()
    return (get_workspace_root(settings) / p).resolve()


def document_suffix_from_skills(skills: list[str]) -> str:
    """`.md` или `.adoc` по форматирующему скиллу Hermes (остальное – через skills/LLM)."""
    has_md = "my/markdown" in skills
    has_adoc = "my/asciidoc" in skills
    if has_md and has_adoc:
        raise ValueError("hermes.skills: укажите только один из my/markdown или my/asciidoc")
    if has_md:
        return ".md"
    if has_adoc:
        return ".adoc"
    raise ValueError("hermes.skills must include my/markdown or my/asciidoc")


def get_description_layout(
    settings: dict[str, Any],
    *,
    document_suffix: str | None = None,
) -> dict[str, Any]:
    desc = settings.get("description")
    if not isinstance(desc, dict):
        raise KeyError("description")

    input_raw = str(desc.get("input_dir", "")).strip()
    if not input_raw:
        raise ValueError("description.input_dir required")
    input_dir = resolve_path(settings, input_raw)

    out_raw = str(desc.get("output_dir", "input_dir")).strip()
    output_dir = input_dir if out_raw == "input_dir" else resolve_path(settings, out_raw)

    file_name = str(desc.get("file_name", "description.hermes")).strip() or "description.hermes"
    if file_name.endswith((".adoc", ".md")):
        output_file = output_dir / file_name
    elif document_suffix is not None:
        output_file = output_dir / f"{file_name}{document_suffix}"
    else:
        output_file = output_dir / f"{file_name}.adoc"

    issue_order_file = desc.get("issue_order_file")
    issue_order_path = None
    if issue_order_file is not None and str(issue_order_file).strip():
        issue_order_path = resolve_path(settings, str(issue_order_file))

    bsp = desc.get("bundle_subdirs_prefix")
    bundle_subdir_prefix = str(bsp).strip() if bsp is not None and str(bsp).strip() else None

    return {
        "input_dir": input_dir,
        "output_dir": output_dir,
        "output_file": output_file,
        "bundle_subdir_prefix": bundle_subdir_prefix,
        "issue_order_file": issue_order_path,
        "max_context_chars": int(desc.get("max_context_chars", 96000)),
        "max_adoc_text_chars": int(desc.get("max_adoc_text_chars", 32000)),
        "exports_root": input_dir.parent,
    }


def get_hermes_config(settings: dict[str, Any]) -> dict[str, Any]:
    hermes = settings.get("hermes")
    if not isinstance(hermes, dict):
        raise KeyError("hermes")

    skills = hermes.get("skills") or []
    if not isinstance(skills, list):
        raise ValueError("hermes.skills must be a list")

    model = str(hermes.get("model", "default")).strip() or "default"
    provider = str(hermes.get("provider", "")).strip() or None
    base_url = str(hermes.get("base_url", "")).strip() or None
    api_key_env = str(hermes.get("api_key_env", "HERMES_API_KEY")).strip() or "HERMES_API_KEY"
    repo_path = (
        str(hermes.get("hermes_repo_path", "")).strip()
        or os.environ.get("HERMES_REPO_PATH", "").strip()
        or "/Users/vvv/.hermes/hermes-agent"
    )
    hermes_python_path = (
        str(hermes.get("hermes_python_path", "")).strip()
        or os.environ.get("HERMES_PYTHON_PATH", "").strip()
        or None
    )

    raw_ctx = hermes.get("context_length", None)
    context_length: int | None
    if raw_ctx is None:
        context_length = None
    elif isinstance(raw_ctx, str) and not raw_ctx.strip():
        context_length = None
    else:
        try:
            context_length = int(raw_ctx)
            if context_length <= 0:
                context_length = None
        except (TypeError, ValueError):
            context_length = None

    # None = не передавать в AIAgent (все toolsets Hermes). [] = без инструментов, только LLM + skills.
    enabled_toolsets: list[str] | None
    if "enabled_toolsets" in hermes:
        raw_ets = hermes.get("enabled_toolsets")
        if isinstance(raw_ets, list):
            enabled_toolsets = [str(x).strip() for x in raw_ets if str(x).strip()]
        else:
            enabled_toolsets = []
    else:
        enabled_toolsets = None

    return {
        "model": model,
        "provider": provider,
        "base_url": base_url,
        "api_key_env": api_key_env,
        "api_key": os.environ.get(api_key_env),
        "hermes_repo_path": repo_path,
        "hermes_python_path": hermes_python_path,
        "timeout_sec": int(hermes.get("timeout_sec", 120)),
        "retry_attempts": int(hermes.get("retry_attempts", 2)),
        "skip_memory": bool(hermes.get("skip_memory", False)),
        "skip_context_files": bool(hermes.get("skip_context_files", False)),
        "context_length": context_length,
        "enabled_toolsets": enabled_toolsets,
        "skills": [str(x).strip() for x in skills if str(x).strip()],
        "session_toggle": bool(hermes.get("session_toggle", False)),
    }
