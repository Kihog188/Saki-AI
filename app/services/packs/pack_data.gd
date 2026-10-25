class_name PackData
extends RefCounted
## The ACTIVE pack in memory: its manifest plus textures, loaded lazily per animation.
##
## Only one PackData is alive at a time (PackService keeps it). unload() frees every
## texture; switching packs calls it on the old one first.
##
## Animation lookup (what a renderer asks for):
##   get_animation(emotion, state) -> {"name": String, "frames": Array[Texture2D],
##       "outlines": Array[PackedVector2Array] (one per frame, 0..1, see AlphaOutline),
##       "fps": float, "loop": bool}   ({} = use the placeholder)
## Fallback chain for a missing or broken entry (spec 6.4):
##   requested emotion -> default_emotion -> neutral -> first available -> placeholder.

## Pack-index entry this data was loaded from (see PackIndex).
var entry: Dictionary
var manifest: PackManifest
## Folder the pack files are in (user://..., or res://packs/<id> for the built-in pack).
var dir: String
## Longest texture side allowed by the quality tier; larger images are downscaled on load.
var max_texture_size: int = PackRules.IMPORT_MAX_TEXTURE

var _cache: Dictionary = {} # "emotions/happy" -> {"frames": [...], "outlines": [...]}
var _broken: Dictionary = {} # "emotions/happy" -> true


func _init(p_entry: Dictionary, p_manifest: PackManifest, max_texture: int) -> void:
	entry = p_entry
	manifest = p_manifest
	dir = p_entry.get("path", "")
	max_texture_size = max_texture


## Chooses and loads the animation to show for `emotion` during app `state`.
func get_animation(emotion: String, state: StringName = SakiConst.STATE_IDLE) -> Dictionary:
	var key: String = _pick_key(emotion, state)
	while key != "":
		var anim: Dictionary = _animation(key)
		if not anim.is_empty():
			return anim
		key = _pick_key(emotion, state) # _animation marked it broken: pick again
	return {}


## Which "group/name" to show. Pure decision, no loading (tested directly).
func _pick_key(emotion: String, state: StringName) -> String:
	var st: String = String(state)
	# States override emotions: talking always, thinking always, idle only at rest.
	if st != "" and manifest.states.has(st) and not _broken.has("states/" + st):
		if st != String(SakiConst.STATE_IDLE) or emotion == SakiConst.DEFAULT_EMOTION or emotion == manifest.default_emotion:
			return "states/" + st
	var wanted: String = "thinking" if state == SakiConst.STATE_THINKING else emotion
	var name: String = resolve_emotion(_available_emotions(), wanted, manifest.default_emotion)
	return "" if name == "" else "emotions/" + name


## The fallback chain on plain names. `available` is in manifest order.
static func resolve_emotion(available: PackedStringArray, requested: String, default_emotion: String) -> String:
	for candidate: String in [requested, default_emotion, SakiConst.DEFAULT_EMOTION]:
		if available.has(candidate):
			return candidate
	return available[0] if available.size() > 0 else ""


## Emotions that exist and have not failed to load.
func _available_emotions() -> PackedStringArray:
	var out: PackedStringArray = []
	for name: String in manifest.emotions:
		if not _broken.has("emotions/" + name):
			out.append(name)
	return out


## All entry names for previews: {"emotions": [...], "states": [...]}.
func entry_names() -> Dictionary:
	return {"emotions": PackedStringArray(manifest.emotions.keys()), "states": PackedStringArray(manifest.states.keys())}


## Loads one named entry for a preview, without the fallback chain.
func get_named(group: String, name: String) -> Dictionary:
	return _animation("%s/%s" % [group, name])


func is_broken(key: String) -> bool:
	return _broken.has(key)


## Frees every texture. The PackData must not be used afterwards.
func unload() -> void:
	_cache.clear()
	_broken.clear()


func loaded_texture_count() -> int:
	var n: int = 0
	for loaded: Dictionary in _cache.values():
		n += loaded["frames"].size()
	return n


func _spec(key: String) -> Dictionary:
	var parts: PackedStringArray = key.split("/")
	var group: Dictionary = manifest.emotions if parts[0] == "emotions" else manifest.states
	return group.get(parts[1], {})


func _animation(key: String) -> Dictionary:
	var loaded: Dictionary = _load_cached(key)
	if loaded.is_empty():
		return {}
	var spec: Dictionary = _spec(key)
	return {"name": key, "frames": loaded["frames"], "outlines": loaded["outlines"], "fps": spec["fps"], "loop": spec["loop"]}


func _load_cached(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	if _broken.has(key):
		return {}
	var spec: Dictionary = _spec(key)
	var loaded: Dictionary = {} if spec.is_empty() else _load_frames(spec)
	if loaded.is_empty():
		push_warning("Pack '%s': cannot load '%s', using the fallback" % [entry.get("id", "?"), key])
		_broken[key] = true
		return {}
	_cache[key] = loaded
	return loaded


## {"frames": Array[Texture2D], "outlines": Array[PackedVector2Array]}, or {} on failure.
func _load_frames(spec: Dictionary) -> Dictionary:
	var frames: Array[Texture2D] = []
	var outlines: Array[PackedVector2Array] = []
	var files: PackedStringArray = spec["files"]
	if spec["kind"] == "sheet":
		var columns: int = int(spec["columns"])
		var rows: int = int(spec["rows"])
		var img: Image = _load_image(files[0], columns, rows)
		if img == null:
			return {}
		var sheet: Texture2D = ImageTexture.create_from_image(img)
		var cell := Vector2i(img.get_width() / columns, img.get_height() / rows)
		for i: int in int(spec["frames"]):
			var origin := Vector2i(i % columns, i / columns) * cell
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(origin, cell)
			atlas.filter_clip = true # no bleeding from the neighbour cell
			frames.append(atlas)
			outlines.append(_outline(img, Rect2i(origin, cell)))
		return {"frames": frames, "outlines": outlines}
	for f: String in files:
		var img: Image = _load_image(f, 1, 1)
		if img == null:
			return {}
		frames.append(ImageTexture.create_from_image(img))
		outlines.append(_outline(img, Rect2i()))
	return {"frames": frames, "outlines": outlines}


static func _outline(img: Image, region: Rect2i) -> PackedVector2Array:
	if not img.detect_alpha():
		return AlphaOutline.full_rect()
	var poly: PackedVector2Array = AlphaOutline.from_image(img, region)
	return poly if poly.size() >= 3 else AlphaOutline.full_rect()


## Loads one image file, downscaled to max_texture_size (keeping a sheet's grid exact).
func _load_image(file: String, columns: int, rows: int) -> Image:
	var path: String = dir.path_join(file)
	if path.begins_with("res://"):
		# Built-in pack: images are imported by Godot (trusted, part of the app).
		var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
		if tex == null:
			return null
		var builtin: Image = tex.get_image()
		if builtin != null and builtin.is_compressed():
			builtin.decompress()
		return builtin
	if PackRules.check_path(file) != "" or not FileAccess.file_exists(path):
		return null
	var data: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if ImageProbe.check_size(file, ImageProbe.size_of(data)) != "":
		return null
	var img: Image = ImageProbe.decode(data)
	if img == null:
		return null
	PackData.fit_image(img, max_texture_size, columns, rows)
	if img.get_format() != Image.FORMAT_RGBA8 and img.detect_alpha():
		img.convert(Image.FORMAT_RGBA8)
	return img


## Downscales `img` in place so its longest side is <= max_side. For sheets the result
## stays an exact multiple of the grid, so every cell keeps the same size.
## Returns true if the image was resized.
static func fit_image(img: Image, max_side: int, columns: int = 1, rows: int = 1) -> bool:
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest <= max_side:
		return false
	var f: float = float(max_side) / longest
	var cell_w: int = maxi(1, floori(img.get_width() * f / columns))
	var cell_h: int = maxi(1, floori(img.get_height() * f / rows))
	img.resize(cell_w * columns, cell_h * rows, Image.INTERPOLATE_LANCZOS)
	return true
