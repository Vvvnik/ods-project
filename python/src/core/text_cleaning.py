from __future__ import annotations

import re
import sys
from pathlib import Path


def clean_adoc_line_for_index(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"image::[^\[]+\[[^\]]*\]", " ", text)
    text = re.sub(r"link:[^\[]+\[([^\]]*)\]", r"\1", text)
    text = re.sub(r"https?://[^\s\]]+", " ", text)
    text = re.sub(r"^\s*//.*$", " ", text)
    text = re.sub(r"^\s*:[^:]+:\s*.*$", " ", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"\*([^*]+)\*", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"^\s*\[\s*[xX ]?\s*\]\s*", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def extract_text_for_embedding(file_path: Path, max_chars: int) -> str:
    raw = file_path.read_text(encoding="utf-8")
    out_lines: list[str] = []
    for line in raw.splitlines():
        stripped = line.strip()
        out_lines.append("" if not stripped else clean_adoc_line_for_index(stripped))
    text = "\n".join(out_lines)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if len(text) > max_chars:
        print(file_path, file=sys.stderr, flush=True)
    return text[:max_chars].strip()


def extract_adoc_title(file_path: Path, fallback: str = "") -> str:
    raw = file_path.read_text(encoding="utf-8")
    for line in raw.splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith("="):
            s = s.lstrip("=").strip()
        elif re.match(r"^#+\s*", s):
            s = re.sub(r"^#+\s*", "", s).strip()
        return s[:200] if len(s) > 200 else s
    return fallback
