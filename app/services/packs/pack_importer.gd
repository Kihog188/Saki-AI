class_name PackImporter
extends RefCounted
## Installs a .sakip file into the user packs folder. No UI dependency.
##
## import_zip() is synchronous and safe to call from a worker thread (PackService runs it
## on one). It validates everything first, then extracts to a temporary folder, checks
## and optimises every image, writes a thumbnail and swaps the folder into place.
## Nothing is written into the final folder until every check passed.
##
## Result: {"ok": bool, "message": String (Vietnamese summary or error), "entry": Dictionary,
##          "resized": int, "reencoded": int}

## Called as progress.call(fraction: float, text: String). May run on the worker thread.
var progress: Callable = Callable()

var _user_dir: String
var _thumbs_dir: String


func _init(user_dir: String, thumbs_dir: String) -> void:
	_user_dir = user_dir
	_thumbs_dir = thumbs_dir


func import_zip(zip_path: String) -> Dictionary:
	_report_progress(0.0, I18n.t("IMPORT_STEP_CHECK"))
	var report: Dictionary = PackValidator.validate_zip(zip_path)
	if not report["ok"]:
		return _fail(report["error"])
	var m: PackManifest = report["manifest"]
	if m.id == SakiConst.DEFAULT_PACK_ID:
		return _fail(I18n.t("PACK_ERR_ID_RESERVED"))
	if m.type != "2d":
		push_warning("Importing a pack of type '%s' (no renderer yet, shown as thumbnail)" % m.type)

	var tmp: String = _user_dir.path_join(".incoming_%d" % (Time.get_ticks_usec() % 1000000000))
	DirAccess.make_dir_recursive_absolute(tmp)
	var result: Dictionary = _extract(zip_path, report, tmp)
	if not result["ok"]:
		PackFiles.remove_tree(tmp)
		return result

	_report_progress(0.9, I18n.t("IMPORT_STEP_INSTALL"))
	var final_dir: String = _user_dir.path_join(m.id)
	var old_dir: String = ""
	if DirAccess.dir_exists_absolute(final_dir):
		old_dir = _user_dir.path_join(".old_%s_%d" % [m.id, Time.get_ticks_usec() % 1000000])
		if DirAccess.rename_absolute(final_dir, old_dir) != OK:
			PackFiles.remove_tree(tmp)
			return _fail(I18n.t("IMPORT_ERR_REPLACE", {"id": m.id}))
	if DirAccess.rename_absolute(tmp, final_dir) != OK:
		if old_dir != "":
			DirAccess.rename_absolute(old_dir, final_dir)
		PackFiles.remove_tree(tmp)
		return _fail(I18n.t("IMPORT_ERR_WRITE"))
	if old_dir != "":
		PackFiles.remove_tree(old_dir)

	var entry: Dictionary = {
		"key": m.id, "id": m.id, "name": m.name, "author": m.author, "version": m.version,
		"type": m.type, "source": "user", "path": final_dir, "thumbnail": "",
		"hash": PackFiles.content_hash(final_dir, report["files"]), "valid": true, "error": "",
		"stamp": FileAccess.get_modified_time(final_dir.path_join(PackValidator.MANIFEST)),
	}
	var preview: Image = PackFiles.preview_image(final_dir, m)
	if preview != null:
		var thumb: String = _thumbs_dir.path_join(m.id + ".png")
		if PackFiles.write_thumbnail(preview, thumb):
			entry["thumbnail"] = thumb
	result["entry"] = entry
	var summary: String = I18n.t("IMPORT_DONE", {"name": m.name})
	if result["resized"] > 0:
		summary += " " + I18n.t("IMPORT_RESIZED", {"n": result["resized"], "max": PackRules.IMPORT_MAX_TEXTURE})
	result["message"] = summary
	_report_progress(1.0, summary)
	return result


## Extracts every file into `tmp`, checking real sizes and re-encoding images.
func _extract(zip_path: String, report: Dictionary, tmp: String) -> Dictionary:
	var result: Dictionary = {"ok": true, "message": "", "entry": {}, "resized": 0, "reencoded": 0}
	var m: PackManifest = report["manifest"]
	var sheets: Dictionary = _sheet_grids(m)
	var files: PackedStringArray = report["files"]
	var prefix: String = report["prefix"]
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return _fail(I18n.t("PACK_ERR_ZIP_CORRUPT"))
	var total_bytes: int = 0
	for i: int in files.size():
		var file: String = files[i]
		_report_progress(0.05 + 0.85 * float(i) / files.size(), I18n.t("IMPORT_STEP_FILE", {"file": file}))
		var data: PackedByteArray = reader.read_file(prefix + file)
		total_bytes += data.size()
		if total_bytes > PackRules.MAX_TOTAL_BYTES:
			reader.close()
			return _fail(I18n.t("PACK_ERR_TOTAL_TOO_BIG", {"mb": PackRules.MAX_TOTAL_BYTES / 1048576}))
		if PackRules.is_image(file):
			var size_error: String = ImageProbe.check_size(file, ImageProbe.size_of(data))
			if size_error != "":
				reader.close()
				return _fail(size_error)
			var img: Image = ImageProbe.decode(data)
			if img == null:
				reader.close()
				return _fail(I18n.t("PACK_ERR_IMAGE_UNREADABLE", {"file": file}))
			var grid: Vector2i = sheets.get(file, Vector2i.ONE)
			if PackData.fit_image(img, PackRules.IMPORT_MAX_TEXTURE, grid.x, grid.y):
				result["resized"] += 1
			# Re-encoding drops anything hidden after the pixel data and fixes a wrong
			# extension (the format follows the file name from now on).
			data = _encode(img, file.get_extension().to_lower())
			result["reencoded"] += 1
		elif file == PackValidator.MANIFEST:
			pass # already validated
		var out_path: String = tmp.path_join(file)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			reader.close()
			return _fail(I18n.t("IMPORT_ERR_WRITE"))
		f.store_buffer(data)
		f.close()
	reader.close()
	return result


static func _encode(img: Image, ext: String) -> PackedByteArray:
	match ext:
		"jpg", "jpeg":
			return img.save_jpg_to_buffer(0.92)
		"webp":
			return img.save_webp_to_buffer(false) # lossless
	return img.save_png_to_buffer()


## Sheet file -> its grid, so downscaling keeps every cell the same size.
static func _sheet_grids(m: PackManifest) -> Dictionary:
	var out: Dictionary = {}
	for group: Dictionary in [m.emotions, m.states]:
		for spec: Dictionary in group.values():
			if spec["kind"] == "sheet":
				out[spec["files"][0]] = Vector2i(int(spec["columns"]), int(spec["rows"]))
	return out


func _report_progress(fraction: float, text: String) -> void:
	if progress.is_valid():
		progress.call(fraction, text)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "entry": {}, "resized": 0, "reencoded": 0}
