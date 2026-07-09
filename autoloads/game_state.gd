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

## Debug/display flag: when false the fog-of-war darkness is removed so the lit
## map is fully visible. Toggled at runtime (L); persists across levels and
## restarts, so it is deliberately NOT reset by start_new_run().
var darkness_enabled := true

## Dev tool (K): the player walks through walls (GridMover blocking ignored).
var noclip := false

## Dev tool (J): freeze every mover except the player (enemy + larvae stop).
var freeze_others := false

## Dev tool (G): freezes the player's health and hunger — no incoming damage,
## no starvation drain, no metabolic action cost, no passive hunger growth.
## Scoped to the player only (checked via the "player" group), not other spiders.
var god_mode := false

## Round tally: one "round" is one depth, decided by whoever clears it first
## (enemy defeated = a player win, player died = an enemy win). A session-long
## count, deliberately NOT reset by start_new_run() — permadeath resets the
## run's depth/vitals, not the scoreboard.
var player_wins := 0
var enemy_wins := 0

## Currency (design §5: Economy). Earned by play (e.g. excess consumption,
## clearing a round), spent only on permanent upgrades via buy_upgrade().
## Session-long like player_wins/enemy_wins — deliberately NOT reset by
## start_new_run(). "Permanent" means for this session: true cross-session
## persistence needs a save system, which doesn't exist in this project yet.
var runes: int = 0
var purchased_upgrades: Array[StringName] = []


func _ready() -> void:
	EventBus.enemy_defeated.connect(func(_cause: String) -> void: player_wins += 1)
	EventBus.player_died.connect(func() -> void: enemy_wins += 1)
	start_new_run()


## Begin a fresh run (also used for permadeath restart). Pass a fixed seed for
## reproducible runs; -1 picks a random one.
func start_new_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else randi()
	depth = STARTING_DEPTH
	clear_carried_vitals()
	EventBus.depth_changed.emit(depth)


## Drop any carried vitals so the next spawn uses the component defaults (full
## health, no hunger) instead of continuing a previous run's state.
func clear_carried_vitals() -> void:
	carried_health = NAN
	carried_hunger = NAN


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


## Add runes (e.g. an excess-consumption reward, a round win). No-op on a
## non-positive amount.
func earn_runes(amount: int) -> void:
	if amount <= 0:
		return
	runes += amount
	EventBus.runes_changed.emit(runes)


## Spend runes on something other than an upgrade purchase. Returns false
## (no-op) if `amount` exceeds the current balance.
func spend_runes(amount: int) -> bool:
	if amount <= 0 or runes < amount:
		return false
	runes -= amount
	EventBus.runes_changed.emit(runes)
	return true


## The only spend path for a permanent upgrade: charges its rune_cost and
## records it as purchased. Returns false (no charge, not recorded) if
## already purchased or unaffordable.
func buy_upgrade(upgrade: UpgradeCatalog) -> bool:
	if upgrade == null or upgrade.upgrade_id in purchased_upgrades:
		return false
	if not spend_runes(upgrade.rune_cost):
		return false
	purchased_upgrades.append(upgrade.upgrade_id)
	return true
