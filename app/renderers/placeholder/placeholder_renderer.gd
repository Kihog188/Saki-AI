extends CharacterRenderer
## Code-drawn stand-in for the built-in pack until the owner adds real images
## (app/packs/default/manifest.json). A round face whose eyes, mouth and blush change per
## emotion and state. Unknown emotions get the neutral face.
##
## Cheap on purpose: it only redraws when something visible changes (blink, mouth
## open/close, a bob step), never every frame.

const SIZE: Vector2 = Vector2(240, 270)
const SKIN: Color = Color(1.0, 0.89, 0.84)
const HAIR: Color = Color(0.36, 0.25, 0.42)
const INK: Color = Color(0.22, 0.14, 0.2)
const BLUSH: Color = Color(0.96, 0.5, 0.6, 0.55)
const BLINK_EVERY: float = 4.0
const BLINK_LENGTH: float = 0.14
const MOUTH_RATE: float = 6.0 # mouth flaps per second while talking
const BOB_PERIOD: float = 3.0
const BOB_PIXELS: float = 3.0

var _time: float = 0.0
var _blink: bool = false
var _mouth_open: bool = false
var _bob: float = 0.0


func _ready() -> void:
	_update_processing()


func natural_size() -> Vector2:
	return SIZE * (pack.manifest.base_scale if pack != null and pack.manifest.base_scale > 0 else 1.0)


func get_alpha_outline() -> PackedVector2Array:
	# An ellipse around head and hair, in the 0..1 space of the drawn rect.
	var poly := PackedVector2Array()
	for i: int in 20:
		var a: float = TAU * i / 20.0
		poly.append(Vector2(0.5 + 0.48 * cos(a), 0.52 + 0.48 * sin(a)))
	return AlphaOutline.map_to_rect(poly, get_visible_rect())


func _on_quality_changed() -> void:
	_update_processing()


func _on_display_changed() -> void:
	_mouth_open = false
	_update_processing()


func _update_processing() -> void:
	set_process(animations_enabled() or effects_enabled())


func _process(delta: float) -> void:
	_time += delta
	var dirty: bool = false
	if animations_enabled():
		var blink: bool = fmod(_time, BLINK_EVERY) < BLINK_LENGTH
		var mouth: bool = state == SakiConst.STATE_TALKING and fmod(_time * MOUTH_RATE, 1.0) < 0.5
		dirty = blink != _blink or mouth != _mouth_open
		_blink = blink
		_mouth_open = mouth
	if effects_enabled():
		var bob: float = roundf(sin(_time * TAU / BOB_PERIOD) * BOB_PIXELS * 2.0) / 2.0
		if bob != _bob:
			_bob = bob
			dirty = true
	if dirty:
		queue_redraw() # shape is the same, so no visual_changed (passthrough unchanged)


func _draw() -> void:
	var rect: Rect2 = get_visible_rect()
	var k: float = rect.size.x / SIZE.x # 1 unit = 1 px at natural size
	var c: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.55 + _bob * k)
	var r: float = 100.0 * k
	# Hair behind, face, fringe.
	draw_circle(c + Vector2(0, -8 * k), r * 1.12, HAIR)
	draw_circle(c, r, SKIN)
	draw_arc(c + Vector2(0, -8 * k), r * 1.05, PI * 1.05, PI * 1.95, 24, HAIR, 26 * k)
	_draw_face(c, k)
	if state == SakiConst.STATE_THINKING:
		for i: int in 3:
			draw_circle(c + Vector2((40 + i * 22) * k, (-120 - i * 14) * k), (5 + i * 2) * k, INK)


func _draw_face(c: Vector2, k: float) -> void:
	var eye_y: float = -10 * k
	var eye_dx: float = 36 * k
	var mood: String = emotion if state != SakiConst.STATE_THINKING else "thinking"
	# Eyes
	for side: float in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(side * eye_dx, eye_y)
		if _blink or mood == "happy":
			# Closed / smiling eyes: an arc.
			var up: bool = mood == "happy" and not _blink
			draw_arc(e + Vector2(0, (4 if up else 0) * k), 11 * k, PI if up else 0.0, TAU if up else PI, 12, INK, 4 * k)
		elif mood == "surprised":
			draw_circle(e, 13 * k, Color.WHITE)
			draw_arc(e, 13 * k, 0, TAU, 20, INK, 3 * k)
			draw_circle(e, 5 * k, INK)
		elif mood == "thinking":
			draw_circle(e + Vector2(4 * k, -4 * k), 8 * k, INK) # looking up
		else:
			draw_circle(e, 9 * k, INK)
			draw_circle(e + Vector2(-3, -3) * k, 3 * k, Color.WHITE)
		if mood == "sad":
			draw_line(e + Vector2(-12 * side, -20) * k, e + Vector2(10 * side, -14) * k, INK, 3 * k)
	# Blush
	if mood == "embarrassed" or mood == "happy":
		var alpha: float = 1.0 if mood == "embarrassed" else 0.6
		for side: float in [-1.0, 1.0]:
			draw_circle(c + Vector2(side * 58 * k, 18 * k), 14 * k, Color(BLUSH, BLUSH.a * alpha))
	# Mouth
	var m: Vector2 = c + Vector2(0, 40 * k)
	if _mouth_open:
		draw_circle(m, 11 * k, INK)
		draw_circle(m + Vector2(0, 4 * k), 6 * k, Color(0.9, 0.45, 0.5))
		return
	match mood:
		"happy":
			draw_arc(m + Vector2(0, -8 * k), 18 * k, 0.15 * PI, 0.85 * PI, 16, INK, 4 * k)
		"sad":
			draw_arc(m + Vector2(0, 12 * k), 14 * k, 1.15 * PI, 1.85 * PI, 16, INK, 4 * k)
		"surprised":
			draw_circle(m, 9 * k, INK)
		"embarrassed":
			draw_polyline(PackedVector2Array([m + Vector2(-14, 0) * k, m + Vector2(-5, -5) * k, m + Vector2(4, 0) * k, m + Vector2(13, -5) * k]), INK, 3 * k)
		"thinking":
			draw_line(m + Vector2(-8, 2) * k, m + Vector2(10, -2) * k, INK, 4 * k)
		_:
			draw_arc(m + Vector2(0, -6 * k), 12 * k, 0.25 * PI, 0.75 * PI, 12, INK, 4 * k)
