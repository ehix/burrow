class_name CocoonMine
extends Area2D
## Wolf Spider's Egg/Cocoon Mine (design §3): a hidden proximity trap. On
## detonation it bursts into `_burst_count` TinySpiderling attackers around
## itself, then frees. Placeholder visual: a small drawn cocoon, no art
## asset yet. collision_mask = player(2) | enemy(4) | larva(8) = 14, mirroring
## WebTrap.CatchArea's own proximity mask.

const TinySpiderlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")

@export var trigger_radius: float = 24.0
@export var hatchling_lifetime: float = 6.0

var _owner_spider: Node
var _burst_count: int = 4
var _armed := false


## Called by EggMineSkill right after placement.
func arm(owner_spider: Node, burst_count: int) -> void:
	_owner_spider = owner_spider
	_burst_count = burst_count
	_armed = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(0.5, 0.35, 0.2, 0.85))


func _on_body_entered(body: Node2D) -> void:
	if not _armed or body == _owner_spider:
		return
	if not (body.is_in_group("spiders") or body.is_in_group("larvae")):
		return
	_detonate()


func _detonate() -> void:
	_armed = false
	var holder := get_parent()
	if holder != null:
		for i in _burst_count:
			var spiderling := TinySpiderlingScene.instantiate()
			holder.add_child(spiderling)
			var offset := Vector2(trigger_radius, 0).rotated(TAU * float(i) / float(_burst_count))
			spiderling.global_position = global_position + offset
			spiderling.setup(_owner_spider, hatchling_lifetime)
	queue_free()
