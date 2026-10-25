extends Node
## Composition root (autoload "App").
##
## The ONLY place that creates services and wires them together. Everything else gets
## what it needs from here (or from its constructor), never by creating services itself.
## _ready() does nothing heavy, so GUT tests (which also load autoloads) start no backend
## and open no windows; main.gd calls boot() when the real app starts.

var settings: SettingsService
var packs: PackService
var backend_process: BackendProcess
var backend: BackendClient
var performance: PerformanceService
var session: ChatSession
var mood: MoodController
## Services + actions handed to every UI component (see UiContext).
var ui: UiContext

var _booted: bool = false


## Creates and starts every service. Called once by main.gd.
func boot() -> void:
	if _booted:
		return
	_booted = true
	TranslationServer.set_locale("vi")
	settings = SettingsService.new(SakiConst.SETTINGS_PATH, EventBus)
	settings.load_file()

	performance = PerformanceService.new(EventBus)
	add_child(performance)
	packs = PackService.new(EventBus)
	add_child(packs)
	# Services never call each other: the root connects them.
	EventBus.quality_tier_changed.connect(func(t: Resource) -> void:
		packs.set_max_texture_size((t as QualityTier).max_texture_size))
	EventBus.setting_changed.connect(_on_setting_changed)
	performance.set_quality(settings.get_value("quality"), settings.get_value("auto_tier"))
	packs.max_texture_size = performance.tier.max_texture_size
	packs.refresh()
	var active: String = packs.activate(settings.get_value("active_pack"))
	settings.set_value("active_pack", active)

	var port: int = settings.get_value("port")
	backend_process = BackendProcess.new(EventBus, ProcessLauncher.new(), HttpRequestTransport.new())
	backend_process.backend_dir = settings.get_value("backend_dir")
	backend_process.port = port
	add_child(backend_process)
	backend = BackendClient.new(EventBus, WebSocketTransport.new(), HttpRequestTransport.new(), backend_process.base_url())
	add_child(backend)

	session = ChatSession.new(EventBus, backend)
	add_child(session)
	mood = MoodController.new(EventBus)
	add_child(mood)
	EventBus.active_pack_changed.connect(func(_k: String) -> void: _sync_idle_seconds())
	_sync_idle_seconds()
	# On every (re)connect: reload history and re-send the hotkey choice (the backend may
	# have restarted, and it releases the hotkey when no client is connected).
	EventBus.backend_state_changed.connect(func(state: StringName, _m: String) -> void:
		if state == SakiConst.CONN_CONNECTED:
			session.load_recent()
			_send_hotkey_config())

	ui = UiContext.new()
	ui.bus = EventBus
	ui.settings = settings
	ui.packs = packs
	ui.backend = backend
	ui.session = session
	ui.performance = performance
	ui.mood = mood
	ui.restart_backend = start_backend
	ui.detect_tier = run_tier_detection
	ui.create_shortcut = DesktopShortcut.create
	apply_theme()
	# "Theo Windows": re-theme when the user switches Windows between light and dark.
	DisplayServer.set_system_theme_change_callback(func() -> void:
		if settings.get_value("theme") == "system":
			apply_theme())
	start_backend()


## Measures the machine and stores the result (first run, or "Đo lại" in Settings).
## Coroutine; needs a visible window for the frame-time benchmark.
func run_tier_detection() -> String:
	var ram_gb: float = -1.0
	var hw: Variant = backend.last_health.get("hardware") if backend != null else null
	if hw is Dictionary and (hw.get("free_ram_gb") is float or hw.get("free_ram_gb") is int):
		ram_gb = float(hw["free_ram_gb"])
	var id: String = await performance.detect_tier(ram_gb)
	settings.set_value("auto_tier", id)
	performance.set_quality(settings.get_value("quality"), id)
	return id


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"quality":
			performance.set_quality(String(value), settings.get_value("auto_tier"))
		"theme":
			apply_theme()
		"hotkey", "hotkey_enabled":
			_send_hotkey_config()


## Global hotkey: registered by the backend (Windows RegisterHotKey), see saki/hotkey.py.
func _send_hotkey_config() -> void:
	if backend.connected:
		backend.send_hotkey_config(settings.get_value("hotkey_enabled"), settings.get_value("hotkey"))


## Builds the Godot Theme from the theme setting ("Theo Windows" follows dark mode) and
## applies it to the main window and every open panel.
func apply_theme() -> void:
	ui.saki_theme = ThemeBuilder.resolve(settings.get_value("theme"))
	ui.theme = ThemeBuilder.build(ui.saki_theme)
	get_tree().root.theme = ui.theme
	PanelWindow.apply_theme(ui.theme)
	EventBus.theme_changed.emit(ui.saki_theme)


func _sync_idle_seconds() -> void:
	mood.set_idle_seconds(packs.active.manifest.idle_seconds if packs.active != null else 0.0)


## Starts the backend process if needed, then connects. Also used by "Khởi động lại".
func start_backend() -> void:
	backend.stop()
	EventBus.backend_state_changed.emit(SakiConst.CONN_STARTING, tr("STATUS_STARTING"))
	backend_process.backend_dir = settings.get_value("backend_dir")
	var t0: int = Time.get_ticks_msec()
	var r: Dictionary = await backend_process.ensure_running()
	print("Backend ready check: code='%s' owned=%s in %d ms (app uptime %d ms)" % [r["code"], r["owned"], Time.get_ticks_msec() - t0, Time.get_ticks_msec()])
	if r["code"] != BackendProcess.OK_RUNNING:
		push_warning("Backend not available: %s" % r["code"])
		var state: StringName = SakiConst.CONN_NOT_FOUND if r["code"] == BackendProcess.ERR_NOT_FOUND else SakiConst.CONN_FAILED
		EventBus.backend_state_changed.emit(state, r["message"])
		return
	backend.start()


## Stops what this app started. Called on window close and on exit.
func shutdown() -> void:
	if backend != null:
		backend.stop()
	if backend_process != null:
		backend_process.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func _exit_tree() -> void:
	shutdown()
