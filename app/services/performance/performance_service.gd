class_name PerformanceService
extends Node
## Adaptive performance: quality tiers, frame-rate caps, stop rendering when minimized.
##
## FPS policy (TierSelector.target_fps): minimized chat window -> no rendering;
## backend busy (thinking/searching/streaming) -> tier.busy_fps, so the model gets the CPU;
## user input in the last ACTIVE_HOLD_SEC -> tier.active_fps; otherwise tier.idle_fps.
## Godot's low-processor mode is on (project.godot), so frames are only drawn when
## something changed; Engine.max_fps and the low-processor sleep cap the loop rate.
##
## Public API: tiers, tier, set_quality(id_or_auto), detect_tier(), state_name(), set_pet_mode().

const TIER_FILES: PackedStringArray = [
	"res://services/performance/tiers/low.tres",
	"res://services/performance/tiers/medium.tres",
	"res://services/performance/tiers/high.tres",
]
const ACTIVE_HOLD_SEC: float = 1.5
## Loop rate while minimized: just enough to notice the window coming back.
const MINIMIZED_LOOP_FPS: int = 2
const BENCHMARK_FRAMES: int = 45

## id -> QualityTier, in rank order.
var tiers: Dictionary = {}
var tier: QualityTier = null
## "auto" or a tier id: what the user chose in Settings.
var quality_setting: String = "auto"
var busy: bool = false
var minimized: bool = false
## The pet window is always visible: it never stops rendering.
var pet_mode: bool = false

var _bus: Node
var _since_input: float = 999.0
var _active: bool = false
var _applied_fps: int = -1
var _window_check: float = 0.0
var _apply_engine: bool = true


## `apply_engine` = false in tests: decide everything but leave Engine/OS untouched.
func _init(bus: Node, apply_engine: bool = true) -> void:
	name = "PerformanceService"
	_bus = bus
	_apply_engine = apply_engine
	for path: String in TIER_FILES:
		var t: QualityTier = load(path) as QualityTier
		if t != null:
			tiers[t.id] = t
	tier = tiers.get("medium", QualityTier.new())
	_bus.busy_changed.connect(_on_busy_changed)


## Applies a Settings choice. `auto_tier` is the stored detection result ("" = unknown).
func set_quality(setting: String, auto_tier: String = "") -> void:
	quality_setting = setting
	var id: String = auto_tier if setting == "auto" else setting
	var next: QualityTier = tiers.get(id, tiers.get("medium", tier))
	if next != tier:
		tier = next
		_bus.quality_tier_changed.emit(tier)
	_update_fps()


## Measures the machine and returns the tier id it supports. Coroutine (the benchmark
## draws BENCHMARK_FRAMES frames uncapped). `backend_free_ram_gb` < 0 = unknown.
func detect_tier(backend_free_ram_gb: float = -1.0) -> String:
	# "free" = free physical RAM. ("available" on Windows includes the page file.)
	var ram_mb: float = float(OS.get_memory_info().get("free", -1)) / 1048576.0
	if backend_free_ram_gb >= 0.0:
		ram_mb = minf(ram_mb, backend_free_ram_gb * 1024.0) if ram_mb >= 0.0 else backend_free_ram_gb * 1024.0
	var adapter: String = RenderingServer.get_video_adapter_name()
	var frame_ms: float = await _benchmark()
	var id: String = TierSelector.select(ram_mb, adapter, frame_ms)
	print("Quality auto-detect: free RAM %.0f MB, GPU '%s', frame %.1f ms -> %s" % [ram_mb, adapter, frame_ms, id])
	return id


func _benchmark() -> float:
	if DisplayServer.get_name() == "headless":
		return -1.0
	var old_fps: int = Engine.max_fps
	var old_low: bool = OS.low_processor_usage_mode
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	await get_tree().process_frame # first frame after the change is not representative
	var t0: int = Time.get_ticks_usec()
	# With low-processor mode off every frame is drawn, so this measures real frame cost
	# (the current scene plus presenting the window).
	for _i: int in BENCHMARK_FRAMES:
		await get_tree().process_frame
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / BENCHMARK_FRAMES
	Engine.max_fps = old_fps
	OS.low_processor_usage_mode = old_low
	_applied_fps = -1
	_update_fps()
	return ms


func set_pet_mode(on: bool) -> void:
	pet_mode = on
	minimized = false
	_update_fps()


## "minimized", "busy", "active" or "idle" (for the debug overlay).
func state_name() -> String:
	if minimized:
		return "minimized"
	if busy:
		return "busy"
	return "active" if _active else "idle"


func current_fps_cap() -> int:
	return _applied_fps


func _on_busy_changed(on: bool) -> void:
	busy = on
	_update_fps()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		note_input()


## Marks user activity now (called from _input; UI may call it for drags as well).
func note_input() -> void:
	_since_input = 0.0
	if not _active:
		_active = true
		_update_fps()


func _process(delta: float) -> void:
	_since_input += delta
	if _active and _since_input > ACTIVE_HOLD_SEC:
		_active = false
		_update_fps()
	_window_check -= delta
	if _window_check <= 0.0:
		_window_check = 0.5
		var now_min: bool = not pet_mode and DisplayServer.get_name() != "headless" \
			and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
		if now_min != minimized:
			minimized = now_min
			_update_fps()


func _update_fps() -> void:
	var fps: int = TierSelector.target_fps(tier, minimized, busy, _active)
	if fps == _applied_fps:
		return
	_applied_fps = fps
	if not _apply_engine:
		return
	# 0 = minimized: stop drawing completely, loop slowly to notice the restore.
	RenderingServer.render_loop_enabled = fps > 0
	var loop_fps: int = fps if fps > 0 else MINIMIZED_LOOP_FPS
	Engine.max_fps = loop_fps
	OS.low_processor_usage_mode_sleep_usec = int(1000000.0 / loop_fps)
