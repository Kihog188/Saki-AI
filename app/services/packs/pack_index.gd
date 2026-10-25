class_name PackIndex
extends RefCounted
## Cached list of installed packs (index.json in the user packs folder).
##
## Listing packs never opens every pack: refresh() lists the pack folders and compares
## each manifest's modification time with the cached one. Only new or changed packs are
## validated (and get a thumbnail); everything else comes from index.json.
##
## Entry (Dictionary): {"key", "id", "name", "author", "version", "type", "source"
##   ("builtin" | "user" | "dev"), "path", "thumbnail" (file path or ""), "hash",
##   "valid", "error", "stamp"}
## `key` is unique: the id for built-in and user packs, "dev/<id>" for dev packs.

const INDEX_VERSION: int = 1
const THUMBS_DIR: String = ".thumbs"

var _user_dir: String
var _dev_dir: String
var _builtin_dir: String
var _entries: Dictionary = {} # key -> entry


func _init(user_dir: String, dev_dir: String, builtin_dir: String) -> void:
	_user_dir = user_dir
	_dev_dir = dev_dir
	_builtin_dir = builtin_dir


func index_path() -> String:
	return _user_dir.path_join(SakiConst.PACK_INDEX_FILE)


func thumbs_dir() -> String:
	return _user_dir.path_join(THUMBS_DIR)


## Reads index.json and brings it up to date with the folders. Returns the entry list.
func refresh() -> Array[Dictionary]:
	var cached: Dictionary = _read_index()
	_entries.clear()
	_entries[SakiConst.DEFAULT_PACK_ID] = _builtin_entry()
	var changed: bool = false
	for source: String in ["user", "dev"]:
		var root: String = _user_dir if source == "user" else _dev_dir
		if not DirAccess.dir_exists_absolute(root):
			continue
		for folder: String in DirAccess.get_directories_at(root):
			if folder.begins_with("."):
				continue # our own folders (.thumbs, .incoming_*)
			var key: String = folder if source == "user" else "dev/" + folder
			var path: String = root.path_join(folder)
			var stamp: int = FileAccess.get_modified_time(path.path_join(PackValidator.MANIFEST))
			var old: Dictionary = cached.get(key, {})
			if not old.is_empty() and int(old.get("stamp", -1)) == stamp and old.get("source") == source:
				_entries[key] = old
			else:
				_entries[key] = _scan_entry(key, folder, source, path, stamp)
				changed = true
	if changed or cached.size() != _entries.size() - 1 or not FileAccess.file_exists(index_path()):
		_write_index()
	return list()


## Every entry: built-in first, then by name. Valid and broken together (see `valid`).
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _entries.values():
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a["source"] == "builtin") != (b["source"] == "builtin"):
			return a["source"] == "builtin"
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return out


func get_entry(key: String) -> Dictionary:
	return _entries.get(key, {})


## Adds or replaces one entry (used by the importer) and saves index.json.
func put(entry: Dictionary) -> void:
	_entries[entry["key"]] = entry
	_write_index()


func remove(key: String) -> void:
	if _entries.erase(key):
		_write_index()


## Re-validates one pack now (the "Tải lại" button of dev packs).
func rescan(key: String) -> Dictionary:
	var e: Dictionary = _entries.get(key, {})
	if e.is_empty() or e["source"] == "builtin":
		return e
	var stamp: int = FileAccess.get_modified_time(String(e["path"]).path_join(PackValidator.MANIFEST))
	var folder: String = String(e["path"]).get_file()
	var fresh: Dictionary = _scan_entry(key, folder, e["source"], e["path"], stamp)
	put(fresh)
	return fresh


## Built-in pack: images in res://packs/default, or the code-drawn placeholder until the
## owner adds them (no manifest yet).
func _builtin_entry() -> Dictionary:
	var e: Dictionary = _empty_entry(SakiConst.DEFAULT_PACK_ID, SakiConst.DEFAULT_PACK_ID, "builtin", _builtin_dir.path_join(SakiConst.DEFAULT_PACK_ID))
	e["name"] = I18n.t("PACK_DEFAULT_NAME")
	e["author"] = "Saki"
	e["type"] = "placeholder"
	e["valid"] = true
	var manifest_path: String = String(e["path"]).path_join(PackValidator.MANIFEST)
	if FileAccess.file_exists(manifest_path):
		var m: PackManifest = PackManifest.parse(FileAccess.get_file_as_string(manifest_path))
		if m.is_valid():
			e["type"] = m.type
			e["name"] = m.name
			e["author"] = m.author
			e["version"] = m.version
			if m.thumbnail != "":
				e["thumbnail"] = String(e["path"]).path_join(m.thumbnail)
		else:
			push_warning("Built-in pack manifest is invalid, using the placeholder: %s" % m.first_error())
	return e


func _scan_entry(key: String, folder: String, source: String, path: String, stamp: int) -> Dictionary:
	var e: Dictionary = _empty_entry(key, folder, source, path)
	e["stamp"] = stamp
	e["name"] = folder
	var report: Dictionary = PackValidator.validate_folder(path)
	var m: PackManifest = report["manifest"]
	if m != null:
		e["name"] = m.name if m.name != "" else folder
		e["author"] = m.author
		e["version"] = m.version
		e["type"] = m.type
	if not PackRules.is_valid_id(folder):
		e["error"] = I18n.t("PACK_ERR_FOLDER_NAME", {"folder": folder})
		return e
	if not report["ok"]:
		e["error"] = report["error"]
		return e
	if m.id != folder:
		e["error"] = I18n.t("PACK_ERR_ID_FOLDER", {"id": m.id, "folder": folder})
		return e
	if source == "user" and m.id == SakiConst.DEFAULT_PACK_ID:
		e["error"] = I18n.t("PACK_ERR_ID_RESERVED")
		return e
	e["valid"] = true
	e["hash"] = PackFiles.content_hash(path, report["files"]) if source == "user" else ""
	var img: Image = PackFiles.preview_image(path, m)
	if img != null:
		var thumb: String = thumbs_dir().path_join(key.replace("/", "_") + ".png")
		if PackFiles.write_thumbnail(img, thumb):
			e["thumbnail"] = thumb
	return e


func _empty_entry(key: String, id: String, source: String, path: String) -> Dictionary:
	return {
		"key": key, "id": id, "name": id, "author": "", "version": "", "type": "",
		"source": source, "path": path, "thumbnail": "", "hash": "", "valid": false,
		"error": "", "stamp": 0,
	}


func _read_index() -> Dictionary:
	if not FileAccess.file_exists(index_path()):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(index_path())) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != INDEX_VERSION or not data.get("packs") is Array:
		return {}
	var out: Dictionary = {}
	for e: Variant in data["packs"]:
		if e is Dictionary and e.has("key"):
			out[e["key"]] = e
	return out


func _write_index() -> void:
	DirAccess.make_dir_recursive_absolute(_user_dir)
	var packs: Array = []
	for e: Dictionary in _entries.values():
		if e["source"] != "builtin":
			packs.append(e)
	var f := FileAccess.open(index_path(), FileAccess.WRITE)
	if f == null:
		push_warning("Cannot write the pack index: %s" % index_path())
		return
	f.store_string(JSON.stringify({"version": INDEX_VERSION, "packs": packs}, "\t"))
