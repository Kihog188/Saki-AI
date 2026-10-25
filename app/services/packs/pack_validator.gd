class_name PackValidator
## Checks a .sakip file or a pack folder against PackRules and the manifest rules.
## Pure logic, no UI: usable by the importer, the pack index, a future Studio or a CLI.
##
## Both functions return a report Dictionary:
##   {"ok": bool, "error": String (Vietnamese, names the file and the rule),
##    "manifest": PackManifest or null, "files": PackedStringArray (paths in the pack),
##    "prefix": String (zip only: folder the pack sits in inside the zip, usually "")}

const MANIFEST: String = "manifest.json"
## Entries smaller than this are not checked for the compression ratio (tiny text files
## compress very well and are harmless).
const RATIO_CHECK_MIN_BYTES: int = 64 * 1024


static func validate_zip(zip_path: String) -> Dictionary:
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
		var rule: String = PackRules.check_path(name)
		if rule != "":
			return _fail(report, I18n.t("PACK_ERR_FILE_RULE", {"file": name, "rule": I18n.t(rule)}))
		var key: String = name.trim_suffix("/").to_lower()
		if seen.has(key):
			return _fail(report, I18n.t("PACK_ERR_DUPLICATE", {"file": name}))
		seen[key] = true
		if e["is_dir"]:
			continue
		if not PackRules.extension_allowed(name):
			return _fail(report, I18n.t("PACK_ERR_EXTENSION", {"file": name, "allowed": ", ".join(PackRules.ALLOWED_EXTENSIONS)}))
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

	# manifest.json at the root, or inside one top-level folder (what "Send to > Compressed
	# folder" in Windows Explorer produces when you zip the pack folder itself).
	var prefix: String = ""
	if not names.has(MANIFEST):
		prefix = _single_folder_prefix(names)
		if prefix == "" or not names.has(prefix + MANIFEST):
			return _fail(report, I18n.t("PACK_ERR_NO_MANIFEST"))
	var files: PackedStringArray = []
	for n: String in names:
		if n.begins_with(prefix):
			files.append(n.substr(prefix.length()))
	report["files"] = files
	report["prefix"] = prefix

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


## Validates a pack folder as it is on disk (dev packs, or re-checking an installed pack).
static func validate_folder(dir: String) -> Dictionary:
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
	if not files.has(MANIFEST):
		return _fail(report, I18n.t("PACK_ERR_NO_MANIFEST"))
	report["files"] = files
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


static func _scan_folder(root: String, rel: String, out: PackedStringArray, total: Array[int]) -> String:
	var dir := DirAccess.open(root.path_join(rel))
	if dir == null:
		return I18n.t("PACK_ERR_FOLDER_MISSING", {"dir": root.path_join(rel)})
	dir.include_hidden = true
	for sub: String in dir.get_directories():
		var sub_rel: String = sub if rel == "" else rel.path_join(sub)
		if dir.is_link(sub):
			return I18n.t("PACK_ERR_SYMLINK", {"file": sub_rel})
		var rule: String = PackRules.check_path(sub_rel + "/")
		if rule != "":
			return I18n.t("PACK_ERR_FILE_RULE", {"file": sub_rel, "rule": I18n.t(rule)})
		var err: String = _scan_folder(root, sub_rel, out, total)
		if err != "":
			return err
	for file: String in dir.get_files():
		var file_rel: String = file if rel == "" else rel.path_join(file)
		if dir.is_link(file):
			return I18n.t("PACK_ERR_SYMLINK", {"file": file_rel})
		var rule: String = PackRules.check_path(file_rel)
		if rule != "":
			return I18n.t("PACK_ERR_FILE_RULE", {"file": file_rel, "rule": I18n.t(rule)})
		if not PackRules.extension_allowed(file_rel):
			return I18n.t("PACK_ERR_EXTENSION", {"file": file_rel, "allowed": ", ".join(PackRules.ALLOWED_EXTENSIONS)})
		total[0] += _file_size(root.path_join(file_rel))
		out.append(file_rel)
		if out.size() > PackRules.MAX_FILES:
			return I18n.t("PACK_ERR_TOO_MANY_FILES", {"n": PackRules.MAX_FILES})
	return ""


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
	return {"ok": false, "error": "", "manifest": null, "files": PackedStringArray(), "prefix": ""}


static func _fail(report: Dictionary, message: String) -> Dictionary:
	report["ok"] = false
	report["error"] = message
	return report
