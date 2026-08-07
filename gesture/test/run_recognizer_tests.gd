extends SceneTree

## Recognizer tuning harness (STEP_1_CLAUDE_CODE_TASK §3–§5).
## Run headless:  godot --headless --script gesture/test/run_recognizer_tests.gd
##
## Feeds synthetic sloppy strokes (StrokeSynth) through GestureRecognizer and
## writes gesture/test/results.json with per-symbol self-match stats, confusion
## pair separability, and a suggested leniency value.

const INTENSITIES: Array = [0.3, 0.6, 1.0]
const VARIANTS_PER_INTENSITY: int = 30
const CONFUSION_MARGIN: float = 0.05
const LENIENCY_SAFETY_MARGIN: float = 0.03
const OUTPUT_PATH: String = "res://gesture/test/results.json"

# Fixed seed: the whole point of synthetic strokes is a repeatable signal.
const RNG_SEED: int = 0x5EED_C0DE


func _initialize() -> void:
	seed(RNG_SEED)

	var recognizer := GestureRecognizer.new()
	SymbolLibrary.install_templates(recognizer)

	var symbols: Array = SymbolLibrary.all_symbols()
	print("Testing %d symbols, %d variants each (%d per intensity at %s)..." % [
		symbols.size(), VARIANTS_PER_INTENSITY * INTENSITIES.size(),
		VARIANTS_PER_INTENSITY, str(INTENSITIES)])

	# ---------------------------------------------------------- generate variants
	# variants[symbol][intensity] -> Array of jittered strokes. Kept so the
	# confusion-pair pass reuses the exact same strokes as the self-match pass.
	var variants: Dictionary = {}
	for symbol_id in symbols:
		var templates: Array = SymbolLibrary.get_raw_templates(symbol_id)
		var by_intensity: Dictionary = {}
		for intensity in INTENSITIES:
			var strokes: Array = []
			for i in VARIANTS_PER_INTENSITY:
				var template: Array = templates[i % templates.size()]
				strokes.append(StrokeSynth.jitter(template, intensity))
			by_intensity[intensity] = strokes
		variants[symbol_id] = by_intensity

	# ------------------------------------------------------------ self-match pass
	var symbols_out: Dictionary = {}
	var flags: Array = []
	var lowest_self_min := 1.0

	for symbol_id in symbols:
		var self_scores: Array = []
		var picks_total := 0
		var picks_correct := 0
		var pick_rate_by_intensity: Dictionary = {}

		for intensity in INTENSITIES:
			var correct_at_intensity := 0
			for stroke in variants[symbol_id][intensity]:
				var result: Dictionary = recognizer.recognize(stroke, 0.0, [])
				var own_score: float = float(result["scores"].get(symbol_id, 0.0))
				self_scores.append(own_score)
				picks_total += 1
				if result["symbol"] == symbol_id:
					picks_correct += 1
					correct_at_intensity += 1
			pick_rate_by_intensity[str(intensity)] = \
				float(correct_at_intensity) / float(VARIANTS_PER_INTENSITY)

		var s_min := 1.0
		var s_max := -1.0
		var s_sum := 0.0
		for s in self_scores:
			s_min = minf(s_min, s)
			s_max = maxf(s_max, s)
			s_sum += s
		var s_mean := s_sum / float(self_scores.size())
		lowest_self_min = minf(lowest_self_min, s_min)

		var pick_rate := float(picks_correct) / float(picks_total)
		symbols_out[String(symbol_id)] = {
			"self_score_min": snappedf(s_min, 0.0001),
			"self_score_max": snappedf(s_max, 0.0001),
			"self_score_mean": snappedf(s_mean, 0.0001),
			"self_pick_rate": snappedf(pick_rate, 0.0001),
			"self_pick_rate_by_intensity": pick_rate_by_intensity,
		}

		var rate_at_max: float = pick_rate_by_intensity[str(1.0)]
		if rate_at_max < 0.95:
			flags.append("%s self_pick_rate=%.4f at intensity=1.0" % [symbol_id, rate_at_max])

		print("  %-16s min=%.4f mean=%.4f max=%.4f pick_rate=%.4f %s" % [
			symbol_id, s_min, s_mean, s_max, pick_rate, str(pick_rate_by_intensity)])

	# -------------------------------------------------------- confusion-pair pass
	var pairs_out: Dictionary = {}
	for pair in SymbolLibrary.CONFUSION_PAIRS:
		var a: StringName = pair[0]
		var b: StringName = pair[1]
		var rate_a_to_b := _confusion_rate(recognizer, variants, a, b)
		var rate_b_to_a := _confusion_rate(recognizer, variants, b, a)
		var key := "%s/%s" % [a, b]
		pairs_out[key] = {
			"confusion_rate_a_to_b": snappedf(rate_a_to_b, 0.0001),
			"confusion_rate_b_to_a": snappedf(rate_b_to_a, 0.0001),
		}
		if rate_a_to_b > CONFUSION_MARGIN:
			flags.append("%s confusion_rate=%.4f" % [key, rate_a_to_b])
		if rate_b_to_a > CONFUSION_MARGIN:
			flags.append("%s (reverse) confusion_rate=%.4f" % [key, rate_b_to_a])
		print("  pair %-28s a->b=%.4f b->a=%.4f" % [key, rate_a_to_b, rate_b_to_a])

	# ---------------------------------------------------------------------- output
	var suggested := snappedf(lowest_self_min - LENIENCY_SAFETY_MARGIN, 0.0001)
	var results: Dictionary = {
		"generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"rng_seed": RNG_SEED,
		"symbols": symbols_out,
		"confusion_pairs": pairs_out,
		"suggested_leniency": suggested,
		"flags": flags,
	}

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open %s for writing" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(results, "  "))
	file.close()

	print("\nsuggested_leniency = %.4f" % suggested)
	print("flags (%d):" % flags.size())
	for f in flags:
		print("  - " + f)
	print("Wrote " + OUTPUT_PATH)
	quit(0)


## Fraction of `source`'s jittered variants (all intensities) where `other`'s
## score comes within CONFUSION_MARGIN of — or exceeds — the source's own
## score, with the pool restricted to just the two symbols.
func _confusion_rate(recognizer: GestureRecognizer, variants: Dictionary,
		source: StringName, other: StringName) -> float:
	var pool: Array = [source, other]
	var confused := 0
	var total := 0
	for intensity in INTENSITIES:
		for stroke in variants[source][intensity]:
			var result: Dictionary = recognizer.recognize(stroke, 0.0, pool)
			var own: float = float(result["scores"].get(source, 0.0))
			var theirs: float = float(result["scores"].get(other, -1.0))
			total += 1
			if theirs >= own - CONFUSION_MARGIN:
				confused += 1
	return float(confused) / float(total)
