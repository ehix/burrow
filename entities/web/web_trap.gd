class_name WebTrap
extends StaticBody2D
## A placed web trap. Its solid body blocks spiders from crossing (arming after
## a short delay so the placer can step off); its CatchArea catches a wandering
## larva and lets *any* adjacent spider consume it. Consumption spends the trap.
##
## catch_larva() / try_consume() are public and guard against missing child
## nodes so the resolution logic can be unit-tested without the full scene.

const SpentScene := preload("res://entities/web/web_trap_spent.tscn")

@export var satiation: float = 40.0
## Seconds before the blocking body becomes solid (lets the placer leave).
@export var arm_delay: float = 0.4
## Web shots needed to destroy a placed trap.
@export var hits_to_destroy: int = 3

var owner_spider: Node = null
var caught_larva: Node = null
var spent := false
var web_hits := 0

@onready var _catch_area: Area2D = get_node_or_null("CatchArea")
@onready var _block_shape: CollisionShape2D = get_node_or_null("BlockShape")


func setup(placer: Node) -> void:
	owner_spider = placer


func _ready() -> void:
	add_to_group("traps")
	if _block_shape != null:
		_block_shape.disabled = true # not solid until armed
		var timer := get_tree().create_timer(arm_delay)
		timer.timeout.connect(_arm)
	if _catch_area != null:
		_catch_area.body_entered.connect(_on_body_entered)


func _arm() -> void:
	if is_instance_valid(_block_shape):
		_block_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if spent:
		return
	if body.is_in_group("larvae"):
		catch_larva(body)
	elif body.is_in_group("spiders"):
		try_consume(body)


## Hold a larva. Emits larva_trapped and immediately resolves consumption if a
## spider is already standing on the trap.
func catch_larva(larva: Node) -> void:
	if spent or caught_larva != null:
		return
	caught_larva = larva
	if larva.has_method("set_caught"):
		larva.set_caught(global_position)
	EventBus.larva_trapped.emit(larva, self)
	if _catch_area != null:
		for body in _catch_area.get_overlapping_bodies():
			if body.is_in_group("spiders"):
				try_consume(body)
				return


## A spider eats the caught larva: satiate it, announce the meal, remove the
## larva, and spend the trap. No-op if empty or already spent.
func try_consume(spider: Node) -> void:
	if spent or caught_larva == null:
		return
	var hunger := _find_hunger(spider)
	var overflow := 0.0
	if hunger != null:
		overflow = hunger.satiate(satiation)
	EventBus.larva_consumed.emit(spider, overflow)
	if overflow > 0.0:
		EventBus.excess_consumed.emit(spider, overflow)
	if is_instance_valid(caught_larva):
		caught_larva.queue_free()
	caught_larva = null
	spent = true
	_leave_torn_web()
	queue_free()


## A web shot struck this trap. The Nth hit destroys it, leaving a torn web.
func take_web_hit() -> void:
	if spent:
		return
	web_hits += 1
	if web_hits >= hits_to_destroy:
		spent = true
		if is_instance_valid(caught_larva):
			caught_larva.queue_free()
			caught_larva = null
		_leave_torn_web()
		queue_free()


func _leave_torn_web() -> void:
	var holder := get_parent()
	if holder == null:
		return
	var torn := SpentScene.instantiate()
	holder.add_child(torn)
	torn.global_position = global_position


func _find_hunger(spider: Node) -> HungerComponent:
	for child in spider.get_children():
		if child is HungerComponent:
			return child
	return null
