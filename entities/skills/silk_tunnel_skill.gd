class_name SilkTunnelSkill
extends SkillComponent
## Funnel/Weaver Spider (male): coats `tile_count` tiles ahead of the caster
## in web (reuses WebTrap's own placement/scene — enemy slowdown when
## crossing is already its existing entangle behaviour, no separate mechanic
## needed), then buffs the caster's own speed via StatusEffectComponent for
## `self_buff_duration`. The self-buff deliberately drives GridMover.speed_scale
## through the unified status-timer rather than GridMover.apply_slow's own ad
## hoc timer, so a Seed Pod or Silk Tunnel buff active at once refresh cleanly
## instead of fighting over the same field (design guardrail §3).

@export var trap_scene: PackedScene
@export var tile_count: int = 6
@export var self_speed_bonus: float = 0.3
@export var self_buff_duration: float = 6.0


func _on_activate(source: Node) -> void:
	_lay_tunnel(source)
	_buff_self(source)


func _lay_tunnel(source: Node) -> void:
	if trap_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null or level.maze == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var dir := _dominant(facing)
	# GridMover.committed_tile() rather than origin's raw, interpolated
	# global_position -- mirrors BlockadeSkill._target_tile()'s own fix for
	# the identical bug (see its doc comment): floor-dividing the
	# interpolated position flips which tile it resolves to partway through
	# a step's animation, so spamming this while moving could start the
	# tunnel from a tile inconsistent with where the caster visually was,
	# reading as a web placed "between tiles" (playtest feedback).
	var mover := _mover_of(source)
	var tile := mover.committed_tile() if mover != null else level.tile_of(origin.global_position)
	var holder := _spawn_parent(source)
	for i in tile_count:
		tile += dir
		if level.maze.is_ground_blocked(tile.x, tile.y):
			break
		var trap := trap_scene.instantiate()
		holder.add_child(trap)
		trap.global_position = level.centre_of(tile)
		if trap.has_method("setup"):
			trap.setup(source)


func _buff_self(source: Node) -> void:
	var status := _status_of(source)
	var mover := _mover_of(source)
	if status == null or mover == null:
		return
	status.apply(&"silk_haste", self_speed_bonus, self_buff_duration,
		func(_delta: float, magnitude: float) -> void: mover.speed_scale = 1.0 + magnitude,
		func() -> void: mover.speed_scale = 1.0)


func _dominant(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null


func _mover_of(entity: Node) -> GridMover:
	for child in entity.get_children():
		if child is GridMover:
			return child
	return null


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
