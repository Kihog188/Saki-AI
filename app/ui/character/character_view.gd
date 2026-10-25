class_name CharacterView
extends Control
## Shows the ACTIVE pack with the right renderer and keeps it in sync with the mood
## (EventBus.character_*), pack changes and the quality tier. Used by both modes.

## Re-emitted from the renderer (pet: update the click-through region).
signal visual_changed()

var renderer: CharacterRenderer = null

var _ctx: UiContext


func setup(ctx: UiContext) -> void:
	_ctx = ctx
	mouse_filter = Control.MOUSE_FILTER_PASS
	ctx.bus.active_pack_changed.connect(func(_k: String) -> void: _rebuild())
	ctx.bus.character_emotion_changed.connect(func(e: String) -> void:
		if renderer:
			renderer.set_emotion(e))
	ctx.bus.character_state_changed.connect(func(s: StringName) -> void:
		if renderer:
			renderer.set_state(s))
	ctx.bus.quality_tier_changed.connect(func(t: Resource) -> void:
		if renderer:
			renderer.set_quality(t as QualityTier))
	_rebuild()


## Size of the character at scale 1 (pet window sizing).
func natural_size() -> Vector2:
	return renderer.natural_size() if renderer else Vector2(240, 270)


func _rebuild() -> void:
	if renderer != null:
		renderer.unload()
		renderer.queue_free()
		renderer = null
	renderer = RendererRegistry.create_for_pack(_ctx.packs.active)
	renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	renderer.set_quality(_ctx.performance.tier if _ctx.performance else null)
	if _ctx.mood != null:
		renderer.set_emotion(_ctx.mood.shown_emotion())
		renderer.set_state(_ctx.mood.state)
	renderer.visual_changed.connect(visual_changed.emit)
	add_child(renderer)
	visual_changed.emit()
