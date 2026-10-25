extends GutTest
## Quality tiers (data files), auto selection logic, FPS policy.

var _bus: Node
var _perf: PerformanceService


func before_each() -> void:
	_bus = add_child_autofree(load("res://core/event_bus.gd").new())
	_perf = PerformanceService.new(_bus, false) # never touches Engine.max_fps in tests
	add_child_autofree(_perf)


func test_tier_files_are_valid_data() -> void:
	assert_eq(_perf.tiers.size(), PerformanceService.TIER_FILES.size())
	var ranks: Array[int] = []
	for id: String in _perf.tiers:
		var t: QualityTier = _perf.tiers[id]
		ranks.append(t.rank)
		assert_lt(t.busy_fps, t.active_fps, id + ": busy leaves CPU to the model")
		assert_between(t.idle_fps, 10, 15, id + ": idle 10-15 FPS")
		assert_between(t.busy_fps, 5, 10, id + ": busy 5-10 FPS")
		assert_gt(t.max_texture_size, 0)
		assert_ne(tr(t.label_key), t.label_key, id + ": has a Vietnamese name")
	assert_eq(ranks, [0, 1, 2])
	assert_false(_perf.tiers["low"].animations)
	assert_true(_perf.tiers["high"].effects)


func test_selection_rules() -> void:
	assert_eq(TierSelector.select(8000, "NVIDIA GeForce GTX 1650", 16.7), "high")
	assert_eq(TierSelector.select(1536, "Intel(R) HD Graphics 4000", 16.8), "medium", "dev machine")
	assert_eq(TierSelector.select(800, "NVIDIA GeForce RTX 4090", 5.0), "low", "little free RAM")
	assert_eq(TierSelector.select(8000, "llvmpipe (LLVM 15.0.7, 256 bits)", 16.7), "low", "software rendering")
	assert_eq(TierSelector.select(8000, "AMD Radeon RX 580", 30.0), "medium", "slow frames")
	assert_eq(TierSelector.select(8000, "AMD Radeon RX 580", 55.0), "low")
	assert_eq(TierSelector.select(-1, "", -1), "high", "unknown measurements do not lower the tier")


func test_fps_priority() -> void:
	var t: QualityTier = _perf.tiers["medium"]
	assert_eq(TierSelector.target_fps(t, true, true, true), 0, "minimized: stop rendering")
	assert_eq(TierSelector.target_fps(t, false, true, true), t.busy_fps, "busy beats active")
	assert_eq(TierSelector.target_fps(t, false, false, true), t.active_fps)
	assert_eq(TierSelector.target_fps(t, false, false, false), t.idle_fps)


func test_busy_signal_drops_fps() -> void:
	_perf.set_quality("medium")
	_perf.set("_since_input", 999.0)
	_perf.set("_active", false)
	_perf._update_fps()
	assert_eq(_perf.current_fps_cap(), 12)
	_bus.busy_changed.emit(true)
	assert_eq(_perf.current_fps_cap(), 8)
	assert_eq(_perf.state_name(), "busy")
	_bus.busy_changed.emit(false)
	assert_eq(_perf.current_fps_cap(), 12)


func test_input_raises_then_returns_to_idle() -> void:
	_perf.set_quality("high")
	_perf.note_input()
	assert_eq(_perf.current_fps_cap(), 60)
	_perf._process(PerformanceService.ACTIVE_HOLD_SEC + 0.1)
	assert_eq(_perf.current_fps_cap(), 15)
	assert_eq(_perf.state_name(), "idle")


func test_set_quality_auto_and_manual() -> void:
	watch_signals(_bus)
	_perf.set_quality("auto", "low")
	assert_eq(_perf.tier.id, "low")
	assert_signal_emitted(_bus, "quality_tier_changed")
	_perf.set_quality("high", "low")
	assert_eq(_perf.tier.id, "high", "manual override")
	_perf.set_quality("auto", "")
	assert_eq(_perf.tier.id, "medium", "not detected yet -> medium")
	_perf.set_quality("ultra-future")
	assert_eq(_perf.tier.id, "medium", "unknown id -> medium")


func test_pet_mode_never_counts_as_minimized() -> void:
	_perf.set_pet_mode(true)
	_perf._process(1.0)
	assert_false(_perf.minimized)
