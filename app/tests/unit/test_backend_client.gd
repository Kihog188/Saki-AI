extends GutTest
## BackendClient with a fake WebSocket and fake HTTP: event parsing, connection, reconnect
## backoff, protocol check, superseding turns, REST errors.

var _bus: Node
var _ws: TestFakes.FakeWs
var _http: TestFakes.FakeHttp
var _client: BackendClient


func before_each() -> void:
	_bus = add_child_autofree(load("res://core/event_bus.gd").new())
	_ws = TestFakes.FakeWs.new()
	_http = TestFakes.FakeHttp.new()
	_http.routes["/health"] = TestFakes.FakeHttp.health()
	_client = BackendClient.new(_bus, _ws, _http, "http://127.0.0.1:8765")
	add_child_autofree(_client)
	watch_signals(_bus)


func _connect() -> void:
	_client.start()
	await wait_until(func() -> bool: return _client.connected, 2.0)
	assert_true(_client.connected, "connected")


func test_parse_event_is_defensive() -> void:
	assert_eq(BackendClient.parse_event("not json"), {})
	assert_eq(BackendClient.parse_event("[1,2]"), {})
	assert_eq(BackendClient.parse_event("{\"type\": 5}"), {})
	var ev: Dictionary = BackendClient.parse_event(JSON.stringify({"type": "end", "emotion": 3, "text": "Hi", "sources": [
		{"index": 1, "title": "T", "url": "https://a.vn/x", "date": "2026-10-19", "paywalled": true}, "junk"]}))
	assert_eq(ev["emotion"], "neutral", "wrong type -> default")
	assert_eq(ev["system"], false)
	assert_eq(ev["sources"].size(), 1)
	assert_eq(ev["sources"][0]["display_url"], "https://a.vn/x", "display_url falls back to url")
	assert_true(ev["sources"][0]["paywalled"])


func test_connects_after_health_check() -> void:
	await _connect()
	assert_eq(_ws.opened_urls, PackedStringArray(["ws://127.0.0.1:8765/ws"]))
	assert_signal_emitted_with_parameters(_bus, "backend_state_changed", [SakiConst.CONN_CONNECTED, ""])
	assert_signal_emitted_with_parameters(_bus, "llm_reachability_changed", [true])


func test_protocol_mismatch_stops_with_message() -> void:
	_http.routes["/health"] = TestFakes.FakeHttp.health(2)
	_client.start()
	await wait_until(func() -> bool: return get_signal_emit_count(_bus, "backend_state_changed") >= 2, 2.0)
	var params: Array = get_signal_parameters(_bus, "backend_state_changed")
	assert_eq(params[0], SakiConst.CONN_FAILED)
	assert_string_contains(params[1], "Phiên bản backend không khớp")
	assert_eq(_ws.opened_urls.size(), 0, "no WebSocket opened")


func test_llm_down_is_reported() -> void:
	_http.routes["/health"] = TestFakes.FakeHttp.health(1, false)
	await _connect()
	assert_false(_client.llm_reachable)
	assert_signal_emitted_with_parameters(_bus, "llm_reachability_changed", [false])


func test_reconnect_backoff_schedule() -> void:
	_http.routes.erase("/health") # backend down: connection refused
	_client.start()
	var delays: Array[float] = []
	for i: int in 5:
		await wait_until(func() -> bool: return _client._retry_in > 0.0, 2.0)
		delays.append(_client.last_retry_delay)
		_client._retry_in = 0.001 # skip the wait
		await wait_process_frames(2)
	assert_eq(delays, [1.0, 2.0, 5.0, 10.0, 10.0])
	assert_signal_emitted_with_parameters(_bus, "backend_state_changed", [SakiConst.CONN_DISCONNECTED, "Mất kết nối với Saki"])


func test_failed_handshake_retries() -> void:
	_ws.next_open_result = WsTransport.State.CLOSED
	_client.start()
	await wait_until(func() -> bool: return _client._retry_in > 0.0, 2.0)
	assert_eq(_client.last_retry_delay, 1.0)


func test_full_turn_events() -> void:
	await _connect()
	assert_true(_client.send_message("Chào Saki"))
	assert_eq(_ws.sent[-1], {"type": "user_message", "text": "Chào Saki"})
	assert_signal_emitted_with_parameters(_bus, "busy_changed", [true])
	for ev: Dictionary in [
		{"type": "status", "state": "thinking"},
		{"type": "start", "emotion": "neutral", "system": false},
		{"type": "delta", "text": "Không có gì."},
		{"type": "reset"},
		{"type": "start", "emotion": "happy", "system": false},
		{"type": "delta", "text": "Chào bạn."},
		{"type": "end", "emotion": "happy", "text": "Chào bạn.", "sources": [], "system": false},
	]:
		_ws.push(ev)
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(_bus, "turn_status", ["thinking"])
	assert_signal_emit_count(_bus, "turn_started", 2)
	assert_signal_emit_count(_bus, "turn_reset", 1)
	assert_signal_emitted_with_parameters(_bus, "turn_ended", ["happy", "Chào bạn.", [], false])
	assert_false(_client.turn_running)
	assert_signal_emitted_with_parameters(_bus, "busy_changed", [false])


func test_error_and_cancelled_end_the_turn() -> void:
	await _connect()
	_client.send_message("a")
	_ws.push({"type": "error", "message": "Saki chưa kết nối được với mô hình."})
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(_bus, "turn_error", ["Saki chưa kết nối được với mô hình."])
	assert_false(_client.turn_running)
	_client.send_message("b")
	_client.cancel()
	assert_eq(_ws.sent[-1], {"type": "cancel"})
	_ws.push({"type": "cancelled"})
	await wait_process_frames(2)
	assert_signal_emitted(_bus, "turn_cancelled")
	assert_false(_client.turn_running)


func test_new_message_supersedes_running_turn() -> void:
	await _connect()
	_client.send_message("first")
	_ws.push({"type": "status", "state": "thinking"})
	await wait_process_frames(2)
	_client.send_message("second")
	assert_eq(_ws.sent[-1], {"type": "cancel"}, "cancel first, do not overlap turns")
	_ws.push({"type": "cancelled"})
	await wait_process_frames(2)
	assert_eq(_ws.sent[-1], {"type": "user_message", "text": "second"})
	assert_true(_client.turn_running)


func test_cancel_without_confirmation_ends_locally() -> void:
	await _connect()
	_client.send_message("first")
	_client.send_message("second")
	_client._cancel_wait = 0.01 # pretend 3 s passed
	await wait_process_frames(3)
	assert_push_warning("did not confirm the cancel")
	assert_signal_emitted(_bus, "turn_cancelled")
	assert_eq(_ws.sent[-1], {"type": "user_message", "text": "second"})


func test_socket_lost_mid_turn() -> void:
	await _connect()
	_client.send_message("a")
	_ws.drop()
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(_bus, "turn_error", ["Mất kết nối với Saki"])
	assert_false(_client.connected)
	assert_false(_client.turn_running)
	assert_eq(_client.last_retry_delay, 1.0)
	assert_false(_client.send_message("offline"), "cannot send while disconnected")


func test_unknown_event_is_ignored() -> void:
	await _connect()
	_ws.push({"type": "future_thing", "x": 1})
	_ws.inbox.append("garbage{")
	await wait_process_frames(2)
	assert_push_warning("malformed backend event")
	assert_true(_client.connected)


func test_rest_errors_carry_backend_detail() -> void:
	_http.routes["/settings"] = TestFakes.FakeHttp.ok({"detail": "Cách xưng hô không được để trống."}, 400)
	var r: Dictionary = await _client.put_settings({"user_name": ""})
	assert_false(r["ok"])
	assert_eq(r["error"], "Cách xưng hô không được để trống.")
	assert_eq(_http.calls[-1]["method"], HTTPClient.METHOD_PUT)
	var down: Dictionary = await _client.get_memories()
	assert_eq(down["error"], "Mất kết nối với Saki")


func test_history_paging_url() -> void:
	_http.routes["/history"] = TestFakes.FakeHttp.ok({"messages": []})
	await _client.get_history(50, 120)
	assert_string_ends_with(_http.calls[-1]["url"], "/history?limit=50&before=120")
	await _client.get_history()
	assert_string_ends_with(_http.calls[-1]["url"], "/history?limit=50")


func test_hotkey_events() -> void:
	await _connect()
	_ws.push({"type": "hotkey"})
	_ws.push({"type": "hotkey_status", "ok": false, "message": ""})
	await wait_process_frames(2)
	assert_signal_emitted(_bus, "hotkey_pressed")
	assert_signal_emitted_with_parameters(_bus, "notice", ["Không đăng ký được phím tắt toàn cục. Tính năng này đã tắt."])
