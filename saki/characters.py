"""Character packs: a manifest plus one image per emotion.

Built-in packs ship inside the package (`saki/packs/`) and are trusted, so they may use
SVG. User packs live in `<data_dir>/characters/<pack_id>/` and are untrusted: strict
names, raster images only, size limits, and every path must stay inside the pack folder.
Nothing in a manifest is ever executed or inserted as HTML.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .postprocess import EMOTIONS

PACK_FORMAT = 1
BUILTIN_DIR = Path(__file__).parent / "packs"
DEFAULT_PACK = "default"

MAX_MANIFEST_BYTES = 64 * 1024
MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_NAME_CHARS = 50
MAX_AUTHOR_CHARS = 100
DEFAULT_IDLE_SECONDS = 10

PACK_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
FILENAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,100}\.[A-Za-z0-9]{1,5}$")

RASTER_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
}
BUILTIN_TYPES = {**RASTER_TYPES, ".svg": "image/svg+xml"}


class PackError(ValueError):
    """The pack is missing or invalid. The message is user-facing Vietnamese."""


@dataclass(frozen=True)
class Pack:
    id: str
    name: str
    author: str
    default: str
    idle_seconds: float
    emotions: dict[str, str]  # every emotion -> filename, missing ones resolved to `default`
    builtin: bool

    @property
    def files(self) -> set[str]:
        return {self.default, *self.emotions.values()}

    def to_dict(self) -> dict:
        def url(name: str) -> str:
            return f"/characters/{self.id}/files/{name}"

        return {
            "format": PACK_FORMAT,
            "id": self.id,
            "name": self.name,
            "author": self.author,
            "builtin": self.builtin,
            "idle_seconds": self.idle_seconds,
            "default": url(self.default),
            "emotions": {emo: url(name) for emo, name in self.emotions.items()},
        }


class CharacterStore:
    """Finds, validates and resolves packs. Nothing is cached: packs are re-read on use."""

    def __init__(self, data_dir: Path, builtin_dir: Path = BUILTIN_DIR):
        self.user_dir = Path(data_dir) / "characters"
        self.builtin_dir = builtin_dir

    def list(self) -> list[dict]:
        """All packs, built-in first, as `{id, name, author, builtin, valid, error}`."""
        out = []
        for pack_id, builtin in self._candidates():
            try:
                pack = self.load(pack_id)
                out.append(_summary(pack_id, pack.name, pack.author, builtin, None))
            except PackError as exc:
                out.append(_summary(pack_id, pack_id, "", builtin, str(exc)))
        return out

    def is_valid(self, pack_id: str) -> bool:
        try:
            self.load(pack_id)
        except PackError:
            return False
        return True

    def load(self, pack_id: str) -> Pack:
        folder, builtin = self._folder(pack_id)
        types = BUILTIN_TYPES if builtin else RASTER_TYPES
        manifest = _read_manifest(folder)

        if manifest.get("format") != PACK_FORMAT:
            raise PackError(f"manifest.json phải có \"format\": {PACK_FORMAT}.")
        name = manifest.get("name")
        if not isinstance(name, str) or not name.strip() or len(name) > MAX_NAME_CHARS:
            raise PackError(f"\"name\" phải là chuỗi 1–{MAX_NAME_CHARS} ký tự.")
        author = manifest.get("author", "")
        if not isinstance(author, str) or len(author) > MAX_AUTHOR_CHARS:
            raise PackError(f"\"author\" phải là chuỗi tối đa {MAX_AUTHOR_CHARS} ký tự.")
        idle = manifest.get("idle_seconds", DEFAULT_IDLE_SECONDS)
        if isinstance(idle, bool) or not isinstance(idle, (int, float)) or not 1 <= idle <= 3600:
            raise PackError("\"idle_seconds\" phải là số từ 1 đến 3600.")

        default = manifest.get("default")
        _check_image(folder, default, types, "default")
        emotions = manifest.get("emotions", {})
        if not isinstance(emotions, dict):
            raise PackError("\"emotions\" phải là một object.")
        resolved = {}
        for emo in EMOTIONS:
            filename = emotions.get(emo)
            if filename is None:
                resolved[emo] = default
            else:
                _check_image(folder, filename, types, f"emotions.{emo}")
                resolved[emo] = filename
        unknown = sorted(set(emotions) - set(EMOTIONS))
        if unknown:
            raise PackError(f"Cảm xúc không hỗ trợ: {', '.join(unknown)}.")
        return Pack(pack_id, name.strip(), author.strip(), default, idle, resolved, builtin)

    def image(self, pack_id: str, filename: str) -> tuple[Path, str]:
        """Path and content type of one image of a valid pack, or PackError."""
        if not isinstance(filename, str) or not FILENAME_RE.match(filename):
            raise PackError("Tên tệp không hợp lệ.")
        pack = self.load(pack_id)
        if filename not in pack.files:
            raise PackError("Tệp không thuộc gói nhân vật.")
        folder, builtin = self._folder(pack_id)
        types = BUILTIN_TYPES if builtin else RASTER_TYPES
        path = _check_image(folder, filename, types, filename)
        return path, types[path.suffix.lower()]

    # --- internals -------------------------------------------------------------

    def _candidates(self) -> list[tuple[str, bool]]:
        found = []
        if self.builtin_dir.is_dir():
            found += [(p.name, True) for p in sorted(self.builtin_dir.iterdir()) if p.is_dir()]
        builtin_ids = {pid for pid, _ in found}
        if self.user_dir.is_dir():
            found += [
                (p.name, False)
                for p in sorted(self.user_dir.iterdir())
                if p.is_dir() and p.name not in builtin_ids
            ]
        return found

    def _folder(self, pack_id: str) -> tuple[Path, bool]:
        if not isinstance(pack_id, str) or not PACK_ID_RE.match(pack_id):
            raise PackError("Tên gói nhân vật chỉ được gồm chữ, số, '-' và '_'.")
        builtin = self.builtin_dir / pack_id
        if builtin.is_dir():
            return builtin, True
        folder = self.user_dir / pack_id
        if folder.is_symlink() or not folder.is_dir():
            raise PackError(f"Không tìm thấy gói nhân vật '{pack_id}'.")
        if folder.resolve().parent != self.user_dir.resolve():
            raise PackError("Thư mục gói nhân vật nằm ngoài thư mục characters.")
        return folder, False


def _summary(pack_id: str, name: str, author: str, builtin: bool, error: str | None) -> dict:
    return {
        "id": pack_id,
        "name": name,
        "author": author,
        "builtin": builtin,
        "valid": error is None,
        "error": error,
    }


def _read_manifest(folder: Path) -> dict:
    path = folder / "manifest.json"
    if path.is_symlink() or not path.is_file():
        raise PackError("Thiếu tệp manifest.json.")
    if path.stat().st_size > MAX_MANIFEST_BYTES:
        raise PackError("manifest.json quá lớn (tối đa 64 KB).")
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, ValueError):
        raise PackError("manifest.json không phải JSON hợp lệ.") from None
    if not isinstance(data, dict):
        raise PackError("manifest.json phải là một object JSON.")
    return data


def _check_image(folder: Path, filename: object, types: dict[str, str], field: str) -> Path:
    """Validate one image reference and return its path inside `folder`."""
    if not isinstance(filename, str) or not FILENAME_RE.match(filename):
        raise PackError(f"\"{field}\": tên tệp không hợp lệ.")
    ext = Path(filename).suffix.lower()
    if ext not in types:
        allowed = ", ".join(sorted(types))
        raise PackError(f"\"{field}\": chỉ chấp nhận ảnh {allowed}.")
    path = folder / filename
    if path.is_symlink() or not path.is_file():
        raise PackError(f"\"{field}\": không tìm thấy tệp {filename}.")
    if path.resolve().parent != folder.resolve():
        raise PackError(f"\"{field}\": tệp nằm ngoài thư mục gói.")
    if path.stat().st_size > MAX_IMAGE_BYTES:
        raise PackError(f"\"{field}\": ảnh {filename} quá lớn (tối đa 5 MB).")
    return path
