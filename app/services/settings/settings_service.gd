class_name SettingsService
extends RefCounted
## App-owned settings, stored in %APPDATA%\Saki\app_settings.json.
##
## Backend-owned settings (address pair, model) are NOT here: they go through
## PUT /settings (BackendClient). The file has a `version`; older files are upgraded by
## the functions in MIGRATIONS, one version at a time.
##
## To change the file format: bump CURRENT_VERSION, write `_migrate_<N>_to_<N+1>` and add
## it to _apply_migration (plus a test).
##
## Public API: load_file(), save(), get_value(), set_value(), is_first_run().

const CURRENT_VERSION: int = 1

## Every key with its default. A value of the wrong type in the file falls back to this.
const DEFAULTS: Dictionary = {
	"mode": "chat", # "chat" | "pet"; the app starts in the mode used last time
	"chat_window": {}, # {"x","y","w","h"} in screen pixels; {} = centered default
	"pet_position": {}, # {"x","y"}; {} = bottom-right of the primary screen
	"pet_scale": 1.0, # 1.0 = "vừa"
	"always_on_top": true,
	"active_pack": "default",
	"quality": "auto", # "auto" | "low" | "medium" | "high"
	"auto_tier": "", # result of the last auto detection ("" = never ran)
	"theme": "system", # "system" | "light" | "dark"
	"hotkey_enabled": true,
	"hotkey": "Ctrl+Shift+S",
	"debug_overlay": false,
	"backend_dir": "", # "" = repository root next to the app
	"port": 8765,
}


var _path: String
var _bus: Node
var _data: Dictionary = {}
var _first_run: bool = false


func _init(path: String, bus: Node = null) -> void:
	_path = path
	_bus = bus


## Reads the file (or starts from defaults). Never fails: a broken file is kept as
## `.bak` and replaced with defaults.
func load_file() -> void:
	_first_run = not FileAccess.file_exists(_path)
	var raw: Dictionary = {}
	if not _first_run:
		var text: String = FileAccess.get_file_as_string(_path)
		var json := JSON.new()
		if json.parse(text) == OK and json.data is Dictionary:
			raw = json.data
		else:
			push_warning("Settings file is broken, starting from defaults: %s" % _path)
			DirAccess.copy_absolute(_path, _path + ".bak")
	_data = sanitize(migrate(raw))


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var tmp: String = _path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write settings: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()
	# Write-then-rename so a crash never leaves a half-written file.
	return DirAccess.rename_absolute(tmp, _path) == OK


func get_value(key: String) -> Variant:
	return _data.get(key, DEFAULTS.get(key))


## Stores the value, saves the file and emits EventBus.setting_changed.
## `persist` = false applies the value now and leaves writing to a later save() (for
## values that change many times per second, like Ctrl + wheel scaling).
func set_value(key: String, value: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		push_error("Unknown setting: %s" % key)
		return
	if _data.get(key) == value:
		return
	_data[key] = value
	if persist:
		save()
	if _bus:
		_bus.setting_changed.emit(key, value)


## True when no settings file existed before load_file() (used for the first-run tier probe).
func is_first_run() -> bool:
	return _first_run


func get_all() -> Dictionary:
	return _data.duplicate(true)


# --- pure helpers (tested directly) ----------------------------------------------------

## Upgrades `raw` to CURRENT_VERSION. A file without `version` is version 0.
## A file from a NEWER app keeps its values (unknown keys are dropped by sanitize).
static func migrate(raw: Dictionary) -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	var version: int = int(data.get("version", 0)) if raw.size() > 0 else CURRENT_VERSION
	while version < CURRENT_VERSION:
		var next: Variant = _apply_migration(version, data)
		if next == null:
			push_error("No settings migration from version %d" % version)
			break
		data = next
		version += 1
	data["version"] = maxi(version, CURRENT_VERSION)
	return data


## Keeps known keys with the right type; everything else falls back to DEFAULTS.
static func sanitize(data: Dictionary) -> Dictionary:
	var out: Dictionary = {"version": data.get("version", CURRENT_VERSION)}
	for key: String in DEFAULTS:
		var default_value: Variant = DEFAULTS[key]
		var value: Variant = data.get(key, default_value)
		# JSON has only floats: accept 8765.0 for an int key, 1 for a float key.
		if typeof(default_value) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			value = int(value)
		elif typeof(default_value) == TYPE_FLOAT and typeof(value) == TYPE_INT:
			value = float(value)
		if typeof(value) != typeof(default_value):
			value = default_value
		out[key] = value.duplicate(true) if value is Dictionary else value
	return out


## Returns the migrated dictionary, or null if there is no migration from `from_version`.
static func _apply_migration(from_version: int, data: Dictionary) -> Variant:
	match from_version:
		0:
			return _migrate_0_to_1(data)
	return null


## Version 0 was the development format: the active pack was stored as "pack" and the
## pet scale as a percentage.
static func _migrate_0_to_1(data: Dictionary) -> Dictionary:
	if data.has("pack") and not data.has("active_pack"):
		data["active_pack"] = data["pack"]
	data.erase("pack")
	if data.has("pet_scale_percent"):
		data["pet_scale"] = float(data["pet_scale_percent"]) / 100.0
		data.erase("pet_scale_percent")
	return data
