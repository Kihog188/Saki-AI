class_name DebugOverlay
extends CanvasLayer
## F3 overlay (off by default): FPS, FPS cap, memory, quality tier, active pack, state.
## Updates twice per second and only while visible.

const UPDATE_SEC: float = 0.5

var _perf: PerformanceService
var _packs: PackService
var _settings: SettingsService
var _label: Label
var _elapsed: float = 0.0


func setup(perf: PerformanceService, packs: PackService, settings: SettingsService) -> void:
	_perf = perf
	_packs = packs
	_settings = settings


func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(6, 6)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.set_content_margin_all(6)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(_label)
	add_child(panel)
	visible = _settings != null and bool(_settings.get_value("debug_overlay"))
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		if _settings != null:
			_settings.set_value("debug_overlay", visible)
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= UPDATE_SEC:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	if _label == null or not visible:
		return
	var mb: float = 1048576.0
	var lines: PackedStringArray = [
		"FPS %d  (cap %d)" % [Engine.get_frames_per_second(), _perf.current_fps_cap() if _perf else -1],
		"Mem %.1f MB  tex %.1f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / mb, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / mb],
		"Tier %s (%s)  state %s" % [_perf.tier.id if _perf else "?", _perf.quality_setting if _perf else "?", _perf.state_name() if _perf else "?"],
		"Pack %s  textures %d" % [_packs.active_key() if _packs else "?", _packs.active.loaded_texture_count() if _packs and _packs.active else 0],
		"GPU %s" % RenderingServer.get_video_adapter_name(),
	]
	_label.text = "\n".join(lines)
