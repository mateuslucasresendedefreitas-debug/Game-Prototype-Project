# Gesture Defence — Implementation Spec (Pass 1: Systems Only)

Theme-agnostic mechanical implementation derived from the Magic Touch systems analysis.
**No art, texture, or level-content decisions are made or implied in this pass.**

---

## Section 1 — World Rules

Rules that hold regardless of theme, enemy fiction, or visual treatment.

- **R1 — Broadcast resolution.** One recognized gesture resolves every matching symbol on screen simultaneously. Never single-target. This rule is the source of all strategic depth; violating it collapses the game into a queue.
- **R2 — Silent failure.** An unrecognized stroke produces no user-facing feedback. The cost of a miss is elapsed time only.
- **R3 — Instant loss.** Any threat reaching the breach line ends the run. No health, no lives, no grace period.
- **R4 — Progress is inviolable.** Currency and best-score persist to disk before any death transition. Normal failure never costs earned progress.
- **R5 — Readability guarantee.** A threat's required symbol must always be visible. Occlusion is a bug, not a difficulty feature.
- **R6 — Partial resolution increases urgency.** Resolving some but not all of a multi-symbol threat makes it descend faster. Half-commitment is punished.
- **R7 — No consumable revives.** Skill must remain the perceived variable in the outcome.

---

## Section 2 — Systems

### 2.1 Gesture Recognition — `gesture/gesture_recognizer.gd`

- $1 Unistroke Recognizer. Rotation/scale/translation invariant.
- Resample 64 points → rotate to indicative angle → scale to 250px square → translate to origin → golden-section angular search ±45°.
- Score = `1 - (distance / half_diagonal)`. Default match threshold `0.78`.
- **`active_pool` parameter is the primary accuracy lever.** Restricting candidates to symbols currently in play cuts false positives substantially. Always pass it.

**Tuning procedure (do this first, before any other work):**
1. Build a bare scene: `GestureInputLayer` + a `Label` bound to `gesture_rejected` showing `best_symbol` and `score`.
2. Draw each symbol 20× at deliberately sloppy speed. Log scores.
3. Set `leniency` just below the 10th-percentile score of *intentional* draws.
4. Then draw each symbol's confusion-pair partner 20× and confirm cross-matches score below that line. If they don't, the two symbols are too similar — redesign one.

### 2.2 Symbol Library — `gesture/symbol_library.gd`

- Four tiers: BASIC / INTERMEDIATE / ADVANCED / AMBIGUOUS.
- Templates are procedurally generated (arcs, polylines, Catmull-Rom chains) — no hand-recorded data needed.
- Multiple stroke variants per symbol cover drawing-direction differences.
- `CONFUSION_PAIRS` drives the reading-load difficulty axis. Both members of a pair never enter the pool until the AMBIGUOUS phase.

### 2.3 Input Layer — `gesture/gesture_input_layer.gd`

- Full-rect `Control`, above gameplay, below HUD. Add to group `gesture_input`.
- Signals: `gesture_matched(symbol_id, score)` → gameplay. `gesture_rejected(...)` → **telemetry only, never wire to feedback.**
- 3px minimum point spacing filters jitter; sub-12px bounding boxes rejected as taps.

### 2.4 Difficulty Ladder — `data/difficulty_phase.gd` + `systems/difficulty_manager.gd`

Four independent axes. **Exactly one advances per phase** — see the comment column in `_build_default_ladder()`.

| Axis | Property | Purpose |
|---|---|---|
| Speed | `descent_speed_multiplier` | Raw reaction pressure |
| Density | `max_simultaneous_enemies`, `spawn_interval_seconds` | Parallel tracking load |
| Symbol complexity | `symbol_tiers` | Execution-time cost per threat |
| Reading load | `allow_confusion_pairs` | **Ceiling extender** — the original never used this |

Default ladder spans score 0 → 140 across 11 phases. Confusion pairs unlock at 100.

### 2.5 Spawner — `systems/enemy_spawner.gd`

Three non-obvious behaviours:

- **Deliberate symbol clustering** (`symbol_reuse_chance`, default 0.35). New spawns re-use an on-screen symbol at a tuned probability. Pure randomness produces too few combo opportunities and the mass-pop mechanic goes unexploited.
- **Guaranteed breathing points.** If `max_seconds_without_relief` elapses under pressure, a relief object is force-spawned. Invisible pity that prevents runs experienced as unfair.
- **Lane anti-occlusion.** Least-recently-used lane selection. Enforces R5.

### 2.6 Enemy Base — `systems/enemy.gd`

Every type is one point on a 2D grid: `base_descent_speed` × `symbol_count`. Spread the roster across both axes.

| Type id | Urgency | Cost | Role |
|---|---|---|---|
| `grunt_1` | Medium | 1 | Baseline |
| `grunt_2` | Medium | 2–3 | Sustained attention |
| `tank` | Low | 4–7 | Time sink; forces commitment |
| `rusher` | High | 1 (hard symbol) | Urgency spike |
| `harasser` | Medium | 1–3 | Competing priority (`steals_currency = true`) |

The **tank + rusher** pairing is the designed compression moment: committing to the tank gets you killed by the rusher; panicking on the rusher leaves the tank's draw debt unpaid.

---

## Section 3 — Application / Build Order

Reference Section 2 for system detail; this section covers sequencing only.

**Step 1 — Recognizer harness (highest technical risk, do first).**
Bare scene, no gameplay. Tune `leniency` per §2.1. Do not proceed until sloppy draws match >95% of the time.

**Step 2 — Single enemy, single symbol.**
One `grunt_1` descending, one symbol, breach line. Verify broadcast wiring and R6 speed gain.

**Step 3 — Spawner + ladder.**
Wire `DifficultyManager` → `EnemySpawner`. Verify staggered axis advancement by logging phase changes against score.

**Step 4 — Clustering validation.**
Instrument: log how many combos (2+ enemies resolved by one gesture) occur per run. Target 1 combo per 8–12 kills at mid difficulty. Tune `symbol_reuse_chance` to hit it.

**Step 5 — Session loop.**
Persistent `GameRoot`; `GameplayScene` and `ScoreScreen` as show/hide siblings. **Never `change_scene_to_file()`** — target under 2s death-to-replay. Save `PlayerData` before any transition (R4).

**Step 6 — Powerups.**
Tap-activated UI slots. **Not gesture-activated.** This is the deliberate correction to the original's central flaw: its emergency tools required the hardest input at the highest-stress moment, so players avoided using rewards they had earned.

---

## Open tuning targets

| Metric | Target | Instrument in step |
|---|---|---|
| Novice session length | 60–90s | 5 |
| Combo frequency, mid-difficulty | 1 per 8–12 kills | 4 |
| Recognizer accept rate, intentional sloppy draws | >95% | 1 |
| Death → active gameplay | <2.0s | 5 |
| Sessions to first unlock | 2–3 | 6 |
