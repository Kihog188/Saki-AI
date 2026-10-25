extends GutTest
## SettingsService: defaults, type sanitising, migration, save/load round trip.

const TMP_DIR: String = "user://test_tmp/settings"

var _path: String


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_path = TMP_DIR.path_join("s_%d.json" % randi())


func after_each() -> void:
	for f: String in [_path, _path + ".bak", _path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_first_run_uses_defaults() -> void:
	var s := SettingsService.new(_path)
	s.load_file()
	assert_true(s.is_first_run())
	assert_eq(s.get_value("mode"), "chat")
	assert_eq(s.get_value("pet_scale"), 1.0)
	assert_eq(s.get_value("port"), 8765)


func test_round_trip_and_signal() -> void:
	var bus: Node = autofree(load("res://core/event_bus.gd").new())
	watch_signals(bus)
	var s := SettingsService.new(_path, bus)
	s.load_file()
	s.set_value("mode", "pet")
	s.set_value("pet_scale", 1.4)
	assert_signal_emit_count(bus, "setting_changed", 2)
	var again := SettingsService.new(_path)
	again.load_file()
	assert_false(again.is_first_run())
	assert_eq(again.get_value("mode"), "pet")
	assert_almost_eq(float(again.get_value("pet_scale")), 1.4, 0.0001)
	assert_eq(again.get_value("port"), 8765, "JSON float 8765.0 comes back as int")
	assert_typeof(again.get_value("port"), TYPE_INT)


func test_unknown_key_is_rejected() -> void:
	var s := SettingsService.new(_path)
	s.load_file()
	s.set_value("nope", 1)
	assert_push_error("Unknown setting")
	assert_false(s.get_all().has("nope"))


func test_wrong_types_fall_back_to_defaults() -> void:
	var clean: Dictionary = SettingsService.sanitize({
		"mode": 3, "always_on_top": "yes", "chat_window": [], "port": 9000.0, "pet_scale": 2,
		"extra": "dropped",
	})
	assert_eq(clean["mode"], "chat")
	assert_eq(clean["always_on_top"], true)
	assert_eq(clean["chat_window"], {})
	assert_eq(clean["port"], 9000)
	assert_eq(clean["pet_scale"], 2.0)
	assert_false(clean.has("extra"))


func test_migration_from_version_0() -> void:
	var migrated: Dictionary = SettingsService.migrate({"pack": "miku", "pet_scale_percent": 150})
	assert_eq(migrated["version"], SettingsService.CURRENT_VERSION)
	assert_eq(migrated["active_pack"], "miku")
	assert_almost_eq(float(migrated["pet_scale"]), 1.5, 0.0001)
	assert_false(migrated.has("pack"))


func test_migration_keeps_newer_files() -> void:
	var migrated: Dictionary = SettingsService.migrate({"version": 99, "mode": "pet"})
	assert_eq(migrated["version"], 99)
	assert_eq(SettingsService.sanitize(migrated)["mode"], "pet")


func test_broken_file_is_backed_up() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var s := SettingsService.new(_path)
	s.load_file()
	assert_push_warning("Settings file is broken")
	assert_true(FileAccess.file_exists(_path + ".bak"))
	assert_eq(s.get_value("mode"), "chat")
