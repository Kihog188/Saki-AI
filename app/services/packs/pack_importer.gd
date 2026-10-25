class_name PackImporter
extends RefCounted
## Installs a .sakip file or a pack folder into the user packs folder. No UI dependency.
##
## import_zip() / import_folder() are synchronous and safe to call from a worker thread
## (PackService runs them on one). They validate everything first, then copy the used
## files to a temporary folder, checking and optimising every image, write a thumbnail and
## swap the folder into place. Nothing is written into the final folder until every check
## passed, and the source (zip or folder) is only read, never changed.
##
## A pack without manifest.json gets the manifest built by PackAutoManifest written into
## the installed copy, under an id made unique (an existing pack is never replaced).
## Warnings (ignored files, images without a transparent background...) are saved in
## WARNINGS_FILE so the pack manager can show them later.
##
## Result: {"ok": bool, "message": String (Vietnamese summary or error), "entry": Dictionary,
##          "resized": int, "reencoded": int, "warnings": PackedStringArray}

const WARNINGS_FILE: String = "import_warnings.txt"
## At most this many file names in the "no transparent background" warning.
const MAX_LISTED_OPAQUE: int = 3

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
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return _fail(I18n.t("PACK_ERR_ZIP_CORRUPT"))
	var prefix: String = report["prefix"]
	var result: Dictionary = _install(report, func(file: String) -> PackedByteArray:
		return reader.read_file(prefix + file))
	reader.close()
	return result


func import_folder(dir: String) -> Dictionary:
	_report_progress(0.0, I18n.t("IMPORT_STEP_CHECK"))
	var report: Dictionary = PackValidator.validate_folder(dir)
	if not report["ok"]:
		return _fail(report["error"])
	return _install(report, func(file: String) -> PackedByteArray:
		return FileAccess.get_file_as_bytes(dir.path_join(file)))


## Copies the files of a validated pack (read through `read`) into place.
func _install(report: Dictionary, read: Callable) -> Dictionary:
	var m: PackManifest = report["manifest"]
	var manifest_text: String = ""
	if report["auto"]:
		var data: Dictionary = report["manifest_data"]
		data["id"] = unique_id(String(data["id"]))
		m.id = data["id"]
		manifest_text = JSON.stringify(data, "\t")
	elif m.id == SakiConst.DEFAULT_PACK_ID:
		return _fail(I18n.t("PACK_ERR_ID_RESERVED"))
	if m.type != "2d":
		push_warning("Importing a pack of type '%s' (no renderer yet, shown as thumbnail)" % m.type)

	var tmp: String = _user_dir.path_join(".incoming_%d" % (Time.get_ticks_usec() % 1000000000))
	DirAccess.make_dir_recursive_absolute(tmp)
	var result: Dictionary = _extract(report, read, tmp)
	if result["ok"] and manifest_text != "":
		result = _write_text(result, tmp.path_join(PackValidator.MANIFEST), manifest_text)
	var warnings: PackedStringArray = report["warnings"].duplicate()
	warnings.append_array(result["warnings"])
	result["warnings"] = warnings
	if result["ok"] and not warnings.is_empty():
		result = _write_text(result, tmp.path_join(WARNINGS_FILE), "\n".join(warnings))
	elif result["ok"] and FileAccess.file_exists(tmp.path_join(WARNINGS_FILE)):
		DirAccess.remove_absolute(tmp.path_join(WARNINGS_FILE)) # one shipped inside the pack is not ours
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
		"warnings": Array(warnings),
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
	if not warnings.is_empty():
		summary += " " + I18n.t("IMPORT_HAS_WARNINGS", {"n": warnings.size()})
	result["message"] = summary
	_report_progress(1.0, summary)
	return result


## `base`, or base-2, base-3... so that no installed pack (and not the built-in id) is hit.
func unique_id(base: String) -> String:
	var id: String = base
	var n: int = 2
	while id == SakiConst.DEFAULT_PACK_ID or DirAccess.dir_exists_absolute(_user_dir.path_join(id)):
		var suffix: String = "-%d" % n
		id = base.left(64 - suffix.length()) + suffix
		n += 1
	return id


## Copies every listed file into `tmp`, checking real sizes and re-encoding images.
func _extract(report: Dictionary, read: Callable, tmp: String) -> Dictionary:
	var result: Dictionary = {"ok": true, "message": "", "entry": {}, "resized": 0, "reencoded": 0, "warnings": PackedStringArray()}
	var m: PackManifest = report["manifest"]
	var sheets: Dictionary = _sheet_grids(m)
	var drawn: Dictionary = _drawn_files(m)
	var opaque: PackedStringArray = []
	var files: PackedStringArray = report["files"]
	var total_bytes: int = 0
	for i: int in files.size():
		var file: String = files[i]
		_report_progress(0.05 + 0.85 * float(i) / files.size(), I18n.t("IMPORT_STEP_FILE", {"file": file}))
		var data: PackedByteArray = read.call(file)
		total_bytes += data.size()
		if total_bytes > PackRules.MAX_TOTAL_BYTES:
			return _fail(I18n.t("PACK_ERR_TOTAL_TOO_BIG", {"mb": PackRules.MAX_TOTAL_BYTES / 1048576}))
		if PackRules.is_image(file):
			var size_error: String = ImageProbe.check_size(file, ImageProbe.size_of(data))
			if size_error != "":
				return _fail(size_error)
			var img: Image = ImageProbe.decode(data)
			if img == null:
				return _fail(I18n.t("PACK_ERR_IMAGE_UNREADABLE", {"file": file}))
			if drawn.has(file) and img.detect_alpha() == Image.ALPHA_NONE:
				opaque.append(file)
			var grid: Vector2i = sheets.get(file, Vector2i.ONE)
			if PackData.fit_image(img, PackRules.IMPORT_MAX_TEXTURE, grid.x, grid.y):
				result["resized"] += 1
			# Re-encoding drops anything hidden after the pixel data and fixes a wrong
			# extension (the format follows the file name from now on).
			data = _encode(img, file.get_extension().to_lower())
			result["reencoded"] += 1
		var out_path: String = tmp.path_join(file)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			return _fail(I18n.t("IMPORT_ERR_WRITE"))
		f.store_buffer(data)
		f.close()
	if not opaque.is_empty():
		result["warnings"].append(opaque_warning(opaque))
	return result


## "Ảnh happy.png chưa xóa nền..." (one file) or a short list for several.
static func opaque_warning(files: PackedStringArray) -> String:
	if files.size() == 1:
		return I18n.t("PACK_WARN_OPAQUE", {"file": files[0]})
	var shown: String = ", ".join(files.slice(0, MAX_LISTED_OPAQUE))
	if files.size() > MAX_LISTED_OPAQUE:
		shown += " " + I18n.t("PACK_AUTO_MORE", {"n": files.size() - MAX_LISTED_OPAQUE})
	return I18n.t("PACK_WARN_OPAQUE_MANY", {"files": shown})


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


## Files drawn as the character (not the thumbnail): these should have a transparent
## background.
static func _drawn_files(m: PackManifest) -> Dictionary:
	var out: Dictionary = {}
	for group: Dictionary in [m.emotions, m.states]:
		for spec: Dictionary in group.values():
			for f: String in spec["files"]:
				out[f] = true
	return out


static func _write_text(result: Dictionary, path: String, text: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _fail(I18n.t("IMPORT_ERR_WRITE"))
	f.store_string(text)
	f.close()
	return result


func _report_progress(fraction: float, text: String) -> void:
	if progress.is_valid():
		progress.call(fraction, text)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "entry": {}, "resized": 0, "reencoded": 0, "warnings": PackedStringArray()}
