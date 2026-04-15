from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Iterable, Optional

from .ollama_client import OllamaClient
from .release_containers import (
    AdocDoc,
    ContainerInfo,
    detect_container_info,
    list_container_dirs,
    list_flat_issue_files,
    load_container_group,
    load_flat_folder_bundle,
)

KIND_RU = {"jira": "задача Jira", "unknown": "контейнер"}

_JIRA_KEY_RE = re.compile(r"^([A-Z][A-Z0-9]*)-(\d+)$")


def _jira_natural_sort_key(base_id: str) -> tuple:
    m = _JIRA_KEY_RE.match(base_id)
    if m:
        return (0, m.group(1), int(m.group(2)))
    return (1, base_id, 0)


def _order_base_ids(base_ids: Iterable[str], order_file: Path | None) -> list[str]:
    keys = list(base_ids)
    if order_file is not None and order_file.is_file():
        upper_actual = {k.upper(): k for k in keys}
        listed: list[str] = []
        seen: set[str] = set()
        for line in order_file.read_text(encoding="utf-8").splitlines():
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue
            act = upper_actual.get(raw.upper())
            if act is not None and act not in seen:
                listed.append(act)
                seen.add(act)
        rest = [k for k in keys if k not in seen]
        rest.sort(key=_jira_natural_sort_key)
        return listed + rest
    return sorted(keys, key=_jira_natural_sort_key)


def load_prompt_template(
    prompt_template_path: Path,
    *,
    prompt_template_paths: list[Path] | None = None,
) -> str:
    if prompt_template_paths:
        parts: list[str] = []
        for p in prompt_template_paths:
            t = p.read_text(encoding="utf-8").strip()
            if t:
                parts.append(t)
        return ("\n\n---\n\n".join(parts) + "\n") if parts else ""

    return prompt_template_path.read_text(encoding="utf-8").strip()


def cleanup_llm_body(base_id: str, response_text: str) -> str:
    lines = response_text.strip().splitlines()
    while lines and lines[0].strip().startswith(f"== {base_id}"):
        lines.pop(0)
    body = "\n".join(lines).strip()
    if body.startswith(f"=== {base_id}"):
        body = "=== Описание изменений\n" + body[len(f"=== {base_id}") :].lstrip("\n")
    return body


def wrap_section_with_tag(base_id: str, content: str) -> str:
    """Wrap section body with asciidoc tag markers for include:: tags."""
    tag_open = f"//tag::{base_id}[]"
    tag_close = f"//end::{base_id}[]"
    text = content.strip()
    if tag_open in text and tag_close in text:
        return text
    return f"{tag_open}\n{text}\n{tag_close}"


def build_user_block(container: ContainerInfo, title: str, context_str: str) -> str:
    kind = KIND_RU.get(container.kind, "контейнер")
    g = f"\nГруппа: {container.group}" if container.group else ""
    return f"ФТ ({kind}): {container.base_id} – {title}{g}\n\nТексты задач:\n\n{context_str}"


def generate_sections(
    source_dir: Path,
    prompt_template_path: Path,
    ollama_host: str,
    llm_model: str,
    *,
    max_adoc_text_chars: int,
    max_context_chars: int,
    temperature: float = 0.2,
    dry_run: bool = False,
    only_base_ids: Optional[Iterable[str]] = None,
    prompt_template_paths: list[Path] | None = None,
    bundle_subdir_prefix: str | None = None,
    issue_order_file: Path | None = None,
) -> str:
    ollama_client = OllamaClient(host=ollama_host)
    prompt_template = load_prompt_template(
        prompt_template_path,
        prompt_template_paths=prompt_template_paths,
    )
    container_dirs = list_container_dirs(source_dir)
    if bundle_subdir_prefix and container_dirs:
        pref = bundle_subdir_prefix
        filtered = [d for d in container_dirs if d.name.startswith(pref)]
        if not filtered:
            raise ValueError(
                f"bundle_subdirs_prefix={pref!r}: в {source_dir} нет подходящих подпапок"
            )
        container_dirs = filtered

    by_base_id: dict[str, list[Path]] = {}
    use_flat_files = False
    if container_dirs:
        for d in container_dirs:
            info = detect_container_info(d.name)
            by_base_id.setdefault(info.base_id, []).append(d)
    else:
        files = list_flat_issue_files(source_dir)
        if files:
            use_flat_files = True
            info0 = detect_container_info(source_dir.name)
            by_base_id = {info0.base_id: []}

    sections: list[str] = []
    base_ids_sorted = _order_base_ids(by_base_id.keys(), issue_order_file)
    if only_base_ids is not None:
        want = frozenset(str(x).strip().upper() for x in only_base_ids if str(x).strip())
        if want:
            present_upper = {b.upper() for b in by_base_id}
            missing = sorted(want - present_upper)
            if missing:
                raise ValueError("--only: " + ", ".join(missing))
            base_ids_sorted = [b for b in base_ids_sorted if b.upper() in want]

    for i, base_id in enumerate(base_ids_sorted, start=1):
        paths = by_base_id[base_id]
        if use_flat_files:
            container_info, docs_by_key = load_flat_folder_bundle(source_dir, max_adoc_text_chars)
        else:
            container_info, docs_by_key = load_container_group(paths, max_adoc_text_chars)
        main_doc: Optional[AdocDoc] = docs_by_key.get(base_id)
        tasks = sorted((doc for k, doc in docs_by_key.items() if k != base_id), key=lambda d: d.key)
        title = main_doc.title if main_doc else base_id
        context_parts: list[str] = []
        if main_doc and main_doc.text.strip():
            ck = KIND_RU.get(container_info.kind, "контейнер")
            context_parts.append(f"{base_id} ({ck}):\n{main_doc.text}")
        context_parts.extend([f"{t.key}: {t.title}\n{t.text}" for t in tasks])
        context_str = "\n\n----\n\n".join(context_parts)
        if len(context_str) > max_context_chars:
            context_str = context_str[:max_context_chars] + "\n\n(текст обрезан)"
            print(f"[{container_info.base_id}] обрезка → {max_context_chars}", file=sys.stderr, flush=True)

        user_block = build_user_block(container_info, title=title, context_str=context_str)
        full_prompt = prompt_template + "\n\n---\n\n" + user_block
        heading = f"== {container_info.base_id}" + (
            f", {container_info.group}" if container_info.group else ""
        )

        if dry_run:
            dry_body = wrap_section_with_tag(
                container_info.base_id,
                f"_DRY_RUN_: n={len(docs_by_key)}",
            )
            sections.append(heading + "\n\n" + dry_body)
            continue

        response = ollama_client.generate(prompt=full_prompt, model=llm_model, temperature=temperature)
        body = cleanup_llm_body(container_info.base_id, response)
        tagged_body = wrap_section_with_tag(container_info.base_id, body)
        sections.append(heading + "\n\n" + tagged_body)
        print(f"[{i}/{len(base_ids_sorted)}] {container_info.base_id}", file=sys.stderr, flush=True)

    return "\n\n".join(sections)
