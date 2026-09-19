from __future__ import annotations

from pathlib import Path

from . import export, lod, names, vmat, vmod

try:
    import bpy
    from bpy.props import StringProperty
    from bpy_extras.io_utils import ExportHelper, ImportHelper
except ImportError:  # pragma: no cover
    bpy = None
    ExportHelper = type("ExportHelper", (), {})
    ImportHelper = type("ImportHelper", (), {})
    StringProperty = lambda **kwargs: None


def import_sidecars(glb_path: Path) -> tuple[dict, dict[str, dict]]:
    vmod_path = glb_path.with_suffix(".vmod")
    assembly = vmod.load(vmod_path) if vmod_path.exists() else vmod.canonical({}, stem=glb_path.stem)
    materials = {}
    for mat_path in glb_path.parent.glob("*.vmat"):
        materials[mat_path.stem] = vmat.load(mat_path)
    return assembly, materials


def resolve_mesh_path(path: Path) -> Path | None:
    """`.vmod` (or any sidecar) → sibling `.glb` / `.gltf`. The mesh is never the JSON."""
    suffix = path.suffix.lower()
    if suffix in {".glb", ".gltf"}:
        return path if path.is_file() else None
    for ext in (".glb", ".gltf"):
        cand = path.with_suffix(ext)
        if cand.is_file():
            return cand
    return None


def vmat_for_name(mat_name: str, materials: dict[str, dict]) -> dict | None:
    if mat_name in materials:
        return materials[mat_name]
    return materials.get(names.stem_from_name(mat_name))


class IMPORT_SCENE_OT_visu_model(*( (bpy.types.Operator, ImportHelper) if bpy else (object,) )):
    bl_idname = "import_scene.visu_model"
    bl_label = "VISU model"
    bl_description = (
        "Open a VISU source folder. Pick the .glb or the .vmod next to it — both load "
        "the mesh plus PNG textures named in the .vmat files"
    )
    filename_ext = ".glb"
    filter_glob: StringProperty(default="*.glb;*.gltf;*.vmod", options={"HIDDEN"})

    def execute(self, context):
        picked = Path(self.filepath)
        mesh_path = resolve_mesh_path(picked)
        if mesh_path is None:
            self.report(
                {"ERROR"},
                f"no .glb next to {picked.name} — pick bush_01.glb or bush_01.vmod in the same folder",
            )
            return {"CANCELLED"}
        assembly, materials = import_sidecars(mesh_path)
        before = set(context.scene.objects)
        try:
            bpy.ops.import_scene.gltf(filepath=str(mesh_path))
        except Exception as e:
            self.report({"ERROR"}, f"glTF import failed: {e}")
            return {"CANCELLED"}
        imported = [obj for obj in context.scene.objects if obj not in before]
        if not imported:
            imported = list(context.selected_objects)
        imported = prune_imported(imported)
        apply_imported(context, mesh_path, assembly, materials, imported)
        n_maps = len(
            {
                slot.material.name
                for obj in imported
                for slot in obj.material_slots
                if slot.material is not None and vmat_for_name(slot.material.name, materials)
            }
        )
        self.report({"INFO"}, f"imported {mesh_path.name} ({n_maps} material(s) from sidecar PNG)")
        return {"FINISHED"}


_DROP_EMPTY = {"Scene", "Camera", "Light"}


def prune_imported(imported: list) -> list:
    """Drop glTF cameras, lights, and assimp Scene/Camera/Light empties so only meshes remain."""
    if bpy is None:
        return imported
    drop = []
    keep = []
    for obj in imported:
        if obj.type in {"CAMERA", "LIGHT"}:
            drop.append(obj)
            continue
        if obj.type == "EMPTY" and obj.name.split(".")[0] in _DROP_EMPTY:
            drop.append(obj)
            continue
        keep.append(obj)
    for obj in drop:
        for child in list(obj.children):
            mw = child.matrix_world.copy()
            child.parent = None
            child.matrix_world = mw
        bpy.data.objects.remove(obj, do_unlink=True)
    return keep


def apply_imported(context, path: Path, assembly: dict, materials: dict[str, dict], imported: list) -> None:
    """Collections, VISU tags, and sibling PNG maps from .vmat (the glb URIs are often stale)."""
    folder = path.parent
    coll = bpy.data.collections.new(path.stem)
    context.scene.collection.children.link(coll)
    coll.visu_asset = True
    coll.visu_cull_distance = float(assembly.get("cullDistance") or 0)
    parts = assembly.get("parts") or {}
    part_colls: dict[str, object] = {}
    for name, part in parts.items():
        if name == coll.name:
            sub = coll
        else:
            sub = bpy.data.collections.new(name)
            coll.children.link(sub)
        sub.visu_part = True
        sub.visu_dynamic = bool(part.get("dynamic"))
        sub.visu_lod_bias = float(part.get("lodBias") or 1)
        sub.visu_cull_distance = float(part.get("cullDistance") or 0)
        lods = part.get("lod") or []
        sub.visu_lod_distances = ",".join(str(x) for x in lods)
        sub.visu_impostor = bool(part.get("impostor"))
        part_colls[name] = sub
    for obj in imported:
        level = lod.lod_level(obj.name)
        base = lod.lod_base(obj.name)
        if level >= 0:
            obj.visu_lod = level
        obj.visu_part_name = base
        if obj.type == "MESH" and obj.data is not None and obj.data.name != obj.name:
            try:
                obj.data.name = obj.name
            except Exception:
                pass
        target = part_colls.get(base, coll)
        try:
            target.objects.link(obj)
        except RuntimeError:
            pass
        for user in list(obj.users_collection):
            if user != target:
                try:
                    user.objects.unlink(obj)
                except RuntimeError:
                    pass
    seen = set()
    for obj in imported:
        for slot in obj.material_slots:
            mat = slot.material
            if mat is None or mat.name in seen:
                continue
            seen.add(mat.name)
            data = vmat_for_name(mat.name, materials)
            if data is None:
                continue
            apply_vmat_to_blender(mat, data, folder)
    _spread_parts(imported)
    from .preview import apply_lod_preview

    apply_lod_preview(imported, 0)
    try:
        context.scene.visu_lod_preview = "0"
    except Exception:
        pass


def _spread_parts(imported: list) -> None:
    """Park each unique mesh next to the last one so four bushes are not stacked at the origin."""
    if bpy is None:
        return
    from mathutils import Vector

    roots = [
        obj
        for obj in imported
        if obj.type == "MESH" and obj.parent is None and lod.lod_level(obj.name) == 0
    ]
    roots.sort(key=lambda o: o.name)
    x = 0.0
    gap = 0.6
    for obj in roots:
        corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        xs = [c.x for c in corners]
        width = max(xs) - min(xs)
        obj.location.x += x - min(xs)
        x += max(width, 0.5) + gap


def apply_vmat_to_blender(mat, data: dict, folder: Path) -> None:
    mat.visu_id = names.stem_from_name(mat.name)
    fb = data.get("fallback") or [1, 1, 1]
    mat.visu_fallback = (float(fb[0]), float(fb[1]), float(fb[2]))
    mat.visu_roughness_factor = float(data.get("roughnessFactor") or 0.8)
    mat.visu_metallic_factor = float(data.get("metallicFactor") or 0)
    scale = data.get("textureScale") or 1
    mat.visu_texture_scale = float(scale[0] if isinstance(scale, list) else scale)
    mat.visu_alpha_cutoff = float(data.get("alphaCutoff") or 0)
    mat.visu_backface_cull = bool(data.get("backfaceCull", True))
    if hasattr(mat, "use_backface_culling"):
        mat.use_backface_culling = mat.visu_backface_cull
    if mat.visu_alpha_cutoff:
        try:
            mat.blend_method = "CLIP"
        except TypeError:
            mat.blend_method = "HASHED"
        if hasattr(mat, "alpha_threshold"):
            mat.alpha_threshold = mat.visu_alpha_cutoff
    files = vmat.map_files(folder, data)
    if not files or bpy is None:
        return
    from .export import _principled, _socket

    bsdf = _principled(mat)
    if bsdf is None:
        return
    tree = mat.node_tree
    x = bsdf.location[0] - 420
    y = bsdf.location[1]
    if "albedo" in files:
        _link_image(tree, bsdf, "Base Color", files["albedo"], linear=False, loc=(x, y))
        y -= 280
    col = _socket(bsdf, ("Base Color",))
    if col is not None:
        col.default_value = (float(fb[0]), float(fb[1]), float(fb[2]), 1.0)
    if "normal" in files:
        _link_image(tree, bsdf, "Normal", files["normal"], linear=True, loc=(x, y), normal=True)
        y -= 280
    if "rough" in files:
        _link_image(tree, bsdf, "Roughness", files["rough"], linear=True, loc=(x, y))
        y -= 280
    else:
        rough = _socket(bsdf, ("Roughness",))
        if rough is not None:
            rough.default_value = mat.visu_roughness_factor
    if "metal" in files:
        _link_image(tree, bsdf, "Metallic", files["metal"], linear=True, loc=(x, y))
        y -= 280
    else:
        metal = _socket(bsdf, ("Metallic",))
        if metal is not None:
            metal.default_value = mat.visu_metallic_factor
    if "alpha" in files:
        _link_image(tree, bsdf, "Alpha", files["alpha"], linear=True, loc=(x, y))
        y -= 280
    if "emissive" in files:
        _link_image(tree, bsdf, "Emission Color", files["emissive"], linear=False, loc=(x, y))
    _purge_unused_images(tree)


def _link_image(tree, bsdf, socket_name: str, path: Path, *, linear: bool, loc: tuple, normal: bool = False) -> None:
    sock = bsdf.inputs.get(socket_name)
    if sock is None:
        return
    for link in list(sock.links):
        tree.links.remove(link)
    img = bpy.data.images.load(str(path), check_existing=True)
    img.colorspace_settings.name = "Non-Color" if linear else "sRGB"
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.location = loc
    if linear:
        tex.image.colorspace_settings.name = "Non-Color"
    if normal:
        nrm = tree.nodes.new("ShaderNodeNormalMap")
        nrm.location = (loc[0] + 220, loc[1])
        tree.links.new(tex.outputs["Color"], nrm.inputs["Color"])
        tree.links.new(nrm.outputs["Normal"], sock)
    else:
        tree.links.new(tex.outputs["Color"], sock)


def _purge_unused_images(tree) -> None:
    for node in list(tree.nodes):
        if getattr(node, "type", "") != "TEX_IMAGE":
            continue
        img = getattr(node, "image", None)
        size = tuple(img.size) if img is not None else (0, 0)
        dead = img is None or size == (0, 0)
        unused = not any(out.links for out in node.outputs)
        if dead or unused:
            tree.nodes.remove(node)


class EXPORT_SCENE_OT_visu_model(*( (bpy.types.Operator, ExportHelper) if bpy else (object,) )):
    bl_idname = "export_scene.visu_model"
    bl_label = "VISU model (.glb)"
    bl_description = (
        "Write the selected mesh into a folder the game can load: the .glb, PNG copies of "
        "its textures, and small JSON files for materials. Save under the game's "
        "resources/source directory, then run: echoc run --target cook"
    )
    filename_ext = ".glb"
    filter_glob: StringProperty(default="*.glb", options={"HIDDEN"})

    def execute(self, context):
        path = Path(self.filepath)
        objects = export.export_objects(context)
        if not objects:
            self.report({"ERROR"}, "select a mesh, or tick VISU asset on the object")
            return {"CANCELLED"}
        export.select_only(context, objects)
        try:
            kwargs = {
                "filepath": str(path),
                "export_format": "GLB",
                "use_selection": True,
                "export_animations": True,
            }
            try:
                bpy.ops.export_scene.gltf(
                    **kwargs,
                    export_skins=True,
                    export_nla_strips=True,
                    export_force_sampling=True,
                )
            except TypeError:
                bpy.ops.export_scene.gltf(**kwargs)
        except Exception as e:
            self.report({"ERROR"}, f"glTF export failed: {e}")
            return {"CANCELLED"}
        try:
            assembly, materials, vtex = export.dump_from_blender(objects, path)
            export.write_asset(path, assembly, materials, vtex)
        except Exception as e:
            self.report({"ERROR"}, f"VISU sidecars failed: {e}")
            return {"CANCELLED"}
        self.report({"INFO"}, f"exported {path.name} + {len(materials)} material(s)")
        return {"FINISHED"}


_CLASSES = (IMPORT_SCENE_OT_visu_model, EXPORT_SCENE_OT_visu_model)


def _menu_import(self, context):
    self.layout.operator(IMPORT_SCENE_OT_visu_model.bl_idname, text="VISU model (.glb / .vmod)")


def _menu_export(self, context):
    self.layout.operator(EXPORT_SCENE_OT_visu_model.bl_idname, text="VISU model (.glb)")


def register():
    if bpy is None:
        return
    for cls in _CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.TOPBAR_MT_file_import.append(_menu_import)
    bpy.types.TOPBAR_MT_file_export.append(_menu_export)


def unregister():
    if bpy is None:
        return
    bpy.types.TOPBAR_MT_file_import.remove(_menu_import)
    bpy.types.TOPBAR_MT_file_export.remove(_menu_export)
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)
