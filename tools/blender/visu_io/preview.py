"""Viewport LOD preview: show one detail level per mesh family."""

from __future__ import annotations

from . import lod

try:
    import bpy
except ImportError:  # pragma: no cover
    bpy = None


def apply_lod_preview(objects, preview: int | None) -> None:
    specs = []
    for obj in objects:
        if getattr(obj, "type", "MESH") != "MESH":
            continue
        level = lod.lod_level(obj.name)
        if level < 0:
            _set_visible(obj, False)
            continue
        if getattr(obj, "visu_lod", None) not in (None, 0) and level == 0:
            # name had no _L prefix; trust the property if it was set
            tagged = int(obj.visu_lod)
            if tagged > 0:
                level = tagged
        part = getattr(obj, "visu_part_name", "") or lod.lod_base(obj.name)
        specs.append((obj.name, level, part, obj))
    vis = lod.visible_names([(n, lv, p) for n, lv, p, _ in specs], preview)
    for name, _level, _part, obj in specs:
        _set_visible(obj, name in vis)


def apply_scene_preview(context) -> None:
    if bpy is None:
        return
    raw = getattr(context.scene, "visu_lod_preview", "0")
    preview = None if raw == "ALL" else int(raw)
    apply_lod_preview(context.scene.objects, preview)


def _set_visible(obj, show: bool) -> None:
    obj.hide_viewport = not show
    try:
        obj.hide_set(not show)
    except Exception:
        pass
