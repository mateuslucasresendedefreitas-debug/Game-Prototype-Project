class_name DifficultyPhase
extends Resource

## One rung of the difficulty ladder. Authored as .tres files so tuning is a
## DATA problem, not a code problem — you can rebalance the entire curve
## without touching a script.
##
## DESIGN RULE (from analysis, Dimension 4): the three axes below must ramp on
## STAGGERED thresholds. Never advance speed, density, and symbol tier in the
## same phase. Each phase should introduce exactly ONE new pressure variable.

@export var phase_name: String = ""
@export var score_threshold: int = 0

## AXIS 1 — SPEED
@export_range(0.5, 4.0, 0.05) var descent_speed_multiplier: float = 1.0

## AXIS 2 — DENSITY
@export_range(1, 12) var max_simultaneous_enemies: int = 1
@export_range(0.2, 6.0, 0.1) var spawn_interval_seconds: float = 2.5
@export_range(0.0, 2.0, 0.05) var spawn_interval_jitter: float = 0.4

## AXIS 3 — SYMBOL COMPLEXITY
## Tier indices from SymbolLibrary.Tier. Only these tiers enter the active pool.
@export var symbol_tiers: Array[int] = [0]

## AXIS 4 — READING LOAD (ceiling extender)
## When true, confusion pairs are allowed into the pool simultaneously.
## Do not enable before the player is fluent with each symbol individually.
@export var allow_confusion_pairs: bool = false

## ENEMY MIX — weighted spawn table. Keys are enemy type ids, values are
## relative weights. An absent key means that type cannot spawn in this phase.
@export var enemy_weights: Dictionary = { &"grunt_1": 1.0 }

## MASS-POP CLUSTERING (from analysis, Dimension 3)
## Probability that a newly spawned enemy re-uses a symbol already active on
## screen. This is what manufactures combo opportunities. Deliberate, not random.
@export_range(0.0, 1.0, 0.05) var symbol_reuse_chance: float = 0.35

## BREATHING POINTS (from analysis, Dimension 4)
## If no relief event has occurred within this window, the scheduler forces one.
@export_range(4.0, 60.0, 1.0) var max_seconds_without_relief: float = 22.0
@export_range(0.0, 1.0, 0.05) var relief_spawn_weight: float = 0.15
