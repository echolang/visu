"""Build a cookable VISU source folder from Blender meshes (or from a fake description in tests)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from . import names, png, vmat as vmat_mod, vmod as vmod_mod

LINEAR_ROLES = ("normal", "rough", "metal", "ao", "height", "alpha")

# Principled sockets we care about: Blender 4.2 / 5.x names first.
_SOCKETS = {
    "albedo": ("Base Color",),
    "metallic": ("Metallic",),
    "roughness": ("Roughness",),
    "normal": ("Normal",),
    "alpha": ("Alpha",),
    "emissive": ("Emission Color", "Emission"),
}

_SEPARATE = {
    "R": 0,
    "G": 1,
    "B": 2,
    "Red": 0,
    "Green": 1,
    "Blue": 2,
}


def assembly_for_parts(
    glb_stem: str,
    folder: str,
    parts: list[dict[str, Any]],
) -> dict[str, Any]:
    """`parts` items: name, slots (glTF mat name → vmat stem), optional lod / cull / model."""
    out_parts: dict[str, Any] = {}
    nodes: list[dict[str, Any]] = []
    single = len(parts) == 1
    for spec in parts:
        name = spec["name"]
        slots = {}
        for mat_name, stem in (spec.get("slots") or {}).items():
            slots[mat_name] = names.catalog_id(folder, stem)
        rec: dict[str, Any] = {
            "lod": list(spec.get("lod") or []),
            "lodBias": float(spec.get("lodBias") or 1),
            "cullDistance": float(spec.get("cullDistance") or 0),
            "dynamic": bool(spec.get("dynamic") or False),
            "impostor": bool(spec.get("impostor") or False),
            "slots": slots,
        }
        model = spec.get("model")
        if model:
            rec["model"] = model
        elif single:
            rec["model"] = names.catalog_id(folder, glb_stem)
        out_parts[name] = rec
        nodes.append({"name": name, "part": name})
    return {"cullDistance": 0.0, "impostor": {}, "parts": out_parts, "nodes": nodes}


def vmat_from_maps(
    maps: dict[str, str],
    *,
    fallback: list[float] | None = None,
    roughness_factor: float = 0.8,
    metallic_factor: float = 0.0,
    texture_scale: float = 1.0,
    alpha_cutoff: float = 0.0,
    backface_cull: bool = True,
) -> dict[str, Any]:
    """`maps` keys are vmat bind names (`albedo`, `normal`, `rough`, `metal`, `alpha`, …)."""
    data: dict[str, Any] = {}
    if fallback is not None:
        data["fallback"] = fallback
    if roughness_factor != vmat_mod.DEFAULTS["roughnessFactor"]:
        data["roughnessFactor"] = roughness_factor
    if metallic_factor != vmat_mod.DEFAULTS["metallicFactor"]:
        data["metallicFactor"] = metallic_factor
    if texture_scale != vmat_mod.DEFAULTS["textureScale"]:
        data["textureScale"] = texture_scale
    if alpha_cutoff:
        data["alphaCutoff"] = alpha_cutoff
    if backface_cull != vmat_mod.DEFAULTS["backfaceCull"]:
        data["backfaceCull"] = backface_cull
    data.update(maps)
    return data


def vtex_for_stem(stem: str, role: str) -> dict[str, Any] | None:
    if role in LINEAR_ROLES:
        return {"srgb": False}
    return None


def write_asset(
    glb_path: Path,
    assembly: dict[str, Any],
    materials: dict[str, dict[str, Any]],
    vtex: dict[str, dict[str, Any]],
) -> None:
    folder = glb_path.parent
    folder.mkdir(parents=True, exist_ok=True)
    vmod_mod.dump(glb_path.with_suffix(".vmod"), assembly)
    for stem, data in materials.items():
        vmat_mod.dump(folder / f"{stem}.vmat", data)
    for stem, data in vtex.items():
        (folder / f"{stem}.vtex").write_text(json.dumps(data, indent=4) + "\n")


# --- Blender ---

try:
    import bpy
except ImportError:  # pragma: no cover
    bpy = None


def export_objects(context) -> list:
    """Meshes to put in the glb: selection (with children), else VISU asset objects.

    Armature and empty ancestors come along so bone-parented clips survive `use_selection`.
    """
    if bpy is None:
        return []
    selected = list(context.selected_objects)
    if selected:
        return _with_ancestors(_with_mesh_children(selected))
    tagged = []
    for obj in context.scene.objects:
        if obj.type != "MESH":
            continue
        if getattr(obj, "hide_viewport", False) or not obj.visible_get():
            continue
        if getattr(obj, "visu_asset", False):
            tagged.append(obj)
            continue
        for col in obj.users_collection:
            if getattr(col, "visu_asset", False):
                tagged.append(obj)
                break
    return _with_ancestors(_with_mesh_children(tagged))


def _with_ancestors(objects: list) -> list:
    seen: set[int] = {id(obj) for obj in objects}
    extra = []
    for obj in objects:
        parent = obj.parent
        while parent is not None:
            if id(parent) not in seen:
                extra.append(parent)
                seen.add(id(parent))
            parent = parent.parent
    return list(objects) + extra


def _with_mesh_children(roots: list) -> list:
    seen: set[int] = set()
    out = []
    stack = list(roots)
    while stack:
        obj = stack.pop()
        if id(obj) in seen:
            continue
        seen.add(id(obj))
        from . import lod

        if lod.lod_level(obj.name) == -2:
            continue
        if obj.type == "MESH":
            out.append(obj)
        stack.extend(obj.children)
    return out


def select_only(context, objects: list) -> None:
    if bpy is None:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        context.view_layer.objects.active = objects[0]


def dump_from_blender(objects: list, glb_path: Path) -> tuple[dict, dict, dict]:
    """Walk meshes, write PNG maps, return assembly / materials / vtex."""
    folder = names.folder_id(glb_path)
    glb_stem = glb_path.stem
    dest = glb_path.parent
    dest.mkdir(parents=True, exist_ok=True)

    parts = _parts_from_objects(objects, folder, glb_stem)
    mat_by_name: dict[str, Any] = {}
    for obj in objects:
        for slot in obj.material_slots:
            if slot.material is not None:
                mat_by_name[slot.material.name] = slot.material

    materials: dict[str, dict[str, Any]] = {}
    vtex: dict[str, dict[str, Any]] = {}
    stems_for_mat: dict[str, str] = {}
    used_files: set[str] = set()
    known_stems: set[str] = set()
    for mat_name, mat in mat_by_name.items():
        vid = getattr(mat, "visu_id", "") or ""
        known_stems.add(vid or names.stem_from_name(mat_name))

    for mat_name, mat in mat_by_name.items():
        vid = getattr(mat, "visu_id", "") or ""
        stem = vid or names.file_stem(mat_name, known_stems)
        if not vid:
            try:
                mat.visu_id = stem
            except Exception:
                pass
        stems_for_mat[mat_name] = stem
        if stem in materials:
            continue
        maps, extra_vtex, meta = _extract_material(mat, stem, dest, used_files)
        materials[stem] = vmat_from_maps(maps, **meta)
        vtex.update(extra_vtex)

    for spec in parts:
        slots = {}
        for mat_name in spec.get("mat_names") or []:
            stem = stems_for_mat.get(mat_name)
            if stem:
                slots[mat_name] = stem
        spec["slots"] = slots

    assembly = assembly_for_parts(glb_stem, folder, parts)
    return assembly, materials, vtex


def _object_animated(obj) -> bool:
    ad = getattr(obj, "animation_data", None)
    if ad is not None and (ad.action or len(ad.nla_tracks) > 0):
        return True
    if getattr(obj, "parent_type", "") == "BONE":
        arm = obj.parent
        if arm is not None and _object_animated(arm):
            return True
    parent = obj.parent
    while parent is not None:
        if _object_animated(parent):
            return True
        parent = parent.parent
    return False


def _parts_from_objects(objects: list, folder: str, glb_stem: str) -> list[dict[str, Any]]:
    from . import lod

    grouped: dict[str, dict[str, Any]] = {}
    for obj in objects:
        if getattr(obj, "type", "") != "MESH":
            continue
        coll_part = None
        for col in obj.users_collection:
            if getattr(col, "visu_part", False):
                coll_part = col
                break
        if coll_part is not None:
            name = coll_part.name
            spec = grouped.setdefault(
                name,
                {
                    "name": name,
                    "lod": _parse_lods(getattr(coll_part, "visu_lod_distances", "")),
                    "lodBias": float(getattr(coll_part, "visu_lod_bias", 1) or 1),
                    "cullDistance": float(getattr(coll_part, "visu_cull_distance", 0) or 0),
                    "dynamic": bool(getattr(coll_part, "visu_dynamic", False) or _object_animated(obj)),
                    "impostor": bool(getattr(coll_part, "visu_impostor", False)),
                    "mat_names": [],
                },
            )
        else:
            name = getattr(obj, "visu_part_name", "") or lod.lod_base(obj.name)
            spec = grouped.setdefault(
                name,
                {
                    "name": name,
                    "lod": [],
                    "lodBias": 1.0,
                    "cullDistance": 0.0,
                    "dynamic": bool(_object_animated(obj)),
                    "impostor": False,
                    "mat_names": [],
                },
            )
            spec["dynamic"] = bool(spec.get("dynamic") or _object_animated(obj))
        for slot in obj.material_slots:
            if slot.material is not None and slot.material.name not in spec["mat_names"]:
                spec["mat_names"].append(slot.material.name)
    out = list(grouped.values())
    for spec in out:
        if spec.get("impostor"):
            continue
        if any("_imp" in (n or "").lower() for n in spec.get("mat_names") or []):
            spec["impostor"] = True
    return out


def _parse_lods(raw: str) -> list[float]:
    if not raw or not str(raw).strip():
        return []
    return [float(x) for x in str(raw).split(",") if x.strip()]


def _extract_material(
    mat,
    stem: str,
    dest: Path,
    used_files: set[str],
) -> tuple[dict[str, str], dict[str, dict], dict]:
    maps: dict[str, str] = {}
    vtex: dict[str, dict] = {}
    fallback = [1.0, 1.0, 1.0]
    roughness_factor = float(getattr(mat, "visu_roughness_factor", 0.8))
    metallic_factor = float(getattr(mat, "visu_metallic_factor", 0.0))
    texture_scale = float(getattr(mat, "visu_texture_scale", 1.0))
    alpha_cutoff = float(getattr(mat, "visu_alpha_cutoff", 0.0))
    backface = bool(getattr(mat, "visu_backface_cull", True))
    if hasattr(mat, "use_backface_culling"):
        backface = bool(mat.use_backface_culling)

    bsdf = _principled(mat)
    if bsdf is not None:
        col = _socket(bsdf, _SOCKETS["albedo"])
        if col is not None:
            img, channel = _follow_image(col)
            if img is None:
                fb = _color3(col)
                if fb is not None:
                    fallback = fb
            else:
                maps["albedo"] = _save_map(img, dest, stem, "albedo", used_files, channel)
        metal = _socket(bsdf, _SOCKETS["metallic"])
        if metal is not None:
            img, channel = _follow_image(metal)
            if img is None:
                metallic_factor = _scalar(metal, metallic_factor)
            else:
                maps["metal"] = _save_map(img, dest, stem, "metallic", used_files, channel)
                vtex[maps["metal"]] = {"srgb": False}
        rough = _socket(bsdf, _SOCKETS["roughness"])
        if rough is not None:
            img, channel = _follow_image(rough)
            if img is None:
                roughness_factor = _scalar(rough, roughness_factor)
            else:
                maps["rough"] = _save_map(img, dest, stem, "roughness", used_files, channel)
                vtex[maps["rough"]] = {"srgb": False}
        normal = _socket(bsdf, _SOCKETS["normal"])
        if normal is not None:
            img, channel = _follow_image(normal)
            if img is not None:
                maps["normal"] = _save_map(img, dest, stem, "normal", used_files, channel)
                vtex[maps["normal"]] = {"srgb": False}
        alpha = _socket(bsdf, _SOCKETS["alpha"])
        if alpha is not None:
            img, channel = _follow_image(alpha)
            if img is not None:
                maps["alpha"] = _save_map(img, dest, stem, "alpha", used_files, channel)
                vtex[maps["alpha"]] = {"srgb": False}
        emit = _socket(bsdf, _SOCKETS["emissive"])
        if emit is not None:
            img, channel = _follow_image(emit)
            if img is not None:
                maps["emissive"] = _save_map(img, dest, stem, "emissive", used_files, channel)

    if not alpha_cutoff:
        blend = getattr(mat, "blend_method", "OPAQUE")
        if blend in ("CLIP", "HASHED"):
            alpha_cutoff = float(getattr(mat, "alpha_threshold", 0.5) or 0.5)

    meta = {
        "fallback": fallback,
        "roughness_factor": roughness_factor,
        "metallic_factor": metallic_factor,
        "texture_scale": texture_scale,
        "alpha_cutoff": alpha_cutoff,
        "backface_cull": backface,
    }
    return maps, vtex, meta


def _principled(mat):
    if mat is None or not getattr(mat, "use_nodes", False) or mat.node_tree is None:
        return None
    for node in mat.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    return None


def _socket(node, names: tuple[str, ...]):
    for n in names:
        if n in node.inputs:
            return node.inputs[n]
    return None


def _follow_image(socket, depth: int = 0) -> tuple[Any, int | None]:
    if socket is None or not socket.links or depth > 8:
        return None, None
    link = socket.links[0]
    node = link.from_node
    ntype = getattr(node, "type", "")
    if ntype == "TEX_IMAGE":
        img = getattr(node, "image", None)
        sock_name = getattr(link.from_socket, "name", "")
        if sock_name in ("Alpha", "A"):
            return img, 3
        return img, None
    if ntype == "NORMAL_MAP":
        return _follow_image(node.inputs.get("Color"), depth + 1)
    if ntype in ("SEPARATE_COLOR", "SEPARATE_RGB", "SEPRGB"):
        ch = _SEPARATE.get(link.from_socket.name, 0)
        img, inner = _follow_image(node.inputs[0] if node.inputs else None, depth + 1)
        if img is not None:
            return img, ch if inner is None else inner
        return None, None
    if ntype == "GROUP" and getattr(node, "node_tree", None) is not None:
        # glTF importer groups: follow the group output back into the tree
        group = node.node_tree
        sock_name = link.from_socket.name
        for inner in group.nodes:
            if inner.type == "GROUP_OUTPUT":
                inp = inner.inputs.get(sock_name)
                return _follow_image(inp, depth + 1)
    return None, None


def _color3(socket) -> list[float] | None:
    v = getattr(socket, "default_value", None)
    if v is None:
        return None
    try:
        return [float(v[0]), float(v[1]), float(v[2])]
    except (TypeError, IndexError):
        return None


def _scalar(socket, fallback: float) -> float:
    v = getattr(socket, "default_value", None)
    try:
        return float(v)
    except (TypeError, ValueError):
        return fallback


def _save_map(
    img,
    dest: Path,
    mat_stem: str,
    role: str,
    used: set[str],
    channel: int | None,
) -> str:
    stem = f"{mat_stem}_{role}"
    n = 2
    while stem in used:
        stem = f"{mat_stem}_{role}_{n}"
        n += 1
    used.add(stem)
    path = dest / f"{stem}.png"
    if channel is None:
        _save_image_png(img, path)
    else:
        _save_image_channel(img, path, channel)
    return stem


def _save_image_png(img, path: Path) -> None:
    if img is None:
        raise ValueError("no image")
    try:
        img.save(filepath=str(path))
        if path.exists() and path.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n":
            return
    except Exception:
        pass
    w, h, rgba = _blender_rgba(img)
    png.write_rgba(path, w, h, rgba)


def _save_image_channel(img, path: Path, channel: int) -> None:
    w, h, rgba = _blender_rgba(img)
    gray = png.channel(rgba, 4, channel)
    png.write_gray_as_rgb(path, w, h, gray)


def _blender_rgba(img) -> tuple[int, int, bytes]:
    w, h = int(img.size[0]), int(img.size[1])
    px = list(img.pixels)
    out = bytearray(w * h * 4)
    for y in range(h):
        src_y = h - 1 - y
        for x in range(w):
            i = (src_y * w + x) * 4
            o = (y * w + x) * 4
            out[o] = _u8(px[i])
            out[o + 1] = _u8(px[i + 1])
            out[o + 2] = _u8(px[i + 2])
            out[o + 3] = _u8(px[i + 3]) if i + 3 < len(px) else 255
    return w, h, bytes(out)


def _u8(v: float) -> int:
    if v <= 0.0:
        return 0
    if v >= 1.0:
        return 255
    return int(v * 255.0 + 0.5)
