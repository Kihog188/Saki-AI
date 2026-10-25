class_name PackService
extends Node
## Facade over the pack modules for the rest of the app: list, activate, import (on a
## worker thread), delete, reload dev packs. Emits EventBus signals; no UI code.
##
## Only the active pack is loaded (`active`); the pack manager may load ONE extra pack
## for its preview (load_preview / free_preview).

var index: PackIndex
var active: PackData = null
## Longest texture side for the current quality tier (PerformanceService sets it).
var max_texture_size: int = PackRules.IMPORT_MAX_TEXTURE

var _bus: Node
var _user_dir: String
var _import_thread: Thread = null
var _preview: PackData = null


func _init(bus: Node, user_dir: String = SakiConst.USER_PACKS_DIR, dev_dir: String = SakiConst.DEV_PACKS_DIR, builtin_dir: String = SakiConst.BUILTIN_PACKS_DIR) -> void:
	name = "PackService"
	_bus = bus
	_user_dir = user_dir
	index = PackIndex.new(user_dir, dev_dir, builtin_dir)
	DirAccess.make_dir_recursive_absolute(user_dir)
	DirAccess.make_dir_recursive_absolute(dev_dir)


func refresh() -> Array[Dictionary]:
	var entries: Array[Dictionary] = index.refresh()
	_bus.packs_changed.emit()
	return entries


func list() -> Array[Dictionary]:
	return index.list()


## Loads `key` as the active pack (falls back to the built-in pack if it is missing or
## broken). The previous pack's textures are freed first.
func activate(key: String) -> String:
	var e: Dictionary = index.get_entry(key)
	if e.is_empty() or not e["valid"]:
		if key != SakiConst.DEFAULT_PACK_ID:
			push_warning("Pack '%s' is missing or broken, using the built-in pack" % key)
		e = index.get_entry(SakiConst.DEFAULT_PACK_ID)
	if active != null:
		active.unload()
		active = null
	active = PackService.load_pack(e, max_texture_size)
	_bus.active_pack_changed.emit(String(e["key"]))
	return e["key"]


func active_key() -> String:
	return "" if active == null else String(active.entry["key"])


## Applies a new texture limit: reloads the active pack at the new size.
func set_max_texture_size(size: int) -> void:
	if size == max_texture_size:
		return
	max_texture_size = size
	if active != null:
		activate(active_key())


func load_preview(key: String) -> PackData:
	free_preview()
	var e: Dictionary = index.get_entry(key)
	if e.is_empty() or not e["valid"]:
		return null
	if key == active_key():
		return active
	_preview = PackService.load_pack(e, max_texture_size)
	return _preview


func free_preview() -> void:
	if _preview != null and _preview != active:
		_preview.unload()
	_preview = null


## Builds the PackData for an index entry. Does not load any texture yet.
static func load_pack(e: Dictionary, max_texture: int) -> PackData:
	var m := PackManifest.new()
	m.type = e.get("type", "placeholder")
	var manifest_path: String = String(e.get("path", "")).path_join(PackValidator.MANIFEST)
	if e.get("source") == "dev" or (e.get("source") == "user" and not FileAccess.file_exists(manifest_path)):
		# Dev packs and plain image folders copied in by hand are loaded as they are:
		# validate the whole folder every time (this also builds a missing manifest).
		var report: Dictionary = PackValidator.validate_folder(e["path"])
		if report["ok"]:
			m = report["manifest"]
	elif m.type != "placeholder" and FileAccess.file_exists(manifest_path):
		var parsed: PackManifest = PackManifest.parse(FileAccess.get_file_as_string(manifest_path))
		if parsed.is_valid():
			m = parsed
	return PackData.new(e, m, max_texture)


# --- import ----------------------------------------------------------------------------

func is_importing() -> bool:
	return _import_thread != null


## Starts importing a .sakip file or a pack folder in the background. Progress and the
## result arrive through EventBus.pack_import_progress / pack_import_finished.
## Returns false if busy.
func import_file(path: String) -> bool:
	if _import_thread != null:
		return false
	var importer := PackImporter.new(_user_dir, index.thumbs_dir())
	importer.progress = func(fraction: float, text: String) -> void:
		_bus.pack_import_progress.emit.call_deferred(fraction, text)
	_import_thread = Thread.new()
	_import_thread.start(_import_worker.bind(importer, path), Thread.PRIORITY_LOW)
	return true


func _import_worker(importer: PackImporter, path: String) -> void:
	var result: Dictionary = importer.import_folder(path) if DirAccess.dir_exists_absolute(path) else importer.import_zip(path)
	_import_done.call_deferred(result)


func _import_done(result: Dictionary) -> void:
	_import_thread.wait_to_finish()
	_import_thread = null
	if result["ok"]:
		index.put(result["entry"])
		if active_key() == result["entry"]["key"]:
			activate(active_key()) # an update of the active pack: reload it
		_bus.packs_changed.emit()
	_bus.pack_import_finished.emit(result["ok"], result["message"])


# --- delete / reload -------------------------------------------------------------------

## Deletes an installed user pack. The built-in pack and dev packs cannot be deleted here
## (dev packs are the creator's own folders).
func delete_pack(key: String) -> bool:
	var e: Dictionary = index.get_entry(key)
	if e.is_empty() or e["source"] != "user":
		return false
	if key == active_key():
		activate(SakiConst.DEFAULT_PACK_ID)
	PackFiles.remove_tree(e["path"])
	if String(e.get("thumbnail", "")).begins_with(_user_dir):
		DirAccess.remove_absolute(e["thumbnail"])
	index.remove(key)
	_bus.packs_changed.emit()
	return true


## "Tải lại" for a dev pack: validate it again and reload it if active.
func reload_dev(key: String) -> Dictionary:
	var e: Dictionary = index.rescan(key)
	if key == active_key():
		activate(key)
	_bus.packs_changed.emit()
	return e


func _exit_tree() -> void:
	if _import_thread != null:
		_import_thread.wait_to_finish()
		_import_thread = null
