class_name PackValidator
## Checks a .sakip file or a pack folder against PackRules and the manifest rules.
## Pure logic, no UI: usable by the importer, the pack index, a future Studio or a CLI.
##
## A pack without manifest.json ("just a folder of images") gets one built from its file
## names (PackAutoManifest). Then only the images it uses are listed in `files`, every
## other file is ignored (never read), and file names that break the naming rules are
## ignored instead of rejected. The hard rules (symlinks, traversal, absolute paths,
## encryption, duplicates, zip bombs, size and count limits) apply in both cases.
##
## Both functions return a report Dictionary:
##   {"ok": bool, "error": String (Vietnamese, names the file and the rule),
##    "manifest": PackManifest or null, "files": PackedStringArray (paths in the pack),
##    "prefix": String (zip only: folder the pack sits in inside the zip, usually ""),
##    "auto": bool (no manifest.json), "manifest_data": Dictionary (auto only: the built
##    manifest as JSON data), "warnings": PackedStringArray (Vietnamese, not errors)}

const MANIFEST: String = "manifest.json"
## Entries smaller than this are not checked for the compression ratio (tiny text files
## compress very well and are harmless).
const RATIO_CHECK_MIN_BYTES: int = 64 * 1024


## `pack_name` names a pack without manifest.json; "" = the zip file name.
static func validate_zip(zip_path: String, pack_name: String = "") -> Dictionary:
	var report: Dictionary = _report()
	if not FileAccess.file_exists(zip_path):
		return _fail(report, I18n.t("PACK_ERR_ZIP_OPEN"))
	var zip_size: int = _file_size(zip_path)
	if zip_size > PackRules.MAX_ZIP_BYTES:
		return _fail(report, I18n.t("PACK_ERR_ZIP_TOO_BIG", {"mb": PackRules.MAX_ZIP_BYTES / 1048576}))
	var info: Dictionary = ZipInspector.inspect(zip_path)
	if info["error"] != "":
		return _fail(report, I18n.t(info["error"]))

	var names: PackedStringArray = []
	var seen: Dictionary = {}
	var total: int = 0
	for e: Dictionary in info["entries"]:
		var name: String = e["name"]
		if e["is_symlink"]:
			return _fail(report, I18n.t("PACK_ERR_SYMLINK", {"file": name}))
		if e["encrypted"]:
			return _fail(report, I18n.t("PACK_ERR_ENCRYPTED", {"file": name}))
		var rule: String = _hard_rule(name)
		if rule != "":
			return _fail(report, I18n.t("PACK_ERR_FILE_RULE", {"file": name, "rule": I18n.t(rule)}))
		var key: String = name.trim_suffix("/").to_lower()
		if seen.has(key):
			return _fail(report, I18n.t("PACK_ERR_DUPLICATE", {"file": name}))
		seen[key] = true
		if e["is_dir"] or _is_junk(name):
			continue
		if e["method"] != 0 and e["method"] != 8:
			return _fail(report, I18n.t("PACK_ERR_ZIP_METHOD", {"file": name}))
		var compressed: int = e["compressed"]
		var uncompressed: int = e["uncompressed"]
		if uncompressed >= RATIO_CHECK_MIN_BYTES and (compressed == 0 or float(uncompressed) / compressed > PackRules.MAX_COMPRESSION_RATIO):
			return _fail(report, I18n.t("PACK_ERR_ZIP_BOMB", {"file": name}))
		total += uncompressed
		names.append(name)
	if names.size() > PackRules.MAX_FILES:
		return _fail(report, I18n.t("PACK_ERR_TOO_MANY_FILES", {"n": PackRules.MAX_FILES}))
	if total > PackRules.MAX_TOTAL_BYTES:
		return _fail(report, I18n.t("PACK_ERR_TOTAL_TOO_BIG", {"mb": PackRules.MAX_TOTAL_BYTES / 1048576}))

	# The pack is at the root, or inside one top-level folder (what "Send to > Compressed
	# folder" in Windows Explorer produces when you zip the pack folder itself). That
	# folder's name is not part of the pack, so it may contain spaces or accents.
	var prefix: String = ""
	if not names.has(MANIFEST):
		prefix = _single_folder_prefix(names)
	var files: PackedStringArray = []
	for n: String in names:
		if n.begins_with(prefix):
			files.append(n.substr(prefix.length()))
	report["files"] = files
	report["prefix"] = prefix

	if not files.has(MANIFEST):
		if pack_name == "":
			pack_name = prefix.trim_suffix("/") if prefix != "" else zip_path.get_file().get_basename()
		return _check_auto(report, files, pack_name)
	var soft_error: String = _first_soft_error(files)
	if soft_error != "":
		return _fail(report, soft_error)
	var manifest_entry: Dictionary = {}
	for e: Dictionary in info["entries"]:
		if e["name"] == prefix + MANIFEST:
			manifest_entry = e
	if manifest_entry["uncompressed"] > PackRules.MAX_MANIFEST_BYTES:
		return _fail(report, I18n.t("PACK_ERR_MANIFEST_SIZE"))
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return _fail(report, I18n.t("PACK_ERR_ZIP_CORRUPT"))
	var bytes: PackedByteArray = reader.read_file(prefix + MANIFEST)
	reader.close()
	return _check_manifest(report, bytes.get_string_from_utf8(), files)


## Validates a pack folder as it is on disk (dev packs, a folder being imported, or
## re-checking an installed pack). `pack_name` names a pack without manifest.json;
## "" = the folder name.
static func validate_folder(dir: String, pack_name: String = "") -> Dictionary:
	var report: Dictionary = _report()
	if not DirAccess.dir_exists_absolute(dir):
		return _fail(report, I18n.t("PACK_ERR_FOLDER_MISSING", {"dir": dir}))
	var files: PackedStringArray = []
	var total: Array[int] = [0]
	var err: String = _scan_folder(dir, "", files, total)
	if err != "":
		return _fail(report, err)
	if files.size() > PackRules.MAX_FILES:
		return _fail(report, I18n.t("PACK_ERR_TOO_MANY_FILES", {"n": PackRules.MAX_FILES}))
	if total[0] > PackRules.MAX_TOTAL_BYTES:
		return _fail(report, I18n.t("PACK_ERR_TOTAL_TOO_BIG", {"mb": PackRules.MAX_TOTAL_BYTES / 1048576}))
	report["files"] = files
	if not files.has(MANIFEST):
		return _check_auto(report, files, pack_name if pack_name != "" else dir.trim_suffix("/").get_file())
	var soft_error: String = _first_soft_error(files)
	if soft_error != "":
		return _fail(report, soft_error)
	var path: String = dir.path_join(MANIFEST)
	if _file_size(path) > PackRules.MAX_MANIFEST_BYTES:
		return _fail(report, I18n.t("PACK_ERR_MANIFEST_SIZE"))
	return _check_manifest(report, FileAccess.get_file_as_string(path), files)


## Reads only the manifest of a folder (for the pack index): cheap, no file walk.
static func read_folder_manifest(dir: String) -> PackManifest:
	var path: String = dir.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		var m := PackManifest.new()
		m.errors.append(I18n.t("PACK_ERR_NO_MANIFEST"))
		return m
	if _file_size(path) > PackRules.MAX_MANIFEST_BYTES:
		var big := PackManifest.new()
		big.errors.append(I18n.t("PACK_ERR_MANIFEST_SIZE"))
		return big
	return PackManifest.parse(FileAccess.get_file_as_string(path))


static func _check_manifest(report: Dictionary, text: String, files: PackedStringArray) -> Dictionary:
	var m: PackManifest = PackManifest.parse(text)
	report["manifest"] = m
	if not m.is_valid():
		return _fail(report, m.first_error())
	for f: String in m.referenced_files():
		if not files.has(f):
			return _fail(report, I18n.t("PACK_ERR_FILE_MISSING", {"file": f}))
	report["ok"] = true
	return report


## No manifest.json: build one from the file names. Only the files it uses stay in `files`.
static func _check_auto(report: Dictionary, files: PackedStringArray, pack_name: String) -> Dictionary:
	report["auto"] = true
	var built: Dictionary = PackAutoManifest.build(files, pack_name)
	report["warnings"] = built["warnings"]
	if built["error"] != "":
		return _fail(report, built["error"])
	report["manifest_data"] = built["data"]
	var m: PackManifest = PackManifest.parse(JSON.stringify(built["data"]))
	report["manifest"] = m
	if not m.is_valid():
		return _fail(report, m.first_error())
	report["files"] = m.referenced_files()
	report["ok"] = true
	return report


## The naming rules that a pack WITH a manifest must follow for every file (a pack without
## one just ignores such files): segment characters, depth, allowed extensions.
static func _first_soft_error(files: PackedStringArray) -> String:
	for f: String in files:
		var rule: String = PackRules.check_path(f)
		if rule != "":
			return I18n.t("PACK_ERR_FILE_RULE", {"file": f, "rule": I18n.t(rule)})
		if not PackRules.extension_allowed(f):
			return I18n.t("PACK_ERR_EXTENSION", {"file": f, "allowed": ", ".join(PackRules.ALLOWED_EXTENSIONS)})
	return ""


## The path rules no pack may break: empty, backslash, absolute, "." or ".." segments.
static func _hard_rule(path: String) -> String:
	if path.is_empty():
		return "PACK_ERR_PATH_EMPTY"
	if path.contains("\\"):
		return "PACK_ERR_PATH_BACKSLASH"
	if path.begins_with("/") or (path.length() > 1 and path[1] == ":"):
		return "PACK_ERR_PATH_ABSOLUTE"
	for seg: String in path.trim_suffix("/").split("/"):
		if seg == ".." or seg == ".":
			return "PACK_ERR_PATH_TRAVERSAL"
	return ""


## Lists every file under `root` (relative paths) and adds up their sizes. Only symlinks
## stop the scan; naming rules are checked later (_first_soft_error), because a pack
## without a manifest ignores badly named files instead of failing.
static func _scan_folder(root: String, rel: String, out: PackedStringArray, total: Array[int]) -> String:
	var dir := DirAccess.open(root.path_join(rel))
	if dir == null:
		return I18n.t("PACK_ERR_FOLDER_MISSING", {"dir": root.path_join(rel)})
	dir.include_hidden = true
	for sub: String in dir.get_directories():
		var sub_rel: String = sub if rel == "" else rel.path_join(sub)
		if dir.is_link(sub):
			return I18n.t("PACK_ERR_SYMLINK", {"file": sub_rel})
		var err: String = _scan_folder(root, sub_rel, out, total)
		if err != "":
			return err
	for file: String in dir.get_files():
		var file_rel: String = file if rel == "" else rel.path_join(file)
		if dir.is_link(file):
			return I18n.t("PACK_ERR_SYMLINK", {"file": file_rel})
		if _is_junk(file):
			continue
		total[0] += _file_size(root.path_join(file_rel))
		out.append(file_rel)
		if out.size() > PackRules.MAX_FILES:
			return I18n.t("PACK_ERR_TOO_MANY_FILES", {"n": PackRules.MAX_FILES})
	return ""


## Files the OS creates by itself (Thumbs.db, desktop.ini, .DS_Store): never part of a pack.
static func _is_junk(path: String) -> bool:
	return PackAutoManifest.JUNK_FILES.has(path.get_file().to_lower())


static func _single_folder_prefix(names: PackedStringArray) -> String:
	var top: String = ""
	for n: String in names:
		var slash: int = n.find("/")
		if slash < 0:
			return ""
		var first: String = n.substr(0, slash + 1)
		if top == "":
			top = first
		elif first != top:
			return ""
	return top


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


static func _report() -> Dictionary:
	return {"ok": false, "error": "", "manifest": null, "files": PackedStringArray(), "prefix": "",
		"auto": false, "manifest_data": {}, "warnings": PackedStringArray()}


static func _fail(report: Dictionary, message: String) -> Dictionary:
	report["ok"] = false
	report["error"] = message
	return report
