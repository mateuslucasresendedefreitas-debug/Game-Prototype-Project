class_name GestureRecognizer
extends RefCounted

## $1 Unistroke Recognizer (Wobbrock, Wilson & Li 2007).
## Rotation / scale / translation invariant, per IMPLEMENTATION_SPEC §2.1:
##   resample 64 points -> rotate to indicative angle -> scale to 250px square
##   -> translate to origin -> golden-section angular search ±45°.
## Score = 1 - (distance / half_diagonal).
##
## `active_pool` is the primary accuracy lever: restricting candidates to the
## symbols currently in play cuts false positives substantially. An empty pool
## means "match against every installed template" (worst case).

const RESAMPLE_COUNT: int = 64
const SQUARE_SIZE: float = 250.0
const ANGLE_RANGE_DEG: float = 45.0
const ANGLE_PRECISION_DEG: float = 2.0

# 0.5 * sqrt(SQUARE_SIZE^2 + SQUARE_SIZE^2)
const HALF_DIAGONAL: float = 176.7766952966369

# Golden ratio conjugate for the golden-section search.
const PHI: float = 0.6180339887498949

# Each entry: { "symbol": StringName, "points": PackedVector2Array (normalized) }
var _templates: Array = []


func add_template(symbol_id: StringName, points) -> void:
	var pts := _to_packed(points)
	if pts.size() < 2:
		push_warning("GestureRecognizer: template for %s has too few points" % symbol_id)
		return
	_templates.append({ "symbol": symbol_id, "points": _normalize(pts) })


## Returns:
##   matched: bool         — best score >= threshold
##   symbol:  StringName   — best-scoring symbol (even when not matched)
##   score:   float        — best score
##   scores:  Dictionary   — best score per candidate symbol (telemetry/tests)
func recognize(points, threshold: float = 0.78, active_pool: Array = []) -> Dictionary:
	var candidate := _to_packed(points)
	var result := {
		"matched": false,
		"symbol": &"",
		"score": -1.0,
		"scores": {},
	}
	if candidate.size() < 2 or _templates.is_empty():
		return result

	var normalized := _normalize(candidate)
	var scores: Dictionary = {}
	var best_score := -1.0
	var best_symbol: StringName = &""

	for t in _templates:
		var sym: StringName = t["symbol"]
		if not active_pool.is_empty() and not active_pool.has(sym):
			continue
		var d := _distance_at_best_angle(normalized, t["points"])
		var score := 1.0 - (d / HALF_DIAGONAL)
		if score > float(scores.get(sym, -1.0)):
			scores[sym] = score
		if score > best_score:
			best_score = score
			best_symbol = sym

	result["symbol"] = best_symbol
	result["score"] = best_score
	result["scores"] = scores
	result["matched"] = best_score >= threshold and best_symbol != &""
	return result

# ------------------------------------------------------------- normalization

func _normalize(points: PackedVector2Array) -> PackedVector2Array:
	var pts := _resample(points, RESAMPLE_COUNT)
	pts = _rotate_by(pts, -_indicative_angle(pts))
	pts = _scale_to_square(pts, SQUARE_SIZE)
	pts = _translate_to_origin(pts)
	return pts


func _resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var interval := _path_length(points) / float(n - 1)
	if interval <= 0.0:
		# Degenerate stroke (all points identical) — just repeat the point.
		var flat := PackedVector2Array()
		flat.resize(n)
		flat.fill(points[0])
		return flat

	var out := PackedVector2Array([points[0]])
	var acc := 0.0
	var src := points.duplicate()
	var i := 1
	while i < src.size():
		var d := src[i - 1].distance_to(src[i])
		if acc + d >= interval and d > 0.0:
			var t := (interval - acc) / d
			var q := src[i - 1].lerp(src[i], t)
			out.append(q)
			src.insert(i, q)   # q becomes the new previous point
			acc = 0.0
		else:
			acc += d
		i += 1

	# Floating-point drift can leave us one point short.
	while out.size() < n:
		out.append(src[src.size() - 1])
	if out.size() > n:
		out.resize(n)
	return out


func _path_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length


func _centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())


func _indicative_angle(points: PackedVector2Array) -> float:
	var c := _centroid(points)
	var v := points[0] - c
	if v.length_squared() < 0.000001:
		return 0.0
	return atan2(v.y, v.x)


func _rotate_by(points: PackedVector2Array, angle: float) -> PackedVector2Array:
	var c := _centroid(points)
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		var p := points[i] - c
		out[i] = Vector2(p.x * cos_a - p.y * sin_a, p.x * sin_a + p.y * cos_a) + c
	return out


func _scale_to_square(points: PackedVector2Array, size: float) -> PackedVector2Array:
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var w := hi.x - lo.x
	var h := hi.y - lo.y

	# Degenerate (1D) strokes: non-uniform scaling would divide by ~zero and
	# explode a straight line into noise. Fall back to uniform scale.
	var sx: float
	var sy: float
	if w < 1.0 and h < 1.0:
		sx = 1.0
		sy = 1.0
	elif w < 1.0:
		sx = size / h
		sy = size / h
	elif h < 1.0:
		sx = size / w
		sy = size / w
	else:
		sx = size / w
		sy = size / h

	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = Vector2(points[i].x * sx, points[i].y * sy)
	return out


func _translate_to_origin(points: PackedVector2Array) -> PackedVector2Array:
	var c := _centroid(points)
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] - c
	return out

# ------------------------------------------------------------------ matching

func _distance_at_best_angle(candidate: PackedVector2Array, template: PackedVector2Array) -> float:
	var a := -deg_to_rad(ANGLE_RANGE_DEG)
	var b := deg_to_rad(ANGLE_RANGE_DEG)
	var precision := deg_to_rad(ANGLE_PRECISION_DEG)

	var x1 := PHI * a + (1.0 - PHI) * b
	var f1 := _distance_at_angle(candidate, template, x1)
	var x2 := (1.0 - PHI) * a + PHI * b
	var f2 := _distance_at_angle(candidate, template, x2)

	while absf(b - a) > precision:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = PHI * a + (1.0 - PHI) * b
			f1 = _distance_at_angle(candidate, template, x1)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - PHI) * a + PHI * b
			f2 = _distance_at_angle(candidate, template, x2)

	return minf(f1, f2)


func _distance_at_angle(candidate: PackedVector2Array, template: PackedVector2Array, angle: float) -> float:
	var rotated := _rotate_by(candidate, angle)
	return _path_distance(rotated, template)


func _path_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var n := mini(a.size(), b.size())
	var d := 0.0
	for i in n:
		d += a[i].distance_to(b[i])
	return d / float(n)

# ------------------------------------------------------------------- helpers

func _to_packed(points) -> PackedVector2Array:
	if points is PackedVector2Array:
		return points
	var out := PackedVector2Array()
	for p in points:
		out.append(p)
	return out
