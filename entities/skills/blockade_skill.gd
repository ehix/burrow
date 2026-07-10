class_name BlockadeSkill
extends SkillComponent
## Funnel/Weaver Spider (male): deploys a destructible rock/dirt barrier one
## tile ahead of the caster (playtest fix: previously placed at the
## caster's own position, which trapped them inside their own barricade).
## Unlike WebTrap (never blocks movement, just slows), a blockade is a hard
## obstacle until destroyed. Placing one directly over a pit tile also patches
## it for ground traversal, via Level.patch_pit_at — the same mechanism the
## ceiling plane already bypasses structurally (see CeilingData).
##
## Can't be placed on top of the enemy spider, into an already-blocked tile
## (a wall, a pit, or an existing blockade), or off the edge of the maze
## (activate() refuses outright, charging no cost) — a larva on the target
## tile is crushed instead and the blockade is placed as normal.
##
## `blockade_scene` is a high-durability StaticBody2D — its script must call
## `setup(hits_to_destroy)`.

@export var hits_to_destroy: int = 6
@export var blockade_scene: PackedScene


func activate(source: Node) -> bool:
	var origin := source as Node2D
	if origin == null:
		return false
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null:
		return false
	var target_tile := _target_tile(origin, level)
	if _spider_occupies(target_tile, source):
		return false
	if level.is_blocked(target_tile, _plane_of(source)):
		return false
	return super.activate(source)


func _on_activate(source: Node) -> void:
	if blockade_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null:
		return
	var target_tile := _target_tile(origin, level)
	_crush_larva_at(target_tile, level)
	var blockade := blockade_scene.instantiate()
	_spawn_parent(source).add_child(blockade)
	blockade.global_position = level.centre_of(target_tile)
	if blockade.has_method("setup"):
		blockade.setup(hits_to_destroy)
	level.patch_pit_at(target_tile)


## The tile directly ahead of `origin`, in its current facing direction.
func _target_tile(origin: Node2D, level: Level) -> Vector2i:
	var facing: Vector2 = origin.get("facing") if "facing" in origin else Vector2.RIGHT
	return level.tile_of(origin.global_position) + Vector2i(int(facing.x), int(facing.y))


## True if another spider (not `source`) is already committed to `tile` —
## mirrors GridMover.spider_tile_contested()'s own idiom, so a blockade can
## never be used to trap or damage the enemy spider directly.
func _spider_occupies(tile: Vector2i, source: Node) -> bool:
	for node in source.get_tree().get_nodes_in_group("spiders"):
		if node == source:
			continue
		var other := node as Node2D
		if other == null:
			continue
		var other_mover := other.get_node_or_null("GridMover") as GridMover
		if other_mover != null and other_mover.committed_tile() == tile:
			return true
	return false


## The plane `source` currently occupies. `Player` tracks this via its
## PlaneComponent; anything without one (e.g. `Enemy`, which never leaves the
## ground) is treated as ground-only.
func _plane_of(source: Node) -> Level.Layer:
	var plane_component: PlaneComponent = source.get("_plane") if "_plane" in source else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND


## A larva standing on the target tile is crushed and killed (not eaten) the
## instant a blockade lands on it.
func _crush_larva_at(tile: Vector2i, level: Level) -> void:
	for node in level.get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva != null and level.tile_of(larva.global_position) == tile and larva.has_method("web_kill"):
			larva.web_kill()


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
