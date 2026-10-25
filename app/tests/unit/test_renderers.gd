extends GutTest
## Renderer registry, unknown-type fallback, and each renderer running on its own in an
## empty scene (given only a pack and an emotion).

const TMP: String = "user://test_tmp/renderers"

var _root: String


func before_each() -> void:
	_root = TMP.path_join(str(randi()))
	TestPackGenerator.generate(_root, 1, 32)


func after_each() -> void:
	PackFiles.remove_tree(_root)


func _pack() -> PackData:
	var dir: String = _root.path_join("test-pack-000")
	var report: Dictionary = PackValidator.validate_folder(dir)
	assert_true(report["ok"], report["error"])
	return PackData.new({"key": "test-pack-000", "id": "test-pack-000", "path": dir}, report["manifest"], 1024)


func _tier(animations: bool) -> QualityTier:
	var t := QualityTier.new()
	t.animations = animations
	t.effects = animations
	return t


func _mount(r: CharacterRenderer) -> CharacterRenderer:
	add_child_autofree(r)
	r.size = Vector2(300, 300)
	return r


func test_registry_maps_types() -> void:
	var r2d: CharacterRenderer = autofree(RendererRegistry.create("2d"))
	assert_eq(r2d.get_script().resource_path, RendererRegistry.RENDERERS["2d"])
	var ph: CharacterRenderer = autofree(RendererRegistry.create("placeholder"))
	assert_eq(ph.get_script().resource_path, RendererRegistry.RENDERERS["placeholder"])


func test_unknown_type_falls_back_to_thumbnail() -> void:
	var r: CharacterRenderer = autofree(RendererRegistry.create("3d-gltf"))
	assert_push_warning("No renderer for pack type '3d-gltf'")
	assert_true(r is FallbackRenderer)
	assert_true((r as FallbackRenderer).unsupported)
	var pack := _pack()
	pack.entry["thumbnail"] = _root.path_join("test-pack-000/neutral.png")
	_mount(r)
	r.load_pack(pack)
	await wait_process_frames(1)
	assert_eq(r.natural_size(), Vector2(64, 64), "thumbnail loaded (32 px x 2)")
	var label: Label = r.get_child(0) as Label
	assert_eq(label.text, "Loại gói này chưa được hỗ trợ")


func test_deleted_renderer_folder_falls_back() -> void:
	var table: Dictionary = {"2d": "res://renderers/deleted_folder/sprite_renderer.gd"}
	assert_false(RendererRegistry.has_renderer("2d", table))
	var r: CharacterRenderer = autofree(RendererRegistry.create("2d", table))
	assert_push_warning("No renderer for pack type '2d'")
	assert_true(r is FallbackRenderer)


func test_2d_renderer_standalone() -> void:
	var r: CharacterRenderer = _mount(RendererRegistry.create("2d"))
	r.set_quality(_tier(true))
	r.load_pack(_pack())
	r.set_emotion("neutral")
	await wait_process_frames(1)
	assert_eq(r.natural_size(), Vector2(32, 32))
	assert_gte(r.get_alpha_outline().size(), 3)
	var rect: Rect2 = r.get_visible_rect()
	assert_eq(rect.size, Vector2(300, 300), "fits the panel keeping aspect")
	for p: Vector2 in r.get_alpha_outline():
		assert_true(rect.grow(0.01).has_point(p), "outline inside the drawn rect")
	r.set_emotion("happy")
	assert_true(r.is_processing(), "2-frame sheet animates")
	watch_signals(r)
	r._process(1.0)
	assert_signal_emitted(r, "visual_changed")
	r.set_quality(_tier(false))
	assert_false(r.is_processing(), "animations off in a low tier")
	r.unload()
	assert_null(r.pack)


func test_2d_renderer_unknown_emotion_uses_chain() -> void:
	var r: CharacterRenderer = _mount(RendererRegistry.create("2d"))
	r.load_pack(_pack())
	r.set_emotion("very-angry-unknown")
	assert_eq(r.get("_anim")["name"], "emotions/neutral")


func test_2d_renderer_with_broken_pack_shows_placeholder() -> void:
	var pack := _pack()
	DirAccess.remove_absolute(_root.path_join("test-pack-000/neutral.png"))
	DirAccess.remove_absolute(_root.path_join("test-pack-000/happy_sheet.png"))
	var r: CharacterRenderer = _mount(RendererRegistry.create("2d"))
	r.load_pack(pack)
	assert_push_warning_count(2)
	assert_eq(r.get_child_count(), 1, "placeholder child drawn instead")
	assert_gte(r.get_alpha_outline().size(), 3)


func test_placeholder_standalone_every_emotion_and_state() -> void:
	var r: CharacterRenderer = _mount(RendererRegistry.create("placeholder"))
	r.set_quality(_tier(true))
	r.load_pack(null)
	for e: String in SakiConst.EMOTIONS + PackedStringArray(["unknown"]):
		for s: String in SakiConst.STATES:
			r.set_emotion(e)
			r.set_state(StringName(s))
			r._process(0.3)
			r.queue_redraw()
			await wait_process_frames(1)
	assert_gte(r.get_alpha_outline().size(), 3)
	assert_eq(r.natural_size(), Vector2(240, 270))


func test_fit_rect() -> void:
	var rect: Rect2 = CharacterRenderer.fit_rect(Vector2(100, 200), Vector2(400, 400), Vector2(0.5, 1.0))
	assert_eq(rect, Rect2(Vector2(100, 0), Vector2(200, 400)))
	rect = CharacterRenderer.fit_rect(Vector2(200, 100), Vector2(400, 400), Vector2(0.5, 1.0))
	assert_eq(rect, Rect2(Vector2(0, 200), Vector2(400, 200)), "bottom aligned")


func test_alpha_outline_follows_visible_pixels() -> void:
	var img := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(40, 10, 20, 80), Color.WHITE)
	var poly: PackedVector2Array = AlphaOutline.from_image(img)
	var xs: Array[float] = []
	for p: Vector2 in poly:
		xs.append(p.x)
	assert_lt(xs.max(), 0.7)
	assert_gt(xs.min(), 0.3)
	assert_eq(AlphaOutline.from_image(Image.create(10, 10, false, Image.FORMAT_RGBA8)).size(), 0, "fully transparent")
