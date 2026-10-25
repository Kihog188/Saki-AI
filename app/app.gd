extends Node
## Composition root (autoload "App").
##
## The ONLY place that creates services and wires them together. Everything else gets
## what it needs from here (or from its constructor), never by creating services itself.
## _ready() does nothing heavy, so GUT tests (which also load autoloads) start no backend
## and open no windows; main.gd calls boot() when the real app starts.

var settings: SettingsService
var packs: PackService

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
