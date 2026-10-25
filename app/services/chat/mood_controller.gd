class_name MoodController
extends Node
## Decides what the character shows (emotion + state) from the chat events, and emits
## EventBus.character_emotion_changed / character_state_changed. Renderers just follow.
##
## Rules (spec 6.4): thinking/searching -> state "thinking"; `start` and `end` set the
## turn's emotion; streaming deltas -> state "talking"; after the turn the state is "idle",
## and after `idle_seconds` without activity the emotion returns to neutral.
## A reaction (pet click) overrides the emotion for a moment, without touching the turn.

var emotion: String = SakiConst.DEFAULT_EMOTION
var state: StringName = SakiConst.STATE_IDLE
## Set from the active pack's `idle_seconds` (0 = default).
var idle_seconds: float = SakiConst.DEFAULT_IDLE_SECONDS

var _bus: Node
var _idle_left: float = -1.0
var _reaction: String = ""
var _reaction_left: float = 0.0
var _shown_emotion: String = ""
var _shown_state: StringName = &""


func _init(bus: Node) -> void:
	name = "MoodController"
	_bus = bus
	_bus.turn_status.connect(func(_s: String) -> void: _apply(emotion, SakiConst.STATE_THINKING))
	_bus.turn_started.connect(func(e: String, _sys: bool) -> void: _apply(e, state))
	_bus.turn_delta.connect(func(_t: String) -> void: _apply(emotion, SakiConst.STATE_TALKING))
	_bus.turn_ended.connect(func(e: String, _t: String, _s: Array, _sys: bool) -> void: _turn_over(e))
	_bus.turn_error.connect(func(_m: String) -> void: _turn_over(emotion))
	_bus.turn_cancelled.connect(func() -> void: _turn_over(emotion))
	_bus.character_reaction.connect(react)


## Shows `p_emotion` for `seconds`, then returns to the current emotion.
func react(p_emotion: String, seconds: float) -> void:
	_reaction = p_emotion
	_reaction_left = seconds
	_publish()


func set_idle_seconds(seconds: float) -> void:
	idle_seconds = seconds if seconds > 0.0 else SakiConst.DEFAULT_IDLE_SECONDS


func shown_emotion() -> String:
	return _reaction if _reaction != "" else emotion


func _turn_over(e: String) -> void:
	_apply(e, SakiConst.STATE_IDLE)
	_idle_left = idle_seconds


func _apply(e: String, s: StringName) -> void:
	emotion = e
	state = s
	if s != SakiConst.STATE_IDLE:
		_idle_left = -1.0
	_publish()


func _process(delta: float) -> void:
	if _reaction != "":
		_reaction_left -= delta
		if _reaction_left <= 0.0:
			_reaction = ""
			_publish()
	if _idle_left >= 0.0:
		_idle_left -= delta
		if _idle_left < 0.0 and state == SakiConst.STATE_IDLE:
			emotion = SakiConst.DEFAULT_EMOTION
			_publish()


func _publish() -> void:
	var e: String = shown_emotion()
	if e != _shown_emotion:
		_shown_emotion = e
		_bus.character_emotion_changed.emit(e)
	if state != _shown_state:
		_shown_state = state
		_bus.character_state_changed.emit(state)
