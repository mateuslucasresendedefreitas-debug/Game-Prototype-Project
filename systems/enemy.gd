class_name Enemy
extends Node2D

## Base class for every descending threat.
##
## Every enemy type is defined by exactly TWO axes (analysis, Dimension 3):
##   DESCENT URGENCY  -> base_descent_speed
##   RESOLUTION COST  -> symbol_count
##
## Everything else (coin magnetism, etc.) is a modifier that creates COMPETING
## PRIORITIES. Do not add a third primary axis — combinatorial pressure comes
## from mixing positions on these two, not from adding dimensions.

signal symbol_resolved(enemy: Enemy, symbol_id: StringName)
signal destroyed(enemy: Enemy, was_combo: bool)
signal breached(enemy: Enemy)

## AXIS 1 — descent urgency (pixels/sec before difficulty multiplier)
@export var base_descent_speed: float = 60.0

## AXIS 2 — resolution cost (how many symbols must be drawn)
@export var symbol_count: int = 1

## Each resolved symbol removes one "lifter" and the remainder falls FASTER.
## This is the original's sharpest tension mechanic: partially resolving a
## multi-symbol enemy makes it more urgent, not less. Punishes half-commitment.
@export_range(0.0, 1.0, 0.05) var speed_gain_per_resolve: float = 0.35

## Competing-priority modifier. A coin-magnet type forces the player to weigh
## economy against survival — the core of triage.
@export var steals_currency: bool = false

var _symbols: Array = []
var _speed_multiplier: float = 1.0
var _falling: bool = false
var _fall_velocity: float = 0.0
var _breach_y: float = 0.0


func configure(symbols: Array, speed_multiplier: float) -> void:
	_symbols = symbols.duplicate()
	symbol_count = _symbols.size()
	_speed_multiplier = speed_multiplier
	_refresh_symbol_display()


func _ready() -> void:
	_breach_y = get_viewport_rect().size.y - 120.0
	var layer := get_tree().get_first_node_in_group(&"gesture_input")
	if layer and layer.has_signal("gesture_matched"):
		layer.gesture_matched.connect(_on_gesture_matched)


func _physics_process(delta: float) -> void:
	if _falling:
		_fall_velocity += 1400.0 * delta   # gravity takes over — reads as "dropped"
		global_position.y += _fall_velocity * delta
		return

	global_position.y += _current_descent_speed() * delta

	if global_position.y >= _breach_y:
		breached.emit(self)
		set_physics_process(false)


func _current_descent_speed() -> float:
	var resolved: int = symbol_count - _symbols.size()
	var gain := 1.0 + (speed_gain_per_resolve * float(resolved))
	return base_descent_speed * _speed_multiplier * gain

# ------------------------------------------------------------- broadcast match

## BROADCAST SEMANTICS: this fires on EVERY enemy when any gesture is matched.
## Each enemy decides for itself whether it carries the symbol. Do not filter
## by proximity, lane, or "nearest" — that would break mass-pop combos, which
## are the entire strategic layer.
func _on_gesture_matched(symbol_id: StringName, _score: float) -> void:
	if _falling or _symbols.is_empty():
		return
	if not _symbols.has(symbol_id):
		return

	# Remove ALL instances of the symbol on this enemy — an enemy carrying the
	# same symbol twice resolves both at once. Consistent with the broadcast rule.
	var removed := false
	while _symbols.has(symbol_id):
		_symbols.erase(symbol_id)
		removed = true

	if not removed:
		return

	symbol_resolved.emit(self, symbol_id)
	_refresh_symbol_display()

	if _symbols.is_empty():
		_begin_fall()


func _begin_fall() -> void:
	_falling = true
	_fall_velocity = _current_descent_speed()
	# Combo determination is owned by ScoreManager, which counts how many
	# enemies entered _begin_fall() within the same frame as one gesture.
	destroyed.emit(self, false)


func remaining_symbols() -> Array:
	return _symbols.duplicate()


func remaining_cost() -> int:
	return _symbols.size()


## Override in subclasses / scene scripts to update the visual symbol markers.
## Deliberately empty here — no visual decisions in this pass.
func _refresh_symbol_display() -> void:
	pass
