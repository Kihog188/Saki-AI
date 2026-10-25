class_name PackFiles
## Small file-system helpers for pack folders (delete a tree, make thumbnails, hashing).


## Deletes `path` and everything below it. Refuses paths outside user:// for safety.
static func remove_tree(path: String) -> bool:
	if not path.begins_with("user://") or path.trim_suffix("/") == "user:":
		push_error("remove_tree refused: %s" % path)
		return false
	if not DirAccess.dir_exists_absolute(path):
		return true
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	for sub: String in dir.get_directories():
		if dir.is_link(sub):
			DirAccess.remove_absolute(path.path_join(sub)) # remove the link, never follow it
		else:
			remove_tree(path.path_join(sub))
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	return DirAccess.remove_absolute(path) == OK


## Writes a PNG thumbnail (longest side THUMBNAIL_SIZE) of `img` to `out_path`.
static func write_thumbnail(img: Image, out_path: String) -> bool:
	var thumb: Image = img.duplicate()
	var longest: int = maxi(thumb.get_width(), thumb.get_height())
	if longest > PackRules.THUMBNAIL_SIZE:
		var f: float = float(PackRules.THUMBNAIL_SIZE) / longest
		thumb.resize(maxi(1, roundi(thumb.get_width() * f)), maxi(1, roundi(thumb.get_height() * f)), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	return thumb.save_png(out_path) == OK


## First frame of the thumbnail, or of the default emotion's first image, as an Image.
## For sheets only the first cell is returned. null if nothing can be read.
static func preview_image(dir: String, manifest: PackManifest) -> Image:
	var file: String = manifest.thumbnail
	var cell := Vector2i.ZERO
	if file == "":
		var name: String = PackData.resolve_emotion(PackedStringArray(manifest.emotions.keys()), manifest.default_emotion, manifest.default_emotion)
		if name == "":
			return null
		var spec: Dictionary = manifest.emotions[name]
		file = spec["files"][0]
		if spec["kind"] == "sheet":
			cell = Vector2i(int(spec["columns"]), int(spec["rows"]))
	var data: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join(file))
	if ImageProbe.check_size(file, ImageProbe.size_of(data)) != "":
		return null
	var img: Image = ImageProbe.decode(data)
	if img != null and cell != Vector2i.ZERO:
		var w: int = img.get_width() / cell.x
		var h: int = img.get_height() / cell.y
		img = img.get_region(Rect2i(0, 0, maxi(1, w), maxi(1, h)))
	return img


## SHA-256 over the file names and contents (sorted), as hex.
static func content_hash(dir: String, files: PackedStringArray) -> String:
	var sorted: PackedStringArray = files.duplicate()
	sorted.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for f: String in sorted:
		ctx.update(f.to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		ctx.update(FileAccess.get_file_as_bytes(dir.path_join(f)))
	return ctx.finish().hex_encode()
