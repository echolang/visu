"""Catalog ids and filenames for a VISU source folder."""

from __future__ import annotations

import re
from pathlib import Path

_UNSAFE = re.compile(r"[^\w.-]+")


def stem_from_name(name: str) -> str:
    """Filename-safe stem. Dots stay (Material_0.001); path junk becomes underscore."""
    s = _UNSAFE.sub("_", name).strip("._")
    return s or "material"


def file_stem(name: str, known: set[str] | None = None) -> str:
    """Like stem_from_name, but Blender's `.001` duplicate reuses the unsuffixed stem."""
    stem = stem_from_name(name)
    base = re.sub(r"\.\d+$", "", stem)
    if base != stem and known is not None and base in known:
        return base
    return stem


def folder_id(glb_path: Path) -> str:
    """`props/testsrobot` when saved under `resources/source`; else the parent folder name."""
    parent = glb_path.parent.resolve()
    for p in (parent, *parent.parents):
        if p.name == "source" and p.parent.name == "resources":
            rel = parent.relative_to(p)
            return rel.as_posix() if str(rel) != "." else ""
    return parent.name


def catalog_id(folder: str, stem: str) -> str:
    if not folder:
        return stem
    return f"{folder}/{stem}"
