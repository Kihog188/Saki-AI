import json
import os

import pytest

from saki.characters import MAX_IMAGE_BYTES, MAX_MANIFEST_BYTES, CharacterStore
from saki.postprocess import EMOTIONS

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


def make_pack(data_dir, pack_id="mine", manifest=None, files=("neutral.png",)):
    folder = data_dir / "characters" / pack_id
    folder.mkdir(parents=True)
    for name in files:
        (folder / name).write_bytes(PNG)
    if manifest is None:
        manifest = {"format": 1, "name": "Của tôi", "author": "Tôi", "default": "neutral.png"}
    text = manifest if isinstance(manifest, str) else json.dumps(manifest, ensure_ascii=False)
    (folder / "manifest.json").write_text(text, encoding="utf-8")
    return folder


def packs_by_id(client):
    return {p["id"]: p for p in client.get("/characters").json()["packs"]}


# --- listing and manifests ------------------------------------------------------------


def test_builtin_pack_is_listed_and_complete(web):
    client, _ = web
    packs = packs_by_id(client)
    assert packs["default"]["valid"] is True and packs["default"]["builtin"] is True
    m = client.get("/characters/default/manifest").json()
    assert m["format"] == 1 and m["idle_seconds"] == 10
    assert set(m["emotions"]) == set(EMOTIONS)
    assert m["emotions"]["happy"] == "/characters/default/files/happy.svg"
    for emo in EMOTIONS:
        r = client.get(m["emotions"][emo])
        assert r.status_code == 200
        assert r.headers["content-type"] == "image/svg+xml"
        assert r.headers["x-content-type-options"] == "nosniff"


def test_valid_user_pack_with_missing_emotions_falls_back_to_default(web):
    client, data_dir = web
    make_pack(
        data_dir,
        manifest={
            "format": 1, "name": "Của tôi", "default": "neutral.png", "idle_seconds": 5,
            "emotions": {"happy": "happy.png"},
        },
        files=("neutral.png", "happy.png"),
    )
    assert packs_by_id(client)["mine"] == {
        "id": "mine", "name": "Của tôi", "author": "", "builtin": False, "valid": True, "error": None,
    }
    m = client.get("/characters/mine/manifest").json()
    assert m["idle_seconds"] == 5
    assert m["emotions"]["happy"].endswith("/happy.png")
    assert m["emotions"]["sad"] == m["default"] == "/characters/mine/files/neutral.png"
    r = client.get("/characters/mine/files/happy.png")
    assert r.status_code == 200 and r.content == PNG
    assert r.headers["content-type"] == "image/png"
    assert r.headers["x-content-type-options"] == "nosniff"


@pytest.mark.parametrize(
    "manifest, files, error_part",
    [
        ("{not json", ("neutral.png",), "JSON"),
        ("[]", ("neutral.png",), "object"),
        ({"format": 2, "name": "x", "default": "neutral.png"}, ("neutral.png",), "format"),
        ({"format": 1, "name": "x", "default": "neutral.png"}, (), "không tìm thấy"),
        ({"format": 1, "name": "", "default": "neutral.png"}, ("neutral.png",), "name"),
        ({"format": 1, "name": "x", "default": "a.svg"}, ("a.svg",), "chỉ chấp nhận"),
        ({"format": 1, "name": "x", "default": "../saki.db"}, (), "tên tệp"),
        ({"format": 1, "name": "x", "default": "n.png", "emotions": {"angry": "n.png"}}, ("n.png",), "angry"),
        ({"format": 1, "name": "x", "default": "n.png", "emotions": {"sad": "s.png"}}, ("n.png",), "sad"),
        ({"format": 1, "name": "x", "default": "n.png", "idle_seconds": 0}, ("n.png",), "idle_seconds"),
    ],
)
def test_invalid_user_packs_are_listed_with_error(web, manifest, files, error_part):
    client, data_dir = web
    make_pack(data_dir, manifest=manifest, files=files)
    pack = packs_by_id(client)["mine"]
    assert pack["valid"] is False and error_part in pack["error"]
    r = client.get("/characters/mine/manifest")
    assert r.status_code == 404 and r.json()["detail"] == pack["error"]


def test_too_large_manifest_is_invalid(web):
    client, data_dir = web
    make_pack(data_dir, manifest='{"format": 1, "pad": "' + "x" * MAX_MANIFEST_BYTES + '"}')
    assert "64 KB" in packs_by_id(client)["mine"]["error"]


def test_oversized_image_is_invalid_and_not_served(web):
    client, data_dir = web
    folder = make_pack(data_dir)
    (folder / "neutral.png").write_bytes(b"\0" * (MAX_IMAGE_BYTES + 1))
    assert "5 MB" in packs_by_id(client)["mine"]["error"]
    assert client.get("/characters/mine/files/neutral.png").status_code == 404


def test_bad_folder_name_is_listed_invalid(web):
    client, data_dir = web
    make_pack(data_dir, pack_id="có dấu")
    pack = packs_by_id(client)["có dấu"]
    assert pack["valid"] is False and "chữ, số" in pack["error"]


def test_user_folder_cannot_shadow_builtin_pack(web):
    client, data_dir = web
    make_pack(data_dir, pack_id="default")
    packs = client.get("/characters").json()["packs"]
    assert [p["id"] for p in packs].count("default") == 1
    assert client.get("/characters/default/manifest").json()["builtin"] is True


# --- file serving security ------------------------------------------------------------


@pytest.mark.parametrize(
    "path",
    [
        "/characters/mine/files/..%2f..%2fsaki.db",
        "/characters/mine/files/%2e%2e",
        "/characters/mine/files/..",
        "/characters/%2e%2e/files/saki.db",
        "/characters/mine/files/C:%5Cwindows%5Cwin.ini",
        "/characters/mine/files/%2Fetc%2Fpasswd",
        "/characters/mine/files/manifest.json",
        "/characters/mine/files/extra.png",  # exists, but the manifest does not reference it
        "/characters/mine/files/evil.svg",
        "/characters/mine/files/evil.html",
        "/characters/mine/files/evil.js",
        "/characters/nope/files/neutral.png",
    ],
)
def test_file_requests_outside_the_manifest_are_rejected(web, path):
    client, data_dir = web
    folder = make_pack(data_dir, files=("neutral.png", "extra.png"))
    for name in ("evil.svg", "evil.html", "evil.js"):
        (folder / name).write_text("<script>alert(1)</script>", encoding="utf-8")
    (data_dir / "saki.db").touch()
    r = client.get(path)
    assert r.status_code in (400, 404)
    assert b"script" not in r.content


def test_store_rejects_traversal_directly(tmp_path):
    make_pack(tmp_path)
    store = CharacterStore(tmp_path)
    for pack_id, filename in [("..", "neutral.png"), ("mine", "../mine/neutral.png"), ("mine", "/etc/passwd")]:
        with pytest.raises(ValueError):
            store.image(pack_id, filename)


def test_symlinked_image_leaving_the_pack_is_rejected(web, tmp_path_factory):
    client, data_dir = web
    folder = make_pack(data_dir, files=())
    outside = tmp_path_factory.mktemp("outside") / "secret.png"
    outside.write_bytes(PNG)
    try:
        os.symlink(outside, folder / "neutral.png")
    except (OSError, NotImplementedError):
        pytest.skip("creating symlinks is not allowed here")
    assert packs_by_id(client)["mine"]["valid"] is False
    assert client.get("/characters/mine/files/neutral.png").status_code == 404


# --- character_pack setting ------------------------------------------------------------


def test_character_pack_setting_is_validated_and_persisted(web):
    client, data_dir = web
    assert client.get("/settings").json()["character_pack"] == "default"
    make_pack(data_dir)
    r = client.put("/settings", json={"character_pack": "mine"})
    assert r.status_code == 200 and r.json()["character_pack"] == "mine"
    assert client.get("/settings").json()["character_pack"] == "mine"

    r = client.put("/settings", json={"character_pack": "khong-co"})
    assert r.status_code == 400 and "khong-co" in r.json()["detail"]
    make_pack(data_dir, pack_id="broken", manifest="{")
    assert client.put("/settings", json={"character_pack": "broken"}).status_code == 400
    assert client.put("/settings", json={"character_pack": "../x"}).status_code == 400
    assert client.get("/settings").json()["character_pack"] == "mine"
