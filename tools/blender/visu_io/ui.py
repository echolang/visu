try:
    import bpy
except ImportError:  # pragma: no cover
    bpy = None

from . import lod


def _hint(layout, *lines: str) -> None:
    box = layout.box()
    for line in lines:
        box.label(text=line)


class VISU_PT_lod_preview(bpy.types.Panel if bpy else object):
    bl_label = "LOD preview"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "VISU"
    bl_order = 0

    def draw(self, context):
        layout = self.layout
        _hint(
            layout,
            "The game swaps to a cheaper mesh as you",
            "walk away. Pick a level to see that mesh.",
            "Higher = farther / simpler. 4 is often the",
            "flat card (impostor).",
        )
        layout.prop(context.scene, "visu_lod_preview", expand=True)
        obj = context.object
        if obj is None or obj.type != "MESH":
            return
        part = getattr(obj, "visu_part_name", "") or lod.lod_base(obj.name)
        levels = sorted(
            {
                lod.lod_level(o.name)
                for o in context.scene.objects
                if o.type == "MESH"
                and (getattr(o, "visu_part_name", "") or lod.lod_base(o.name)) == part
                and lod.lod_level(o.name) >= 0
            }
        )
        if not levels:
            return
        raw = getattr(context.scene, "visu_lod_preview", "0")
        showing = None if raw == "ALL" else lod.shown_level(levels, int(raw))
        names = ", ".join(str(x) for x in levels)
        layout.label(text=f"{part} has LOD {names}")
        if showing is not None:
            layout.label(text=f"Viewport is showing LOD {showing}")
        coll = context.collection
        dists = getattr(coll, "visu_lod_distances", "") if coll is not None else ""
        if dists:
            layout.label(text=f"Switches at {dists} m")


class VISU_PT_asset(bpy.types.Panel if bpy else object):
    bl_label = "Export"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "VISU"
    bl_order = 1

    def draw(self, context):
        layout = self.layout
        obj = context.object
        mesh = obj is not None and obj.type == "MESH"

        _hint(
            layout,
            "This writes a folder the game can load.",
            "The .glb is the mesh. Next to it, export",
            "copies textures as PNG and writes small",
            "JSON files for materials and LOD.",
            "",
            "The running game does not read the .glb.",
            "From the game project, convert the folder:",
            "    echoc run --target cook",
            "Then spawn it by folder/filename, e.g.",
            "    props/testsrobot/robot",
        )

        if not mesh:
            layout.label(text="Select a mesh object to export it.", icon="INFO")
        else:
            col = layout.column(align=True)
            col.prop(obj, "visu_asset")
            col.prop(obj, "visu_part_name")
            col.prop(obj, "visu_lod")
            layout.operator("export_scene.visu_model", text="Export to folder…", icon="EXPORT")
            layout.label(text="Save into resources/source/<folder>/name.glb")
            layout.label(text="Textures are taken from Principled BSDF.")

        layout.separator()
        coll = context.collection
        if coll is None:
            return
        box = layout.box()
        box.label(text="Several meshes in one file")
        box.label(text="Leave this off for one object.")
        box.prop(coll, "visu_asset")
        if coll.visu_asset:
            box.prop(coll, "visu_cull_distance")
            box.operator("export_scene.visu_model", text="Export this collection")


class VISU_PT_part(bpy.types.Panel if bpy else object):
    bl_label = "Multi-part collection"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "VISU"
    bl_order = 2
    bl_options = {"DEFAULT_CLOSED"}

    def draw_header(self, context):
        coll = context.collection
        if coll is not None:
            self.layout.prop(coll, "visu_part", text="")

    def draw(self, context):
        coll = context.collection
        layout = self.layout
        if coll is None:
            return
        _hint(
            layout,
            "One object = skip this panel.",
            "Two unique meshes (crate and lid):",
            "put each in its own collection, tick",
            "the checkbox, parent both under one",
            "collection that is marked for export.",
        )
        layout.prop(coll, "visu_part")
        if not coll.visu_part:
            return
        col = layout.column(align=True)
        col.prop(coll, "visu_dynamic")
        col.prop(coll, "visu_lod_bias")
        col.prop(coll, "visu_cull_distance")
        col.prop(coll, "visu_lod_distances")
        col.prop(coll, "visu_impostor")
        layout.label(text="Name extra detail meshes _L1_name, _L2_name, …")


class VISU_PT_material(bpy.types.Panel if bpy else object):
    bl_label = "VISU material"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "material"

    def draw(self, context):
        mat = context.material
        layout = self.layout
        if mat is None:
            layout.label(text="No material on the active object.")
            return
        _hint(
            layout,
            "Connect images on Principled BSDF",
            "(Base Color, Normal, Roughness, Metallic).",
            "Export copies those images as PNG.",
            "Settings below are only the name, the",
            "colour if there is no image, and how",
            "shiny / see-through the surface is.",
        )
        layout.prop(mat, "visu_id")
        layout.prop(mat, "visu_fallback")
        col = layout.column(align=True)
        col.prop(mat, "visu_roughness_factor")
        col.prop(mat, "visu_metallic_factor")
        col.prop(mat, "visu_texture_scale")
        col.prop(mat, "visu_alpha_cutoff")
        layout.prop(mat, "visu_backface_cull")


_CLASSES = (VISU_PT_lod_preview, VISU_PT_asset, VISU_PT_part, VISU_PT_material)


def register():
    if bpy is None:
        return
    for cls in _CLASSES:
        bpy.utils.register_class(cls)


def unregister():
    if bpy is None:
        return
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)
