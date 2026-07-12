class_name PlaneComponent
extends Node
## Tracks which physical plane (ground/ceiling) the owner currently occupies
## (design §1: Dual-Plane Map Architecture). Player.gd wires its GridMover's
## block_check through `blocked(tile, dir)` here while on the ceiling (ground
## stepping keeps its existing test_move-based check unchanged — see
## Player._blocked). `level` is normally assigned directly by whoever binds
## the level (Player.bind_level, mirroring Enemy.bind_level); `level_path` is
## a fallback for a scene that wants to wire it by NodePath instead.
##
## Ceiling/plane mechanics rework: also the shared plane authority for combat
## and tile-stacking (effective_plane()/same_plane()), and owns the
## knockdown-plus-fall-damage penalty for getting hit while on the ceiling
## (apply_hit_fall()) — kept here rather than on Hurtbox so any future
## plane-aware entity gets consistent fall behavior automatically.

signal plane_changed(plane: Level.Layer)

@export var level_path: NodePath
## First-pass balance number — tune during playtest.
@export var fall_damage: float = 8.0

var level: Level
var current_plane: Level.Layer = Level.Layer.GROUND


func _ready() -> void:
	if level == null and not level_path.is_empty():
		level = get_node_or_null(level_path) as Level


func transition() -> void:
	current_plane = Level.Layer.CEILING if current_plane == Level.Layer.GROUND else Level.Layer.GROUND
	plane_changed.emit(current_plane)
	EventBus.plane_changed.emit(get_parent(), current_plane)


## Blocking seam: whether stepping from `tile` in `dir` is blocked on
## whichever plane this owner currently occupies.
func blocked(tile: Vector2i, dir: Vector2i) -> bool:
	if level == null:
		return false
	return level.is_blocked(tile + dir, current_plane)


## A node's plane if it has a PlaneComponent child, else GROUND — the
## default for every entity that never tracks planes at all (larvae,
## decoys, hatchlings, traps, Blockade).
static func effective_plane(node: Node) -> Level.Layer:
	if node == null:
		return Level.Layer.GROUND
	var plane := node.get_node_or_null("PlaneComponent") as PlaneComponent
	return plane.current_plane if plane != null else Level.Layer.GROUND


static func same_plane(a: Node, b: Node) -> bool:
	return effective_plane(a) == effective_plane(b)


## Called by Hurtbox after a hit lands: knocks the owner down to the ground
## plane and applies bonus fall damage. No-op while already on the ground.
func apply_hit_fall(health: HealthComponent) -> void:
	if current_plane != Level.Layer.CEILING:
		return
	transition()
	if health != null:
		health.take_damage(fall_damage)
