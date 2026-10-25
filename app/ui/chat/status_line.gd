class_name StatusLine
extends HBoxContainer
## "Sẵn sàng" / "Saki đang suy nghĩ..." / "Đang tìm kiếm..." / "Mất kết nối với Saki" /
## the Ollama hint with "Thử lại" / a backend failure with "Khởi động lại".
## The wording rules live in StatusModel (tested); this only displays them.

var _ctx: UiContext
var _label: Label
var _action: Button
var _conn: StringName = SakiConst.CONN_STARTING
var _conn_message: String = ""
var _llm: bool = true
var _turn: String = ""
var _action_id: String = ""


func setup(ctx: UiContext) -> void:
	_ctx = ctx
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)
	_action = Button.new()
	_action.visible = false
	_action.pressed.connect(_on_action)
	add_child(_action)
	var bus: Node = ctx.bus
	bus.backend_state_changed.connect(func(s: StringName, m: String) -> void:
		_conn = s
		_conn_message = m
		_refresh())
	bus.llm_reachability_changed.connect(func(ok: bool) -> void:
		_llm = ok
		_refresh())
	bus.turn_status.connect(func(s: String) -> void:
		_turn = s
		_refresh())
	bus.turn_delta.connect(func(_t: String) -> void:
		if _turn != "streaming":
			_turn = "streaming"
			_refresh())
	bus.busy_changed.connect(func(busy: bool) -> void:
		if not busy:
			_turn = ""
			_refresh())
	if ctx.backend != null and ctx.backend.connected:
		_conn = SakiConst.CONN_CONNECTED
		_llm = ctx.backend.llm_reachable
	_refresh()


func _refresh() -> void:
	var d: Dictionary = StatusModel.describe(_conn, _conn_message, _llm, _turn)
	_label.text = d["text"]
	_label.theme_type_variation = {"error": &"ErrorLabel", "warn": &"WarnLabel", "busy": &"MutedLabel"}.get(d["level"], &"")
	_action_id = d["action"]
	_action.visible = _action_id != ""
	_action.text = tr("ACTION_RETRY") if _action_id == "retry_llm" else tr("ACTION_RESTART")


func _on_action() -> void:
	match _action_id:
		"retry_llm":
			_ctx.backend.refresh_llm_status()
		"restart_backend":
			if _ctx.restart_backend.is_valid():
				_ctx.restart_backend.call()
