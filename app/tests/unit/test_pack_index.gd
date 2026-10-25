extends GutTest
## PackIndex cache, PackService activation/deletion, and the 200-pack timing check.

const TMP: String = "user://test_tmp/index"

var _root: String
var _users: String
var _devs: String
var _builtin: String


func before_each() -> void:
	_root = TMP.path_join(str(randi()))
	_users = _root.path_join("characters")
	_devs = _root.path_join("characters_dev")
	_builtin = _root.path_join("builtin") # no default/manifest.json -> placeholder
	DirAccess.make_dir_recursive_absolute(_users)
	DirAccess.make_dir_recursive_absolute(_devs)


func after_each() -> void:
	PackFiles.remove_tree(_root)


func _index() -> PackIndex:
	return PackIndex.new(_users, _devs, _builtin)


func test_builtin_placeholder_without_images() -> void:
	var list: Array[Dictionary] = _index().refresh()
	assert_eq(list.size(), 1)
	assert_eq(list[0]["key"], "default")
	assert_eq(list[0]["type"], "placeholder")
	assert_eq(list[0]["name"], "Saki (mặc định)")


func test_lists_user_dev_and_broken_packs() -> void:
	TestPackGenerator.generate(_users, 2)
	TestPackGenerator.generate(_devs, 1)
	DirAccess.make_dir_recursive_absolute(_users.path_join("broken"))
	DirAccess.make_dir_recursive_absolute(_users.path_join("Bad Name"))
	var list: Array[Dictionary] = _index().refresh()
	var by_key: Dictionary = {}
	for e: Dictionary in list:
		by_key[e["key"]] = e
	assert_eq(list[0]["key"], "default", "built-in first")
	assert_true(by_key["test-pack-000"]["valid"])
	assert_true(FileAccess.file_exists(by_key["test-pack-000"]["thumbnail"]))
	assert_eq(by_key["dev/test-pack-000"]["source"], "dev")
	assert_false(by_key["broken"]["valid"])
	assert_string_contains(by_key["broken"]["error"], "manifest.json")
	assert_string_contains(by_key["Bad Name"]["error"], "Tên thư mục")


func test_cache_reuses_unchanged_entries() -> void:
	TestPackGenerator.generate(_users, 1)
	var first: Dictionary = _index().refresh()[1]
	assert_true(FileAccess.file_exists(_users.path_join("index.json")))
	# Corrupt the pack's image: a cached (unchanged manifest) entry must not re-open it.
	var f := FileAccess.open(_users.path_join("test-pack-000/neutral.png"), FileAccess.WRITE)
	f.store_string("broken")
	f.close()
	var again: Dictionary = _index().refresh()[1]
	assert_eq(again["hash"], first["hash"], "came from index.json, pack not re-read")
	# Deleting a folder drops it from the index.
	PackFiles.remove_tree(_users.path_join("test-pack-000"))
	assert_eq(_index().refresh().size(), 1)


func test_id_must_match_folder() -> void:
	TestPackGenerator.generate(_users, 1)
	DirAccess.rename_absolute(_users.path_join("test-pack-000"), _users.path_join("renamed"))
	var e: Dictionary = _index().refresh()[1]
	assert_false(e["valid"])
	assert_string_contains(e["error"], "trùng với tên thư mục")


func test_service_activate_switch_and_delete() -> void:
	TestPackGenerator.generate(_users, 2)
	var bus: Node = autofree(load("res://core/event_bus.gd").new())
	var svc: PackService = autofree(PackService.new(bus, _users, _devs, _builtin))
	svc.refresh()
	watch_signals(bus)
	assert_eq(svc.activate("test-pack-000"), "test-pack-000")
	var anim: Dictionary = svc.active.get_animation("happy")
	assert_eq(anim["frames"].size(), 2, "2x1 sheet")
	var first: PackData = svc.active
	assert_eq(svc.activate("test-pack-001"), "test-pack-001")
	assert_eq(first.loaded_texture_count(), 0, "previous pack unloaded")
	assert_eq(svc.activate("does-not-exist"), "default")
	assert_push_warning("missing or broken")
	svc.activate("test-pack-001")
	assert_true(svc.delete_pack("test-pack-001"))
	assert_eq(svc.active_key(), "default", "deleting the active pack falls back")
	assert_false(DirAccess.dir_exists_absolute(_users.path_join("test-pack-001")))
	assert_false(svc.delete_pack("default"), "built-in cannot be deleted")
	assert_signal_emitted(bus, "active_pack_changed")


func test_texture_limit_applies_on_load() -> void:
	TestPackGenerator.generate(_users, 1, 256)
	var bus: Node = autofree(load("res://core/event_bus.gd").new())
	var svc: PackService = autofree(PackService.new(bus, _users, _devs, _builtin))
	svc.refresh()
	svc.max_texture_size = 64
	svc.activate("test-pack-000")
	var tex: Texture2D = svc.active.get_animation("neutral")["frames"][0]
	assert_eq(tex.get_width(), 64)


func test_200_packs_list_fast() -> void:
	TestPackGenerator.generate(_users, 200, 16)
	var t0: int = Time.get_ticks_msec()
	_index().refresh() # cold: validates every pack once and builds index.json
	var cold: int = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var list: Array[Dictionary] = _index().refresh() # warm: what opening the pack list costs
	var warm: int = Time.get_ticks_msec() - t0
	gut.p("200 packs: cold refresh %d ms, warm refresh %d ms" % [cold, warm])
	assert_eq(list.size(), 201)
	assert_lt(warm, 1000, "pack list must open in under 1 s")
