"""Assembly sidecar: shorthand (one part) or full parts + nodes."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def load(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"{path}: vmod is not a JSON object")
    return canonical(data, stem=path.stem)


def dump(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(compact(data, stem=path.stem), indent=4) + "\n")


def canonical(data: dict[str, Any], stem: str) -> dict[str, Any]:
    """Expand shorthand to parts + nodes. Full form is returned as-is with defaults filled."""
    if "parts" in data:
        parts = data["parts"]
        nodes = data.get("nodes") or [
            {"name": name, "part": name} for name in parts
        ]
        return {
            "cullDistance": float(data.get("cullDistance") or 0),
            "impostor": data.get("impostor") or {},
            "parts": parts,
            "nodes": nodes,
        }
    part = {
        "lod": list(data.get("lod") or []),
        "lodBias": float(data.get("lodBias") or 1),
        "cullDistance": float(data.get("cullDistance") or 0),
        "slots": dict(data.get("slots") or {}),
        "dynamic": bool(data.get("dynamic") or False),
        "impostor": bool(data.get("impostor") or False),
    }
    return {
        "cullDistance": 0.0,
        "impostor": {},
        "parts": {stem: part},
        "nodes": [{"name": stem, "part": stem}],
    }


def compact(data: dict[str, Any], stem: str = "") -> dict[str, Any]:
    """Write shorthand when one part is named like the vmod stem (cooker uses the stem)."""
    parts = data.get("parts") or {}
    nodes = data.get("nodes") or []
    if len(parts) == 1 and len(nodes) == 1:
        name, part = next(iter(parts.items()))
        node = nodes[0]
        same = node.get("name") == name and node.get("part") == name and not node.get("parent")
        # shorthand reloads as `{stem: part}`; only safe when that is the glTF object name
        if same and (not stem or name == stem):
            out: dict[str, Any] = {}
            if part.get("lod"):
                out["lod"] = part["lod"]
            if part.get("lodBias", 1) != 1:
                out["lodBias"] = part["lodBias"]
            if part.get("cullDistance"):
                out["cullDistance"] = part["cullDistance"]
            if part.get("slots"):
                out["slots"] = part["slots"]
            if part.get("dynamic"):
                out["dynamic"] = True
            if part.get("model"):
                out["model"] = part["model"]
            return out
    out = {}
    if data.get("cullDistance"):
        out["cullDistance"] = data["cullDistance"]
    if data.get("impostor"):
        out["impostor"] = data["impostor"]
    out["parts"] = parts
    out["nodes"] = nodes
    return out
