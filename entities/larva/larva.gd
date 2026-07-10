class_name Larva
extends CharacterBody2D
## A wandering creature. Steps cell-to-cell on the maze grid, avoiding an
## immediate reversal unless it is dead-ended. Freezes when a trap catches it,
## and can be killed (not eaten) by a web shot, leaving an inedible corpse.
## Body collides with walls only (mask = world) so it passes through traps and
## spiders until a trap's catch area grabs it.

const CorpseScene := preload("res://entities/web/web_shot_spent.tscn")

@onready var _mover: GridMover = $GridMover
@onready var _sprite: Node2D = get_node_or_null("Sprite")
@onready var growth: LarvaGrowth = $LarvaGrowth

var caught := false
var _dead := false
var _last_dir := Vector2i.RIGHT
var _base_sprite_scale := Vector2.ONE


func _ready() -> void:
	add_to_group("larvae")
	_mover.step_finished.connect(_on_step_finished)
	if _sprite != null:
		_base_sprite_scale = _sprite.scale


## Hunger satiated / health restored when this larva is eaten right now
## (design §2: the longer it's survived, the more it's worth). Duck-typed by
## WebTrap.try_consume()/Enemy._eat_larva() via has_method() so a bare test
## double without a LarvaGrowth child still falls back to a flat amount.
func heal_value() -> float:
	return growth.heal_value()


## Set initial facing (Level derives this from the spawn tile's type).
func set_facing(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		_last_dir = dir
		rotation = Vector2(dir).angle()


## Called by a trap: stop and snap to the trap centre. Halts the mover first —
## a larva is often caught mid-step (the catch area is wider than a tile), and
## without this the in-flight step keeps lerping toward its pre-capture
## destination on the next frame, dragging the larva right back off-centre.
func set_caught(at_position: Vector2) -> void:
	caught = true
	_mover.stop()
	global_position = at_position


func _physics_process(_delta: float) -> void:
	if _sprite != null:
		_sprite.scale = _base_sprite_scale * growth.size_scale
	if caught or _dead or _mover.is_moving() or GameState.freeze_others:
		return
	_wander_step()


## Flash in distress (called when a web catches it).
func flash_distress() -> void:
	CombatFx.flash(_sprite)


## A step landed on a spider's tile: give the larva a tiny visual bump to
## acknowledge the interaction (juice only — mirrors the spider's own shunt
## when it steps onto a larva, never touches the grid position). Compares
## exact tile coordinates rather than a pixel-distance threshold, so it can't
## be missed by any small position drift (e.g. right after a knockback/stun).
func _on_step_finished() -> void:
	var my_tile := _tile_of(global_position)
	for node in get_tree().get_nodes_in_group("spiders"):
		var spider := node as Node2D
		if spider != null and _tile_of(spider.global_position) == my_tile:
			CombatFx.shunt(_sprite, Vector2(_last_dir) * 5.0)
			return


func _tile_of(world: Vector2) -> Vector2i:
	var ts := float(_mover.tile_size)
	return Vector2i(int(floorf(world.x / ts)), int(floorf(world.y / ts)))


## Force a single step toward `target_position`, overriding the normal wander
## choice for this tick — used by LureItem's radial pulse (design §5) to draw
## nearby larvae toward it. Same guards as _wander_step(); a no-op if blocked
## or already mid-step.
func nudge_toward(target_position: Vector2) -> void:
	if caught or _dead or _mover.is_moving() or GameState.freeze_others:
		return
	var to_target := target_position - global_position
	if to_target.length_squared() < 1.0:
		return
	var dir := Vector2i(int(signf(to_target.x)), 0) if absf(to_target.x) >= absf(to_target.y) \
		else Vector2i(0, int(signf(to_target.y)))
	if _mover.try_step(dir):
		_last_dir = dir
		rotation = Vector2(dir).angle()


func _wander_step() -> void:
	# Prefer any non-reverse direction; fall back to reversing at a dead-end.
	# A web currently holding a caught larva is a boundary too, like a wall —
	# even though larvae otherwise pass through webs freely, an occupied web
	# is someone else's meal, not open ground to wander onto.
	var my_tile := _tile_of(global_position)
	var options: Array[Vector2i] = []
	for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if d != -_last_dir and not _is_occupied_web(my_tile + d):
			options.append(d)
	options.shuffle()
	if not _is_occupied_web(my_tile - _last_dir):
		options.append(-_last_dir)
	for d in options:
		if _mover.try_step(d):
			_last_dir = d
			rotation = Vector2(d).angle()
			return


func _is_occupied_web(tile: Vector2i) -> bool:
	return WebTrap.tile_has_caught_web(get_tree(), tile, _mover.tile_size)


## A web shot killed this larva: drop out of the edible pool, leave a corpse.
func web_kill() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("larvae")
	var holder := get_parent()
	if holder != null:
		var corpse := CorpseScene.instantiate()
		holder.add_child(corpse)
		corpse.global_position = global_position
	queue_free()
