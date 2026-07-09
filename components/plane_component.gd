class_name PlaneComponent
extends Node
## Tracks which physical plane (ground/ceiling) the owner currently occupies
## (design §1: Dual-Plane Map Architecture). Player.gd wires its GridMover's
## block_check through `blocked(tile, dir)` here while on the ceiling (ground
## stepping keeps its existing test_move-based check unchanged — see
## Player._blocked). `level` is normally assigned directly by whoever binds
## the level (Player.bind_level, mirroring Enemy.bind_level); `level_path` is
## a fallback for a scene that wants to wire it by NodePath instead.

signal plane_changed(plane: Level.Layer)

@export var level_path: NodePath

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
