class_name SettingsPanel
extends ScrollContainer
## "Cài đặt". Backend-owned values (address pair, model) go through PUT /settings and show
## its Vietnamese 400 errors; app-owned values are stored by SettingsService
## (%APPDATA%\Saki\app_settings.json) and apply immediately.

const MODEL_SUGGESTIONS: PackedStringArray = ["saki", "saki-lite", "saki-standard"]
const QUALITY_IDS: PackedStringArray = ["auto", "low", "medium", "high"]
const QUALITY_KEYS: PackedStringArray = ["TIER_AUTO", "TIER_LOW", "TIER_MEDIUM", "TIER_HIGH"]
const THEME_IDS: PackedStringArray = ["system", "light", "dark"]
const THEME_KEYS: PackedStringArray = ["THEME_SYSTEM", "THEME_LIGHT", "THEME_DARK"]

var _ctx: UiContext
var _box: VBoxContainer
var _self_name: LineEdit
var _user_name: LineEdit
var _model: LineEdit
var _backend_msg: Label
var _backend_dir: LineEdit
var _dir_msg: Label
var _quality: OptionButton
var _quality_msg: Label
var _danger_msg: Label
var _confirm_clear: ConfirmationDialog
var _dir_dialog: FileDialog


func setup(ctx: UiContext) -> void:
	_ctx = ctx
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	_build_backend_section()
	_build_app_section()
	_build_danger_section()
	_load_backend_values()


# --- backend-owned ---------------------------------------------------------------------

func _build_backend_section() -> void:
	_header("SETTINGS_SECTION_CHAT")
	_self_name = _line_edit(_row("SETTINGS_SELF_NAME"), 20)
	_user_name = _line_edit(_row("SETTINGS_USER_NAME"), 20)
	var model_row: HBoxContainer = _row("SETTINGS_MODEL")
	_model = _line_edit(model_row, 80)
	var suggest := MenuButton.new()
	suggest.text = "▾"
	suggest.tooltip_text = tr("SETTINGS_MODEL_SUGGESTIONS")
	for m: String in MODEL_SUGGESTIONS:
		suggest.get_popup().add_item(m)
	suggest.get_popup().index_pressed.connect(func(i: int) -> void: _model.text = MODEL_SUGGESTIONS[i])
	model_row.add_child(suggest)
	var save := Button.new()
	save.text = tr("ACTION_SAVE")
	save.theme_type_variation = &"AccentButton"
	save.pressed.connect(_save_backend)
	_box.add_child(save)
	_backend_msg = _message_label()


func _load_backend_values() -> void:
	if _ctx.backend == null or not _ctx.backend.connected:
		_show(_backend_msg, tr("STATUS_DISCONNECTED"), true)
		return
	var r: Dictionary = await _ctx.backend.get_settings()
	if r["ok"] and r["data"] is Dictionary:
		_self_name.text = String(r["data"].get("self_name", ""))
		_user_name.text = String(r["data"].get("user_name", ""))
		_model.text = String(r["data"].get("model", ""))
	else:
		_show(_backend_msg, r["error"], true)


func _save_backend() -> void:
	var r: Dictionary = await _ctx.backend.put_settings({
		"self_name": _self_name.text, "user_name": _user_name.text, "model": _model.text.strip_edges(),
	})
	if r["ok"]:
		_show(_backend_msg, tr("SETTINGS_SAVED"), false)
	else:
		_show(_backend_msg, r["error"], true)


# --- app-owned -------------------------------------------------------------------------

func _build_app_section() -> void:
	_header("SETTINGS_SECTION_APP")
	var s: SettingsService = _ctx.settings

	var dir_row: HBoxContainer = _row("SETTINGS_BACKEND_DIR")
	_backend_dir = _line_edit(dir_row, 400)
	_backend_dir.placeholder_text = tr("SETTINGS_BACKEND_DIR_AUTO")
	_backend_dir.text = s.get_value("backend_dir")
	_backend_dir.text_submitted.connect(func(t: String) -> void: _set_backend_dir(t))
	var pick := Button.new()
	pick.text = tr("ACTION_BROWSE")
	pick.pressed.connect(_pick_backend_dir)
	dir_row.add_child(pick)
	_dir_msg = _message_label()

	var q_row: HBoxContainer = _row("SETTINGS_QUALITY")
	_quality = OptionButton.new()
	for i: int in QUALITY_IDS.size():
		_quality.add_item(tr(QUALITY_KEYS[i]), i)
	_quality.select(maxi(0, QUALITY_IDS.find(s.get_value("quality"))))
	_quality.item_selected.connect(func(i: int) -> void: s.set_value("quality", QUALITY_IDS[i]))
	q_row.add_child(_quality)
	var redetect := Button.new()
	redetect.text = tr("SETTINGS_REDETECT")
	redetect.pressed.connect(_redetect)
	q_row.add_child(redetect)
	_quality_msg = _message_label()
	_update_quality_hint()

	var t_row: HBoxContainer = _row("SETTINGS_THEME")
	var theme_opt := OptionButton.new()
	for i: int in THEME_IDS.size():
		theme_opt.add_item(tr(THEME_KEYS[i]), i)
	theme_opt.select(maxi(0, THEME_IDS.find(s.get_value("theme"))))
	theme_opt.item_selected.connect(func(i: int) -> void: s.set_value("theme", THEME_IDS[i]))
	t_row.add_child(theme_opt)

	var scale_row: HBoxContainer = _row("SETTINGS_PET_SCALE")
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = s.get_value("pet_scale")
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 160
	var scale_label := Label.new()
	scale_label.text = "%d%%" % roundi(slider.value * 100)
	slider.value_changed.connect(func(v: float) -> void:
		scale_label.text = "%d%%" % roundi(v * 100)
		s.set_value("pet_scale", v))
	scale_row.add_child(slider)
	scale_row.add_child(scale_label)

	_check("SETTINGS_ALWAYS_ON_TOP", "always_on_top")
	var hk_row: HBoxContainer = _check("SETTINGS_HOTKEY", "hotkey_enabled")
	var combo := LineEdit.new()
	combo.text = s.get_value("hotkey")
	combo.custom_minimum_size.x = 140
	combo.tooltip_text = tr("SETTINGS_HOTKEY_HINT")
	combo.text_submitted.connect(func(t: String) -> void: s.set_value("hotkey", t.strip_edges()))
	combo.focus_exited.connect(func() -> void: s.set_value("hotkey", combo.text.strip_edges()))
	hk_row.add_child(combo)
	_check("SETTINGS_DEBUG_OVERLAY", "debug_overlay")

	var shortcut := Button.new()
	shortcut.text = tr("SETTINGS_SHORTCUT")
	_box.add_child(shortcut)
	# Created before the lambda: lambdas capture local variables when they are created.
	var shortcut_msg: Label = _message_label()
	shortcut.pressed.connect(func() -> void:
		if not _ctx.create_shortcut.is_valid():
			_show(shortcut_msg, tr("SETTINGS_SHORTCUT_UNAVAILABLE"), true)
			return
		var r: Dictionary = _ctx.create_shortcut.call()
		_show(shortcut_msg, r.get("message", ""), not r.get("ok", false)))


func _pick_backend_dir() -> void:
	if _dir_dialog == null:
		_dir_dialog = FileDialog.new()
		_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dir_dialog.use_native_dialog = true
		_dir_dialog.title = tr("SETTINGS_BACKEND_DIR")
		_dir_dialog.dir_selected.connect(func(d: String) -> void:
			_backend_dir.text = d
			_set_backend_dir(d))
		add_child(_dir_dialog)
	_dir_dialog.popup_centered(Vector2i(700, 500))


func _set_backend_dir(dir: String) -> void:
	var d: String = dir.strip_edges()
	if d != "" and not BackendProcess.is_backend_dir(d):
		_show(_dir_msg, tr("SETTINGS_BACKEND_DIR_INVALID"), true)
		return
	_ctx.settings.set_value("backend_dir", d)
	_show(_dir_msg, tr("SETTINGS_BACKEND_DIR_SAVED"), false)


func _redetect() -> void:
	if not _ctx.detect_tier.is_valid():
		return
	_show(_quality_msg, tr("SETTINGS_DETECTING"), false)
	await _ctx.detect_tier.call()
	_update_quality_hint()


func _update_quality_hint() -> void:
	var auto_id: String = _ctx.settings.get_value("auto_tier")
	if auto_id == "":
		_show(_quality_msg, "", false)
		return
	var key: String = QUALITY_KEYS[maxi(0, QUALITY_IDS.find(auto_id))]
	_show(_quality_msg, tr("SETTINGS_DETECTED").format({"tier": tr(key)}), false)


# --- danger zone -----------------------------------------------------------------------

func _build_danger_section() -> void:
	_header("SETTINGS_SECTION_DATA")
	var clear := Button.new()
	clear.text = tr("SETTINGS_CLEAR_HISTORY")
	clear.pressed.connect(func() -> void: _confirm_clear.popup_centered())
	_box.add_child(clear)
	_danger_msg = _message_label()
	_confirm_clear = ConfirmationDialog.new()
	_confirm_clear.dialog_text = tr("SETTINGS_CLEAR_CONFIRM")
	_confirm_clear.ok_button_text = tr("ACTION_DELETE")
	_confirm_clear.cancel_button_text = tr("ACTION_CANCEL")
	_confirm_clear.confirmed.connect(_clear_history)
	add_child(_confirm_clear)


func _clear_history() -> void:
	var r: Dictionary = await _ctx.backend.delete_history()
	if r["ok"]:
		_ctx.bus.history_cleared.emit()
		_show(_danger_msg, tr("SETTINGS_HISTORY_CLEARED"), false)
	else:
		_show(_danger_msg, r["error"], true)


# --- small builders --------------------------------------------------------------------

func _header(key: String) -> void:
	var l := Label.new()
	l.text = tr(key)
	l.add_theme_font_size_override("font_size", 17)
	_box.add_child(l)


func _row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = tr(key)
	l.custom_minimum_size.x = 150
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	_box.add_child(row)
	return row


func _line_edit(row: HBoxContainer, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.max_length = max_len
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	return e


func _check(key: String, setting: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var c := CheckBox.new()
	c.text = tr(key)
	c.button_pressed = _ctx.settings.get_value(setting)
	c.toggled.connect(func(on: bool) -> void: _ctx.settings.set_value(setting, on))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(c)
	_box.add_child(row)
	return row


func _message_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.visible = false
	_box.add_child(l)
	return l


func _show(label: Label, text: String, error: bool) -> void:
	if label == null:
		return
	label.text = text
	label.visible = text != ""
	label.theme_type_variation = &"ErrorLabel" if error else &"MutedLabel"
