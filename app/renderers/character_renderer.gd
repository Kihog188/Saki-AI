class_name CharacterRenderer
extends Control
## Base class of every character renderer. A renderer is SELF-CONTAINED: give it a pack
## (PackData) and an emotion and it draws; it needs no service, no autoload and no other
## node. That is what lets the pack manager (and later Character Studio) preview packs.
##
## The renderer draws inside its own rect (keep aspect, aligned by the pack's anchor).
## Subclasses override the _on_* hooks and _draw(); the public API stays the same:
##   load_pack(pack), set_emotion(name), set_state(state), set_quality(tier),
##   get_visible_rect(), get_alpha_outline(), natural_size(), unload()

## Emitted when what is drawn changes shape (frame, emotion, pack, size), so the pet can
## update its click-through region. Throttling is the listener's job.
signal visual_changed()

var pack: PackData = null
var emotion: String = SakiConst.DEFAULT_EMOTION
var state: StringName = SakiConst.STATE_IDLE
var quality: QualityTier = null


func load_pack(p_pack: PackData) -> void:
	pack = p_pack
	_on_pack_loaded()
	_changed()


func set_emotion(p_emotion: String) -> void:
	if p_emotion == emotion:
		return
	emotion = p_emotion
	_on_display_changed()
	_changed()


func set_state(p_state: StringName) -> void:
	if p_state == state:
		return
	state = p_state
	_on_display_changed()
	_changed()


func set_quality(tier: QualityTier) -> void:
	quality = tier
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if tier == null or tier.linear_filter else CanvasItem.TEXTURE_FILTER_NEAREST
	_on_quality_changed()
	queue_redraw()


func unload() -> void:
	_on_unload()
	pack = null
	queue_redraw()


## Size of the character at scale 1 (the current frame times the pack's base_scale).
## The pet window uses it; the chat window just fits the renderer into its panel.
func natural_size() -> Vector2:
	return Vector2(256, 320)


## The drawn area in local coordinates.
func get_visible_rect() -> Rect2:
	return fit_rect(natural_size(), size, _anchor())


## Visible pixels as one polygon in local coordinates (for mouse passthrough).
func get_alpha_outline() -> PackedVector2Array:
	return AlphaOutline.map_to_rect(AlphaOutline.full_rect(), get_visible_rect())


func animations_enabled() -> bool:
	return quality == null or quality.animations


func effects_enabled() -> bool:
	return quality == null or quality.effects


## Biggest rect with the aspect of `content` that fits in `area`, placed by `anchor`
## (0..1 on each axis; [0.5, 1] = bottom centre).
static func fit_rect(content: Vector2, area: Vector2, anchor: Vector2) -> Rect2:
	if content.x <= 0 or content.y <= 0 or area.x <= 0 or area.y <= 0:
		return Rect2(Vector2.ZERO, area)
	var s: float = minf(area.x / content.x, area.y / content.y)
	var drawn: Vector2 = content * s
	return Rect2((area - drawn) * anchor, drawn)


func _anchor() -> Vector2:
	return pack.manifest.anchor if pack != null else Vector2(0.5, 1.0)


func _changed() -> void:
	queue_redraw()
	visual_changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		visual_changed.emit()


# --- hooks for subclasses -------------------------------------------------------------

func _on_pack_loaded() -> void:
	pass


func _on_display_changed() -> void:
	pass


func _on_quality_changed() -> void:
	pass


func _on_unload() -> void:
	pass
