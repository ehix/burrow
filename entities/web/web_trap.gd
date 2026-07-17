class_name WebTrap
extends StaticBody2D
## A placed web trap. Never physically blocks movement — every spider (and
## every larva) can walk straight across a web; its collision shape exists only
## so a web shot can detect and destroy it (spiders' own collision masks omit
## the trap layer, so `test_move` never reports one as an obstacle). Its
## CatchArea slows any spider that crosses it and catches a wandering larva,
## letting *any* adjacent spider consume it. Consumption spends the trap.
##
## catch_larva() / try_consume() are public and guard against missing child
## nodes so the resolution logic can be unit-tested without the full scene.
##
## Plane-aware (mirrors CocoonMine/BlockadeSkill's own `_plane_of()` idiom):
## a trap physically sits on whichever plane its placer occupied at the
## moment it was laid, and only interacts with bodies on that same plane —
## a web laid on the ceiling can't catch a larva wandering the floor below
## it (larvae have no PlaneComponent, so they're always effectively GROUND),
## nor entangle/feed a spider crossing the same tile on the other plane.

const SpentScene := preload("res://entities/web/web_trap_spent.tscn")

@export var satiation: float = 40.0
## Web shots needed to destroy a placed trap.
@export var hits_to_destroy: int = 3
## Any spider crossing the web is entangled: move speed drops to this fraction
## (50% slow == 0.5) for web_slow_duration seconds. Applies uniformly, including
## to the spider that placed it — walking a web always costs you speed.
@export var web_slow_factor: float = 0.5
@export var web_slow_duration: float = 1.5
## Seconds after placement before the entangle effect can trigger at all. A
## trap spawns at the placer's own position, so its CatchArea sees their
## already-standing body as a "new" overlap the instant it's created — without
## this grace period the placer is entangled the moment they lay the trap,
## before they've actually crossed anything. Catching/consuming a larva is
## unaffected by this — only the slow is gated.
@export var entangle_grace_period: float = 0.4

var owner_spider: Node = null
var caught_larva: Node = null
var spent := false
var web_hits := 0
var _entangle_armed := false
var _plane: Level.Layer = Level.Layer.GROUND

@onready var _catch_area: Area2D = get_node_or_null("CatchArea")


## `plane` is the plane `placer` occupied at the moment of placement —
## defaults to GROUND so every existing caller that never passes one keeps
## behaving exactly as before.
func setup(placer: Node, plane: Level.Layer = Level.Layer.GROUND) -> void:
	owner_spider = placer
	_plane = plane


func _ready() -> void:
	add_to_group("traps")
	if _catch_area != null:
		_catch_area.body_entered.connect(_on_body_entered)
	if is_inside_tree():
		get_tree().create_timer(entangle_grace_period).timeout.connect(
			func() -> void: _entangle_armed = true)


func _on_body_entered(body: Node) -> void:
	if spent or _plane_of(body) != _plane:
		return
	if body.is_in_group("larvae"):
		catch_larva(body)
	elif body.is_in_group("spiders"):
		# Eating a caught larva is a reward, not a hazard: only entangle a
		# spider that's merely crossing an empty web, never one that's about
		# to consume what's caught in it.
		if caught_larva != null:
			try_consume(body)
		else:
			_entangle(body)


## Mirrors BlockadeSkill._plane_of()/CocoonMine._plane_of(): PlaneComponent-
## tracked plane, or GROUND for anything without one (every larva, and a
## bare test double).
func _plane_of(body: Node) -> Level.Layer:
	var plane_component: PlaneComponent = body.get("_plane") if "_plane" in body else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND


## Slow any spider that crosses the web — no exception for the placer; webs
## always impede whoever walks over them, and deal zero damage. No-op during
## entangle_grace_period, straight after placement.
func _entangle(spider: Node) -> void:
	if not _entangle_armed:
		return
	if spider.has_method("apply_web_hit"):
		spider.apply_web_hit(Vector2i.ZERO, web_slow_factor, web_slow_duration, 0.0)


## Hold a larva. Emits larva_trapped and immediately resolves consumption if a
## spider is already standing on the trap.
func catch_larva(larva: Node) -> void:
	if spent or caught_larva != null or _plane_of(larva) != _plane:
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
## larva, and spend the trap. No-op if empty or already spent. Uses the
## larva's own growth-scaled heal_value() (design §2) when it has one —
## falls back to the trap's flat `satiation` for a bare test double.
func try_consume(spider: Node) -> void:
	if spent or caught_larva == null:
		return
	var hunger := _find_hunger(spider)
	var heal_amount: float = caught_larva.heal_value() if caught_larva.has_method("heal_value") else satiation
	var overflow := 0.0
	if hunger != null:
		overflow = hunger.satiate(heal_amount)
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


## Destroys the trap immediately, regardless of hits_to_destroy — used by
## anything that removes a trap's tile out from under it (water flooding
## it, a compacted tile crushing it), as opposed to take_web_hit()'s
## shot-counter path. Same cleanup either way: releases any caught larva,
## leaves a torn-web visual, frees itself.
func force_destroy() -> void:
	if spent:
		return
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


## True if a trap holding a caught larva sits on `tile` — an occupied web is a
## boundary for other larvae (like a dead end), even though it never blocks a
## spider. An empty web has nothing to protect, so it isn't a boundary at all.
static func tile_has_caught_web(tree: SceneTree, tile: Vector2i, tile_size: int) -> bool:
	var ts := float(tile_size)
	for node in tree.get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap == null or trap.caught_larva == null:
			continue
		var trap_tile := Vector2i(int(floorf(trap.global_position.x / ts)), int(floorf(trap.global_position.y / ts)))
		if trap_tile == tile:
			return true
	return false
