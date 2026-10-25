class_name QualityTier
extends Resource
## One quality tier ("Thấp", "Vừa", "Cao"). Tiers are DATA: every tier is a .tres file in
## services/performance/tiers/. Adding a tier = adding a file (and, to offer it in
## Settings, listing it in PerformanceService.TIER_FILES).

## Stable id stored in the settings file ("low", "medium", "high").
@export var id: String = "medium"
## Translation key of the name shown in Settings.
@export var label_key: String = "TIER_MEDIUM"
## Order used by auto selection (higher = heavier).
@export var rank: int = 1

@export_group("Frame rate")
## FPS when nothing happens (character idle, no input).
@export var idle_fps: int = 12
## FPS while the user interacts (typing, dragging, animations playing).
@export var active_fps: int = 30
## FPS while the backend generates a reply: leaves CPU to the model.
@export var busy_fps: int = 8

@export_group("Graphics")
## Longest texture side; pack images above it are downscaled when loaded.
@export var max_texture_size: int = 2048
## Smooth (linear) texture filtering. Off = nearest, cheaper and sharp for pixel art.
@export var linear_filter: bool = true
## Play animations (sheets, frame lists). Off = first frame only.
@export var animations: bool = true
## Small extra effects (breathing bob, fades).
@export var effects: bool = true
