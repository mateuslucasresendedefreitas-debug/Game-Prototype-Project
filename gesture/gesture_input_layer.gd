class_name GestureInputLayer
extends Control

## Full-screen transparent capture layer. Sits ABOVE gameplay, BELOW HUD.
##
## Enforces two design rules from the analysis:
##   1. BROADCAST SEMANTICS — one recognized gesture resolves every matching
##      target simultaneously. Never single-target.
##   2. SILENT FAILURE — an unrecognized stroke emits nothing user-facing.
##      The cost of a miss is time, not a rejection message. Do NOT wire a
##      buzzer, red flash, or "wrong!" label to `gesture_rejected`.
##
## `gesture_rejected` exists for telemetry only (near-miss tuning).

signal gesture_matched(symbol_id: StringName, score: float)
signal gesture_rejected(best_symbol: StringName, score: float)  # TELEMETRY ONLY
signal stroke_started()
signal stroke_updated(points: PackedVector2Array)

@export_range(0.5, 1.0, 0.01) var leniency: float = 0.78
@export var min_points: int = 5
@export var max_points: int = 512
@export var draw_trail: bool = true
@export var trail_width: float = 6.0
@export var trail_fade_time: float = 0.18

var _recognizer: GestureRecognizer
var _points: PackedVector2Array = PackedVector2Array()
var _drawing: bool = false
var _fading_trail: PackedVector2Array = PackedVector2Array()
var _fade_alpha: float = 0.0

## Set by DifficultyManager each phase. Empty = match against everything.
## Keeping this tight is the single biggest accuracy lever in the system.
var active_pool: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_recognizer = GestureRecognizer.new()
	SymbolLibrary.install_templates(_recognizer)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			_begin_stroke(pos)
		else:
			_end_stroke()
		accept_event()

	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _drawing:
			_append_point(event.position)
			accept_event()


func _begin_stroke(pos: Vector2) -> void:
	_drawing = true
	_points = PackedVector2Array([pos])
	stroke_started.emit()


func _append_point(pos: Vector2) -> void:
	if _points.size() >= max_points:
		return
	# Skip micro-jitter: keeps resampling stable and reduces noise.
	if _points.size() > 0 and _points[_points.size() - 1].distance_to(pos) < 3.0:
		return
	_points.append(pos)
	stroke_updated.emit(_points)
	if draw_trail:
		queue_redraw()


func _end_stroke() -> void:
	if not _drawing:
		return
	_drawing = false

	if draw_trail:
		_fading_trail = _points.duplicate()
		_fade_alpha = 1.0

	if _points.size() < min_points:
		_points = PackedVector2Array()
		queue_redraw()
		return

	var result := _recognizer.recognize(_points, leniency, active_pool)
	_points = PackedVector2Array()

	if result["matched"]:
		# BROADCAST: every balloon carrying this symbol resolves. Listeners are
		# responsible for their own matching — do not filter by proximity here.
		gesture_matched.emit(result["symbol"], result["score"])
	else:
		gesture_rejected.emit(result["symbol"], result["score"])

	queue_redraw()


func _process(delta: float) -> void:
	if _fade_alpha > 0.0:
		_fade_alpha = max(0.0, _fade_alpha - delta / trail_fade_time)
		queue_redraw()


func _draw() -> void:
	if not draw_trail:
		return
	if _points.size() >= 2:
		draw_polyline(_points, Color(1, 1, 1, 0.85), trail_width, true)
	if _fade_alpha > 0.0 and _fading_trail.size() >= 2:
		draw_polyline(_fading_trail, Color(1, 1, 1, 0.85 * _fade_alpha), trail_width, true)


## Called by DifficultyManager when the symbol pool changes.
func set_active_pool(symbols: Array) -> void:
	active_pool = symbols.duplicate()
