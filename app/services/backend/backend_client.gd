class_name BackendClient
extends Node
## Talks to the Saki backend: the WebSocket chat protocol and the REST endpoints, exactly
## as in README.md "Protocol". No UI code: results go out as EventBus signals (chat events)
## or as return values of the REST coroutines.
##
## Connection: health check (protocol version) -> WebSocket. When the socket drops it
## reconnects after 1 s, 2 s, 5 s, then every 10 s. A protocol mismatch stops retrying.
##
## Turns: the backend has no turn ids, so the client never overlaps turns. A new message
## while a turn runs sends `cancel` first and waits for that turn's terminal event
## (at most SUPERSEDE_TIMEOUT, then the turn is ended locally) before sending.

const RECONNECT_DELAYS: Array[float] = [1.0, 2.0, 5.0, 10.0]
const SUPERSEDE_TIMEOUT: float = 3.0
const TERMINAL_EVENTS: PackedStringArray = ["end", "error", "cancelled"]

## http://127.0.0.1:<port>
var base_url: String
var connected: bool = false
var turn_running: bool = false
## From GET /health (llm.reachable). Assumed true until a check says otherwise.
var llm_reachable: bool = true
## Last GET /health body ({} if none yet).
var last_health: Dictionary = {}

var _bus: Node
var _ws: WsTransport
var _http: HttpTransport
var _want_connection: bool = false
var _connecting: bool = false
var _protocol_failed: bool = false
var _attempt: int = 0
var _retry_in: float = -1.0
## Delay chosen by the last scheduled retry (seconds), for the status line and tests.
var last_retry_delay: float = 0.0
var _was_open: bool = false
var _opening: bool = false # ws.open() called, socket not OPEN yet
var _pending_text: String = ""
var _has_pending: bool = false
var _cancel_wait: float = -1.0


func _init(bus: Node, ws: WsTransport, http: HttpTransport, url: String) -> void:
	name = "BackendClient"
	_bus = bus
	_ws = ws
	_http = http
	base_url = url.trim_suffix("/")


func _ready() -> void:
	if _http.get_parent() == null:
		add_child(_http)


## Starts (or restarts) connecting. Safe to call again, e.g. from a "Thử lại" button.
func start() -> void:
	_want_connection = true
	_protocol_failed = false
	_attempt = 0
	_retry_in = 0.0


func stop() -> void:
	_want_connection = false
	_retry_in = -1.0
	_ws.close()
	_set_connected(false, "")


func ws_url() -> String:
	return base_url.replace("http://", "ws://") + "/ws"


# --- chat ------------------------------------------------------------------------------

## Sends a user message. If a turn is running, it is cancelled first (see class doc).
func send_message(text: String) -> bool:
	if not connected:
		return false
	if turn_running:
		_pending_text = text
		_has_pending = true
		cancel()
		return true
	return _send_now(text)


## Stops the current turn. If the backend does not confirm within SUPERSEDE_TIMEOUT, the
## turn is ended locally (as cancelled).
func cancel() -> void:
	if not turn_running:
		return
	_send({"type": "cancel"})
	if _cancel_wait < 0.0:
		_cancel_wait = SUPERSEDE_TIMEOUT


func _send_now(text: String) -> bool:
	if _send({"type": "user_message", "text": text}) != OK:
		return false
	_set_turn_running(true)
	return true


## Optional protocol addition: ask the backend to (un)register the global hotkey.
func send_hotkey_config(enabled: bool, combo: String) -> void:
	_send({"type": "hotkey_config", "enabled": enabled, "combo": combo})


func _send(msg: Dictionary) -> int:
	return _ws.send_text(JSON.stringify(msg))


# --- frame loop ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_ws.poll()
	var state: WsTransport.State = _ws.get_state()
	if _opening and state != WsTransport.State.CONNECTING:
		_opening = false
		if state == WsTransport.State.CLOSED and _want_connection:
			_schedule_retry() # the handshake failed
	if state == WsTransport.State.OPEN and not _was_open:
		_was_open = true
		_attempt = 0
		_set_connected(true, "")
	elif state == WsTransport.State.CLOSED and _was_open:
		_was_open = false
		_on_socket_lost()
	if state == WsTransport.State.OPEN:
		for text: String in _ws.receive():
			handle_event_text(text)
	elif state == WsTransport.State.CLOSED and not _connecting and _want_connection and _retry_in >= 0.0:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_retry_in = -1.0
			_try_connect()
	if _cancel_wait >= 0.0:
		_cancel_wait -= delta
		if _cancel_wait < 0.0 and turn_running:
			push_warning("Backend did not confirm the cancel, ending the turn locally")
			_bus.turn_cancelled.emit()
			_end_turn()


func _try_connect() -> void:
	_connecting = true
	_bus.backend_state_changed.emit(SakiConst.CONN_CONNECTING, "")
	var health: Dictionary = await check_health()
	_connecting = false
	if not _want_connection:
		return
	if health.is_empty():
		_schedule_retry()
		return
	if int(health.get("protocol_version", 0)) != SakiConst.PROTOCOL_VERSION:
		_protocol_failed = true
		_want_connection = false
		_bus.backend_state_changed.emit(SakiConst.CONN_FAILED, I18n.t("BACKEND_PROTOCOL_MISMATCH", {
			"theirs": health.get("protocol_version", "?"), "ours": SakiConst.PROTOCOL_VERSION}))
		return
	if _ws.open(ws_url()) != OK:
		_schedule_retry()
	else:
		_opening = true


func _schedule_retry() -> void:
	_retry_in = RECONNECT_DELAYS[mini(_attempt, RECONNECT_DELAYS.size() - 1)]
	last_retry_delay = _retry_in
	_attempt += 1
	_bus.backend_state_changed.emit(SakiConst.CONN_DISCONNECTED, I18n.t("STATUS_DISCONNECTED"))


func _on_socket_lost() -> void:
	if turn_running:
		_bus.turn_error.emit(I18n.t("STATUS_DISCONNECTED"))
		_end_turn()
	_set_connected(false, I18n.t("STATUS_DISCONNECTED"))
	if _want_connection:
		_schedule_retry()


func _set_connected(on: bool, message: String) -> void:
	var changed: bool = on != connected
	connected = on
	if on:
		_bus.backend_state_changed.emit(SakiConst.CONN_CONNECTED, "")
	elif changed:
		_bus.backend_state_changed.emit(SakiConst.CONN_DISCONNECTED, message)


func _set_turn_running(on: bool) -> void:
	if on == turn_running:
		return
	turn_running = on
	_bus.busy_changed.emit(on)


func _end_turn() -> void:
	_cancel_wait = -1.0
	_set_turn_running(false)
	if _has_pending:
		_has_pending = false
		_send_now(_pending_text)


# --- events ----------------------------------------------------------------------------

## Parses one server frame and emits the matching EventBus signal. Unknown or malformed
## events are ignored (logged), never fatal: the text comes from another process.
func handle_event_text(text: String) -> void:
	var ev: Dictionary = BackendClient.parse_event(text)
	if ev.is_empty():
		push_warning("Ignoring a malformed backend event")
		return
	match ev["type"]:
		"status":
			_set_turn_running(true)
			_bus.turn_status.emit(ev["state"])
		"start":
			_set_turn_running(true)
			_bus.turn_started.emit(ev["emotion"], ev["system"])
		"delta":
			_bus.turn_delta.emit(ev["text"])
		"reset":
			_bus.turn_reset.emit()
		"end":
			_bus.turn_ended.emit(ev["emotion"], ev["text"], ev["sources"], ev["system"])
			_end_turn()
		"error":
			_bus.turn_error.emit(ev["message"])
			_end_turn()
			refresh_llm_status() # maybe Ollama went away
		"cancelled":
			_bus.turn_cancelled.emit()
			_end_turn()
		"hotkey":
			_bus.hotkey_pressed.emit()
		"hotkey_status":
			if not ev["ok"]:
				_bus.notice.emit(ev["message"] if ev["message"] != "" else I18n.t("HOTKEY_UNAVAILABLE"))
		_:
			print_verbose("Unknown backend event type: %s" % ev["type"])


## Validates and normalises one event. Returns {} if it is not a JSON object with a
## string `type`. Missing or wrong-typed fields get safe defaults.
static func parse_event(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var raw: Dictionary = json.data
	if not raw.get("type") is String:
		return {}
	var ev: Dictionary = {"type": raw["type"]}
	ev["state"] = _str(raw, "state", "thinking")
	ev["emotion"] = _str(raw, "emotion", SakiConst.DEFAULT_EMOTION)
	ev["text"] = _str(raw, "text", "")
	ev["message"] = _str(raw, "message", "")
	ev["system"] = raw.get("system") == true
	ev["ok"] = raw.get("ok") == true
	var sources: Array[Dictionary] = []
	if raw.get("sources") is Array:
		for s: Variant in raw["sources"]:
			if s is Dictionary:
				sources.append(_source(s))
	ev["sources"] = sources
	return ev


static func _str(d: Dictionary, key: String, fallback: String) -> String:
	return d[key] if d.get(key) is String else fallback


static func _source(s: Dictionary) -> Dictionary:
	return {
		"index": int(s["index"]) if (s.get("index") is float or s.get("index") is int) else 0,
		"title": _str(s, "title", ""),
		"url": _str(s, "url", ""),
		"display_url": _str(s, "display_url", _str(s, "url", "")),
		"site": _str(s, "site", ""),
		"date": _str(s, "date", ""),
		"paywalled": s.get("paywalled") == true,
	}


# --- REST ------------------------------------------------------------------------------
# Each returns {"ok": bool, "code": int, "data": Variant, "error": String (Vietnamese)}.

## GET /health. Returns the body, or {} if the backend does not answer like Saki.
func check_health(timeout: float = 3.0) -> Dictionary:
	var r: Dictionary = await _http.request(HTTPClient.METHOD_GET, base_url + "/health", null, [], timeout)
	if r["code"] != 200 or not r["data"] is Dictionary or r["data"].get("status") != "ok":
		return {}
	last_health = r["data"]
	var llm: Variant = last_health.get("llm")
	llm_reachable = llm is Dictionary and llm.get("reachable") == true
	_bus.llm_reachability_changed.emit(llm_reachable)
	return last_health


## Re-checks the model server (the "Thử lại" button of the Ollama message).
func refresh_llm_status() -> void:
	await check_health()


func get_settings() -> Dictionary:
	return await _rest(HTTPClient.METHOD_GET, "/settings")


func put_settings(changes: Dictionary) -> Dictionary:
	return await _rest(HTTPClient.METHOD_PUT, "/settings", changes)


## Newest `limit` messages, or those older than message id `before` (paging).
func get_history(limit: int = SakiConst.HISTORY_PAGE_SIZE, before: int = -1) -> Dictionary:
	var path: String = "/history?limit=%d" % limit
	if before >= 0:
		path += "&before=%d" % before
	return await _rest(HTTPClient.METHOD_GET, path)


func delete_history() -> Dictionary:
	return await _rest(HTTPClient.METHOD_DELETE, "/history")


func get_memories() -> Dictionary:
	return await _rest(HTTPClient.METHOD_GET, "/memories")


func add_memory(text: String) -> Dictionary:
	return await _rest(HTTPClient.METHOD_POST, "/memories", {"text": text})


func delete_memory(id: int) -> Dictionary:
	return await _rest(HTTPClient.METHOD_DELETE, "/memories/%d" % id)


func _rest(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var r: Dictionary = await _http.request(method, base_url + path, body)
	var ok: bool = r["code"] >= 200 and r["code"] < 300
	var error: String = ""
	if not ok:
		var detail: Variant = r["data"].get("detail") if r["data"] is Dictionary else null
		if detail is String and detail != "":
			error = detail
		elif r["code"] == 0:
			error = I18n.t("STATUS_DISCONNECTED")
		else:
			error = I18n.t("BACKEND_REQUEST_FAILED", {"code": r["code"]})
	return {"ok": ok, "code": r["code"], "data": r["data"], "error": error}
