from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent))

from visu_io import lod, vmod, vmat
from visu_io.ops import resolve_mesh_path, vmat_for_name


def test_lod_names():
    assert lod.lod_level("ball") == 0
    assert lod.lod_level("_L1_ball") == 1
    assert lod.lod_level("$L4_bush") == 4
    assert lod.lod_level("bush_lod2") == 2
    assert lod.lod_level("_PP_body") == -2
    assert lod.lod_base("_L3_bush_01") == "bush_01"
    assert lod.lod_node_name("body", 2) == "_L2_body"


def test_shown_level_clamps_like_the_game():
    assert lod.shown_level([0, 1, 2, 3, 4], 0) == 0
    assert lod.shown_level([0, 1, 2, 3, 4], 2) == 2
    assert lod.shown_level([0, 1, 2, 3, 4], 5) == 4
    assert lod.shown_level([0, 1], 4) == 1
    assert lod.shown_level([0], 3) == 0


def test_visible_names_one_family():
    objs = [
        ("bush_01", 0, "bush_01"),
        ("_L1_bush_01", 1, "bush_01"),
        ("_L4_bush_01", 4, "bush_01"),
        ("bush_03", 0, "bush_03"),
    ]
    assert lod.visible_names(objs, 0) == {"bush_01", "bush_03"}
    assert lod.visible_names(objs, 1) == {"_L1_bush_01", "bush_03"}
    assert lod.visible_names(objs, 4) == {"_L4_bush_01", "bush_03"}
    assert lod.visible_names(objs, None) == {"bush_01", "_L1_bush_01", "_L4_bush_01", "bush_03"}


def test_vmod_shorthand_roundtrip(tmp_path: Path):
    src = {
        "lod": [6, 14],
        "cullDistance": 60,
        "slots": {"skin": "props/ball/skin"},
    }
    path = tmp_path / "ball.vmod"
    vmod.dump(path, vmod.canonical(src, stem="ball"))
    got = vmod.load(path)
    assert "ball" in got["parts"]
    assert got["parts"]["ball"]["cullDistance"] == 60
    compact = vmod.compact(got)
    assert compact["lod"] == [6, 14]
    assert "parts" not in compact


def test_vmat_roundtrip(tmp_path: Path):
    path = tmp_path / "skin.vmat"
    vmat.dump(path, {"albedo": "ball_albedo", "metallicFactor": 0.0})
    got = vmat.load(path)
    assert got["albedo"] == "ball_albedo"


def test_map_files_finds_sibling_pngs(tmp_path: Path):
    (tmp_path / "bush_diff.png").write_bytes(b"x")
    (tmp_path / "bush_normal.png").write_bytes(b"x")
    (tmp_path / "bush_roughness.png").write_bytes(b"x")
    (tmp_path / "bush_alpha.png").write_bytes(b"x")
    files = vmat.map_files(
        tmp_path,
        {
            "albedo": "bush_diff",
            "normal": "bush_normal",
            "rough": "bush_roughness",
            "alpha": "bush_alpha",
        },
    )
    assert files["albedo"].name == "bush_diff.png"
    assert files["normal"].name == "bush_normal.png"
    assert files["rough"].name == "bush_roughness.png"
    assert files["alpha"].name == "bush_alpha.png"
    assert "metal" not in files


def test_map_files_skips_missing_glb_uris(tmp_path: Path):
    files = vmat.map_files(tmp_path, {"albedo": "diffuse.png.007.png"})
    assert files == {}


def test_vmat_for_name_keeps_dots():
    mats = {"model.bush": {"albedo": "bush_diff"}}
    assert vmat_for_name("model.bush", mats)["albedo"] == "bush_diff"
    assert vmat_for_name("model.bush.001", {"model.bush.001": {"albedo": "a"}})["albedo"] == "a"


def test_resolve_mesh_path_from_vmod(tmp_path: Path):
    glb = tmp_path / "bush_01.glb"
    glb.write_bytes(b"glTF")
    sidecar = tmp_path / "bush_01.vmod"
    sidecar.write_text("{}")
    assert resolve_mesh_path(sidecar) == glb
    assert resolve_mesh_path(glb) == glb
    assert resolve_mesh_path(tmp_path / "missing.vmod") is None
