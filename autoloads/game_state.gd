extends Node
## The run's persistent state: current depth, the RNG seed, and the player
## vitals carried forward between levels. Owns run lifecycle (new run / descend).
##
## Maze determinism (design §9) comes from deriving each level's seed from
## (run_seed, depth): the same run replays identical mazes.

const STARTING_DEPTH := 1
const DEFAULT_MAX_HEALTH := 100.0

## Per-depth difficulty growth. Enemy HP/speed/hunger scale by depth_scale().
const DIFFICULTY_PER_DEPTH := 0.15

## Seed for the whole run; per-depth seeds are derived from it.
var run_seed: int = 0

## Current depth, 1-based. Depth 1 is the first maze.
var depth: int = STARTING_DEPTH

## Player vitals carried between levels. NAN = uninitialised (use component
## defaults on first spawn).
var carried_health: float = NAN
var carried_hunger: float = NAN


func _ready() -> void:
	start_new_run()


## Begin a fresh run (also used for permadeath restart). Pass a fixed seed for
## reproducible runs; -1 picks a random one.
func start_new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else randi()
	depth = STARTING_DEPTH
	carried_health = NAN
	carried_hunger = NAN
	EventBus.depth_changed.emit(depth)


## Descend to the next, harder maze. Player vitals are expected to already be
## stored via store_player_vitals() before this is called.
func advance_depth() -> void:
	depth += 1
	EventBus.depth_changed.emit(depth)


## Deterministic per-depth seed. Same run_seed + depth → identical maze.
func maze_seed() -> int:
	return hash([run_seed, depth])


## Multiplier applied to enemy stats; grows with depth. Depth 1 == 1.0.
func depth_scale() -> float:
	return 1.0 + DIFFICULTY_PER_DEPTH * float(depth - STARTING_DEPTH)


## Snapshot the player's vitals before freeing a level on descent.
func store_player_vitals(health: float, hunger: float) -> void:
	carried_health = health
	carried_hunger = hunger


## True once vitals have been carried at least once this run.
func has_carried_vitals() -> bool:
	return not is_nan(carried_health)
