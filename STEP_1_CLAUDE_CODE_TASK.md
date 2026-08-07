# Task: Recognizer Tuning Harness (Automated)

**Scope:** `gesture/` only. Do not modify `systems/` or `data/` in this pass.
**Execution:** headless, via `godot --headless --script`. No editor GUI
interaction, no human-drawn input required.

---

## 1. Objective

Determine a defensible `leniency` value for `GestureInputLayer.leniency` and
flag any symbol pairs that are not separable at that value, without a human
drawing samples by hand. Human mouse/finger input is not a reliable or
repeatable test signal — replace it with synthetic noisy strokes generated
from the existing procedural templates in `symbol_library.gd`.

---

## 2. Synthetic sloppy-stroke generator

Create `gesture/test/stroke_synth.gd` (`class_name StrokeSynth`,
`extends RefCounted`).

Function: `static func jitter(template: Array, intensity: float) -> Array`

Apply, in order, to a copy of the template's `Array[Vector2]`:

- **Point jitter** — add Gaussian-ish noise per point: `randfn(0.0, intensity * 8.0)` on both x and y. Use `randfn` if available in this Godot version; otherwise approximate with `(randf() - 0.5) * 2.0 * intensity * 8.0`.
- **Global rotation** — rotate the whole stroke about its centroid by a random angle in `[-15°, 15°] * intensity`.
- **Anisotropic scale** — scale x and y independently by a random factor in `[0.85, 1.15]` interpolated by `intensity`.
- **Density irregularity** — randomly drop 0–15% of points (simulates uneven sampling from fast drawing) before returning.

`intensity` ranges `0.0` (clean) to `1.0` (very sloppy). Test at three
intensities: `0.3`, `0.6`, `1.0`.

---

## 3. Test harness

Create `gesture/test/run_recognizer_tests.gd`
(`extends SceneTree`, entry point for `--script`).

For each symbol in `SymbolLibrary.all_symbols()`:

1. Pull its templates via the existing `SymbolLibrary._templates_for()` (make
   this method non-private for testing, or add a public wrapper —
   `get_raw_templates(symbol_id) -> Array`).
2. Generate 30 jittered variants per intensity level (90 total per symbol)
   using `StrokeSynth.jitter`.
3. Feed each variant to `GestureRecognizer.recognize()` with:
   - `active_pool = []` (full pool — worst case, no phase restriction)
   - default `threshold` param irrelevant here; capture raw `score` always
4. Record per symbol:
   - `self_score_min`, `self_score_max`, `self_score_mean` (score when
     matched against its own symbol_id)
   - Whether the recognizer's top pick (`result.symbol`) equals the source
     symbol at each intensity — track as `self_pick_rate` (0.0–1.0)

For each pair in `SymbolLibrary.CONFUSION_PAIRS`:

5. Take symbol A's jittered variants, run `recognize()` restricted to
   `active_pool = [A, B]`, record how often B's score comes within `0.05` of
   A's score or exceeds it → `confusion_rate`.
6. Repeat with B's variants against `[A, B]`.

---

## 4. Output

Write `gesture/test/results.json`:

```json
{
  "generated_at": "<ISO8601 timestamp>",
  "symbols": {
    "circle": {
      "self_score_min": 0.0,
      "self_score_max": 0.0,
      "self_score_mean": 0.0,
      "self_pick_rate": 0.0
    }
  },
  "confusion_pairs": {
    "circle/oval": {
      "confusion_rate_a_to_b": 0.0,
      "confusion_rate_b_to_a": 0.0
    }
  },
  "suggested_leniency": 0.0,
  "flags": []
}
```

`suggested_leniency` = lowest `self_score_min` across all symbols, minus a
`0.03` safety margin.

`flags`: append a string entry for any symbol where `self_pick_rate < 0.95`
at intensity `1.0`, and for any confusion pair where either
`confusion_rate_*` exceeds `0.05`. Format:
`"<symbol> self_pick_rate=<value> at intensity=1.0"` or
`"<pair> confusion_rate=<value>"`.

---

## 5. Run

```
godot --headless --script gesture/test/run_recognizer_tests.gd
```

Confirm `gesture/test/results.json` is produced and non-empty. Do not hand-edit
the output.

---

## 6. Report

After the run, summarize `results.json` back in chat:

- `suggested_leniency` value
- Full contents of `flags` (empty array = no issues)
- Any symbols with `self_pick_rate < 1.0` at intensity `0.3` (these are
  concerning even before adding sloppiness)

Do not set `GestureInputLayer.leniency` or redesign any symbol template —
that decision happens after this report is reviewed.

---

## 7. Feel-test scene (build fully, no assembly left for the user)

The person running this project will do subjective play-testing only — they
will not wire nodes, connect signals, or touch code. Build a scene that is
complete and playable on its own.

Create `gesture/test/feel_test.tscn`:

- Root `Control`, full rect, script = `gesture_input_layer.gd`.
- Set `leniency` on the root node to the `suggested_leniency` value from
  step 6 (once computed — do this after step 5 runs, not before).
- Set `active_pool` empty (full symbol pool available) so every symbol from
  `SymbolLibrary.all_symbols()` is testable.
- Child `Label`, top-left, large font (24pt+), showing live feedback:
  - On `gesture_matched(symbol_id, score)`: text = `"MATCHED: <symbol_id> (<score>)"`.
  - On `gesture_rejected(best_symbol, score)`: text = `"missed — closest: <best_symbol> (<score>)"`.
  - Both cases: also print the same line to console via `print()`, so a
    session can be reviewed after the fact without relying on the person to
    transcribe what they saw.
- Child `Label`, bottom of screen, static text: list all drawable symbol
  names (from `SymbolLibrary.all_symbols()`), so the person knows what to
  attempt without reading source.
- Confirm `draw_trail = true` is on (default) so the stroke itself is
  visible while drawing — this is what "feel" is actually testing.

This scene must run with a single **F6 (Play Scene)** press in the Godot
editor once the project is open. No node wiring, no Inspector edits, no
script changes required from the user.
