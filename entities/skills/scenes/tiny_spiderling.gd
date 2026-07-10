class_name TinySpiderling
extends CharacterBody2D
## A temporary attacking hatchling (design §3): spawned by HatchlingsSkill
## (scouting mode) or CocoonMine's burst (ambush mode) — the same entity
## either way, just a different spawn context. Chases the nearest spider
## that isn't its owner and pecks at it on contact until its lifetime runs
## out. Placeholder visual: a small drawn dot, no art asset yet.
## collision_layer = 0 (doesn't block anything itself); collision_mask =
## world(1) only, so move_and_slide() stops at walls but never physically
## collides with a real spider — damage is resolved via a direct Hurtbox
## lookup instead, same pattern Enemy/Player melee already use.

@export var move_speed: float = 90.0
@export var attack_range: float = 20.0
@export var attack_damage: float = 4.0
@export var attack_cooldown: float = 0.6

var _owner_spider: Node
var _lifetime_left: float = 0.0
var _attack_left: float = 0.0


## Called by HatchlingsSkill/CocoonMine right after spawn.
func setup(owner_spider: Node, lifetime: float) -> void:
	_owner_spider = owner_spider
	_lifetime_left = lifetime


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
	var target := _nearest_target()
	if target == null:
		velocity = Vector2.ZERO
		return
	var to_target := target.global_position - global_position
	if to_target.length() <= attack_range:
		velocity = Vector2.ZERO
		_attack(target)
	else:
		velocity = to_target.normalized() * move_speed
		move_and_slide()


func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("spiders"):
		if node == _owner_spider:
			continue
		var spider := node as Node2D
		if spider == null:
			continue
		var d := global_position.distance_squared_to(spider.global_position)
		if d < best_dist:
			best_dist = d
			best = spider
	return best


func _attack(target: Node2D) -> void:
	if _attack_left > 0.0:
		return
	_attack_left = attack_cooldown
	var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(attack_damage, self)
