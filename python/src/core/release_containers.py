from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from .text_cleaning import extract_adoc_title, extract_text_for_embedding


@dataclass(frozen=True)
class ContainerInfo:
    base_id: str
    kind: str
    group: str


@dataclass(frozen=True)
class AdocDoc:
    key: str
    title: str
    text: str


def detect_container_info(dirname: str) -> ContainerInfo:
    m = re.match(r"^([A-Z][A-Z0-9]*-\d+)(?:-(.+))?$", dirname)
    if m:
        return ContainerInfo(
            base_id=m.group(1),
            kind="jira",
            group=(m.group(2) or "").strip(),
        )
    return ContainerInfo(base_id=dirname, kind="unknown", group="")


def read_adoc_doc(file_path: Path, max_text_chars: int) -> AdocDoc:
    key = file_path.stem
    title = extract_adoc_title(file_path, fallback=key)
    text = extract_text_for_embedding(file_path, max_text_chars)
    return AdocDoc(key=key, title=title, text=text)


def _collect_export_paths(container_dir: Path) -> list[Path]:
    skip_stems = {"release_notes", "description"}
    by_stem: dict[str, Path] = {}
    for pattern in ("*.adoc", "*.md"):
        for p in sorted(container_dir.rglob(pattern)):
            if any(part.lower() == "images" for part in p.parts):
                continue
            if p.stem.lower() in skip_stems:
                continue
            stem = p.stem
            cur = by_stem.get(stem)
            if cur is None:
                by_stem[stem] = p
            elif p.suffix.lower() == ".adoc" and cur.suffix.lower() == ".md":
                by_stem[stem] = p
    return [by_stem[k] for k in sorted(by_stem.keys())]


def list_container_dirs(release_dir: Path) -> list[Path]:
    out: list[Path] = []
    for p in sorted(release_dir.iterdir()):
        if p.is_dir() and not p.name.startswith("."):
            out.append(p)
    return out


def list_flat_issue_files(release_dir: Path) -> list[Path]:
    skip = {"release_notes", "description"}
    out: list[Path] = []
    for p in sorted(release_dir.iterdir()):
        if not p.is_file() or p.suffix.lower() not in (".md", ".adoc"):
            continue
        if p.stem.lower() in skip:
            continue
        out.append(p)
    return out


def load_flat_folder_bundle(folder: Path, max_text_chars: int) -> tuple[ContainerInfo, dict[str, AdocDoc]]:
    """Все issue-файлы в одной папке — один контекст; epic/якорь — по имени папки (например ODS-6)."""
    files = list_flat_issue_files(folder)
    if not files:
        raise ValueError(f"no issue files in {folder}")
    info = detect_container_info(folder.name)
    docs_by_key: dict[str, AdocDoc] = {}
    for f in sorted(files, key=lambda p: p.name):
        doc = read_adoc_doc(f, max_text_chars)
        docs_by_key[doc.key] = doc
    return info, docs_by_key


def load_container_group(
    container_dirs: list[Path],
    max_text_chars: int,
) -> tuple[ContainerInfo, dict[str, AdocDoc]]:
    if not container_dirs:
        raise ValueError("container_dirs is empty")

    first_info = detect_container_info(container_dirs[0].name)
    base_prefix = f"{first_info.base_id}-"
    with_group = [d for d in container_dirs if d.name.startswith(base_prefix)]
    preferred_dir = (
        max(with_group, key=lambda x: len(x.name))
        if with_group
        else max(container_dirs, key=lambda x: len(x.name))
    )
    preferred_info = detect_container_info(preferred_dir.name)

    stem_to_path: dict[str, Path] = {}
    for d in container_dirs:
        for p in _collect_export_paths(d):
            stem = p.stem
            cur = stem_to_path.get(stem)
            if cur is None:
                stem_to_path[stem] = p
            elif p.suffix.lower() == ".adoc" and cur.suffix.lower() == ".md":
                stem_to_path[stem] = p

    docs_by_key: dict[str, AdocDoc] = {}
    for stem in sorted(stem_to_path.keys()):
        docs_by_key[stem] = read_adoc_doc(stem_to_path[stem], max_text_chars=max_text_chars)

    return preferred_info, docs_by_key
