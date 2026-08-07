extends Label

## Feel-test feedback readout (STEP_1_CLAUDE_CODE_TASK §7).
## Wires itself to the parent GestureInputLayer so the scene is playable with a
## single F6 — no manual node wiring required. Every line shown on screen is
## also print()ed so a session can be reviewed from the console afterwards.
##
## NOTE: wiring `gesture_rejected` to visible feedback violates the SILENT
## FAILURE rule (R2) — that rule applies to gameplay. This is a tuning harness;
## surfacing the near-miss is the entire point here.


func _ready() -> void:
	var layer := get_parent()
	layer.gesture_matched.connect(_on_gesture_matched)
	layer.gesture_rejected.connect(_on_gesture_rejected)


func _on_gesture_matched(symbol_id: StringName, score: float) -> void:
	var line := "MATCHED: %s (%.4f)" % [symbol_id, score]
	text = line
	print(line)


func _on_gesture_rejected(best_symbol: StringName, score: float) -> void:
	var line := "missed — closest: %s (%.4f)" % [best_symbol, score]
	text = line
	print(line)
