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
## Distance at which the enemy eats a larva by contact.
@export var eat_range: float = 30.0
## Hunger removed by eating one larva.
@export var eat_satiation: float = 40.0

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


## Level calls this right after instancing so the enemy can path on the grid.
func bind_level(level: Node) -> void:
	_level = level


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("enemy")
	_apply_type()
	health.died.connect(_on_died)
	_player = get_tree().get_first_node_in_group("player") as Node2D


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
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	_update_state()

	_repath_left -= delta
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
	elif hunger.fraction() >= hungry_fraction:
		next = State.SEEK_FOOD
	else:
		next = State.PATROL

	if next != state:
		state = next
		_repath_left = 0.0
		_path = []


# --- per-state behaviour ------------------------------------------------------

func _do_chase() -> void:
	if _player == null:
		return
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(_player.global_position))
		_repath_left = repath_interval
	_follow_path()
	var to_player := _player.global_position - global_position
	if to_player.length() <= attack_range and _has_line_of_sight(_player.global_position):
		web_emitter.fire(global_position, to_player, self)


func _do_seek_food() -> void:
	var larva := _nearest_in_group("larvae")
	if larva == null:
		_do_patrol()
		return
	if global_position.distance_to(larva.global_position) <= eat_range:
		_eat_larva(larva)
		return
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(larva.global_position))
		_repath_left = repath_interval
	_follow_path()


func _do_flee() -> void:
	if _mover.is_moving():
		return
	var away := (global_position - _player.global_position) if _player != null else Vector2.RIGHT
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var dir := _dominant(away)
	if not _mover.try_step(dir):
		_mover.try_step(_dominant(Vector2(away.y, -away.x))) # try a perpendicular
	_face(dir)


func _do_patrol() -> void:
	if _mover.is_moving():
		return
	# Greedy random walk on open tiles.
	var options: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	options.shuffle()
	for d in options:
		if _mover.try_step(d):
			_face(d)
			return


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


## Apply a web slow to this spider's movement (called by a web shot).
func apply_web_slow(factor: float, duration: float) -> void:
	if _mover != null:
		_mover.apply_slow(factor, duration)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	var cause := "starved" if hunger.is_starving() else "killed"
	EventBus.enemy_defeated.emit(cause)
	queue_free()
