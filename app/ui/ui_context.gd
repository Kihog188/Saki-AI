class_name UiContext
extends RefCounted
## What UI components may use: services and a few app actions. Built once by the
## composition root (App) and handed to every component, so components never reach for
## the App autoload and can be used in tests or another app (e.g. Character Studio).

var bus: Node
var settings: SettingsService
var packs: PackService
var backend: BackendClient
var session: ChatSession
var performance: PerformanceService
var mood: MoodController

## The Godot Theme built from the current SakiTheme (ThemeBuilder); every window uses it.
var theme: Theme
var saki_theme: SakiTheme

## App actions (Callables provided by App; empty Callable = not available):
var restart_backend: Callable = Callable()
## Coroutine returning the detected tier id.
var detect_tier: Callable = Callable()
## (mode: StringName) -> void
var switch_mode: Callable = Callable()
## () -> Dictionary {"ok": bool, "message": String}
var create_shortcut: Callable = Callable()
