from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

SRC_DIR = Path(__file__).resolve().parents[1]
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from core.description_hermes import generate_sections_hermes
from core.hermes_client import HermesClient
from core.hermes_settings import (
    document_suffix_from_skills,
    get_description_layout,
    get_hermes_config,
    load_hermes_settings,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--config", default=None, help="Path to Hermes config YAML")
    p.add_argument("--subdir", default=None)
    p.add_argument("--nested", default=None)
    p.add_argument("--output", default=None)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--only", action="append", dest="only_base_ids", default=None)
    return p.parse_args(argv if argv is not None else sys.argv[1:])


def _resolve_source_and_output(
    layout: dict[str, Any], args: argparse.Namespace
) -> tuple[Path, Path]:
    if args.subdir:
        root = Path(layout["exports_root"]) / args.subdir
        if not root.is_dir():
            raise FileNotFoundError(root)
        source_dir = root / args.nested if args.nested else root
        if args.nested and not source_dir.is_dir():
            raise FileNotFoundError(source_dir)
        out_path = source_dir / (args.output or layout["output_file"].name)
        return source_dir, out_path

    source_dir = Path(layout["input_dir"])
    if not source_dir.is_dir():
        raise FileNotFoundError(source_dir)
    out_path = Path(args.output).resolve() if args.output else Path(layout["output_file"])
    return source_dir, out_path


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    settings = load_hermes_settings(args.config)
    hermes_cfg = get_hermes_config(settings)
    doc_suffix = document_suffix_from_skills(hermes_cfg["skills"])
    layout = get_description_layout(settings, document_suffix=doc_suffix)

    source_dir, out_path = _resolve_source_and_output(layout, args)

    print(source_dir)
    print(out_path)

    client = HermesClient(
        model=hermes_cfg["model"],
        provider=hermes_cfg["provider"],
        base_url=hermes_cfg["base_url"],
        api_key=hermes_cfg["api_key"],
        hermes_repo_path=hermes_cfg["hermes_repo_path"],
        hermes_python_path=hermes_cfg["hermes_python_path"],
        timeout_sec=hermes_cfg["timeout_sec"],
        retry_attempts=hermes_cfg["retry_attempts"],
        skip_memory=hermes_cfg["skip_memory"],
        skip_context_files=hermes_cfg["skip_context_files"],
        context_length=hermes_cfg.get("context_length"),
        enabled_toolsets=hermes_cfg.get("enabled_toolsets"),
        session_toggle=hermes_cfg["session_toggle"],
    )

    result = generate_sections_hermes(
        source_dir=source_dir,
        hermes_client=client,
        model=hermes_cfg["model"],
        skills=hermes_cfg["skills"],
        max_adoc_text_chars=int(layout["max_adoc_text_chars"]),
        max_context_chars=int(layout["max_context_chars"]),
        markdown_output=(doc_suffix == ".md"),
        dry_run=args.dry_run,
        only_base_ids=args.only_base_ids,
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
