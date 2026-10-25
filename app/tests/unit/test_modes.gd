extends GutTest
## Screen placement, passthrough polygon, and both display modes on fake services.
## Runs headless: window calls are no-ops there, so this checks logic and wiring, not the
## real desktop (that is checked by hand, see HANDOFF.md).

var _bus: Node
var _ctx: UiContext
var _root: String


func before_each() -> void:
	_bus = add_child_autofree(load("res://core/event_bus.gd").new())
	var http := TestFakes.FakeHttp.new()
	var client := BackendClient.new(_bus, TestFakes.FakeWs.new(), http, "http://127.0.0.1:8765")
	add_child_autofree(client)
	_ctx = UiContext.new()
	_ctx.bus = _bus
	_ctx.backend = client
	_ctx.session = add_child_autofree(ChatSession.new(_bus, client))
	_ctx.mood = add_child_autofree(MoodController.new(_bus))
	_ctx.performance = add_child_autofree(PerformanceService.new(_bus, false))
	_root = "user://test_tmp/modes_%d" % randi()
	_ctx.settings = SettingsService.new(_root.path_join("settings.json"), _bus)
	_ctx.settings.load_file()
	_ctx.packs = add_child_autofree(PackService.new(_bus, _root.path_join("characters"), _root.path_join("dev"), _root.path_join("builtin")))
	_ctx.packs.refresh()
	_ctx.packs.activate("default")
	_ctx.saki_theme = ThemeBuilder.resolve("light")
	_ctx.theme = ThemeBuilder.build(_ctx.saki_theme)


func after_each() -> void:
	PanelWindow.close_all()
	PackFiles.remove_tree(_root)


func test_fit_on_screen_keeps_or_recentres() -> void:
	var screens: Array[Rect2i] = [Rect2i(0, 0, 1920, 1040), Rect2i(1920, 0, 1280, 984)]
	assert_eq(WindowService.fit_on_screen(Rect2i(100, 100, 800, 600), screens), Rect2i(100, 100, 800, 600))
	assert_eq(WindowService.fit_on_screen(Rect2i(2000, 50, 800, 600), screens), Rect2i(2000, 50, 800, 600), "second monitor")
	# Second monitor unplugged: the window comes back, centred on the primary screen.
	var lost: Rect2i = WindowService.fit_on_screen(Rect2i(2000, 50, 800, 600), [screens[0]] as Array[Rect2i])
	assert_eq(lost, Rect2i(560, 220, 800, 600))
	assert_eq(WindowService.fit_on_screen(Rect2i(100, -300, 800, 600), screens).position.y, 0, "title bar never above the screen")
	var huge: Rect2i = WindowService.fit_on_screen(Rect2i(-5000, 0, 4000, 3000), screens)
	assert_true(screens[0].encloses(huge), "shrunk to fit")


func test_passthrough_polygon_is_one_shape() -> void:
	var outline := PackedVector2Array([Vector2(40, 100), Vector2(40, 300), Vector2(200, 300), Vector2(200, 100)])
	var poly: PackedVector2Array = WindowService.passthrough_polygon(outline, Rect2(0, 0, 260, 80), Rect2())
	assert_true(Geometry2D.is_point_in_polygon(Vector2(130, 40), poly), "bubble is clickable")
	assert_true(Geometry2D.is_point_in_polygon(Vector2(120, 200), poly), "character is clickable")
	assert_false(Geometry2D.is_point_in_polygon(Vector2(10, 250), poly), "transparent area beside it is not")
	assert_eq(WindowService.passthrough_polygon(outline, Rect2(), Rect2()), outline, "no bubble: just the outline")
	assert_eq(WindowService.passthrough_polygon(PackedVector2Array(), Rect2(), Rect2(0, 0, 10, 10)).size(), 4)


func test_chat_mode_builds_and_saves_window() -> void:
	var mode := ChatWindowMode.new()
	add_child_autofree(mode)
	mode.enter(_ctx)
	await wait_process_frames(2)
	assert_not_null(_find(mode, "ChatPanel"))
	assert_not_null(_find(mode, "CharacterView"))
	assert_not_null(_find(mode, "StatusLine"))
	mode.save_window_rect(Vector2i(5, 6), Vector2i(800, 600), Window.MODE_MINIMIZED)
	assert_eq(_ctx.settings.get_value("chat_window"), {}, "not saved while minimized")
	mode.save_window_rect(Vector2i(5, 6), Vector2i(800, 600), Window.MODE_WINDOWED)
	assert_eq(_ctx.settings.get_value("chat_window"), {"x": 5, "y": 6, "w": 800, "h": 600})


func test_chat_mode_narrow_layout() -> void:
	var mode := ChatWindowMode.new()
	add_child_autofree(mode)
	mode.enter(_ctx)
	mode.apply_layout_for_width(400)
	assert_true(mode._layout.vertical, "narrow: character above the chat")
	mode.apply_layout_for_width(1000)
	assert_false(mode._layout.vertical)


func test_pet_mode_bubble_click_and_scale() -> void:
	var mode := PetMode.new()
	add_child_autofree(mode)
	mode.enter(_ctx)
	await wait_process_frames(2)
	var bubble: SpeechBubble = _find(mode, "SpeechBubble") as SpeechBubble
	assert_false(bubble.visible)
	_bus.turn_started.emit("happy", false)
	_bus.turn_delta.emit("Chào ")
	_bus.turn_delta.emit("bạn")
	assert_true(bubble.visible)
	assert_eq((_find(bubble, "Label") as Label).text, "Chào bạn")
	_bus.turn_ended.emit("happy", "Chào bạn nhé.", [], false)
	assert_eq((_find(bubble, "Label") as Label).text, "Chào bạn nhé.")
	bubble._process(ChatFormat.bubble_seconds("Chào bạn nhé.") + 0.1)
	assert_false(bubble.visible, "auto-hides")
	# Click (no drag): reaction + mini chat with the shared ChatPanel.
	watch_signals(_bus)
	mode._on_click()
	assert_signal_emitted_with_parameters(_bus, "character_reaction", ["surprised", 1.5])
	await wait_process_frames(1)
	var mini: Window = PanelWindow._open.get("chat")
	assert_not_null(mini)
	assert_not_null(_find(mini, "ChatPanel"), "mini chat reuses ChatPanel")
	# Ctrl + wheel scaling is applied at once and saved shortly after.
	var before: float = _ctx.settings.get_value("pet_scale")
	mode._set_scale_live(before + 0.1)
	assert_almost_eq(float(_ctx.settings.get_value("pet_scale")), before + 0.1, 0.001)
	mode.exit()
	assert_true((_ctx.settings.get_value("pet_position") as Dictionary).has_all(["x", "y"]))


func test_long_reply_is_cut_with_read_more() -> void:
	var mode := PetMode.new()
	add_child_autofree(mode)
	mode.enter(_ctx)
	var bubble: SpeechBubble = _find(mode, "SpeechBubble") as SpeechBubble
	bubble.say("Một câu rất dài. ".repeat(40), true)
	var more: Button = _find(bubble, "Button") as Button
	assert_true(more.visible)
	assert_eq(more.text, "…xem tiếp")


func test_no_duplicated_message_rendering() -> void:
	# Both modes render messages only through ui/chat (MessageBubble); modes/ never builds them.
	for path: String in ["res://modes/chat_window/chat_window_mode.gd", "res://modes/pet/pet_mode.gd", "res://modes/display_mode.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_false(src.contains("MessageBubble"), path)
		assert_false(src.contains("RichTextLabel"), path)


func _find(n: Node, cls: String) -> Node:
	for c: Node in n.get_children():
		if c.get_class() == cls or (c.get_script() != null and c.get_script().get_global_name() == cls):
			return c
		var deep: Node = _find(c, cls)
		if deep != null:
			return deep
	return null
