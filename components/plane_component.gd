class_name PlaneComponent
extends Node
## Tracks which physical plane (ground/ceiling) the owner currently occupies
## (design §1: Dual-Plane Map Architecture). A spider's GridMover.block_check
## should route through `blocked(tile, dir)` here instead of querying Level
## directly, so ground and ceiling stepping share one code path. Not yet
## wired into Enemy/Player's own block_check in this pass — attach to a
## spider scene and call `transition()` from an input action or skill to
## enable ceiling traversal.

signal plane_changed(plane: Level.Layer)

@export var level_path: NodePath

var level: Level
var current_plane: Level.Layer = Level.Layer.GROUND


func _ready() -> void:
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
