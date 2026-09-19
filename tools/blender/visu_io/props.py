"""Custom properties on collections (asset / part) and materials."""

from __future__ import annotations

try:
    import bpy
    from bpy.props import (
        BoolProperty,
        EnumProperty,
        FloatProperty,
        FloatVectorProperty,
        IntProperty,
        StringProperty,
    )
except ImportError:  # pragma: no cover - tests import lod/vmod without bpy
    bpy = None


def _on_lod_preview(self, context):
    from .preview import apply_scene_preview

    apply_scene_preview(context)


def register():
    if bpy is None:
        return
    bpy.types.Scene.visu_lod_preview = EnumProperty(
        name="Preview LOD",
        description=(
            "Show one detail mesh per object, the way the game swaps them with distance. "
            "0 is close-up. Higher numbers are cheaper stand-ins. All shows every mesh at "
            "once (they sit on top of each other)."
        ),
        items=(
            ("ALL", "All", "Show every LOD at once. They overlap; use this only to edit."),
            ("0", "0", "Full detail (close)"),
            ("1", "1", "First simplification (_L1_)"),
            ("2", "2", "_L2_"),
            ("3", "3", "_L3_"),
            ("4", "4", "_L4_ / impostor card if you have one"),
            ("5", "5", "_L5_ if present, else the last mesh"),
        ),
        default="0",
        update=_on_lod_preview,
    )
    bpy.types.Collection.visu_asset = BoolProperty(
        name="Export this collection",
        description=(
            "Put every mesh in this collection into one exported folder. Use this when a "
            "prop is several objects (crate + lid). For a single object, tick "
            "'Include this object in export' on the mesh instead."
        ),
        default=False,
    )
    bpy.types.Collection.visu_part = BoolProperty(
        name="This collection is one mesh",
        description=(
            "Treat every object in this collection as one named mesh in the file "
            "(for example the lid of a crate). You do not need this if you only selected "
            "one object — that object is already one mesh."
        ),
        default=False,
    )
    bpy.types.Collection.visu_dynamic = BoolProperty(
        name="Moves in the game",
        description=(
            "On: the game updates this object's position every frame (a walking character). "
            "Off: it is planted once (a bush, a crate) and cheaper to draw."
        ),
        default=False,
    )
    bpy.types.Collection.visu_cull_distance = FloatProperty(
        name="Hide beyond (m)",
        description=(
            "Do not draw this mesh when the camera is farther than this many metres. "
            "0 means never hide it — the lowest-detail version stays on screen. Use 0 "
            "for a distant card/impostor you always want visible."
        ),
        default=0.0,
        min=0.0,
        unit="LENGTH",
    )
    bpy.types.Collection.visu_lod_bias = FloatProperty(
        name="Switch LODs closer",
        description=(
            "1 uses the distances you typed. 2 makes the game switch to the simpler mesh "
            "at half the distance (it looks cheaper sooner). Leave at 1 unless you are tuning."
        ),
        default=1.0,
        min=0.0,
    )
    bpy.types.Collection.visu_lod_distances = StringProperty(
        name="Switch at metres",
        description=(
            "When to swap to the simpler meshes, in metres, comma-separated. "
            "First number is when _L1_ takes over, then _L2_, and so on. "
            "Example: 30, 60, 110, 200. Empty uses engine defaults (20, 50, 100, …)."
        ),
        default="",
    )
    bpy.types.Collection.visu_impostor = BoolProperty(
        name="Farthest mesh is a card",
        description=(
            "The last, cheapest mesh is a flat picture of the object (a bush card), "
            "not a real 3D simplification. The game can treat that differently. "
            "Does not change which files are written."
        ),
        default=False,
    )
    bpy.types.Object.visu_asset = BoolProperty(
        name="Include this object in export",
        description=(
            "Mark this mesh so Export writes it to disk. Then click Export to folder "
            "and save under the game's resources/source directory, e.g. "
            "resources/source/props/robot/robot.glb. That folder is what the game "
            "loads after you run 'echoc run --target cook'. Child objects named "
            "_L1_… _L5_… (simpler versions for far away) are included automatically."
        ),
        default=False,
    )
    bpy.types.Object.visu_lod = IntProperty(
        name="Detail level",
        description=(
            "Which version of the mesh this object is. 0 = full detail, seen up close. "
            "1–5 = simpler versions for farther away. You usually do not set this: name "
            "the object _L1_robot or robot_lod1 and it is filled in for you."
        ),
        default=0,
        min=0,
        max=5,
    )
    bpy.types.Object.visu_part_name = StringProperty(
        name="Mesh name in the file",
        description=(
            "How this object is named in the exported file. Empty = the Blender object "
            "name (without an _L1_ prefix). Give two objects the same name only if they "
            "are the same mesh at different detail levels."
        ),
        default="",
    )
    bpy.types.Material.visu_id = StringProperty(
        name="Material file name",
        description=(
            "Name of the JSON material file written next to the .glb (without .vmat). "
            "Empty = the Blender material name. The game looks this up as folder/that-name. "
            "You do not type texture paths here — export copies images from Principled BSDF."
        ),
        default="",
    )
    bpy.types.Material.visu_fallback = FloatVectorProperty(
        name="Color if no image",
        description=(
            "Diffuse colour used when Principled BSDF has no Base Color image connected. "
            "If there is an image, that image is copied as a PNG and this is unused."
        ),
        size=3,
        min=0.0,
        max=1.0,
        default=(1.0, 1.0, 1.0),
        subtype="COLOR",
    )
    bpy.types.Material.visu_roughness_factor = FloatProperty(
        name="Roughness (no map)",
        description=(
            "How rough the surface is when there is no Roughness image. 0 is a mirror, "
            "1 is chalk. If a Roughness texture is connected, the texture is used instead."
        ),
        default=0.8,
        min=0.0,
        max=1.0,
    )
    bpy.types.Material.visu_metallic_factor = FloatProperty(
        name="Metallic (no map)",
        description=(
            "How metal the surface is when there is no Metallic image. 0 is paint/plastic, "
            "1 is bare metal. A connected Metallic texture overrides this."
        ),
        default=0.0,
        min=0.0,
        max=1.0,
    )
    bpy.types.Material.visu_texture_scale = FloatProperty(
        name="Tile textures",
        description=(
            "How many times the images repeat across the mesh. 1 = UVs as you painted them. "
            "0.05 makes a terrain texture much larger in the world."
        ),
        default=1.0,
        min=0.0,
    )
    bpy.types.Material.visu_alpha_cutoff = FloatProperty(
        name="Cut-out threshold",
        description=(
            "For leaves and fences: pixels dimmer than this in the alpha/opacity image "
            "are not drawn. 0 = fully solid. 0.5 is typical for bushes. If you leave this "
            "at 0 and the material is Clip/Hashed in Eevee, export uses 0.5."
        ),
        default=0.0,
        min=0.0,
        max=1.0,
    )
    bpy.types.Material.visu_backface_cull = BoolProperty(
        name="Hide back faces",
        description=(
            "On for solid objects (you never see the inside of a crate). "
            "Off for thin things that must show from both sides (leaves, a cardboard impostor)."
        ),
        default=True,
    )


def unregister():
    if bpy is None:
        return
    if hasattr(bpy.types.Scene, "visu_lod_preview"):
        delattr(bpy.types.Scene, "visu_lod_preview")
    for name in (
        "visu_asset",
        "visu_part",
        "visu_dynamic",
        "visu_cull_distance",
        "visu_lod_bias",
        "visu_lod_distances",
        "visu_impostor",
    ):
        if hasattr(bpy.types.Collection, name):
            delattr(bpy.types.Collection, name)
    for name in ("visu_asset", "visu_lod", "visu_part_name"):
        if hasattr(bpy.types.Object, name):
            delattr(bpy.types.Object, name)
    for name in (
        "visu_id",
        "visu_fallback",
        "visu_roughness_factor",
        "visu_metallic_factor",
        "visu_texture_scale",
        "visu_alpha_cutoff",
        "visu_backface_cull",
    ):
        if hasattr(bpy.types.Material, name):
            delattr(bpy.types.Material, name)
