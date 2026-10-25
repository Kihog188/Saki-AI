extends GutTest
## PackManifest parsing and validation, PackRules path rules, fallback chain.


func _manifest(overrides: Dictionary = {}) -> String:
	var d: Dictionary = {
		"format": 1, "id": "miku-chibi", "name": "Miku Chibi", "type": "2d",
		"emotions": {"neutral": {"image": "neutral.png"}},
	}
	d.merge(overrides, true)
	return JSON.stringify(d)


func test_full_example_parses() -> void:
	var m := PackManifest.parse(JSON.stringify({
		"format": 1, "id": "miku-chibi", "name": "Miku Chibi", "author": "A", "version": "1.0.0",
		"license": "", "type": "2d", "thumbnail": "thumb.png", "default_emotion": "neutral",
		"base_scale": 1.0, "anchor": [0.5, 1.0], "future_field": {"ignored": true},
		"emotions": {
			"neutral": {"image": "neutral.png"},
			"happy": {"sheet": "happy_sheet.png", "columns": 4, "rows": 2, "frames": 8, "fps": 10, "loop": true},
			"thinking": {"frames": ["t1.png", "t2.png", "t3.png"], "fps": 6, "loop": true},
		},
		"states": {"talking": {"sheet": "talk.png", "columns": 4, "rows": 1, "fps": 12}},
	}))
	assert_true(m.is_valid(), str(m.errors))
	assert_eq(m.emotions["happy"]["kind"], "sheet")
	assert_eq(m.emotions["happy"]["frames"], 8)
	assert_eq(m.states["talking"]["frames"], 4, "frames defaults to columns*rows")
	assert_eq(m.emotions["thinking"]["files"].size(), 3)
	assert_eq(m.anchor, Vector2(0.5, 1.0))
	assert_eq(m.referenced_files().size(), 7, "thumb + neutral + sheet + 3 frames + talk")


func test_future_format_is_unsupported_not_broken() -> void:
	var m := PackManifest.parse(_manifest({"format": 2, "emotions": "whatever"}))
	assert_true(m.unsupported)
	assert_false(m.is_valid())
	assert_string_contains(m.first_error(), "định dạng 2")


func test_other_types_only_need_common_fields() -> void:
	var m := PackManifest.parse(JSON.stringify({"format": 1, "id": "robot", "name": "Robot", "type": "3d-gltf", "thumbnail": "t.png"}))
	assert_true(m.is_valid(), str(m.errors))


func test_errors_name_the_field() -> void:
	var cases: Dictionary = {
		"{not json": "JSON",
		_manifest({"id": "Bad ID"}): "id",
		_manifest({"name": ""}): "name",
		_manifest({"anchor": [2, 0]}): "anchor",
		_manifest({"base_scale": 99}): "base_scale",
		_manifest({"emotions": {"happy": {"image": "a.png", "sheet": "b.png"}}}): "emotions.happy",
		_manifest({"emotions": {"happy": {"sheet": "b.png", "columns": 4}}}): "emotions.happy.rows",
		_manifest({"emotions": {"happy": {"sheet": "b.png", "columns": 2, "rows": 2, "frames": 5}}}): "emotions.happy.frames",
		_manifest({"emotions": {"happy": {"image": "../x.png"}}}): "../x.png",
		_manifest({"emotions": {"happy": {"image": "x.svg"}}}): "x.svg",
		_manifest({"emotions": {"Happy!": {"image": "x.png"}}}): "emotions.Happy!",
		_manifest({"emotions": {"happy": {"image": "x.png", "loop": "yes"}}}): "loop",
		_manifest({"emotions": {}}): "emotions",
	}
	for text: String in cases:
		var m := PackManifest.parse(text)
		assert_false(m.is_valid(), "should fail: " + text)
		assert_string_contains(m.first_error(), cases[text])


func test_frame_limit() -> void:
	var many: Array = []
	for i: int in PackRules.MAX_FRAMES + 1:
		many.append("f%d.png" % i)
	var m := PackManifest.parse(_manifest({"emotions": {"happy": {"frames": many}}}))
	assert_false(m.is_valid())
	assert_string_contains(m.first_error(), "quá nhiều khung hình")


func test_path_rules() -> void:
	assert_eq(PackRules.check_path("a/b.png"), "")
	assert_eq(PackRules.check_path("../a.png"), "PACK_ERR_PATH_TRAVERSAL")
	assert_eq(PackRules.check_path("a/../../b.png"), "PACK_ERR_PATH_TRAVERSAL")
	assert_eq(PackRules.check_path("/etc/passwd"), "PACK_ERR_PATH_ABSOLUTE")
	assert_eq(PackRules.check_path("C:/x.png"), "PACK_ERR_PATH_ABSOLUTE")
	assert_eq(PackRules.check_path("a\\b.png"), "PACK_ERR_PATH_BACKSLASH")
	assert_eq(PackRules.check_path(".hidden.png"), "PACK_ERR_PATH_CHARS")
	assert_eq(PackRules.check_path("tên.png"), "PACK_ERR_PATH_CHARS")
	assert_eq(PackRules.check_path("a b.png"), "PACK_ERR_PATH_CHARS")
	assert_eq(PackRules.check_path("a/b/c/d/e.png"), "PACK_ERR_PATH_DEEP")
	assert_true(PackRules.extension_allowed("x.WEBP"))
	for bad: String in ["x.gd", "x.tscn", "x.tres", "x.res", "x.import", "x.svg", "x.exe", "x"]:
		assert_false(PackRules.extension_allowed(bad), bad)


func test_fallback_chain() -> void:
	var avail := PackedStringArray(["happy", "neutral", "sad"])
	assert_eq(PackData.resolve_emotion(avail, "sad", "happy"), "sad")
	assert_eq(PackData.resolve_emotion(avail, "angry", "happy"), "happy", "unknown -> default_emotion")
	assert_eq(PackData.resolve_emotion(PackedStringArray(["neutral", "sad"]), "angry", "happy"), "neutral")
	assert_eq(PackData.resolve_emotion(PackedStringArray(["sad", "happy"]), "angry", "x"), "sad", "first available")
	assert_eq(PackData.resolve_emotion(PackedStringArray(), "angry", "x"), "", "nothing -> placeholder")


func test_states_override_emotions() -> void:
	var m := PackManifest.parse(_manifest({
		"emotions": {"neutral": {"image": "n.png"}, "happy": {"image": "h.png"}, "thinking": {"image": "t.png"}},
		"states": {"talking": {"image": "talk.png"}, "idle": {"image": "idle.png"}},
	}))
	assert_true(m.is_valid(), str(m.errors))
	var pack := PackData.new({"id": "x", "path": "user://nowhere"}, m, 1024)
	assert_eq(pack._pick_key("happy", SakiConst.STATE_TALKING), "states/talking")
	assert_eq(pack._pick_key("happy", SakiConst.STATE_THINKING), "emotions/thinking")
	assert_eq(pack._pick_key("happy", SakiConst.STATE_IDLE), "emotions/happy", "idle state only at rest")
	assert_eq(pack._pick_key("neutral", SakiConst.STATE_IDLE), "states/idle")
	assert_eq(pack._pick_key("whatever", SakiConst.STATE_LISTENING), "emotions/neutral")


func test_broken_assets_fall_back_without_crashing() -> void:
	var m := PackManifest.parse(_manifest({"emotions": {"neutral": {"image": "missing.png"}, "happy": {"image": "missing2.png"}}}))
	var pack := PackData.new({"id": "x", "path": "user://nowhere"}, m, 1024)
	assert_eq(pack.get_animation("happy"), {}, "everything missing -> placeholder")
	assert_true(pack.is_broken("emotions/happy"))
	assert_true(pack.is_broken("emotions/neutral"))
	assert_push_warning_count(2, "each broken asset is logged once")


func test_fit_image_keeps_sheet_grid() -> void:
	var img := Image.create(1000, 300, false, Image.FORMAT_RGBA8)
	assert_true(PackData.fit_image(img, 512, 4, 3))
	assert_eq(img.get_width() % 4, 0)
	assert_eq(img.get_height() % 3, 0)
	assert_lte(img.get_width(), 512)
	assert_false(PackData.fit_image(img, 4096))
