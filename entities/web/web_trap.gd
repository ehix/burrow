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
## A spider crossing the web is entangled: move speed drops to this fraction...
@export var web_slow_factor: float = 0.4
## ...for this many seconds.
@export var web_slow_duration: float = 1.5

var owner_spider: Node = null
var caught_larva: Node = null
var spent := false
var web_hits := 0
## The placer is immune to its own web's slow until it has stepped off once.
var _owner_left := false

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
		_catch_area.body_exited.connect(_on_body_exited)


func _arm() -> void:
	if is_instance_valid(_block_shape):
		_block_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if spent:
		return
	if body.is_in_group("larvae"):
		catch_larva(body)
	elif body.is_in_group("spiders"):
		_entangle(body)
		try_consume(body)


func _on_body_exited(body: Node) -> void:
	# The placer becomes vulnerable to its own web once it has stepped clear.
	if body == owner_spider:
		_owner_left = true


## Slow a spider that crosses the web, unless it is the placer who has not yet
## stepped off (you are immune to a web you just laid until you leave it).
func _entangle(spider: Node) -> void:
	if spider == owner_spider and not _owner_left:
		return
	if spider.has_method("apply_web_hit"):
		spider.apply_web_hit(Vector2i.ZERO, web_slow_factor, web_slow_duration, 0.0)


## Hold a larva. Emits larva_trapped and immediately resolves consumption if a
## spider is already standing on the trap.
func catch_larva(larva: Node) -> void:
	if spent or caught_larva != null:
		return
	caught_larva = larva
	if larva.has_method("set_caught"):
		larva.set_caught(global_position)
	if larva.has_method("flash_distress"):
		larva.flash_distress()
	EventBus.larva_trapped.emit(larva, self)
	# A spider overlapping the web (its own tile or an adjacent one — the catch
	# area reaches one tile) eats immediately. Otherwise the larva stays held
	# until a spider steps adjacent (its body_entered resolves the consume).
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
