from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Iterable, Optional

from .hermes_client import HermesClient
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


def _epic_human_title(title: str, base_id: str) -> str | None:
    """Из строки вида 'ODS-6: Разработать …' возвращает часть после ключа."""
    m = re.match(re.escape(base_id) + r"\s*:\s*(.+)$", title.strip(), re.IGNORECASE)
    if not m:
        return None
    s = m.group(1).strip()
    return s if s else None


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


def wrap_section_with_tag(base_id: str, content: str, *, markdown: bool = False) -> str:
    if markdown:
        tag_open = f"<!-- //tag::{base_id}[] -->"
        tag_close = f"<!-- //end::{base_id}[] -->"
    else:
        tag_open = f"//tag::{base_id}[]"
        tag_close = f"//end::{base_id}[]"
    text = content.strip()
    if tag_open in text and tag_close in text:
        return text
    return f"{tag_open}\n{text}\n{tag_close}"


def format_issue_section(
    base_id: str,
    group: str | None,
    inner_body: str,
    *,
    markdown: bool,
    human_title: str | None = None,
) -> str:
    group_suffix = f", {group}" if group else ""
    if markdown:
        header_lines = [f"## {base_id}{group_suffix}"]
        if human_title:
            header_lines.extend(["", f"### {human_title}"])
    else:
        header_lines = [f"== {base_id}{group_suffix}"]
        if human_title:
            header_lines.extend(["", f"=== {human_title}"])
    header = "\n".join(header_lines)
    return header + "\n\n" + wrap_section_with_tag(base_id, inner_body, markdown=markdown)


def build_user_block(container: ContainerInfo, title: str, context_str: str) -> str:
    kind = KIND_RU.get(container.kind, "контейнер")
    group = f"\nГруппа: {container.group}" if container.group else ""
    return f"ФТ ({kind}): {container.base_id} – {title}{group}\n\nТексты задач:\n\n{context_str}"


def generate_sections_hermes(
    *,
    source_dir: Path,
    hermes_client: HermesClient,
    model: str,
    skills: list[str],
    max_adoc_text_chars: int,
    max_context_chars: int,
    markdown_output: bool = False,
    dry_run: bool = False,
    only_base_ids: Optional[Iterable[str]] = None,
    bundle_subdir_prefix: str | None = None,
    issue_order_file: Path | None = None,
) -> str:
    container_dirs = list_container_dirs(source_dir)
    if bundle_subdir_prefix and container_dirs:
        filtered = [d for d in container_dirs if d.name.startswith(bundle_subdir_prefix)]
        if not filtered:
            raise ValueError(
                f"bundle_subdirs_prefix={bundle_subdir_prefix!r}: в {source_dir} нет подходящих подпапок"
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

    base_ids_sorted = _order_base_ids(by_base_id.keys(), issue_order_file)
    if only_base_ids is not None:
        want = frozenset(str(x).strip().upper() for x in only_base_ids if str(x).strip())
        if want:
            present_upper = {b.upper() for b in by_base_id}
            missing = sorted(want - present_upper)
            if missing:
                raise ValueError("--only: " + ", ".join(missing))
            base_ids_sorted = [b for b in base_ids_sorted if b.upper() in want]

    sections: list[str] = []
    pending: list[tuple[str, str | None, str, str | None]] = []
    for base_id in base_ids_sorted:
        paths = by_base_id[base_id]
        if use_flat_files:
            container_info, docs_by_key = load_flat_folder_bundle(source_dir, max_adoc_text_chars)
        else:
            container_info, docs_by_key = load_container_group(paths, max_adoc_text_chars)

        main_doc: Optional[AdocDoc] = docs_by_key.get(base_id)
        tasks = sorted((doc for k, doc in docs_by_key.items() if k != base_id), key=lambda d: d.key)
        title = main_doc.title if main_doc else base_id
        human_title = _epic_human_title(title, container_info.base_id)
        context_parts: list[str] = []
        if main_doc and main_doc.text.strip():
            ck = KIND_RU.get(container_info.kind, "контейнер")
            context_parts.append(f"{base_id} ({ck}):\n{main_doc.text}")
        context_parts.extend([f"{t.key}: {t.title}\n{t.text}" for t in tasks])
        context_str = "\n\n".join(context_parts)
        if len(context_str) > max_context_chars:
            context_str = context_str[:max_context_chars] + "\n\n(текст обрезан)"
            print(f"[{container_info.base_id}] обрезка → {max_context_chars}", file=sys.stderr, flush=True)

        if dry_run:
            stub = "_DRY_RUN_: Hermes вызов пропущен."
            sections.append(
                format_issue_section(
                    container_info.base_id,
                    container_info.group,
                    stub,
                    markdown=markdown_output,
                    human_title=human_title,
                )
            )
            continue

        user_prompt = build_user_block(container_info, title=title, context_str=context_str)
        pending.append((container_info.base_id, container_info.group, user_prompt, human_title))

    if pending:
        responses = hermes_client.generate_many(
            prompts=[p[2] for p in pending],
            model=model,
            skills=skills,
            system_instruction=None,
        )
        for i, ((base_id, group, _, human_title), response) in enumerate(
            zip(pending, responses), start=1
        ):
            sections.append(
                format_issue_section(
                    base_id,
                    group,
                    response.strip(),
                    markdown=markdown_output,
                    human_title=human_title,
                )
            )
            print(f"[{i}/{len(pending)}] {base_id}", file=sys.stderr, flush=True)
    return "\n\n".join(sections)
