class_name PackManager
extends VBoxContainer
## "Nhân vật": installed packs as cards (thumbnail, name, author, type), a preview of the
## selected pack with one button per emotion/state, activate, delete (user packs, with
## confirmation), "Tải lại" for dev packs, broken packs with their reason, the import
## warnings of a pack (e.g. an image without a transparent background), and adding packs:
## "Thêm nhân vật" (folder of images), "Nhập tệp .sakip" (file), "Mở thư mục nhân vật".
## Drag-and-drop of a folder or .sakip onto any app window is handled by main.gd.

const CARD_SIZE: Vector2 = Vector2(150, 200)
const THUMB_SIZE: Vector2 = Vector2(120, 120)

var _ctx: UiContext
var _grid: HFlowContainer
var _broken: VBoxContainer
var _broken_title: Label
var _preview_holder: Control
var _preview: CharacterRenderer = null
var _preview_pack: PackData = null
var _preview_buttons: HFlowContainer
var _title: Label
var _info: Label
var _warnings: Label
var _activate: Button
var _delete: Button
var _reload: Button
var _progress: ProgressBar
var _import_msg: Label
var _file_dialog: FileDialog
var _folder_dialog: FileDialog
var _confirm: ConfirmationDialog
var _selected: String = ""
var _thumbs: Dictionary = {} # path -> Texture2D (small, freed with the panel)


func setup(ctx: UiContext) -> void:
	_ctx = ctx
	add_theme_constant_override("separation", 8)
	_build_toolbar()
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := ScrollContainer.new()
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 320
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_child(_grid)
	_broken_title = Label.new()
	_broken_title.text = tr("PACKS_BROKEN")
	left_box.add_child(_broken_title)
	_broken = VBoxContainer.new()
	left_box.add_child(_broken)
	left.add_child(left_box)
	split.add_child(left)

	split.add_child(_build_preview())
	ctx.bus.packs_changed.connect(_refresh_list)
	ctx.bus.active_pack_changed.connect(func(_k: String) -> void: _refresh_list())
	ctx.bus.pack_import_progress.connect(_on_import_progress)
	ctx.bus.pack_import_finished.connect(_on_import_finished)
	_refresh_list()
	_select(ctx.packs.active_key())


func _exit_tree() -> void:
	_clear_preview()
	_thumbs.clear()


# --- toolbar / import ------------------------------------------------------------------

func _build_toolbar() -> void:
	var bar := HFlowContainer.new()
	var add_btn := Button.new()
	add_btn.text = tr("PACKS_ADD_FOLDER")
	add_btn.tooltip_text = tr("PACKS_ADD_FOLDER_TIP")
	add_btn.theme_type_variation = &"AccentButton"
	add_btn.pressed.connect(_open_folder_dialog)
	bar.add_child(add_btn)
	var import_btn := Button.new()
	import_btn.text = tr("PACKS_IMPORT")
	import_btn.pressed.connect(_open_import_dialog)
	bar.add_child(import_btn)
	var packs_folder := Button.new()
	packs_folder.text = tr("PACKS_OPEN_FOLDER")
	packs_folder.tooltip_text = ProjectSettings.globalize_path(SakiConst.USER_PACKS_DIR)
	packs_folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(SakiConst.USER_PACKS_DIR)
		OS.shell_open(ProjectSettings.globalize_path(SakiConst.USER_PACKS_DIR)))
	bar.add_child(packs_folder)
	var folder := Button.new()
	folder.text = tr("PACKS_OPEN_DEV_FOLDER")
	folder.tooltip_text = ProjectSettings.globalize_path(SakiConst.DEV_PACKS_DIR)
	folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(SakiConst.DEV_PACKS_DIR)
		OS.shell_open(ProjectSettings.globalize_path(SakiConst.DEV_PACKS_DIR)))
	bar.add_child(folder)
	var rescan := Button.new()
	rescan.text = tr("PACKS_RESCAN")
	rescan.pressed.connect(func() -> void: _ctx.packs.refresh())
	bar.add_child(rescan)
	add_child(bar)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.text = tr("PACKS_DROP_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.visible = false
	add_child(_progress)
	_import_msg = Label.new()
	_import_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_import_msg.visible = false
	add_child(_import_msg)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = tr("ACTION_DELETE")
	_confirm.cancel_button_text = tr("ACTION_CANCEL")
	_confirm.confirmed.connect(func() -> void:
		_ctx.packs.delete_pack(_selected)
		_ctx.settings.set_value("active_pack", _ctx.packs.active_key())
		_select(_ctx.packs.active_key()))
	add_child(_confirm)


func _open_import_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.filters = PackedStringArray(["*.sakip ; " + tr("PACKS_FILE_TYPE")])
		_file_dialog.title = tr("PACKS_IMPORT")
		_file_dialog.file_selected.connect(func(p: String) -> void: start_import(p))
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(700, 500))


func _open_folder_dialog() -> void:
	if _folder_dialog == null:
		_folder_dialog = FileDialog.new()
		_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_folder_dialog.use_native_dialog = true
		_folder_dialog.title = tr("PACKS_ADD_FOLDER_TIP")
		_folder_dialog.dir_selected.connect(func(p: String) -> void: start_import(p))
		add_child(_folder_dialog)
	_folder_dialog.popup_centered(Vector2i(700, 500))


func start_import(path: String) -> void:
	if not _ctx.packs.import_file(path):
		_show_import(tr("PACKS_IMPORT_BUSY"), true)


func _on_import_progress(p: float, text: String) -> void:
	_progress.visible = true
	_progress.value = p
	_show_import(text, false)


func _on_import_finished(ok: bool, message: String) -> void:
	_progress.visible = false
	_show_import(message, not ok)


func _show_import(text: String, error: bool) -> void:
	_import_msg.visible = true
	_import_msg.text = text
	_import_msg.theme_type_variation = &"ErrorLabel" if error else &"MutedLabel"


# --- list ------------------------------------------------------------------------------

func _refresh_list() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	for c: Node in _broken.get_children():
		c.queue_free()
	var broken: int = 0
	for e: Dictionary in _ctx.packs.list():
		if e["valid"]:
			_grid.add_child(_card(e))
		else:
			broken += 1
			var l := Label.new()
			l.theme_type_variation = &"ErrorLabel"
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.text = "%s (%s): %s" % [e["name"], e["key"], e["error"]]
			_broken.add_child(l)
	_broken_title.visible = broken > 0


func _card(e: Dictionary) -> Control:
	var key: String = e["key"]
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(key))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = THUMB_SIZE
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = _thumb(e["thumbnail"])
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(thumb)
	var name_label := Label.new()
	name_label.text = String(e["name"])
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var meta := Label.new()
	meta.theme_type_variation = &"MutedLabel"
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tags: PackedStringArray = []
	if String(e["author"]) != "":
		tags.append(String(e["author"]))
	tags.append(String(e["type"]))
	if key == _ctx.packs.active_key():
		tags.append(tr("PACKS_ACTIVE"))
	if e["source"] == "dev":
		tags.append(tr("PACKS_DEV"))
	if not Array(e.get("warnings", [])).is_empty():
		tags.append("⚠ " + tr("PACKS_WARNINGS"))
	meta.text = " · ".join(tags)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meta)
	card.add_child(box)
	return card


func _thumb(path: String) -> Texture2D:
	if path == "":
		return null
	if _thumbs.has(path):
		return _thumbs[path]
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
	elif FileAccess.file_exists(path):
		var data: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if ImageProbe.check_size(path.get_file(), ImageProbe.size_of(data)) == "":
			var img: Image = ImageProbe.decode(data)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	_thumbs[path] = tex
	return tex


# --- preview ---------------------------------------------------------------------------

func _build_preview() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 280
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	box.add_child(_title)
	_info = Label.new()
	_info.theme_type_variation = &"MutedLabel"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_warnings = Label.new()
	_warnings.theme_type_variation = &"WarnLabel"
	_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warnings.visible = false
	box.add_child(_warnings)
	_preview_holder = Control.new()
	_preview_holder.custom_minimum_size = Vector2(240, 240)
	_preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_preview_holder)
	_preview_buttons = HFlowContainer.new()
	box.add_child(_preview_buttons)
	var actions := HBoxContainer.new()
	_activate = Button.new()
	_activate.text = tr("PACKS_USE")
	_activate.theme_type_variation = &"AccentButton"
	_activate.pressed.connect(func() -> void:
		var key: String = _ctx.packs.activate(_selected)
		_ctx.settings.set_value("active_pack", key))
	actions.add_child(_activate)
	_reload = Button.new()
	_reload.text = tr("PACKS_RELOAD")
	_reload.pressed.connect(func() -> void:
		_ctx.packs.reload_dev(_selected)
		_select(_selected))
	actions.add_child(_reload)
	_delete = Button.new()
	_delete.text = tr("ACTION_DELETE")
	_delete.pressed.connect(func() -> void:
		_confirm.dialog_text = tr("PACKS_CONFIRM_DELETE").format({"name": _ctx.packs.index.get_entry(_selected).get("name", _selected)})
		_confirm.popup_centered())
	actions.add_child(_delete)
	box.add_child(actions)
	return box


func _select(key: String) -> void:
	_selected = key
	var e: Dictionary = _ctx.packs.index.get_entry(key)
	_clear_preview()
	if e.is_empty():
		_title.text = ""
		_warnings.visible = false
		return
	_title.text = String(e["name"])
	_info.text = tr("PACKS_INFO").format({"author": e["author"] if e["author"] != "" else "—",
		"type": e["type"], "version": e["version"] if e["version"] != "" else "—"})
	var notes: Array = e.get("warnings", [])
	_warnings.visible = not notes.is_empty()
	_warnings.text = tr("PACKS_WARNINGS") + ":\n• " + "\n• ".join(PackedStringArray(notes)) if not notes.is_empty() else ""
	_activate.disabled = not e["valid"] or key == _ctx.packs.active_key()
	_delete.visible = e["source"] == "user"
	_reload.visible = e["source"] == "dev"
	if not e["valid"]:
		return
	_preview_pack = _ctx.packs.load_preview(key)
	_preview = RendererRegistry.create_for_pack(_preview_pack)
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.set_quality(_ctx.performance.tier if _ctx.performance else null)
	_preview_holder.add_child(_preview)
	var names: Dictionary = _preview_pack.entry_names() if _preview_pack else {"emotions": SakiConst.EMOTIONS, "states": PackedStringArray()}
	var emotions: PackedStringArray = names["emotions"]
	if emotions.is_empty():
		emotions = SakiConst.EMOTIONS # placeholder: show the six backend emotions
	for em: String in emotions:
		_preview_button(em, func() -> void:
			_preview.set_state(SakiConst.STATE_IDLE)
			_preview.set_emotion(em))
	for st: String in names["states"]:
		_preview_button("▶ " + st, func() -> void: _preview.set_state(StringName(st)))
	if names["states"].is_empty() and e["type"] == "placeholder":
		for st: String in ["thinking", "talking"]:
			_preview_button("▶ " + st, func() -> void: _preview.set_state(StringName(st)))


func _preview_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	_preview_buttons.add_child(b)


func _clear_preview() -> void:
	for c: Node in _preview_buttons.get_children():
		c.queue_free()
	if _preview != null:
		_preview.queue_free()
		_preview = null
	if is_instance_valid(_ctx.packs):
		_ctx.packs.free_preview()
	_preview_pack = null
