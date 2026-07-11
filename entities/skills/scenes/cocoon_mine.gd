class_name CocoonMine
extends Area2D
## Wolf Spider's Egg/Cocoon Mine (skill fixes bundle): a hidden proximity
## trap. On detonation it deals burst_damage directly to the triggering
## spider, then spawns a cosmetic burst of MineSpiderlings around itself,
## then frees. Larvae are immune. Only triggers for a body on the same
## plane it was armed on (mirrors Level.is_blocked()'s same-plane rule).
## Placeholder visual: a small drawn cocoon, no art asset yet. collision_mask
## = player(2) | enemy(4) = 6, mirroring WebTrap.CatchArea's own proximity
## mask minus larvae, since larvae no longer trigger it.

const MineSpiderlingScene := preload("res://entities/skills/scenes/mine_spiderling.tscn")

@export var trigger_radius: float = 24.0
@export var burst_damage: float = 30.0

var _owner_spider: Node
var _burst_count: int = 4
var _plane: Level.Layer = Level.Layer.GROUND
var _armed := false


## Called by EggMineSkill right after placement. `plane` is the plane the
## caster occupied when placing it.
func arm(owner_spider: Node, burst_count: int, plane: Level.Layer = Level.Layer.GROUND) -> void:
	_owner_spider = owner_spider
	_burst_count = burst_count
	_plane = plane
	_armed = true


func _ready() -> void:
	add_to_group("traps")
	body_entered.connect(_on_body_entered)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(0.5, 0.35, 0.2, 0.85))


func _on_body_entered(body: Node2D) -> void:
	if not _armed or body == _owner_spider:
		return
	if not body.is_in_group("spiders"):
		return
	if _plane_of(body) != _plane:
		return
	_detonate(body)


func _detonate(trigger: Node2D) -> void:
	_armed = false
	var hurtbox := trigger.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(burst_damage, _owner_spider)
	var holder := get_parent()
	if holder != null:
		for i in _burst_count:
			var spiderling := MineSpiderlingScene.instantiate()
			holder.add_child(spiderling)
			var offset := Vector2(trigger_radius, 0).rotated(TAU * float(i) / float(_burst_count))
			spiderling.global_position = global_position + offset
	queue_free()


## Mirrors BlockadeSkill._plane_of(): PlaneComponent-tracked plane, or
## GROUND for anything without one (e.g. a plain test double).
func _plane_of(body: Node) -> Level.Layer:
	var plane_component: PlaneComponent = body.get("_plane") if "_plane" in body else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND
