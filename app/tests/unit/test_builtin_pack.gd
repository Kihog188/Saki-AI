extends GutTest
## The built-in Saki pack (app/packs/default) and the placeholder fallback without it.

const TMP: String = "user://test_tmp/builtin"

var _root: String


func before_each() -> void:
	_root = TMP.path_join(str(randi()))
	DirAccess.make_dir_recursive_absolute(_root)


func after_each() -> void:
	PackFiles.remove_tree(_root)


func _index(builtin_dir: String) -> PackIndex:
	return PackIndex.new(_root.path_join("characters"), _root.path_join("dev"), builtin_dir)


## The built-in pack's own files (without Godot's .import files) in a temp folder, so the
## full user-pack validator can check them.
func _builtin_copy() -> String:
	var dir: String = _root.path_join("default")
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in DirAccess.get_files_at("res://packs/default"):
		if f.get_extension() != "import":
			var out := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
			out.store_buffer(FileAccess.get_file_as_bytes("res://packs/default".path_join(f)))
			out.close()
	return dir


func test_builtin_pack_is_valid_and_not_the_placeholder() -> void:
	var report: Dictionary = PackValidator.validate_folder(_builtin_copy())
	assert_true(report["ok"], report["error"])
	assert_false(report["auto"], "the built-in pack has its own manifest")
	var index := _index(SakiConst.BUILTIN_PACKS_DIR)
	index.refresh()
	var e: Dictionary = index.get_entry(SakiConst.DEFAULT_PACK_ID)
	assert_true(e["valid"])
	assert_eq(e["type"], "2d", "not the code-drawn placeholder")
	assert_eq(e["name"], "Saki")
	assert_eq(e["thumbnail"], "res://packs/default/thumb.png")
	var pack: PackData = PackService.load_pack(e, PackRules.IMPORT_MAX_TEXTURE)
	assert_eq(pack.manifest.id, SakiConst.DEFAULT_PACK_ID)
	assert_eq(RendererRegistry.RENDERERS[pack.manifest.type], "res://renderers/sprite_2d/sprite_renderer.gd")


func test_every_emotion_has_six_frames() -> void:
	var m: PackManifest = PackManifest.parse(FileAccess.get_file_as_string("res://packs/default/manifest.json"))
	assert_true(m.is_valid(), m.first_error())
	for emotion: String in SakiConst.EMOTIONS:
		assert_true(m.emotions.has(emotion), emotion)
		var spec: Dictionary = m.emotions[emotion]
		assert_eq(spec["kind"], "frames", emotion)
		assert_eq(spec["frames"], 6, emotion)
		for f: String in spec["files"]:
			assert_true(ResourceLoader.exists("res://packs/default".path_join(f)), "imported: " + f)


func test_placeholder_when_builtin_folder_is_absent() -> void:
	var index := _index(_root.path_join("no_builtin"))
	index.refresh()
	var e: Dictionary = index.get_entry(SakiConst.DEFAULT_PACK_ID)
	assert_true(e["valid"])
	assert_eq(e["type"], "placeholder")
	var r: CharacterRenderer = RendererRegistry.create_for_pack(PackService.load_pack(e, 1024))
	add_child_autofree(r)
	assert_eq(r.get_script().resource_path, "res://renderers/placeholder/placeholder_renderer.gd")
	r.set_emotion("happy")
	assert_gt(r.natural_size().x, 0.0)


func test_avatar_component_loads_round() -> void:
	var a := SakiAvatar.new()
	add_child_autofree(a)
	assert_not_null(a.texture, "res://assets/avatar.png loads")
	assert_eq(a.custom_minimum_size, Vector2(SakiAvatar.SIZE, SakiAvatar.SIZE))
	var src := Image.create(40, 30, false, Image.FORMAT_RGBA8)
	src.fill(Color.WHITE)
	var img: Image = SakiAvatar.round_image(src, 64)
	assert_eq(img.get_size(), Vector2i(64, 64))
	assert_eq(img.get_pixel(0, 0).a, 0.0, "corner outside the circle")
	assert_eq(img.get_pixel(32, 32).a, 1.0, "centre")
	assert_eq(img.get_pixel(32, 1).a, 1.0, "top edge of the circle")
	assert_same(SakiAvatar.round_texture(SakiAvatar.DEFAULT_PATH, 64), a.texture, "shared, not one copy per message")
