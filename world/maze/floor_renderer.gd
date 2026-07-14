class_name FloorRenderer
extends Node2D
## Draws just the maze's open floor tiles (tunnel visual rework Phase 2) --
## split out of MazeRenderer, which now draws only walls, so this can live
## inside GroundLayer and get desaturated/darkened as a unit while
## MazeRenderer's walls (crisp foreground) stay outside it. Always draws
## the one true ground floor_color -- the old per-plane ceiling_floor_color
## recolor is retired: a real background layer that dims independently
## makes a second recolor redundant. Redrawn on setup() and whenever
## Level's own wall-editing calls (dev_remove_wall_at, collapse_tile_at)
## already redraw MazeRenderer -- no per-frame redraw needed, since floor
## geometry has no per-frame-changing state (no fade dependency, unlike
## MazeRenderer's walls).

var _maze: MazeData
var _tile_size := 48
var floor_color := Color(0.17, 0.15, 0.13)


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


func _draw() -> void:
	if _maze == null:
		return
	for y in _maze.height:
		for x in _maze.width:
			if _maze.is_open(x, y):
				draw_rect(Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), floor_color)
