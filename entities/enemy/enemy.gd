class_name Enemy
extends CharacterBody2D
## The rival spider. A data-driven EnemyType sets base stats; depth scales them.
## An enum FSM drives behaviour — patrol / seek_food / chase / flee — stepping
## on the maze grid via GridMover. Chase and food-seeking path with the level's
## AStarGrid2D; patrol and flee step greedily. It hungers like the player, eats
## larvae by contact, and can be starved out as well as killed.

enum State { PATROL, SEEK_FOOD, CHASE, FLEE }

@export var enemy_type: EnemyType

## Behaviour tuning (design §10 — feel these out in playtest).
@export var vision_range: float = 240.0
@export var attack_range: float = 200.0
@export var flee_health_fraction: float = 0.3
@export var hungry_fraction: float = 0.6
@export var repath_interval: float = 0.35
## Minimum time to stay in PATROL or SEEK_FOOD before switching between them,
## so hunger hovering right at hungry_fraction doesn't flicker every frame.
## FLEE and CHASE always override immediately regardless — an emergency flee
## or spotting the player should never be delayed by "stickiness".
@export var state_min_duration: float = 1.5
## Distance at which the enemy eats a larva by contact.
@export var eat_range: float = 30.0
## Hunger removed by eating one larva.
@export var eat_satiation: float = 40.0
## Close-quarters strike when it catches the player: damage + shove + stun.
@export var melee_range: float = 56.0
@export var melee_damage: float = 12.0
@export var melee_stun: float = 0.3
@export var melee_cooldown: float = 0.6
## Hunger added to every spider per swing (charge_all's max-hunger fail-safe
## drains health instead once a spider is already starving).
@export var melee_hunger_cost: float = 5.0
## Seconds between the enemy laying web traps while hunting food.
@export var trap_interval: float = 5.0

@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer
@onready var _mover: GridMover = $GridMover
@onready var facing_visual: Node2D = get_node_or_null("Sprite")

var state: State = State.PATROL

var _player: Node2D
var _level: Node
var _repath_left := 0.0
var _facing := Vector2.RIGHT
var _dead := false
var _path: Array[Vector2i] = []
var _path_i := 0
var _melee_left := 0.0
var _trap_left := 0.0
var _state_lock_left := 0.0
## Tile -> the _patrol_tick it was last patrolled through, so patrol can bias
## toward unexplored ground instead of a pure random walk. A monotonic step
## counter rather than wall-clock time, so it's deterministic and testable.
var _tile_last_visited: Dictionary = {}
var _patrol_tick := 0


## Level calls this right after instancing so the enemy can path on the grid.
func bind_level(level: Node) -> void:
	_level = level


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("enemy")
	_apply_type()
	_mover.block_check = _blocked
	# The enemy starts in PATROL without ever "transitioning" into it, so the
	# idle-state lock (normally armed by _update_state on a state change) needs
	# arming here too, or the very first hunger check would ignore it.
	_state_lock_left = state_min_duration
	health.died.connect(_on_died)
	# Distress flash is reserved for actually being hurt — never for a status
	# effect like a web's slow, which deals no damage.
	health.damaged.connect(func(_amount: float) -> void: CombatFx.flash(facing_visual))
	health.health_changed.connect(_on_health_changed)
	hunger.hunger_changed.connect(_on_hunger_changed)
	# Prime the HUD with this instance's depth-scaled starting vitals (a fresh
	# enemy is spawned each depth, so the HUD needs a fresh snapshot every time).
	EventBus.health_changed.emit(self, health.current_health, health.max_health)
	EventBus.hunger_changed.emit(self, hunger.current_hunger, hunger.max_hunger)
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _on_health_changed(value: float, max_value: float) -> void:
	EventBus.health_changed.emit(self, value, max_value)


func _on_hunger_changed(value: float, max_value: float) -> void:
	EventBus.hunger_changed.emit(self, value, max_value)


## Blocking seam for the GridMover: checks a tile the player has already
## committed to (mid-step, not just physically standing on) before falling
## back to the body's own physics (walls, traps, a stationary spider).
func _blocked(dir: Vector2i) -> bool:
	if GridMover.spider_tile_contested(_mover, self, dir):
		return true
	return test_move(global_transform, Vector2(dir) * float(_mover.tile_size))


func _apply_type() -> void:
	var depth_mult := GameState.depth_scale()
	if enemy_type != null:
		health.max_health = enemy_type.max_health * depth_mult
		hunger.hunger_rate = enemy_type.hunger_rate * depth_mult
	else:
		health.max_health *= depth_mult
	health.current_health = health.max_health


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if GameState.freeze_others: # dev freeze toggle (J) halts the enemy
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	_update_state()

	_repath_left -= delta
	_melee_left = maxf(0.0, _melee_left - delta)
	_trap_left = maxf(0.0, _trap_left - delta)
	_state_lock_left = maxf(0.0, _state_lock_left - delta)
	match state:
		State.CHASE:
			_do_chase()
		State.FLEE:
			_do_flee()
		State.SEEK_FOOD:
			_do_seek_food()
		State.PATROL:
			_do_patrol()


func _update_state() -> void:
	var next := state
	if health.fraction() <= flee_health_fraction:
		next = State.FLEE
	elif _can_see_player():
		next = State.CHASE
	elif state == State.PATROL or state == State.SEEK_FOOD:
		# Only these two idle states are sticky against each other — a low-health
		# flee or spotting the player (above) always overrides immediately.
		if _state_lock_left > 0.0:
			next = state
		else:
			next = State.SEEK_FOOD if hunger.fraction() >= hungry_fraction else State.PATROL
	else:
		next = State.SEEK_FOOD if hunger.fraction() >= hungry_fraction else State.PATROL

	if next != state:
		state = next
		_repath_left = 0.0
		_path = []
		if next == State.PATROL or next == State.SEEK_FOOD:
			_state_lock_left = state_min_duration


# --- per-state behaviour ------------------------------------------------------

func _do_chase() -> void:
	if _player == null:
		return
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(_player.global_position))
		_repath_left = repath_interval
	_follow_path()
	var to_player := _player.global_position - global_position
	if to_player.length() <= melee_range:
		_melee_player(to_player)
	elif to_player.length() <= attack_range and _has_line_of_sight(_player.global_position):
		web_emitter.fire(global_position, to_player, self)


func _do_seek_food() -> void:
	var larva := _nearest_in_group("larvae")
	if larva == null:
		_do_patrol()
		return
	if global_position.distance_to(larva.global_position) <= eat_range:
		_eat_larva(larva)
		return
	# Lay a web across its own tile now and then — a placed web catches wandering
	# larvae on the enemy's behalf (feeding it) even when it can't chase them all.
	if _trap_left <= 0.0 and not _mover.is_moving() and trap_placer.can_place():
		trap_placer.place(global_position, self)
		_trap_left = trap_interval
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(larva.global_position))
		_repath_left = repath_interval
	_follow_path()


## Strike the player in close quarters: damage, a shove away, a stun, a flash.
## Costs hunger to swing (charge_all's max-hunger fail-safe drains health once
## the enemy is already starving).
func _melee_player(to_player: Vector2) -> void:
	if _melee_left > 0.0 or _player == null:
		return
	_melee_left = melee_cooldown
	HungerComponent.charge_all(get_tree(), melee_hunger_cost)
	var hurtbox := _player.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(melee_damage, self)
	if _player.has_method("apply_web_hit"):
		_player.apply_web_hit(_dominant(to_player), 1.0, 0.0, melee_stun)
	CombatFx.spawn_slash(get_parent(), _player.global_position, to_player)


## Run from the player; if truly cornered (no escape tile at all) turn and
## fight instead of standing there uselessly — the moment you actually corner
## a fleeing enemy should be a decisive one, not an anticlimax.
func _do_flee() -> void:
	if _mover.is_moving():
		return
	var away := (global_position - _player.global_position) if _player != null else Vector2.RIGHT
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var dir := _dominant(away)
	if _mover.try_step(dir):
		_face(dir)
		return
	var perpendicular := _dominant(Vector2(away.y, -away.x))
	if _mover.try_step(perpendicular):
		_face(perpendicular)
		return
	_fight_back()


## No escape route this frame: attack like CHASE would, instead of idling.
func _fight_back() -> void:
	if _player == null:
		return
	var to_player := _player.global_position - global_position
	if to_player.length() <= melee_range:
		_melee_player(to_player)
	elif to_player.length() <= attack_range and _has_line_of_sight(_player.global_position):
		web_emitter.fire(global_position, to_player, self)


## Sweeps toward unexplored ground instead of a pure random walk: candidate
## tiles are tried least-recently-visited first (never-visited sorts first of
## all), falling back down the list if the preferred direction is blocked.
func _do_patrol() -> void:
	if _mover.is_moving():
		return
	var my_tile := _tile_of(global_position)
	_patrol_tick += 1
	_tile_last_visited[my_tile] = _patrol_tick
	var options: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	options.shuffle() # random tie-break among equally-stale (e.g. never-visited) candidates
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _tick_last_visited(my_tile + a) < _tick_last_visited(my_tile + b))
	for d in options:
		if _mover.try_step(d):
			_face(d)
			return


func _tick_last_visited(tile: Vector2i) -> int:
	return _tile_last_visited.get(tile, -1)


# --- grid path following ------------------------------------------------------

func _set_path_to(target_tile: Vector2i) -> void:
	if _level == null:
		_path = []
		return
	_path = _level.path_tiles(_tile_of(global_position), target_tile)
	_path_i = 0


func _follow_path() -> void:
	if _mover.is_moving() or _path.is_empty() or _path_i >= _path.size():
		return
	var my_tile := _tile_of(global_position)
	var dir := _step_dir(my_tile, _path[_path_i])
	if dir == Vector2i.ZERO:
		_path_i += 1
		return
	if _mover.try_step(dir):
		_face(dir)
		_path_i += 1
	else:
		_path = [] # blocked (e.g. a trap dropped in the lane) — repath next tick


## Clamped unit step from `from` toward `to` (cardinal; ties favour x).
static func _step_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


func _dominant(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


func _face(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	_facing = Vector2(dir)
	if facing_visual != null:
		facing_visual.rotation = _facing.angle()


func _tile_of(world: Vector2) -> Vector2i:
	if _level != null:
		return _level.tile_of(world)
	return Vector2i(int(world.x / 48.0), int(world.y / 48.0))


# --- eating -------------------------------------------------------------------

func _eat_larva(larva: Node) -> void:
	if not larva.is_in_group("larvae"):
		return
	hunger.satiate(eat_satiation)
	EventBus.larva_consumed.emit(self, 0.0)
	larva.queue_free()


# --- perception ---------------------------------------------------------------

func _can_see_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if global_position.distance_to(_player.global_position) > vision_range:
		return false
	return _has_line_of_sight(_player.global_position)


func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos, 1) # world layer
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _nearest_in_group(group: String) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(group):
		var n := node as Node2D
		if n == null:
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_dist:
			best_dist = d
			best = n
	return best


## Take a landed web/melee hit: get shoved one tile along `push_dir`
## (Vector2i.ZERO = no shove), slowed, and stunned. Mirrors the player's
## reaction so combat is symmetric. No flash here — that's reserved for actual
## damage (see the HealthComponent.damaged hookup in _ready), since a pure
## web-crossing slow deals none.
func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
	if _mover == null:
		return
	if push_dir != Vector2i.ZERO:
		_mover.knockback(push_dir)
	if factor < 1.0:
		_mover.apply_slow(factor, slow_duration)
	if stun_duration > 0.0:
		_mover.stun(stun_duration)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	var cause := "starved" if hunger.is_starving() else "killed"
	EventBus.enemy_defeated.emit(cause)
	queue_free()
