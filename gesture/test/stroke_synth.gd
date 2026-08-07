class_name StrokeSynth
extends RefCounted

## Synthetic sloppy-stroke generator (STEP_1_CLAUDE_CODE_TASK §2).
##
## Human mouse/finger input is not a repeatable test signal, so recognizer
## tuning uses jittered variants of the procedural templates instead. Applied
## in order: point jitter -> global rotation -> anisotropic scale -> point drop.
##
## `intensity` ranges 0.0 (clean) to 1.0 (very sloppy).

static func jitter(template: Array, intensity: float) -> Array:
	var pts: Array = []

	# 1. Point jitter — Gaussian noise per point.
	for p in template:
		var v: Vector2 = p
		pts.append(Vector2(
			v.x + randfn(0.0, intensity * 8.0),
			v.y + randfn(0.0, intensity * 8.0)))

	# 2. Global rotation about the centroid.
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= float(pts.size())

	var angle := deg_to_rad(randf_range(-15.0, 15.0)) * intensity
	for i in pts.size():
		pts[i] = centroid + (pts[i] - centroid).rotated(angle)

	# 3. Anisotropic scale — x and y independently, interpolated by intensity.
	var sx := lerpf(1.0, randf_range(0.85, 1.15), intensity)
	var sy := lerpf(1.0, randf_range(0.85, 1.15), intensity)
	for i in pts.size():
		var rel: Vector2 = pts[i] - centroid
		pts[i] = centroid + Vector2(rel.x * sx, rel.y * sy)

	# 4. Density irregularity — drop 0–15% of points (uneven sampling from
	# fast drawing). Never drop below the recognizer's useful minimum.
	var drop_fraction := randf() * 0.15
	var out: Array = []
	for p in pts:
		if randf() < drop_fraction:
			continue
		out.append(p)
	if out.size() < 5:
		out = pts
	return out
