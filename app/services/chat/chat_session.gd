class_name ChatSession
extends Node
## The conversation shown in the UI, shared by every display mode (switching modes keeps
## it, because it lives in App, not in a mode). No UI code: message views listen to the
## signals below and read `messages`.
##
## A message is a Dictionary:
##   {"uid": int (local, unique), "id": int (backend id, -1 if not saved/known),
##    "role": "user" | "assistant" | "error", "text": String, "emotion": String,
##    "kind": "chat" | "search", "sources": Array[Dictionary], "system": bool,
##    "status": "done" | "streaming" | "cancelled" | "error"}

signal message_added(index: int)
signal message_changed(index: int)
## `count` older messages were inserted at the front (indices shifted by `count`).
signal older_loaded(count: int)
signal cleared()

const COMMANDS_CHANGING_MEMORIES: PackedStringArray = ["/rmb", "/fgt"]

var messages: Array[Dictionary] = []
## More history exists on the backend before messages[0].
var has_more: bool = false
var loading_older: bool = false

var _bus: Node
var _client: BackendClient
var _next_uid: int = 1
var _current: int = -1 # index of the assistant message being streamed
var _last_sent: String = ""


func _init(bus: Node, client: BackendClient) -> void:
	name = "ChatSession"
	_bus = bus
	_client = client
	_bus.turn_started.connect(_on_started)
	_bus.turn_delta.connect(_on_delta)
	_bus.turn_reset.connect(_on_reset)
	_bus.turn_ended.connect(_on_ended)
	_bus.turn_error.connect(_on_error)
	_bus.turn_cancelled.connect(_on_cancelled)
	_bus.history_cleared.connect(clear)


## Sends a message and shows it. Returns false if the backend is not connected.
func send(text: String) -> bool:
	var clean: String = text.strip_edges()
	if clean == "" or _client == null or not _client.connected:
		return false
	if not _client.send_message(clean):
		return false
	_last_sent = clean
	# A running turn is closed by the `cancelled` event the client waits for before it
	# sends this message, so the streamed text keeps its "(đã dừng)".
	_add({"role": "user", "text": clean})
	return true


func cancel() -> void:
	if _client != null:
		_client.cancel()


## Loads the newest page of history (on start / reconnect). Coroutine.
func load_recent() -> void:
	var r: Dictionary = await _client.get_history(SakiConst.HISTORY_PAGE_SIZE)
	if not r["ok"] or not r["data"] is Dictionary:
		return
	var page: Array[Dictionary] = ChatSession.from_history(r["data"].get("messages", []))
	messages.clear()
	_current = -1
	cleared.emit()
	for m: Dictionary in page:
		m["uid"] = _uid()
		messages.append(m)
		message_added.emit(messages.size() - 1)
	has_more = page.size() >= SakiConst.HISTORY_PAGE_SIZE


## Loads the page before the oldest loaded message. Coroutine; no-op if busy or done.
func load_older() -> void:
	if loading_older or not has_more or messages.is_empty():
		return
	var oldest: int = int(messages[0]["id"])
	if oldest < 0:
		has_more = false
		return
	loading_older = true
	var r: Dictionary = await _client.get_history(SakiConst.HISTORY_PAGE_SIZE, oldest)
	loading_older = false
	if not r["ok"] or not r["data"] is Dictionary:
		return
	var page: Array[Dictionary] = ChatSession.from_history(r["data"].get("messages", []))
	has_more = page.size() >= SakiConst.HISTORY_PAGE_SIZE
	for m: Dictionary in page:
		m["uid"] = _uid()
	var merged: Array[Dictionary] = page.duplicate()
	merged.append_array(messages)
	messages = merged
	if _current >= 0:
		_current += page.size()
	older_loaded.emit(page.size())


func clear() -> void:
	messages.clear()
	_current = -1
	has_more = false
	cleared.emit()


## REST /history rows -> messages (oldest first, as the backend returns them).
static func from_history(rows: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not rows is Array:
		return out
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		var role: String = row.get("role", "")
		if role != "user" and role != "assistant":
			continue
		out.append(ChatSession._message({
			"id": int(row["id"]) if (row.get("id") is float or row.get("id") is int) else -1,
			"role": role,
			"text": row.get("content", "") if row.get("content") is String else "",
			"emotion": row.get("emotion", SakiConst.DEFAULT_EMOTION) if row.get("emotion") is String else SakiConst.DEFAULT_EMOTION,
			"kind": row.get("kind", "chat") if row.get("kind") is String else "chat",
		}))
	return out


# --- turn events ----------------------------------------------------------------------

func _on_started(emotion: String, system: bool) -> void:
	if _current < 0:
		_current = _add({"role": "assistant", "status": "streaming", "emotion": emotion, "system": system})
	else:
		messages[_current]["emotion"] = emotion
		messages[_current]["system"] = system
		message_changed.emit(_current)


func _on_delta(text: String) -> void:
	if _current < 0:
		_current = _add({"role": "assistant", "status": "streaming"})
	messages[_current]["text"] += text
	message_changed.emit(_current)


func _on_reset() -> void:
	if _current >= 0:
		messages[_current]["text"] = ""
		message_changed.emit(_current)


func _on_ended(emotion: String, text: String, sources: Array, system: bool) -> void:
	if _current < 0:
		_current = _add({"role": "assistant"})
	var m: Dictionary = messages[_current]
	m["text"] = text # authoritative
	m["emotion"] = emotion
	m["sources"] = sources
	m["system"] = system
	m["status"] = "done"
	message_changed.emit(_current)
	_current = -1
	if system and _last_sent.split(" ", false).size() > 0 \
			and COMMANDS_CHANGING_MEMORIES.has(_last_sent.split(" ", false)[0].to_lower()):
		_bus.memories_changed.emit()


func _on_error(message: String) -> void:
	if _current >= 0 and messages[_current]["text"] == "":
		var m: Dictionary = messages[_current]
		m["role"] = "error"
		m["text"] = message
		m["status"] = "error"
		message_changed.emit(_current)
		_current = -1
		return
	_finish_current("error")
	_add({"role": "error", "text": message, "status": "error"})


func _on_cancelled() -> void:
	if _current < 0:
		_add({"role": "assistant", "text": I18n.t("CHAT_STOPPED"), "status": "cancelled"})
		return
	_finish_current("cancelled")


## Closes the streaming message (if any) with `status`, adding "(đã dừng)" when stopped.
func _finish_current(status: String) -> void:
	if _current < 0:
		return
	var m: Dictionary = messages[_current]
	m["status"] = status
	if status == "cancelled":
		m["text"] = (m["text"] + " " + I18n.t("CHAT_STOPPED")).strip_edges()
	message_changed.emit(_current)
	_current = -1


func _add(fields: Dictionary) -> int:
	var m: Dictionary = ChatSession._message(fields)
	m["uid"] = _uid()
	messages.append(m)
	message_added.emit(messages.size() - 1)
	return messages.size() - 1


func _uid() -> int:
	_next_uid += 1
	return _next_uid


static func _message(fields: Dictionary) -> Dictionary:
	var m: Dictionary = {
		"uid": 0, "id": -1, "role": "assistant", "text": "", "emotion": SakiConst.DEFAULT_EMOTION,
		"kind": "chat", "sources": [], "system": false, "status": "done",
	}
	m.merge(fields, true)
	return m
