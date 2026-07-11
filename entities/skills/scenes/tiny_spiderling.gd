class_name TinySpiderling
extends CharacterBody2D
## A temporary attacking hatchling (skill fixes bundle: escort/aggro AI +
## line-of-sight). Spawned by HatchlingsSkill (scouting mode) — escorts near
## its owner spider until an enemy spider comes within both aggro_radius and
## line-of-sight, then breaks off to chase/attack it, reverting to escort
## once the target dies, leaves aggro_radius, or line-of-sight breaks.
## Placeholder visual: a small drawn dot, no art asset yet.
## collision_layer = 0 (doesn't block anything itself); collision_mask =
## world(1) only, so move_and_slide() stops at walls but never physically
## collides with a real spider — damage is resolved via a direct Hurtbox
## lookup instead, same pattern Enemy/Player melee already use.

@export var move_speed: float = 180.0
@export var attack_range: float = 20.0
@export var attack_damage: float = 4.0
@export var attack_cooldown: float = 0.6
@export var aggro_radius: float = 180.0

var _owner_spider: Node
var _escort_offset: Vector2 = Vector2.ZERO
var _lifetime_left: float = 0.0
var _attack_left: float = 0.0
var _aggro_target: Node2D = null


## Called by HatchlingsSkill right after spawn. `escort_offset` is the same
## radial offset the caster spawned this hatchling at, relative to the
## owner — the hatchling escorts around owner.global_position + this offset
## when nothing's worth chasing.
func setup(owner_spider: Node, lifetime: float, escort_offset: Vector2 = Vector2.ZERO) -> void:
	_owner_spider = owner_spider
	_lifetime_left = lifetime
	_escort_offset = escort_offset


func _ready() -> void:
	add_to_group("hatchlings")


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(0.85, 0.3, 0.3, 0.9))


func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	_attack_left = maxf(0.0, _attack_left - delta)
	if _lifetime_left <= 0.0:
		queue_free()
		return
	_update_aggro_target()
	if _aggro_target != null:
		_chase(_aggro_target)
	else:
		_escort()


## Keeps the current target if it's still in range/LOS; otherwise looks for
## the nearest qualifying replacement (may be null).
func _update_aggro_target() -> void:
	if _aggro_target != null and is_instance_valid(_aggro_target):
		var still_in_range := global_position.distance_to(_aggro_target.global_position) <= aggro_radius
		if still_in_range and _has_line_of_sight(_aggro_target.global_position):
			return
	_aggro_target = _nearest_target()


func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_dist := aggro_radius
	for node in get_tree().get_nodes_in_group("spiders"):
		if node == _owner_spider:
			continue
		var spider := node as Node2D
		if spider == null:
			continue
		var d := global_position.distance_to(spider.global_position)
		if d <= best_dist and _has_line_of_sight(spider.global_position):
			best_dist = d
			best = spider
	return best


func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos, 1) # world layer
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _chase(target: Node2D) -> void:
	var to_target := target.global_position - global_position
	if to_target.length() <= attack_range:
		velocity = Vector2.ZERO
		_attack(target)
	else:
		velocity = to_target.normalized() * move_speed
		move_and_slide()


## Walks toward the owner's current position plus the fixed spawn-relative
## offset; holds still once within 1px (avoids jittering, and stays below
## the ~3px a single physics tick covers at move_speed 180 so it doesn't
## "arrive" prematurely mid-approach) or if the owner is gone.
func _escort() -> void:
	# Check validity on the raw reference before casting — casting a freed
	# (but non-null) object throws, and the owner spider dying mid-escort is
	# a normal gameplay occurrence, not just a test-teardown artifact.
	if _owner_spider == null or not is_instance_valid(_owner_spider):
		velocity = Vector2.ZERO
		return
	var owner_2d := _owner_spider as Node2D
	if owner_2d == null:
		velocity = Vector2.ZERO
		return
	var desired := owner_2d.global_position + _escort_offset
	var to_desired := desired - global_position
	if to_desired.length() <= 1.0:
		velocity = Vector2.ZERO
	else:
		velocity = to_desired.normalized() * move_speed
		move_and_slide()


func _attack(target: Node2D) -> void:
	if _attack_left > 0.0:
		return
	_attack_left = attack_cooldown
	var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(attack_damage, self)
