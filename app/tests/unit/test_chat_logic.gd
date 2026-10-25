extends GutTest
## ChatSession (messages + history paging), MoodController, ChatFormat, StatusModel.

var _bus: Node
var _ws: TestFakes.FakeWs
var _http: TestFakes.FakeHttp
var _client: BackendClient
var _session: ChatSession


func before_each() -> void:
	_bus = add_child_autofree(load("res://core/event_bus.gd").new())
	_ws = TestFakes.FakeWs.new()
	_http = TestFakes.FakeHttp.new()
	_http.routes["/health"] = TestFakes.FakeHttp.health()
	_client = BackendClient.new(_bus, _ws, _http, "http://127.0.0.1:8765")
	add_child_autofree(_client)
	_session = ChatSession.new(_bus, _client)
	add_child_autofree(_session)


func _connect() -> void:
	_client.start()
	await wait_until(func() -> bool: return _client.connected, 2.0)


func _rows(from: int, to: int) -> Array:
	var rows: Array = []
	for i: int in range(from, to):
		rows.append({"id": i, "role": "user" if i % 2 == 0 else "assistant", "content": "m%d" % i, "kind": "chat", "created_at": 0.0})
	return rows


func test_streaming_reset_end() -> void:
	await _connect()
	assert_true(_session.send("Chào"))
	_bus.turn_started.emit("neutral", false)
	_bus.turn_delta.emit("Lặp lại")
	_bus.turn_reset.emit()
	assert_eq(_session.messages[1]["text"], "", "reset discards the streamed text")
	_bus.turn_started.emit("happy", false)
	_bus.turn_delta.emit("Chào ")
	_bus.turn_delta.emit("bạn")
	_bus.turn_ended.emit("happy", "Chào bạn.", [{"index": 1}], false)
	assert_eq(_session.messages.size(), 2)
	var m: Dictionary = _session.messages[1]
	assert_eq(m["text"], "Chào bạn.", "end text is authoritative")
	assert_eq(m["emotion"], "happy")
	assert_eq(m["status"], "done")
	assert_eq(m["sources"].size(), 1)


func test_cancel_and_error() -> void:
	await _connect()
	_session.send("dài")
	_bus.turn_delta.emit("Một đoạn")
	_bus.turn_cancelled.emit()
	assert_eq(_session.messages[1]["text"], "Một đoạn (đã dừng)")
	assert_eq(_session.messages[1]["status"], "cancelled")
	_session.send("x")
	_bus.turn_status.emit("thinking")
	_bus.turn_error.emit("Saki chưa kết nối được với mô hình.")
	assert_eq(_session.messages[-1]["role"], "error")
	assert_eq(_session.messages.size(), 4)
	_bus.turn_started.emit("neutral", false)
	_bus.turn_error.emit("Lỗi")
	assert_eq(_session.messages[-1]["role"], "error", "empty streaming bubble becomes the error")
	assert_eq(_session.messages.size(), 5)


func test_cannot_send_offline_or_empty() -> void:
	assert_false(_session.send("hi"))
	await _connect()
	assert_false(_session.send("   "))


func test_memory_commands_trigger_refresh() -> void:
	await _connect()
	watch_signals(_bus)
	_session.send("/rmb Tên tôi là Minh")
	_bus.turn_ended.emit("neutral", "Đã nhớ: Tên tôi là Minh", [], true)
	assert_signal_emit_count(_bus, "memories_changed", 1)
	_session.send("hello /rmb")
	_bus.turn_ended.emit("happy", "Chào", [], false)
	assert_signal_emit_count(_bus, "memories_changed", 1)


func test_history_paging() -> void:
	_http.routes["/history"] = TestFakes.FakeHttp.ok({"messages": _rows(950, 1000)})
	await _session.load_recent()
	assert_eq(_session.messages.size(), 50)
	assert_true(_session.has_more)
	assert_eq(_session.messages[0]["text"], "m950")
	_http.routes["/history"] = TestFakes.FakeHttp.ok({"messages": _rows(900, 950)})
	watch_signals(_session)
	await _session.load_older()
	assert_string_ends_with(_http.calls[-1]["url"], "before=950")
	assert_eq(_session.messages.size(), 100)
	assert_eq(_session.messages[0]["text"], "m900")
	assert_signal_emitted_with_parameters(_session, "older_loaded", [50])
	_http.routes["/history"] = TestFakes.FakeHttp.ok({"messages": _rows(880, 900)})
	await _session.load_older()
	assert_false(_session.has_more, "a short page means the start was reached")
	var calls: int = _http.calls.size()
	await _session.load_older()
	assert_eq(_http.calls.size(), calls, "no request once everything is loaded")


func test_history_rows_are_sanitised() -> void:
	var msgs: Array[Dictionary] = ChatSession.from_history([
		{"id": 1, "role": "assistant", "content": "[b]x[/b]", "emotion": "happy"},
		{"id": 2, "role": "system", "content": "skip"},
		"junk",
		{"role": "user", "content": 5},
	])
	assert_eq(msgs.size(), 2)
	assert_eq(msgs[0]["text"], "[b]x[/b]", "kept as plain text, never parsed")
	assert_eq(msgs[1]["text"], "")
	assert_eq(msgs[1]["id"], -1)


func test_mood_flow() -> void:
	var mood: MoodController = add_child_autofree(MoodController.new(_bus))
	watch_signals(_bus)
	_bus.turn_status.emit("thinking")
	assert_eq(mood.state, SakiConst.STATE_THINKING)
	_bus.turn_started.emit("happy", false)
	_bus.turn_delta.emit("a")
	assert_eq(mood.state, SakiConst.STATE_TALKING)
	assert_eq(mood.emotion, "happy")
	_bus.turn_ended.emit("embarrassed", "a", [], false)
	assert_eq(mood.state, SakiConst.STATE_IDLE)
	assert_eq(mood.emotion, "embarrassed")
	mood.react("surprised", 1.5)
	assert_eq(mood.shown_emotion(), "surprised")
	mood._process(1.6)
	assert_eq(mood.shown_emotion(), "embarrassed", "reaction ends")
	mood._process(SakiConst.DEFAULT_IDLE_SECONDS)
	assert_eq(mood.emotion, "neutral", "idle timeout")
	assert_signal_emitted_with_parameters(_bus, "character_emotion_changed", ["neutral"])
	mood.set_idle_seconds(3.0)
	assert_eq(mood.idle_seconds, 3.0)


func test_unknown_emotion_passes_through() -> void:
	var mood: MoodController = add_child_autofree(MoodController.new(_bus))
	_bus.turn_started.emit("angry-new-emotion", false)
	assert_eq(mood.shown_emotion(), "angry-new-emotion", "the renderer applies the fallback chain")


func test_code_segments() -> void:
	var s: Array[Dictionary] = ChatFormat.segments("Xem:\n```python\nprint(1)\n```\nXong")
	assert_eq(s.size(), 3)
	assert_eq(s[1], {"code": true, "text": "print(1)"})
	assert_eq(s[2]["text"], "Xong")
	var open: Array[Dictionary] = ChatFormat.segments("a ```b")
	assert_true(open[1]["code"], "unclosed fence -> code")
	assert_eq(ChatFormat.segments("plain [b]x[/b]"), [{"code": false, "text": "plain [b]x[/b]"}])


func test_sources_and_urls() -> void:
	assert_eq(ChatFormat.format_source({"index": 1, "title": "Giá vàng", "url": "https://news.google.com/x", "display_url": "laodong.vn", "date": "2026-10-19"}),
		"[1] Giá vàng — laodong.vn (19/10/2026)")
	assert_eq(ChatFormat.format_source({"index": 2, "title": "FT", "url": "https://ft.com/a", "date": "", "paywalled": true}),
		"[2] FT — https://ft.com/a (không rõ ngày) (trả phí)")
	assert_true(ChatFormat.is_openable_url("https://dantri.com.vn/a?b=1"))
	assert_true(ChatFormat.is_openable_url("HTTP://x.vn"))
	for bad: String in ["javascript:alert(1)", "file:///C:/Windows", "https://", " https://a.vn", "https://a.vn/\nx", "ftp://a", ""]:
		assert_false(ChatFormat.is_openable_url(bad), bad)


func test_bubble_duration_formula() -> void:
	assert_almost_eq(ChatFormat.bubble_seconds(""), 2.5, 0.001)
	assert_almost_eq(ChatFormat.bubble_seconds("x".repeat(50)), 2.5 + 3.0, 0.001)
	assert_eq(ChatFormat.bubble_seconds("x".repeat(1000)), 12.0, "capped")
	var long: Dictionary = ChatFormat.bubble_text("từ ".repeat(200))
	assert_true(long["truncated"])
	assert_lte(long["text"].length(), SakiConst.BUBBLE_MAX_CHARS + 1)
	assert_false(ChatFormat.bubble_text("ngắn")["truncated"])


func test_status_model() -> void:
	assert_eq(StatusModel.describe(SakiConst.CONN_CONNECTED, "", true, "")["text"], "Sẵn sàng")
	assert_eq(StatusModel.describe(SakiConst.CONN_CONNECTED, "", true, "thinking")["text"], "Saki đang suy nghĩ...")
	assert_eq(StatusModel.describe(SakiConst.CONN_CONNECTED, "", true, "searching")["text"], "Đang tìm kiếm...")
	assert_eq(StatusModel.describe(SakiConst.CONN_DISCONNECTED, "", true, "")["text"], "Mất kết nối với Saki")
	var llm: Dictionary = StatusModel.describe(SakiConst.CONN_CONNECTED, "", false, "")
	assert_eq(llm["text"], "Chưa kết nối được với mô hình. Hãy mở Ollama rồi bấm Thử lại.")
	assert_eq(llm["action"], "retry_llm")
	var crash: Dictionary = StatusModel.describe(SakiConst.CONN_FAILED, "Saki đã dừng bất ngờ.", true, "")
	assert_eq(crash["action"], "restart_backend")
	assert_eq(StatusModel.describe(SakiConst.CONN_STARTING, "", true, "")["text"], "Đang khởi động Saki...")
	var missing: Dictionary = StatusModel.describe(SakiConst.CONN_NOT_FOUND, "", true, "")
	assert_eq(missing["action"], "pick_backend_dir", "folder picker only when the app cannot find the backend")
	assert_string_contains(missing["text"], "Bấm Chọn thư mục...")
