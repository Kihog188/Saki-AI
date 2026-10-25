extends GutTest
## Shared UI components with fake services: message list paging and node cap (1,000
## messages), plain-text bubbles, sources, input keys, status line, panels.

var _bus: Node
var _ws: TestFakes.FakeWs
var _http: TestFakes.FakeHttp
var _ctx: UiContext
var _root: String


func before_each() -> void:
	_bus = add_child_autofree(load("res://core/event_bus.gd").new())
	_ws = TestFakes.FakeWs.new()
	_http = TestFakes.FakeHttp.new()
	_http.routes["/health"] = TestFakes.FakeHttp.health()
	var client := BackendClient.new(_bus, _ws, _http, "http://127.0.0.1:8765")
	add_child_autofree(client)
	_ctx = UiContext.new()
	_ctx.bus = _bus
	_ctx.backend = client
	_ctx.session = add_child_autofree(ChatSession.new(_bus, client))
	_ctx.mood = add_child_autofree(MoodController.new(_bus))
	_ctx.performance = add_child_autofree(PerformanceService.new(_bus, false))
	_root = "user://test_tmp/ui_%d" % randi()
	_ctx.settings = SettingsService.new(_root.path_join("settings.json"), _bus)
	_ctx.settings.load_file()
	_ctx.packs = add_child_autofree(PackService.new(_bus, _root.path_join("characters"), _root.path_join("dev"), _root.path_join("builtin")))
	_ctx.packs.refresh()
	_ctx.packs.activate("default")
	_ctx.saki_theme = ThemeBuilder.resolve("light")
	_ctx.theme = ThemeBuilder.build(_ctx.saki_theme)


func after_each() -> void:
	PackFiles.remove_tree(_root)


func _connect() -> void:
	_ctx.backend.start()
	await wait_until(func() -> bool: return _ctx.backend.connected, 2.0)


func _rows(from: int, to: int) -> Array:
	var rows: Array = []
	for i: int in range(from, to):
		rows.append({"id": i, "role": "user" if i % 2 == 0 else "assistant", "content": "Tin nhắn số %d" % i})
	return rows


func _mount(c: Control, size: Vector2 = Vector2(480, 600)) -> Control:
	c.theme = _ctx.theme
	add_child_autofree(c)
	c.size = size
	return c


func test_1000_messages_keep_node_count_capped() -> void:
	var list: MessageList = _mount(MessageList.new())
	list.setup(_ctx.session)
	_http.routes["/history"] = TestFakes.FakeHttp.ok({"messages": _rows(950, 1000)})
	await _ctx.session.load_recent()
	await wait_process_frames(2)
	assert_eq(list.live_count(), 50)
	var max_live: int = 0
	var worst_ms: float = 0.0
	# Scroll to the top again and again: older pages are fetched from the "backend".
	for step: int in 400:
		var oldest: int = int(_ctx.session.messages[0]["id"])
		_http.routes["/history"] = TestFakes.FakeHttp.ok({"messages": _rows(maxi(0, oldest - 50), oldest)})
		var t0: int = Time.get_ticks_usec()
		list.scroll_vertical = 0
		list._on_scrolled(0)
		await wait_process_frames(2)
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		max_live = maxi(max_live, list.live_count())
		if list.window().x == 0 and not _ctx.session.has_more:
			break
	assert_eq(_ctx.session.messages.size(), 1000)
	assert_eq(list.window().x, 0, "reached the very first message")
	assert_lte(max_live, SakiConst.MAX_LIVE_MESSAGES, "never more live nodes than the cap")
	gut.p("1000 messages: max live nodes %d, worst scroll step %.1f ms (2 frames)" % [max_live, worst_ms])
	# And back down to the newest.
	for step: int in 400:
		list.scroll_vertical = int(list.get_v_scroll_bar().max_value)
		list._on_scrolled(0)
		await wait_process_frames(2)
		max_live = maxi(max_live, list.live_count())
		if list.window().y == 1000:
			break
	assert_eq(list.window().y, 1000)
	assert_lte(max_live, SakiConst.MAX_LIVE_MESSAGES)


func test_new_messages_append_and_trim() -> void:
	await _connect()
	var list: MessageList = _mount(MessageList.new())
	list.setup(_ctx.session)
	for i: int in SakiConst.MAX_LIVE_MESSAGES + 30:
		_ctx.session.send("tin %d" % i)
		_bus.turn_ended.emit("neutral", "ok", [], false)
	await wait_process_frames(2)
	assert_eq(list.live_count(), SakiConst.MAX_LIVE_MESSAGES)
	assert_eq(list.window().y, _ctx.session.messages.size())


func test_bubble_never_interprets_markup() -> void:
	var b: MessageBubble = _mount(MessageBubble.new())
	b.set_message({"uid": 1, "role": "assistant", "text": "[color=red]x[/color] [url=javascript:a]y[/url]\n```\n[b]code[/b]\n```", "sources": []})
	await wait_process_frames(1)
	assert_eq(_all(b, "RichTextLabel").size(), 0, "no markup-capable control at all")
	var labels: Array[Node] = _all(b, "Label")
	assert_eq((labels[0] as Label).text, "[color=red]x[/color] [url=javascript:a]y[/url]")
	assert_eq((labels[1] as Label).text, "[b]code[/b]")
	assert_eq((labels[1] as Label).theme_type_variation, &"CodeLabel")


func test_sources_only_link_http() -> void:
	var s: SourcesList = _mount(SourcesList.new())
	s.set_sources([
		{"index": 1, "title": "A", "url": "https://dantri.com.vn/a", "date": "2026-10-19"},
		{"index": 2, "title": "B", "url": "javascript:alert(1)", "date": ""},
	])
	var buttons: Array[Node] = s.get_children()
	assert_eq(buttons.size(), 2)
	assert_false((buttons[0] as Button).disabled)
	assert_true((buttons[1] as Button).disabled)
	assert_string_contains((buttons[1] as Button).text, "không rõ ngày")


func test_enter_sends_shift_enter_does_not() -> void:
	await _connect()
	var input: ChatInput = _mount(ChatInput.new(), Vector2(400, 60))
	input.setup(_ctx)
	var edit: TextEdit = _find(input, "TextEdit") as TextEdit
	edit.text = "Xin chào"
	var shift := InputEventKey.new()
	shift.keycode = KEY_ENTER
	shift.pressed = true
	shift.shift_pressed = true
	input._on_edit_input(shift)
	assert_eq(_ws.sent.size(), 0)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	input._on_edit_input(enter)
	assert_eq(_ws.sent[-1], {"type": "user_message", "text": "Xin chào"})
	assert_eq(edit.text, "")
	var stop: Button = input.get_child(2) as Button
	assert_true(stop.visible, "Dừng visible while the turn runs")
	_bus.turn_ended.emit("neutral", "x", [], false)
	_ws.push({"type": "end", "emotion": "neutral", "text": "x"})
	await wait_process_frames(2)
	assert_false(stop.visible)


func test_status_line_texts_and_actions() -> void:
	var line: StatusLine = _mount(StatusLine.new(), Vector2(400, 40))
	line.setup(_ctx)
	var label: Label = line.get_child(0) as Label
	var action: Button = line.get_child(1) as Button
	_bus.backend_state_changed.emit(SakiConst.CONN_CONNECTED, "")
	assert_eq(label.text, "Sẵn sàng")
	_bus.turn_status.emit("searching")
	assert_eq(label.text, "Đang tìm kiếm...")
	_bus.busy_changed.emit(false)
	_bus.llm_reachability_changed.emit(false)
	assert_string_contains(label.text, "Hãy mở Ollama")
	assert_eq(action.text, "Thử lại")
	_bus.backend_state_changed.emit(SakiConst.CONN_FAILED, "Saki đã dừng bất ngờ.")
	assert_eq(action.text, "Khởi động lại")
	assert_true(action.visible)


func test_memories_panel_lists_and_adds() -> void:
	_http.routes["/memories"] = TestFakes.FakeHttp.ok({"memories": [{"id": 1, "text": "Thích [b]mèo[/b]"}]})
	var panel: MemoriesPanel = _mount(MemoriesPanel.new())
	panel.setup(_ctx)
	await wait_process_frames(3)
	var texts: PackedStringArray = []
	for l: Node in _all(panel, "Label"):
		texts.append((l as Label).text)
	assert_has(texts, "Thích [b]mèo[/b]")
	assert_true(Array(texts).any(func(t: String) -> bool: return t.contains("/clear chỉ xóa lịch sử")))


func test_settings_panel_shows_backend_errors() -> void:
	await _connect()
	_http.routes["/settings"] = TestFakes.FakeHttp.ok({"detail": "Cách xưng hô không được để trống."}, 400)
	var panel: SettingsPanel = _mount(SettingsPanel.new())
	panel.setup(_ctx)
	await wait_process_frames(3)
	await panel._save_backend()
	var texts: PackedStringArray = []
	for l: Node in _all(panel, "Label"):
		texts.append((l as Label).text)
	assert_has(texts, "Cách xưng hô không được để trống.")


func test_settings_panel_changes_app_settings() -> void:
	var panel: SettingsPanel = _mount(SettingsPanel.new())
	panel.setup(_ctx)
	var boxes: Array[Node] = _all(panel, "CheckBox")
	assert_gte(boxes.size(), 3)
	(boxes[0] as CheckBox).button_pressed = false
	assert_false(_ctx.settings.get_value("always_on_top"))


func test_pack_manager_lists_previews_and_flags_broken() -> void:
	TestPackGenerator.generate(_root.path_join("characters"), 2, 16)
	DirAccess.make_dir_recursive_absolute(_root.path_join("characters/hong"))
	_ctx.packs.refresh()
	var pm: PackManager = _mount(PackManager.new(), Vector2(800, 600))
	pm.setup(_ctx)
	await wait_process_frames(2)
	pm._select("test-pack-001")
	await wait_process_frames(1)
	var names: PackedStringArray = []
	for l: Node in _all(pm, "Label"):
		names.append((l as Label).text)
	assert_has(names, "Gói thử 001")
	assert_true(Array(names).any(func(t: String) -> bool: return t.begins_with("hong (hong): ")), "broken pack with its reason")
	var buttons: PackedStringArray = []
	for b: Node in _all(pm, "Button"):
		buttons.append((b as Button).text)
	assert_has(buttons, "neutral")
	assert_has(buttons, "happy")
	assert_not_null(_ctx.packs.get("_preview"), "only the preview pack is loaded besides the active one")
	pm._activate.pressed.emit()
	assert_eq(_ctx.packs.active_key(), "test-pack-001")
	assert_eq(_ctx.settings.get_value("active_pack"), "test-pack-001")


func test_character_view_follows_mood_and_pack() -> void:
	var view: CharacterView = _mount(CharacterView.new(), Vector2(300, 300))
	view.setup(_ctx)
	assert_eq(view.renderer.get_script().resource_path, RendererRegistry.RENDERERS["placeholder"])
	_bus.turn_started.emit("happy", false)
	assert_eq(view.renderer.emotion, "happy")
	TestPackGenerator.generate(_root.path_join("characters"), 1, 16)
	_ctx.packs.refresh()
	_ctx.packs.activate("test-pack-000")
	await wait_process_frames(1)
	assert_eq(view.renderer.get_script().resource_path, RendererRegistry.RENDERERS["2d"])
	assert_eq(view.renderer.emotion, "happy", "new renderer starts with the current mood")


func _find(n: Node, cls: String) -> Node:
	var all: Array[Node] = _all(n, cls)
	return all[0] if all.size() > 0 else null


func _all(n: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for c: Node in n.get_children():
		if c.get_class() == cls:
			out.append(c)
		out.append_array(_all(c, cls))
	return out
