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


def _load_workspace_and_config() -> tuple[Path, Path]:
    env_ws = (
        os.environ.get("DESCRIPTION_GEN_WORKSPACE", "").strip()
        or os.environ.get("RELEASE_NOTES_WORKSPACE", "").strip()
    )
    env_cfg = (
        os.environ.get("DESCRIPTION_GEN_CONFIG", "").strip()
        or os.environ.get("RELEASE_NOTES_CONFIG", "").strip()
    )
    if env_ws and env_cfg:
        ws = Path(env_ws).expanduser().resolve()
        cfg = Path(env_cfg)
        cfg = cfg.resolve() if cfg.is_absolute() else (ws / cfg).resolve()
        return ws, cfg

    cfg = (PACKAGE_ROOT / "config.yaml").resolve()
    if cfg.is_file():
        raw = yaml.safe_load(cfg.read_text(encoding="utf-8")) or {}
        ws_rel = str(raw.get("workspace", "..")).strip()
        ws = (PACKAGE_ROOT / ws_rel).resolve()
        return ws, cfg

    legacy = PACKAGE_ROOT / "runtime.yaml"
    if legacy.is_file():
        raw = yaml.safe_load(legacy.read_text(encoding="utf-8")) or {}
        ws_rel = str(raw.get("workspace", "..")).strip()
        cfg_rel = str(raw.get("config", "tools/config.yml")).strip()
        ws = (PACKAGE_ROOT / ws_rel).resolve()
        p = Path(cfg_rel)
        p = p.resolve() if p.is_absolute() else (ws / p).resolve()
        return ws, p

    raise FileNotFoundError(
        f"Нет {PACKAGE_ROOT / 'config.yaml'} (или устар. runtime.yaml), "
        "либо задайте DESCRIPTION_GEN_WORKSPACE + DESCRIPTION_GEN_CONFIG "
        "(или устар. RELEASE_NOTES_*)."
    )


WORKSPACE_ROOT, CONFIG_PATH = _load_workspace_and_config()


def load_settings() -> dict[str, Any]:
    if not CONFIG_PATH.is_file():
        raise FileNotFoundError(CONFIG_PATH)
    with CONFIG_PATH.open("r", encoding="utf-8") as fh:
        return _expand_env_in_obj(yaml.safe_load(fh) or {})


def resolve_dotted(settings: dict[str, Any], ref: str) -> Any:
    ref = str(ref).strip()
    if not ref:
        raise ValueError("empty ref")
    cur: Any = settings
    for part in ref.split("."):
        if not isinstance(cur, dict):
            raise KeyError(ref)
        if part not in cur:
            raise KeyError(ref)
        cur = cur[part]
    return cur


def _looks_like_dotted_ref(value: Any) -> bool:
    s = str(value).strip()
    if not s or "/" in s or s.startswith("."):
        return False
    if s.endswith(".adoc"):
        return False
    return "." in s


def _resolve_path(settings: dict[str, Any], ref_or_path: str) -> Path:
    ref_or_path = str(ref_or_path).strip()
    if _looks_like_dotted_ref(ref_or_path):
        p = Path(str(resolve_dotted(settings, ref_or_path)))
    else:
        p = Path(ref_or_path)
    if not p.is_absolute():
        p = WORKSPACE_ROOT / p
    return p.resolve()


def _resolve_prompt_file(raw: Any) -> Path | None:
    if raw is None or not str(raw).strip():
        return None
    s = str(raw).strip()
    p = Path(s)
    if p.is_absolute():
        return p.resolve()
    if s.startswith("data/prompts/"):
        return (PACKAGE_ROOT / s).resolve()
    return (WORKSPACE_ROOT / s).resolve()


def _description_section(settings: dict[str, Any]) -> dict[str, Any] | None:
    d = settings.get("description")
    if isinstance(d, dict) and d:
        return d
    legacy = settings.get("releases") or settings.get("reliases")
    return legacy if isinstance(legacy, dict) and legacy else None


def get_description_layout(settings: dict[str, Any]) -> dict[str, Any] | None:
    desc = _description_section(settings)
    if not desc:
        return None

    input_ref = str(desc.get("input_dir", "")).strip()
    if not input_ref:
        raise ValueError("description.input_dir required")

    input_dir = _resolve_path(settings, input_ref)

    out_raw = desc.get("output_dir", "input_dir")
    output_dir = input_dir if str(out_raw).strip() == "input_dir" else _resolve_path(settings, str(out_raw))

    fn_ref = desc.get("file_name") or desc.get("file_stem") or "description"
    if _looks_like_dotted_ref(str(fn_ref)):
        stem = str(resolve_dotted(settings, str(fn_ref))).strip()
    else:
        stem = str(fn_ref).strip()
    output_file = output_dir / stem if stem.endswith(".adoc") else output_dir / f"{stem}.adoc"

    prompt_files: list[Path] = []
    pfc = desc.get("prompt_files")
    if isinstance(pfc, dict) and pfc:
        for _, raw_path in pfc.items():
            pr = _resolve_prompt_file(raw_path)
            if pr is not None:
                prompt_files.append(pr)
    if not prompt_files:
        intro = _resolve_prompt_file(desc.get("prompt_file_intro_tw"))
        adoc = _resolve_prompt_file(desc.get("prompt_file_asciidoc"))
        body = _resolve_prompt_file(desc.get("prompt_body"))
        if body is None:
            raise ValueError("description.prompt_files (словарь) или prompt_body обязательны")
        prompt_files = [p for p in (intro, adoc, body) if p is not None]
        prompt_asciidoc_path = adoc
        prompt_body_path = body
    else:
        prompt_asciidoc_path = None
        prompt_body_path = prompt_files[-1]

    exports_raw = desc.get("exports_root")
    exports_root = (
        _resolve_path(settings, str(exports_raw)) if exports_raw else input_dir.parent
    )

    intro_path: Path | None = None
    if isinstance(pfc, dict) and pfc.get("intro"):
        intro_path = _resolve_prompt_file(pfc.get("intro"))
    if intro_path is None:
        intro_path = _resolve_prompt_file(desc.get("prompt_file_intro_tw"))

    bsp = desc.get("bundle_subdirs_prefix")
    bundle_subdir_prefix = str(bsp).strip() if bsp is not None and str(bsp).strip() else None

    ior = desc.get("issue_order_file")
    issue_order_file: Path | None = None
    if ior is not None and str(ior).strip():
        issue_order_file = _resolve_path(settings, str(ior).strip())

    return {
        "input_dir": input_dir,
        "output_dir": output_dir,
        "output_file": output_file,
        "prompt_files": prompt_files,
        "prompt_body": prompt_body_path,
        "prompt_file_intro_tw": intro_path,
        "prompt_file_asciidoc": prompt_asciidoc_path,
        "bundle_subdir_prefix": bundle_subdir_prefix,
        "issue_order_file": issue_order_file,
        "max_context_chars": desc.get("max_context_chars"),
        "max_adoc_text_chars": desc.get("max_adoc_text_chars"),
        "exports_root": exports_root,
    }


def get_ollama_host(settings: dict[str, Any]) -> str:
    env_url = os.getenv("OLLAMA_URL", "").strip()
    if env_url:
        return env_url
    o = settings.get("ollama") if isinstance(settings.get("ollama"), dict) else {}
    host = str(o.get("host", "")).strip()
    if not host:
        raise KeyError("ollama.host or OLLAMA_URL")
    return host


def get_llm_model(settings: dict[str, Any]) -> str:
    desc = _description_section(settings)
    if not isinstance(desc, dict):
        raise KeyError("description")
    models = desc.get("models")
    if not isinstance(models, dict) or not models.get("llm"):
        raise KeyError("description.models.llm")
    return str(os.getenv("LLM_MODEL") or models["llm"])


def get_llm_temperature(settings: dict[str, Any]) -> float:
    env = (
        os.environ.get("LLM_TEMPERATURE", "").strip()
        or os.environ.get("DESCRIPTION_GEN_TEMPERATURE", "").strip()
    )
    if env:
        return float(env)
    desc = _description_section(settings)
    if not isinstance(desc, dict):
        return 0.2
    raw = desc.get("temperature")
    if raw is None and isinstance(desc.get("models"), dict):
        raw = desc["models"].get("temperature")
    if raw is not None and str(raw).strip() != "":
        return float(raw)
    return 0.2
