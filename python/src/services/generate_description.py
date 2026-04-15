from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

SRC_DIR = Path(__file__).resolve().parents[1]
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from core.description import generate_sections
from core.settings import (
    get_description_layout,
    get_llm_model,
    get_llm_temperature,
    get_ollama_host,
    load_settings,
)


def _prompt_from_layout(layout: dict[str, Any], args: argparse.Namespace) -> tuple[Path, list[Path] | None]:
    if args.prompt:
        return Path(args.prompt).expanduser(), None
    files: list[Path] = layout.get("prompt_files") or []
    if files:
        return files[0], files
    return layout["prompt_body"], None


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--subdir", default=None)
    p.add_argument("--release", default=None, help=argparse.SUPPRESS)
    p.add_argument("--nested", default=None)
    p.add_argument("--epic-folder", default=None, help=argparse.SUPPRESS)
    p.add_argument("--output", default=None)
    p.add_argument("--prompt", default=None)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--only", action="append", dest="only_base_ids", default=None)
    p.add_argument("--temperature", type=float, default=None)
    return p.parse_args(argv if argv is not None else sys.argv[1:])


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    subdir = args.subdir or args.release
    nested = args.nested or args.epic_folder
    settings = load_settings()
    temperature = (
        float(args.temperature)
        if args.temperature is not None
        else get_llm_temperature(settings)
    )

    desc = settings.get("description") or settings.get("releases") or {}
    max_adoc_text_chars = (
        int(desc["max_adoc_text_chars"])
        if isinstance(desc, dict) and desc.get("max_adoc_text_chars") is not None
        else 32000
    )
    max_context_chars = int(
        os.environ.get("DESCRIPTION_GEN_MAX_CONTEXT", "")
        or os.environ.get("RELEASE_NOTES_MAX_CONTEXT", "96000")
    )

    layout = get_description_layout(settings)
    if not layout:
        print("description: нужна секция в конфиге", file=sys.stderr)
        return 1

    if subdir:
        root = layout["exports_root"] / subdir
        if not root.is_dir():
            raise FileNotFoundError(root)
        source_dir = root / nested if nested else root
        if nested and not source_dir.is_dir():
            raise FileNotFoundError(source_dir)
        out_path = source_dir / (args.output or "description.adoc")
    else:
        source_dir = layout["input_dir"]
        if not source_dir.is_dir():
            raise FileNotFoundError(source_dir)
        out_path = layout["output_file"]

    prompt_template_path, prompt_template_paths = _prompt_from_layout(layout, args)
    if not prompt_template_path.is_absolute():
        prompt_template_path = prompt_template_path.resolve()

    if layout.get("max_adoc_text_chars") is not None:
        max_adoc_text_chars = int(layout["max_adoc_text_chars"])
    if layout.get("max_context_chars") is not None:
        max_context_chars = int(layout["max_context_chars"])

    if prompt_template_paths:
        missing = [str(x) for x in prompt_template_paths if not x.is_file()]
        if missing:
            raise FileNotFoundError(", ".join(missing))
    elif not prompt_template_path.is_file():
        raise FileNotFoundError(prompt_template_path)

    llm_host = get_ollama_host(settings)
    llm_model = get_llm_model(settings)

    print(source_dir)
    print(out_path)

    result = generate_sections(
        source_dir=source_dir,
        prompt_template_path=prompt_template_path,
        ollama_host=llm_host,
        llm_model=llm_model,
        max_adoc_text_chars=max_adoc_text_chars,
        max_context_chars=max_context_chars,
        temperature=temperature,
        dry_run=args.dry_run,
        only_base_ids=args.only_base_ids,
        prompt_template_paths=prompt_template_paths,
        bundle_subdir_prefix=layout.get("bundle_subdir_prefix"),
        issue_order_file=layout.get("issue_order_file"),
    )

    if args.dry_run:
        print(result)
        return 0

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(result, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
