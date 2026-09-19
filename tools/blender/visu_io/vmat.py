"""One PBR material file."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


DEFAULTS = {
    "fallback": [1.0, 1.0, 1.0],
    "roughnessFactor": 0.8,
    "metallicFactor": 0.0,
    "textureScale": 1,
    "alphaCutoff": 0,
    "backfaceCull": True,
}

MAP_KEYS = (
    "albedo",
    "diffuse",
    "normal",
    "rough",
    "roughness",
    "metal",
    "metallic",
    "ao",
    "alpha",
    "opacity",
    "emissive",
    "height",
)

# Bind name used when wiring Blender → first vmat key that has a file.
_MAP_ROLES = (
    ("albedo", ("albedo", "diffuse")),
    ("normal", ("normal",)),
    ("rough", ("rough", "roughness")),
    ("metal", ("metal", "metallic")),
    ("alpha", ("alpha", "opacity")),
    ("emissive", ("emissive",)),
    ("ao", ("ao",)),
    ("height", ("height",)),
)

_IMAGE_EXTS = (".png", ".jpg", ".jpeg")


def load(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"{path}: vmat is not a JSON object")
    return data


def dump(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=4) + "\n")


def catalog_id(folder_id: str, stem: str) -> str:
    if not folder_id:
        return stem
    return f"{folder_id}/{stem}"


def map_files(folder: Path, data: dict[str, Any]) -> dict[str, Path]:
    """Role → existing image next to the vmat (albedo, normal, rough, metal, alpha, …)."""
    out: dict[str, Path] = {}
    for role, keys in _MAP_ROLES:
        for key in keys:
            stem = data.get(key)
            if not stem or not isinstance(stem, str):
                continue
            path = _image_file(folder, stem)
            if path is not None:
                out[role] = path
                break
    return out


def _image_file(folder: Path, stem: str) -> Path | None:
    name = Path(stem).name
    for ext in _IMAGE_EXTS:
        path = folder / f"{name}{ext}"
        if path.is_file():
            return path
        if name.lower().endswith(ext):
            path = folder / name
            if path.is_file():
                return path
    return None
