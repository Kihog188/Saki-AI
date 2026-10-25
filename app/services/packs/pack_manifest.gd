class_name PackManifest
extends RefCounted
## Parsed and validated manifest.json (format 1). See PACK_GUIDE.md for every field.
##
## PackManifest.parse(text) never throws: check `errors` (Vietnamese, one per broken rule)
## and `unsupported` (format newer than this app, or not a number). Unknown fields are
## ignored. For types other than "2d" only the common fields are checked, so packs of
## future types (e.g. "3d-gltf") are still listed with their thumbnail.
##
## Each animation entry (in `emotions` and `states`) is normalised to:
##   {"kind": "image"|"sheet"|"frames", "files": PackedStringArray,
##    "columns": int, "rows": int, "frames": int, "fps": float, "loop": bool}

const FORMAT: int = 1
const DEFAULT_FPS: float = 8.0

var format: int = 0
var id: String = ""
var name: String = ""
var author: String = ""
var version: String = ""
var license: String = ""
var type: String = ""
var thumbnail: String = ""
var default_emotion: String = SakiConst.DEFAULT_EMOTION
var base_scale: float = 1.0
var anchor: Vector2 = Vector2(0.5, 1.0)
## Seconds before returning to neutral; <= 0 means "use the app default".
var idle_seconds: float = 0.0
var emotions: Dictionary = {}
var states: Dictionary = {}

var errors: PackedStringArray = []
var unsupported: bool = false


func is_valid() -> bool:
	return errors.is_empty() and not unsupported


## Every file the manifest refers to (thumbnail and all animation frames), no duplicates.
func referenced_files() -> PackedStringArray:
	var out: PackedStringArray = []
	if thumbnail != "":
		out.append(thumbnail)
	for group: Dictionary in [emotions, states]:
		for entry: Dictionary in group.values():
			for f: String in entry["files"]:
				if not out.has(f):
					out.append(f)
	return out


func first_error() -> String:
	if unsupported:
		return I18n.t("PACK_ERR_FORMAT_NEWER", {"format": format})
	return errors[0] if errors.size() > 0 else ""


static func parse(text: String) -> PackManifest:
	var m := PackManifest.new()
	if text.to_utf8_buffer().size() > PackRules.MAX_MANIFEST_BYTES:
		m.errors.append(I18n.t("PACK_ERR_MANIFEST_SIZE"))
		return m
	var json := JSON.new()
	if json.parse(text) != OK:
		m.errors.append(I18n.t("PACK_ERR_MANIFEST_JSON", {"line": json.get_error_line(), "msg": json.get_error_message()}))
		return m
	if not json.data is Dictionary:
		m.errors.append(I18n.t("PACK_ERR_MANIFEST_JSON", {"line": 1, "msg": "not an object"}))
		return m
	m._read(json.data)
	return m


func _read(d: Dictionary) -> void:
	var fmt: Variant = d.get("format")
	if not (fmt is float or fmt is int) or float(fmt) != floorf(float(fmt)):
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": "format", "rule": I18n.t("PACK_RULE_INT")}))
		return
	format = int(fmt)
	if format > FORMAT:
		unsupported = true
		return
	if format < 1:
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": "format", "rule": I18n.t("PACK_RULE_FORMAT")}))
		return

	id = _string(d, "id", true)
	if id != "" and not PackRules.is_valid_id(id):
		errors.append(I18n.t("PACK_ERR_ID"))
	name = _string(d, "name", true).strip_edges()
	if name.length() > 60:
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": "name", "rule": I18n.t("PACK_RULE_MAX_CHARS").format({"n": 60})}))
	author = _string(d, "author", false).left(60)
	version = _string(d, "version", false).left(20)
	license = _string(d, "license", false).left(200)
	type = _string(d, "type", true)
	thumbnail = _string(d, "thumbnail", false)
	if thumbnail != "":
		_check_image_path("thumbnail", thumbnail)
	if d.has("default_emotion"):
		default_emotion = _string(d, "default_emotion", false)
		if not PackRules.is_valid_name(default_emotion):
			errors.append(I18n.t("PACK_ERR_FIELD", {"field": "default_emotion", "rule": I18n.t("PACK_RULE_NAME")}))
	base_scale = _number(d, "base_scale", 1.0, 0.1, 4.0)
	idle_seconds = _number(d, "idle_seconds", 0.0, 1.0, 3600.0)
	if d.has("anchor"):
		var a: Variant = d["anchor"]
		if a is Array and a.size() == 2 and (a[0] is float or a[0] is int) and (a[1] is float or a[1] is int) \
				and float(a[0]) >= 0.0 and float(a[0]) <= 1.0 and float(a[1]) >= 0.0 and float(a[1]) <= 1.0:
			anchor = Vector2(float(a[0]), float(a[1]))
		else:
			errors.append(I18n.t("PACK_ERR_FIELD", {"field": "anchor", "rule": I18n.t("PACK_RULE_ANCHOR")}))

	if type != "2d":
		return # other types: the renderer for that type validates its own fields
	emotions = _read_group(d, "emotions")
	states = _read_group(d, "states")
	if emotions.is_empty() and states.is_empty() and errors.is_empty():
		errors.append(I18n.t("PACK_ERR_NO_EMOTIONS"))


func _read_group(d: Dictionary, group: String) -> Dictionary:
	var out: Dictionary = {}
	if not d.has(group):
		return out
	if not d[group] is Dictionary:
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": group, "rule": I18n.t("PACK_RULE_OBJECT")}))
		return out
	for key: Variant in d[group]:
		var field: String = "%s.%s" % [group, key]
		if not key is String or not PackRules.is_valid_name(key):
			errors.append(I18n.t("PACK_ERR_FIELD", {"field": field, "rule": I18n.t("PACK_RULE_NAME")}))
			continue
		var raw: Variant = d[group][key]
		if not raw is Dictionary:
			errors.append(I18n.t("PACK_ERR_FIELD", {"field": field, "rule": I18n.t("PACK_RULE_OBJECT")}))
			continue
		var entry: Variant = _read_entry(field, raw)
		if entry != null:
			out[key] = entry
	return out


## One animation entry, or null after recording an error.
func _read_entry(field: String, raw: Dictionary) -> Variant:
	# In a sheet, "frames" is the frame COUNT; elsewhere it is the list of frame files.
	var kinds: Array[String] = []
	for k: String in ["image", "sheet", "frames"]:
		if raw.has(k) and not (k == "frames" and raw.has("sheet")):
			kinds.append(k)
	if kinds.size() != 1:
		errors.append(I18n.t("PACK_ERR_ENTRY_KIND", {"field": field}))
		return null
	var entry: Dictionary = {
		"kind": kinds[0], "files": PackedStringArray(), "columns": 1, "rows": 1, "frames": 1,
		"fps": DEFAULT_FPS, "loop": true,
	}
	var before: int = errors.size()
	match kinds[0]:
		"image":
			var f: String = _string(raw, "image", true, field)
			_check_image_path(field + ".image", f)
			entry["files"] = PackedStringArray([f])
		"sheet":
			var f: String = _string(raw, "sheet", true, field)
			_check_image_path(field + ".sheet", f)
			entry["files"] = PackedStringArray([f])
			var columns: int = _int_field(raw, "columns", field, 1, 64, -1)
			var rows: int = _int_field(raw, "rows", field, 1, 64, -1)
			if columns > 0 and rows > 0:
				entry["columns"] = columns
				entry["rows"] = rows
				var frames: int = _int_field(raw, "frames", field, 1, columns * rows, columns * rows)
				entry["frames"] = frames
				if frames > PackRules.MAX_FRAMES:
					errors.append(I18n.t("PACK_ERR_TOO_MANY_FRAMES", {"field": field, "n": PackRules.MAX_FRAMES}))
		"frames":
			var list: Variant = raw["frames"]
			if not list is Array or list.is_empty():
				errors.append(I18n.t("PACK_ERR_FIELD", {"field": field + ".frames", "rule": I18n.t("PACK_RULE_FILE_LIST")}))
			elif list.size() > PackRules.MAX_FRAMES:
				errors.append(I18n.t("PACK_ERR_TOO_MANY_FRAMES", {"field": field, "n": PackRules.MAX_FRAMES}))
			else:
				var files: PackedStringArray = []
				for i: int in list.size():
					if not list[i] is String:
						errors.append(I18n.t("PACK_ERR_FIELD", {"field": "%s.frames[%d]" % [field, i], "rule": I18n.t("PACK_RULE_STRING")}))
						continue
					_check_image_path("%s.frames[%d]" % [field, i], list[i])
					files.append(list[i])
				entry["files"] = files
				entry["frames"] = files.size()
	if raw.has("fps"):
		entry["fps"] = _number(raw, "fps", DEFAULT_FPS, 0.5, 60.0, field)
	if raw.has("loop"):
		if raw["loop"] is bool:
			entry["loop"] = raw["loop"]
		else:
			errors.append(I18n.t("PACK_ERR_FIELD", {"field": field + ".loop", "rule": I18n.t("PACK_RULE_BOOL")}))
	return entry if errors.size() == before else null


func _check_image_path(field: String, path: String) -> void:
	if path == "":
		return # the missing-field error is already recorded
	var rule: String = PackRules.check_path(path)
	if rule != "":
		errors.append(I18n.t("PACK_ERR_FILE_RULE", {"file": path, "rule": I18n.t(rule)}) + " (%s)" % field)
	elif not PackRules.is_image(path):
		errors.append(I18n.t("PACK_ERR_NOT_IMAGE", {"file": path, "field": field}))


func _string(d: Dictionary, key: String, required: bool, prefix: String = "") -> String:
	var field: String = key if prefix == "" else "%s.%s" % [prefix, key]
	if not d.has(key):
		if required:
			errors.append(I18n.t("PACK_ERR_MISSING", {"field": field}))
		return ""
	if not d[key] is String:
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": field, "rule": I18n.t("PACK_RULE_STRING")}))
		return ""
	if required and String(d[key]).strip_edges() == "":
		errors.append(I18n.t("PACK_ERR_MISSING", {"field": field}))
	return d[key]


func _number(d: Dictionary, key: String, fallback: float, lo: float, hi: float, prefix: String = "") -> float:
	if not d.has(key):
		return fallback
	var v: Variant = d[key]
	var field: String = key if prefix == "" else "%s.%s" % [prefix, key]
	if not (v is float or v is int) or float(v) < lo or float(v) > hi:
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": field, "rule": I18n.t("PACK_RULE_RANGE").format({"lo": lo, "hi": hi})}))
		return fallback
	return float(v)


## Integer field in [lo, hi]. `fallback` < 0 means the field is required.
func _int_field(d: Dictionary, key: String, prefix: String, lo: int, hi: int, fallback: int) -> int:
	var field: String = "%s.%s" % [prefix, key]
	if not d.has(key):
		if fallback < 0:
			errors.append(I18n.t("PACK_ERR_MISSING", {"field": field}))
		return fallback
	var v: Variant = d[key]
	if not (v is float or v is int) or float(v) != floorf(float(v)) or int(v) < lo or int(v) > hi:
		errors.append(I18n.t("PACK_ERR_FIELD", {"field": field, "rule": I18n.t("PACK_RULE_RANGE").format({"lo": lo, "hi": hi})}))
		return -1 if fallback < 0 else fallback
	return int(v)
