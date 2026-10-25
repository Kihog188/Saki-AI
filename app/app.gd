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

var _booted: bool = false


## Creates and starts every service. Called once by main.gd.
func boot() -> void:
	if _booted:
		return
	_booted = true
	TranslationServer.set_locale("vi")
	settings = SettingsService.new(SakiConst.SETTINGS_PATH, EventBus)
	settings.load_file()

	packs = PackService.new(EventBus)
	add_child(packs)
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
	start_backend()


## Starts the backend process if needed, then connects. Also used by "Khởi động lại".
func start_backend() -> void:
	backend.stop()
	EventBus.backend_state_changed.emit(SakiConst.CONN_STARTING, tr("STATUS_STARTING"))
	backend_process.backend_dir = settings.get_value("backend_dir")
	var r: Dictionary = await backend_process.ensure_running()
	if r["code"] != BackendProcess.OK_RUNNING:
		push_warning("Backend not available: %s" % r["code"])
		EventBus.backend_state_changed.emit(SakiConst.CONN_FAILED, r["message"])
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
