# VISU Blender I/O

Blender is where the mesh lives. The game does not load a `.blend`, and it does not unpack a packed glTF. It cooks a folder.

This extension writes that folder: a `.glb` plus sibling PNGs, one `.vmat` per material, a `.vmod` for LOD and slots, and tiny `.vtex` files that tell the cooker which maps are linear.

File > Export > glTF will give you a glb. That is not enough. The cooker never reads images packed inside the glb.

## Install

Blender 4.2+ (I use 5.2). This is an extension (`blender_manifest.toml`). Symlink the folder into the **User Default** extensions repository.

`extensions/user_default` may not exist until Blender has created it. `mkdir -p` first. Pick the version folder you actually have under `~/Library/Application Support/Blender`. From the visu repo root:

```bash
mkdir -p "$HOME/Library/Application Support/Blender/5.2/extensions/user_default"
ln -s "$(pwd)/tools/blender/visu_io" \
  "$HOME/Library/Application Support/Blender/5.2/extensions/user_default/visu_io"
```

Then enable **VISU model I/O** in Preferences > Extensions. Restart Blender if it was already open. The package folder stays `visu_io`. The label in the UI is VISU.

## One mesh

Make it look right in Blender: Principled BSDF, images on Base Color / Normal / Roughness / Metallic.

Select the object. In the N-panel **VISU** tab, tick **Include this object in export**. Hover any setting for a description. A single mesh needs nothing else in that tab.

Then File > Export > VISU model (`.glb`), or the **Export to folder...** button in the same panel. Save under the game's source tree:

```text
resources/source/props/robot/robot.glb
```

The catalog id is the path under `resources/source/` without the extension: `props/robot/robot`. In this repo, cook it with:

```bash
echoc run -m examples --target cli -- cook
```

Then spawn it by that id. LOD children named `_L1_robot` through `_L5_robot` on the selected object are included automatically. You do not need collections for one mesh.

If nothing is selected, export walks objects tagged for export, or meshes sitting in a collection tagged **Export this collection**.

## The folder

Export does not stuff textures into the glb. It writes a pile of siblings the cooker already knows how to walk. The ball fixture in this tree is the real example:

```text
examples/models/resources/source/props/ball/
    ball.glb
    ball.vmod
    skin.vmat
    far.vmat
    ball_rough.vtex
    ball_albedo.png
    ball_rough.png
```

| file | what it is |
|---|---|
| `.glb` | the mesh. The running game never opens this. |
| `.vmat` | one PBR material. Catalog id `folder/stem`. |
| `.vmod` | assembly: parts, LOD switches, cull, slot -> material id. |
| `.vtex` | cook knobs only (`srgb: false` for linear maps). Not pixels. |
| `.png` | the maps the cooker actually reads. |

I split materials out of the model file on purpose. A car is not one mesh plus one LOD table. Body, wheels, doors each need their own switches, and a material should be a file you can reuse.

A `.vmat` stem must not collide with a PNG stem or a part id in the same folder. `wood.vmat` next to `wood.png` is refused at cook time.

## Materials

Textures come from the Principled BSDF node tree. Export copies those images as PNG and names them `{material}_{role}` (`skin_albedo`, `skin_normal`, and so on). If a socket has no image, the BSDF value (or the VISU material knobs) becomes a factor instead.

Linear maps (normal, roughness, metallic, alpha, AO, height) get a sibling `.vtex`:

```json
{
    "srgb": false
}
```

Albedo stays sRGB. You do not type texture paths into the material panel. The **VISU material** panel in Properties is the name of the `.vmat`, the fallback colour when there is no albedo image, roughness / metallic when there is no map, tile scale, cut-out threshold, and backface cull.

The ball's close-up material is just this:

```json
{
    "albedo": "ball_albedo",
    "rough": "ball_rough",
    "metallicFactor": 0.0
}
```

Its far LOD is a colour, no maps:

```json
{
    "fallback": [0.9, 0.3, 0.1],
    "roughnessFactor": 0.6
}
```

If the material is Clip / Hashed in Eevee and you left the cut-out at 0, export uses 0.5. That matches how leaves and fences usually want to look.

## LOD

The game swaps to a cheaper mesh as you walk away. Name the stand-ins so the cooker (and this extension) can group them:

```text
robot
_L1_robot
_L2_robot
```

`$L1_robot` and `robot_lod1` work too. I prefer the `_L1_` prefix. Physics proxies named `_PP_body` or `$PP_body` are skipped on export.

The switch distances are not on the mesh. They are a comma-separated string on the **part collection** (`Collection.visu_lod_distances`):

```text
6, 14
```

First number is when `_L1_` takes over, then `_L2_`, and so on. The cooker wants `lods - 1` numbers. Empty uses engine defaults (20, 50, 100, ...).

The N-panel **LOD preview** hides every stand-in except the one the game would show at that distance. **All** unhides everything so you can edit; they sit on top of each other, which is ugly on purpose.

Here is the catch: the part fields (distances, cull, impostor, "moves in the game") only appear when that inner part collection is the active Outliner collection. Click the collection, not the mesh.

**Farthest mesh is a card** marks the last LOD as an impostor in the `.vmod`. It does not change which files are written, and the game does not billboard it yet.

## Several parts

One object: skip this. Two unique meshes (crate and lid, body and wheels): put each in its own collection, tick **This collection is one mesh**, and parent both under one collection tagged **Export this collection**.

```text
robot                 # Export this collection
  body                # This collection is one mesh
    body
    _L1_body
  wheel_fl
    wheel_fl
    _L1_wheel_fl
```

Each part keeps its own LOD table, cull distance, and dynamic flag. That is the whole point. A walking character is dynamic. A bush is not, and is cheaper to draw.

## Import

File > Import > VISU model. Pick either the `.glb` or the `.vmod` in the same folder.

The `.vmod` is JSON. It is not the mesh. Import loads the sibling `.glb`, puts each named mesh in its own collection, hides `_L1_` through `_L5_` stand-ins, and wires textures from the PNG files named in each `.vmat`. The sidecars are the source of truth for maps.

## Tests

The JSON / LOD / filename tests do not need Blender. From the visu repo root:

```bash
python3 -m pytest tools/blender/visu_io/tests
```
