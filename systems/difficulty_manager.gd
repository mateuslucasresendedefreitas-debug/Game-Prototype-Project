class_name DifficultyManager
extends Node

## Owns the difficulty ladder. Register as an autoload OR as a child of the
## gameplay scene — but it must be reset on every run, so scene-child is safer.
##
## Advances through DifficultyPhase resources by score. Emits phase changes so
## the spawner and the gesture layer stay in sync without polling.

signal phase_changed(phase: DifficultyPhase)
signal symbol_pool_changed(symbols: Array)

@export var phases: Array[DifficultyPhase] = []

var current_phase: DifficultyPhase
var current_phase_index: int = -1
var active_symbol_pool: Array = []

var _score: int = 0


func _ready() -> void:
	if phases.is_empty():
		phases = _build_default_ladder()
	reset()


func reset() -> void:
	_score = 0
	current_phase_index = -1
	_advance_to_index(0)


func on_score_changed(new_score: int) -> void:
	_score = new_score
	var target := current_phase_index
	for i in range(phases.size()):
		if _score >= phases[i].score_threshold:
			target = i
	if target != current_phase_index:
		_advance_to_index(target)


func _advance_to_index(index: int) -> void:
	if index < 0 or index >= phases.size():
		return
	current_phase_index = index
	current_phase = phases[index]
	_rebuild_symbol_pool()
	phase_changed.emit(current_phase)


func _rebuild_symbol_pool() -> void:
	var pool: Array = []
	for tier in current_phase.symbol_tiers:
		pool.append_array(SymbolLibrary.symbols_for_tier(tier))

	if not current_phase.allow_confusion_pairs:
		pool = _strip_confusion_pairs(pool)

	active_symbol_pool = pool
	symbol_pool_changed.emit(active_symbol_pool)


## Removes the SECOND member of any confusion pair present in the pool, so the
## player never faces two look-alike symbols before the reading-load phase.
func _strip_confusion_pairs(pool: Array) -> Array:
	var out := pool.duplicate()
	for pair in SymbolLibrary.CONFUSION_PAIRS:
		if out.has(pair[0]) and out.has(pair[1]):
			out.erase(pair[1])
	return out


## Convenience accessors for the spawner.
func descent_multiplier() -> float:
	return current_phase.descent_speed_multiplier if current_phase else 1.0


func max_enemies() -> int:
	return current_phase.max_simultaneous_enemies if current_phase else 1


func spawn_interval() -> float:
	if not current_phase:
		return 2.5
	var jitter := randf_range(-current_phase.spawn_interval_jitter,
							   current_phase.spawn_interval_jitter)
	return max(0.15, current_phase.spawn_interval_seconds + jitter)

# ------------------------------------------------------------ default ladder
#
# STAGGERED by design. Read the comment column: exactly one axis moves per rung.
# Replace with authored .tres files once you start tuning for real.

func _build_default_ladder() -> Array[DifficultyPhase]:
	var ladder: Array[DifficultyPhase] = []

	ladder.append(_phase("onboard",   0,  1.00, 1, 2.6, [0], false,
		{ &"grunt_1": 1.0 }))                                    # baseline

	ladder.append(_phase("density_1", 5,  1.00, 2, 2.2, [0], false,
		{ &"grunt_1": 1.0 }))                                    # + density

	ladder.append(_phase("stacking", 10,  1.00, 2, 2.0, [0], false,
		{ &"grunt_1": 0.7, &"grunt_2": 0.3 }))                   # + multi-symbol enemy

	ladder.append(_phase("speed_1",  20,  1.25, 2, 1.9, [0], false,
		{ &"grunt_1": 0.6, &"grunt_2": 0.4 }))                   # + speed

	ladder.append(_phase("symbols_1", 30, 1.25, 3, 1.7, [0, 1], false,
		{ &"grunt_1": 0.5, &"grunt_2": 0.3, &"tank": 0.2 }))     # + symbol tier + tank

	ladder.append(_phase("rusher",   40,  1.25, 3, 1.6, [0, 1], false,
		{ &"grunt_1": 0.4, &"grunt_2": 0.25, &"tank": 0.2, &"rusher": 0.15 }))
															     # + urgency spike type

	ladder.append(_phase("density_2", 50, 1.50, 4, 1.4, [0, 1], false,
		{ &"grunt_1": 0.35, &"grunt_2": 0.25, &"tank": 0.2, &"rusher": 0.2 }))
															     # + speed & density

	ladder.append(_phase("harasser", 65,  1.50, 4, 1.3, [0, 1], false,
		{ &"grunt_1": 0.3, &"grunt_2": 0.2, &"tank": 0.2, &"rusher": 0.2, &"harasser": 0.1 }))
															     # + competing-priority type

	ladder.append(_phase("symbols_2", 80, 1.50, 5, 1.2, [0, 1, 2], false,
		{ &"grunt_1": 0.25, &"grunt_2": 0.2, &"tank": 0.2, &"rusher": 0.2, &"harasser": 0.15 }))
															     # + advanced symbol tier

	ladder.append(_phase("reading",  100, 1.65, 5, 1.1, [0, 1, 2, 3], true,
		{ &"grunt_1": 0.25, &"grunt_2": 0.2, &"tank": 0.2, &"rusher": 0.2, &"harasser": 0.15 }))
															     # + CONFUSION PAIRS (ceiling extender)

	ladder.append(_phase("endgame",  140, 1.85, 6, 0.95, [0, 1, 2, 3], true,
		{ &"grunt_1": 0.2, &"grunt_2": 0.2, &"tank": 0.2, &"rusher": 0.25, &"harasser": 0.15 }))

	return ladder


func _phase(p_name: String, threshold: int, speed: float, max_sim: int,
			interval: float, tiers: Array, confusion: bool,
			weights: Dictionary) -> DifficultyPhase:
	var p := DifficultyPhase.new()
	p.phase_name = p_name
	p.score_threshold = threshold
	p.descent_speed_multiplier = speed
	p.max_simultaneous_enemies = max_sim
	p.spawn_interval_seconds = interval
	var typed_tiers: Array[int] = []
	for t in tiers:
		typed_tiers.append(int(t))
	p.symbol_tiers = typed_tiers
	p.allow_confusion_pairs = confusion
	p.enemy_weights = weights
	return p
