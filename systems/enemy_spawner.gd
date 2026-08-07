class_name EnemySpawner
extends Node2D

## Spawns descending threats according to the current DifficultyPhase.
##
## Implements three non-obvious rules from the analysis:
##
##   1. DELIBERATE SYMBOL CLUSTERING (Dimension 3)
##      Newly spawned enemies re-use symbols already on screen at a tuned
##      probability. Pure randomness produces too few combo opportunities and
##      the mass-pop mechanic goes unexploited. This is the system that makes
##      triage a real decision instead of a queue.
##
##   2. GUARANTEED BREATHING POINTS (Dimension 4)
##      If the player has been under sustained pressure past a threshold, a
##      relief object (chest equivalent) is force-spawned. Invisible pity. It
##      prevents statistically-fair-but-experienced-as-unfair runs.
##
##   3. LANE ANTI-OVERLAP
##      Enemies must never fully occlude another enemy's symbol. This was a
##      documented flaw in the original. Occlusion turns a skill failure into a
##      perceived unfairness — the player cannot read what they must resolve.

signal enemy_spawned(enemy: Node2D)
signal relief_spawned(relief: Node2D)

@export var difficulty: DifficultyManager
@export var enemy_scenes: Dictionary = {}   # StringName -> PackedScene
@export var relief_scene: PackedScene       # chest equivalent
@export var spawn_y: float = -80.0
@export var lane_count: int = 5
@export var lane_margin: float = 60.0

var _spawn_timer: float = 0.0
var _seconds_since_relief: float = 0.0
var _active_enemies: Array[Node2D] = []
var _lane_occupancy: Dictionary = {}        # lane_index -> last spawn time
var _elapsed: float = 0.0
var _running: bool = false


func _ready() -> void:
	if difficulty:
		difficulty.phase_changed.connect(_on_phase_changed)


func start() -> void:
	_running = true
	_elapsed = 0.0
	_spawn_timer = 0.0
	_seconds_since_relief = 0.0
	_lane_occupancy.clear()
	for e in _active_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_active_enemies.clear()


func stop() -> void:
	_running = false


func _process(delta: float) -> void:
	if not _running or not difficulty or not difficulty.current_phase:
		return

	_elapsed += delta
	_spawn_timer -= delta
	_seconds_since_relief += delta

	_prune_dead()

	# RULE 2 — forced breathing point.
	var phase := difficulty.current_phase
	if _seconds_since_relief >= phase.max_seconds_without_relief:
		_spawn_relief()
		return

	if _spawn_timer <= 0.0 and _active_enemies.size() < difficulty.max_enemies():
		if randf() < phase.relief_spawn_weight and _seconds_since_relief > 6.0:
			_spawn_relief()
		else:
			_spawn_enemy()
		_spawn_timer = difficulty.spawn_interval()

# --------------------------------------------------------------------- spawning

func _spawn_enemy() -> void:
	var phase := difficulty.current_phase
	var type_id := _weighted_pick(phase.enemy_weights)
	if type_id == &"" or not enemy_scenes.has(type_id):
		return

	var enemy: Node2D = (enemy_scenes[type_id] as PackedScene).instantiate()
	var lane := _pick_free_lane()
	enemy.global_position = Vector2(_lane_x(lane), spawn_y)

	# Assign symbols. Enemy exposes `symbol_count` (its resolution cost).
	var count: int = enemy.get("symbol_count") if enemy.get("symbol_count") != null else 1
	var symbols := _assign_symbols(count)
	if enemy.has_method("configure"):
		enemy.configure(symbols, difficulty.descent_multiplier())

	add_child(enemy)
	_active_enemies.append(enemy)
	_lane_occupancy[lane] = _elapsed
	enemy_spawned.emit(enemy)


func _spawn_relief() -> void:
	if not relief_scene:
		_seconds_since_relief = 0.0
		return
	var relief: Node2D = relief_scene.instantiate()
	var lane := _pick_free_lane()
	relief.global_position = Vector2(_lane_x(lane), spawn_y)
	if relief.has_method("configure"):
		# Relief objects carry a SEQUENCE — drawing it is the structured pause.
		relief.configure(_assign_symbols(4, false), difficulty.descent_multiplier() * 0.6)
	add_child(relief)
	_lane_occupancy[lane] = _elapsed
	_seconds_since_relief = 0.0
	_spawn_timer = difficulty.spawn_interval()
	relief_spawned.emit(relief)

# ------------------------------------------------------- RULE 1: clustering

## Picks `count` symbols for a new spawn. With probability `symbol_reuse_chance`,
## the FIRST symbol is drawn from symbols already visible on screen — this is
## what manufactures mass-pop combo opportunities.
func _assign_symbols(count: int, allow_reuse: bool = true) -> Array:
	var pool: Array = difficulty.active_symbol_pool
	if pool.is_empty():
		return []

	var out: Array = []
	var on_screen := _symbols_on_screen()
	var reuse_chance: float = difficulty.current_phase.symbol_reuse_chance

	for i in count:
		var chosen: StringName
		if i == 0 and allow_reuse and not on_screen.is_empty() and randf() < reuse_chance:
			chosen = on_screen[randi() % on_screen.size()]
		else:
			chosen = pool[randi() % pool.size()]
		out.append(chosen)
	return out


func _symbols_on_screen() -> Array:
	var found: Array = []
	for e in _active_enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("remaining_symbols"):
			for s in e.remaining_symbols():
				if not found.has(s):
					found.append(s)
	return found

# ----------------------------------------------------- RULE 3: lane placement

func _pick_free_lane() -> int:
	var best_lane := 0
	var oldest := INF
	for i in lane_count:
		var last: float = _lane_occupancy.get(i, -999.0)
		if last < oldest:
			oldest = last
			best_lane = i
	return best_lane


func _lane_x(lane: int) -> float:
	var vw: float = get_viewport_rect().size.x
	var usable := vw - (lane_margin * 2.0)
	var step := usable / float(max(lane_count - 1, 1))
	return lane_margin + step * float(lane)

# --------------------------------------------------------------------- helpers

func _weighted_pick(weights: Dictionary) -> StringName:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return &""
	var roll := randf() * total
	var acc := 0.0
	for k in weights.keys():
		acc += float(weights[k])
		if roll <= acc:
			return k
	return weights.keys()[0]


func _prune_dead() -> void:
	var alive: Array[Node2D] = []
	for e in _active_enemies:
		if is_instance_valid(e):
			alive.append(e)
	_active_enemies = alive


func _on_phase_changed(_phase: DifficultyPhase) -> void:
	# Phase transitions do not clear the screen — the player carries their
	# current situation into the new pressure level. This is what makes the
	# ramp feel continuous rather than wave-gated.
	pass
