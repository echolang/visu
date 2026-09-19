"""LOD node names the visu glTF cooker already understands."""

import re

_PREFIX = re.compile(r"^[_$]L([1-5])_(.+)$")
_SUFFIX = re.compile(r"^(.+)_lod([1-5])$")
_PHYSICS = re.compile(r"^[_$]PP_")


def lod_level(name: str) -> int:
    """0 for a base part, 1..5 for an LOD node, -2 for a physics proxy, -1 unknown."""
    if _PHYSICS.match(name):
        return -2
    m = _PREFIX.match(name)
    if m:
        return int(m.group(1))
    m = _SUFFIX.match(name)
    if m:
        return int(m.group(2))
    return 0


def lod_base(name: str) -> str:
    m = _PREFIX.match(name)
    if m:
        return m.group(2)
    m = _SUFFIX.match(name)
    if m:
        return m.group(1)
    return name


def lod_node_name(base: str, level: int) -> str:
    if level <= 0:
        return base
    return f"_L{level}_{base}"


def shown_level(available: list[int], preview: int) -> int:
    """Highest existing LOD that is not more detailed than *preview* (same rule as the game)."""
    have = sorted({int(x) for x in available if x >= 0})
    if not have:
        return 0
    le = [x for x in have if x <= preview]
    return le[-1] if le else have[0]


def visible_names(
    objects: list[tuple[str, int, str]],
    preview: int | None,
) -> set[str]:
    """Which object names should be visible.

    *objects* is ``(name, lod_level, part_name)``. *preview* ``None`` shows every
    mesh (they overlap). Physics proxies (level < 0) stay hidden.
    """
    shown: set[str] = set()
    by_part: dict[str, list[tuple[int, str]]] = {}
    for name, level, part in objects:
        if level < 0:
            continue
        if preview is None:
            shown.add(name)
            continue
        by_part.setdefault(part, []).append((level, name))
    if preview is None:
        return shown
    for items in by_part.values():
        want = shown_level([lv for lv, _ in items], preview)
        for lv, name in items:
            if lv == want:
                shown.add(name)
    return shown
