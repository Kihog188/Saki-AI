class_name PackRules
## Limits and path rules for character packs. Packs are UNTRUSTED data: everything a pack
## contains is checked against these rules before it is copied or loaded.
## Shared by the zip validator, the folder validator and the loader. No UI dependency.

const MAX_ZIP_BYTES: int = 50 * 1024 * 1024
const MAX_TOTAL_BYTES: int = 200 * 1024 * 1024
const MAX_FILES: int = 2000
const MAX_MANIFEST_BYTES: int = 64 * 1024
## Uncompressed / compressed size of one entry above this = zip bomb.
const MAX_COMPRESSION_RATIO: float = 200.0
## Image hard limits (larger = rejected). Downscaling happens below these.
const MAX_IMAGE_SIDE: int = 8192
const MAX_IMAGE_PIXELS: int = 8192 * 4096
## Frames in one animation (sheet cells used or frame list length).
const MAX_FRAMES: int = 120
## Images bigger than this are downscaled on import (the "Cao" tier limit).
const IMPORT_MAX_TEXTURE: int = 4096
const THUMBNAIL_SIZE: int = 160

const ALLOWED_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "json", "txt"]
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]

## Pack ids: lowercase ASCII, digits, - and _, starting with a letter or digit.
const ID_PATTERN: String = "^[a-z0-9][a-z0-9_-]{0,63}$"
## Each part of a file path inside a pack. No leading dot, no spaces, ASCII only.
const SEGMENT_PATTERN: String = "^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$"
## Emotion and state names (open list, but safe characters only).
const NAME_PATTERN: String = "^[a-z][a-z0-9_]{0,31}$"

static var _segment_re: RegEx
static var _id_re: RegEx
static var _name_re: RegEx


static func is_valid_id(id: String) -> bool:
	if _id_re == null:
		_id_re = RegEx.create_from_string(ID_PATTERN)
	return _id_re.search(id) != null


static func is_valid_name(name: String) -> bool:
	if _name_re == null:
		_name_re = RegEx.create_from_string(NAME_PATTERN)
	return _name_re.search(name) != null


## Returns "" if `path` is a safe relative path inside a pack, otherwise the
## translation key of the broken rule. Directory entries end with "/".
static func check_path(path: String) -> String:
	if path.is_empty():
		return "PACK_ERR_PATH_EMPTY"
	if path.contains("\\"):
		return "PACK_ERR_PATH_BACKSLASH"
	if path.begins_with("/") or (path.length() > 1 and path[1] == ":"):
		return "PACK_ERR_PATH_ABSOLUTE"
	var trimmed: String = path.trim_suffix("/")
	if _segment_re == null:
		_segment_re = RegEx.create_from_string(SEGMENT_PATTERN)
	for seg: String in trimmed.split("/"):
		if seg == ".." or seg == ".":
			return "PACK_ERR_PATH_TRAVERSAL"
		if _segment_re.search(seg) == null:
			return "PACK_ERR_PATH_CHARS"
	if trimmed.split("/").size() > 4:
		return "PACK_ERR_PATH_DEEP"
	return ""


static func extension_allowed(path: String) -> bool:
	return ALLOWED_EXTENSIONS.has(path.get_extension().to_lower())


static func is_image(path: String) -> bool:
	return IMAGE_EXTENSIONS.has(path.get_extension().to_lower())
