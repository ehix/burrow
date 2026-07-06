class_name Enemy
extends CharacterBody2D
## The rival spider. A data-driven EnemyType sets its base stats; depth scales
## them. An enum FSM drives behaviour — patrol / seek_food / chase / flee —
## pathing over the level's baked navigation. It hungers like the player and can
## therefore be starved out, not just killed.
##
## Transitions are re-evaluated each physics frame from health, hunger, and
## whether it can see the player; per-state behaviour then acts on that.

enum State { PATROL, SEEK_FOOD, CHASE, FLEE }

@export var enemy_type: EnemyType

## Behaviour tuning (design §10 — feel these out in playtest).
@export var vision_range: float = 240.0
@export var attack_range: float = 200.0
@export var flee_health_fraction: float = 0.3
@export var hungry_fraction: float = 0.6
@export var repath_interval: float = 0.35
@export var arrive_distance: float = 12.0

@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer
@onready var facing_visual: Node2D = get_node_or_null("Facing")

var state: State = State.PATROL
var move_speed: float = 85.0

var _player: Node2D
var _repath_left := 0.0
var _facing := Vector2.RIGHT
var _dead := false


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("enemy")
	_apply_type()
	health.died.connect(_on_died)
	_player = get_tree().get_first_node_in_group("player") as Node2D
	call_deferred("_choose_patrol_target")


func _apply_type() -> void:
	var depth_mult := GameState.depth_scale()
	if enemy_type != null:
		health.max_health = enemy_type.max_health * depth_mult
		move_speed = enemy_type.move_speed * depth_mult
		hunger.hunger_rate = enemy_type.hunger_rate * depth_mult
	else:
		health.max_health *= depth_mult
		move_speed *= depth_mult
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

	_advance_along_path()


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
		_repath_left = 0.0 # force an immediate repath on transition


# --- per-state behaviour ------------------------------------------------------

func _do_chase() -> void:
	if _player == null:
		return
	if _repath_left <= 0.0:
		agent.target_position = _player.global_position
		_repath_left = repath_interval
	var to_player := _player.global_position - global_position
	if to_player.length() <= attack_range and _has_line_of_sight(_player.global_position):
		web_emitter.fire(global_position, to_player, self)


func _do_flee() -> void:
	if _repath_left <= 0.0:
		var away := (global_position - _player.global_position).normalized() if _player != null else Vector2.RIGHT
		if away == Vector2.ZERO:
			away = Vector2.RIGHT
		agent.target_position = global_position + away * 220.0
		_repath_left = repath_interval


func _do_seek_food() -> void:
	var larva := _nearest_in_group("larvae")
	if _repath_left <= 0.0:
		if larva != null:
			agent.target_position = larva.global_position
		else:
			_choose_patrol_target()
		_repath_left = repath_interval
	# Lay a trap near prey to actually catch it (traps do the consuming).
	if larva != null and trap_placer.can_place():
		if global_position.distance_to(larva.global_position) < 64.0:
			trap_placer.place(global_position, self)


func _do_patrol() -> void:
	if _repath_left <= 0.0 or agent.is_navigation_finished():
		_choose_patrol_target()
		_repath_left = repath_interval


# --- movement -----------------------------------------------------------------

func _advance_along_path() -> void:
	if agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var next_point := agent.get_next_path_position()
	var dir := (next_point - global_position).normalized()
	if dir != Vector2.ZERO:
		_facing = dir
		if facing_visual != null:
			facing_visual.rotation = dir.angle()
	velocity = dir * move_speed
	move_and_slide()


func _choose_patrol_target() -> void:
	# A random nudge; the agent clamps it onto the navmesh and paths there.
	var angle := randf() * TAU
	var reach := randf_range(80.0, 260.0)
	agent.target_position = global_position + Vector2.from_angle(angle) * reach


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


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	var cause := "starved" if hunger.is_starving() else "killed"
	EventBus.enemy_defeated.emit(cause)
	queue_free()
