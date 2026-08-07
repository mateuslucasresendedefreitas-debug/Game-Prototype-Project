class_name SymbolLibrary
extends RefCounted

## Canonical symbol set + template stroke data.
##
## Symbols are grouped by TIER. The DifficultyManager unlocks tiers by score
## threshold — this is difficulty axis #3 (symbol complexity), independent of
## speed and density.
##
## AMBIGUOUS PAIRS: tier 3 deliberately introduces symbols that are visually
## similar to tier 1/2 symbols. This extends the difficulty ceiling via reading
## load rather than pure reaction speed. Register them ONLY at high score, and
## keep the recognizer's active_pool tight so false positives stay low.

enum Tier { BASIC, INTERMEDIATE, ADVANCED, AMBIGUOUS }

## line_h was removed: the $1 recognizer normalizes rotation via the indicative
## angle, so a vertical and horizontal line are the SAME stroke to it. Only one
## line symbol can exist in the library.
## oval was replaced by half_circle: $1's scale-to-square erases aspect ratio,
## so a circle look-alike must differ in SHAPE (open vs closed), not proportions.
const TIERS: Dictionary = {
	Tier.BASIC:        [&"circle", &"line_v", &"caret"],
	Tier.INTERMEDIATE: [&"triangle", &"square", &"zigzag"],
	Tier.ADVANCED:     [&"s_curve", &"spiral", &"figure_eight"],
	Tier.AMBIGUOUS:    [&"half_circle", &"rectangle", &"backwards_three"],
}

## Symbols that are easy to confuse. Never place both members of a pair in the
## active pool below score threshold defined in DifficultyManager.
const CONFUSION_PAIRS: Array = [
	[&"circle", &"half_circle"],
	[&"square", &"rectangle"],
	[&"caret", &"line_v"],
	[&"s_curve", &"backwards_three"],
]


static func symbols_for_tier(tier: int) -> Array:
	return TIERS.get(tier, [])


static func all_symbols() -> Array:
	var out: Array = []
	for t in TIERS.keys():
		out.append_array(TIERS[t])
	return out


## Populate a GestureRecognizer with every template in the library.
## Call once at boot; restrict matching later via `active_pool`.
static func install_templates(recognizer: GestureRecognizer) -> void:
	for symbol_id in all_symbols():
		for variant in _templates_for(symbol_id):
			recognizer.add_template(symbol_id, variant)


## Public wrapper over `_templates_for` for test harnesses that need the raw
## stroke data without installing it into a recognizer.
static func get_raw_templates(symbol_id: StringName) -> Array:
	return _templates_for(symbol_id)


## Returns an Array of stroke variants; each variant is an Array[Vector2].
## Multiple variants per symbol cover drawing-direction differences (a circle
## drawn clockwise vs counter-clockwise is a different stroke to $1).
static func _templates_for(symbol_id: StringName) -> Array:
	match symbol_id:
		&"circle":
			return [_arc(100.0, 100.0, 0.0, TAU, 40), _arc(100.0, 100.0, 0.0, -TAU, 40)]
		&"half_circle":
			# Open semicircle — circle's confusion partner. Differs from circle
			# by SHAPE (open arc), which survives $1 normalization; an aspect-
			# ratio difference (the old oval) does not.
			return [_arc(100.0, 100.0, 0.0, PI, 24), _arc(100.0, 100.0, PI, -PI, 24)]
		&"line_v":
			return [_polyline([Vector2(0, -100), Vector2(0, 100)]),
					_polyline([Vector2(0, 100), Vector2(0, -100)])]
		# $1 is SEQUENCE-sensitive: the same shape drawn in the opposite
		# direction is a different stroke. Every open-stroke and cornered
		# symbol therefore ships forward + reversed variants — real players
		# split roughly evenly on direction and the recognizer must not care.
		&"caret":
			return _with_reversed([
				_polyline([Vector2(-80, 80), Vector2(0, -80), Vector2(80, 80)])])
		&"triangle":
			return _with_reversed([
				_polyline([Vector2(0, -90), Vector2(85, 70), Vector2(-85, 70), Vector2(0, -90)])])
		&"square":
			return _with_reversed([
				_polyline([Vector2(-80, -80), Vector2(80, -80), Vector2(80, 80),
						   Vector2(-80, 80), Vector2(-80, -80)])])
		&"rectangle":
			return _with_reversed([
				_polyline([Vector2(-120, -60), Vector2(120, -60), Vector2(120, 60),
						   Vector2(-120, 60), Vector2(-120, -60)])])
		&"zigzag":
			return _with_reversed([
				_polyline([Vector2(-90, -60), Vector2(-30, 60), Vector2(30, -60), Vector2(90, 60)])])
		&"s_curve":
			return _with_reversed([
				_bezier_chain([Vector2(60, -90), Vector2(-60, -60), Vector2(60, 60), Vector2(-60, 90)])])
		&"backwards_three":
			return _with_reversed([
				_bezier_chain([Vector2(-50, -90), Vector2(60, -60), Vector2(-20, 0),
							   Vector2(60, 60), Vector2(-50, 90)])])
		&"spiral":
			# Outside-in only (an inside-out spiral starts at its own centroid,
			# which makes the $1 indicative angle pure noise), both winding
			# directions, at two turn counts — real players wind ~2 to 3 turns.
			# NEVER add reversed variants here: reversed = inside-out.
			return [_spiral(3.0, 110.0, 60), _spiral(-3.0, 110.0, 60),
					_spiral(2.25, 110.0, 60), _spiral(-2.25, 110.0, 60)]
		&"figure_eight":
			# Phase-shifted so the stroke starts at a lobe extreme, never at
			# the crossing point (= centroid, same instability as the spiral).
			return _with_reversed([
				_figure_eight(70.0, 50, PI * 0.5),
				_figure_eight(70.0, 50, PI * 1.5)])
	push_warning("SymbolLibrary: no template defined for %s" % symbol_id)
	return []

# ---------------------------------------------------------- procedural strokes

static func _arc(rx: float, ry: float, from_angle: float, sweep: float, steps: int) -> Array:
	var pts: Array = []
	for i in steps + 1:
		var t := from_angle + sweep * (float(i) / float(steps))
		pts.append(Vector2(cos(t) * rx, sin(t) * ry))
	return pts


static func _polyline(corners: Array, per_segment: int = 12) -> Array:
	var pts: Array = []
	for i in range(corners.size() - 1):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		for s in per_segment:
			pts.append(a.lerp(b, float(s) / float(per_segment)))
	pts.append(corners[corners.size() - 1])
	return pts


static func _bezier_chain(control_points: Array, steps: int = 48) -> Array:
	# Catmull-Rom through the control points; smooth enough for template use.
	var pts: Array = []
	var n := control_points.size()
	for i in range(n - 1):
		var p0: Vector2 = control_points[max(i - 1, 0)]
		var p1: Vector2 = control_points[i]
		var p2: Vector2 = control_points[i + 1]
		var p3: Vector2 = control_points[min(i + 2, n - 1)]
		var seg := int(steps / max(n - 1, 1))
		for s in seg:
			var t := float(s) / float(seg)
			pts.append(_catmull_rom(p0, p1, p2, p3, t))
	pts.append(control_points[n - 1])
	return pts


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Outside-in spiral: starts at full radius (stable indicative angle) and
## winds toward the center. Negative `turns` flips the winding direction.
static func _spiral(turns: float, max_radius: float, steps: int) -> Array:
	var pts: Array = []
	for i in steps + 1:
		var t := 1.0 - float(i) / float(steps)
		var angle := t * TAU * absf(turns) * signf(turns)
		var r := t * max_radius
		pts.append(Vector2(cos(angle) * r, sin(angle) * r))
	return pts


## `phase` shifts the start point along the curve. PI*0.5 starts at the right
## lobe extreme, PI*1.5 at the left — never the crossing point (centroid).
static func _figure_eight(radius: float, steps: int, phase: float = PI * 0.5) -> Array:
	var pts: Array = []
	for i in steps + 1:
		var t := phase + (float(i) / float(steps)) * TAU
		pts.append(Vector2(sin(t) * radius, sin(t * 2.0) * radius * 0.9))
	return pts


static func _reversed(points: Array) -> Array:
	var out := points.duplicate()
	out.reverse()
	return out


## Returns the given variants plus a reversed copy of each.
static func _with_reversed(variants: Array) -> Array:
	var out := variants.duplicate()
	for v in variants:
		out.append(_reversed(v))
	return out
