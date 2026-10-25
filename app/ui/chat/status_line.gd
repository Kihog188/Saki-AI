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
var _dir_dialog: FileDialog


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
	_action.text = {"retry_llm": tr("ACTION_RETRY"), "pick_backend_dir": tr("ACTION_PICK_BACKEND")}.get(_action_id, tr("ACTION_RESTART"))


func _on_action() -> void:
	match _action_id:
		"retry_llm":
			_ctx.backend.refresh_llm_status()
		"restart_backend":
			if _ctx.restart_backend.is_valid():
				_ctx.restart_backend.call()
		"pick_backend_dir":
			_pick_backend_dir()


## Only shown when the app could not find the backend by itself.
func _pick_backend_dir() -> void:
	if _dir_dialog == null:
		_dir_dialog = FileDialog.new()
		_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dir_dialog.use_native_dialog = true
		_dir_dialog.title = tr("BACKEND_PICK_TITLE")
		_dir_dialog.dir_selected.connect(_on_backend_dir_selected)
		add_child(_dir_dialog)
	_dir_dialog.popup_centered(Vector2i(700, 500))


func _on_backend_dir_selected(dir: String) -> void:
	if not BackendProcess.is_backend_dir(dir):
		_conn_message = tr("BACKEND_PICK_INVALID")
		_refresh()
		return
	_ctx.settings.set_value("backend_dir", dir)
	if _ctx.restart_backend.is_valid():
		_ctx.restart_backend.call()
