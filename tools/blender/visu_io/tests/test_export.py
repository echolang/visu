from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent))

from visu_io import export, names, png, vmod


def test_stem_from_name():
    assert names.stem_from_name("Material_0.001") == "Material_0.001"
    assert names.stem_from_name("skin/body") == "skin_body"
    assert names.stem_from_name("...") == "material"


def test_file_stem_reuses_blender_duplicate():
    known = {"model.bush"}
    assert names.file_stem("model.bush.001", known) == "model.bush"
    assert names.file_stem("model.bush.001", set()) == "model.bush.001"
    assert names.file_stem("Material_0.001") == "Material_0.001"


def test_folder_id_under_source(tmp_path: Path):
    folder = tmp_path / "resources" / "source" / "props" / "testsrobot"
    folder.mkdir(parents=True)
    glb = folder / "robot.glb"
    glb.write_bytes(b"")
    assert names.folder_id(glb) == "props/testsrobot"


def test_folder_id_elsewhere(tmp_path: Path):
    folder = tmp_path / "out"
    folder.mkdir()
    glb = folder / "robot.glb"
    glb.write_bytes(b"")
    assert names.folder_id(glb) == "out"


def test_catalog_id():
    assert names.catalog_id("props/testsrobot", "body") == "props/testsrobot/body"
    assert names.catalog_id("", "body") == "body"


def test_assembly_single_part_sets_model_id():
    parts = [{"name": "Mesh1.0", "slots": {"Material_0.001": "Material_0.001"}}]
    asm = export.assembly_for_parts("robot", "props/testsrobot", parts)
    rec = asm["parts"]["Mesh1.0"]
    assert rec["model"] == "props/testsrobot/robot"
    assert rec["slots"]["Material_0.001"] == "props/testsrobot/Material_0.001"


def test_compact_keeps_full_form_when_part_is_not_the_stem():
    parts = [{"name": "Mesh1.0", "slots": {"skin": "body"}}]
    asm = export.assembly_for_parts("robot", "props/x", parts)
    compact = vmod.compact(asm, stem="robot")
    assert "parts" in compact
    assert "Mesh1.0" in compact["parts"]


def test_compact_shorthand_when_part_matches_stem():
    parts = [{"name": "robot", "slots": {"skin": "body"}}]
    asm = export.assembly_for_parts("robot", "props/x", parts)
    compact = vmod.compact(asm, stem="robot")
    assert "parts" not in compact
    assert compact["slots"]["skin"] == "props/x/body"
    assert compact["model"] == "props/x/robot"


def test_vmat_from_maps_omits_defaults():
    data = export.vmat_from_maps(
        {"albedo": "a", "normal": "n"},
        roughness_factor=0.8,
        metallic_factor=0.0,
        backface_cull=False,
    )
    assert data["albedo"] == "a"
    assert data["normal"] == "n"
    assert "roughnessFactor" not in data
    assert data["backfaceCull"] is False


def test_png_channel_roundtrip(tmp_path: Path):
    rgba = bytes(
        [
            255, 10, 0, 255,
            0, 20, 0, 255,
            0, 30, 0, 255,
            0, 40, 0, 255,
        ]
    )
    src = tmp_path / "packed.png"
    png.write_rgba(src, 2, 2, rgba)
    w, h, bpp, pixels = png.read(src)
    assert (w, h, bpp) == (2, 2, 4)
    gray = png.channel(pixels, 4, 1)
    assert list(gray) == [10, 20, 30, 40]
    out = tmp_path / "rough.png"
    png.write_gray_as_rgb(out, 2, 2, gray)
    _, _, bpp2, rgb = png.read(out)
    assert bpp2 == 3
    assert rgb[0:3] == bytes([10, 10, 10])


def test_write_asset_sidecars(tmp_path: Path):
    glb = tmp_path / "props" / "testsrobot" / "robot.glb"
    glb.parent.mkdir(parents=True)
    glb.write_bytes(b"")
    parts = [{"name": "Mesh1.0", "slots": {"Material_0.001": "Material_0.001"}}]
    folder = names.folder_id(glb)
    asm = export.assembly_for_parts("robot", folder, parts)
    mats = {
        "Material_0.001": export.vmat_from_maps(
            {"albedo": "Material_0.001_albedo", "normal": "Material_0.001_normal"},
            backface_cull=False,
        )
    }
    vtex = {"Material_0.001_normal": {"srgb": False}}
    export.write_asset(glb, asm, mats, vtex)
    vmod_data = json.loads((glb.with_suffix(".vmod")).read_text())
    assert "Mesh1.0" in vmod_data["parts"]
    assert vmod_data["parts"]["Mesh1.0"]["model"].endswith("/robot")
    mat = json.loads((glb.parent / "Material_0.001.vmat").read_text())
    assert mat["albedo"] == "Material_0.001_albedo"
    tex = json.loads((glb.parent / "Material_0.001_normal.vtex").read_text())
    assert tex["srgb"] is False
