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
var _floor_texture: Texture2D = preload("res://assets/textures/floor_material.png")

## The generated floor material's own pixels are already close to floor_color
## in absolute brightness, so modulating by floor_color directly would
## near-black-crush it (multiplying two already-dark values). Boosted so the
## texture's own detail stays visible while preserving floor_color's hue.
const _TEXTURE_TINT_BOOST := 2.7


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


func _draw() -> void:
	if _maze == null:
		return
	var tint := Color(
		minf(floor_color.r * _TEXTURE_TINT_BOOST, 1.0),
		minf(floor_color.g * _TEXTURE_TINT_BOOST, 1.0),
		minf(floor_color.b * _TEXTURE_TINT_BOOST, 1.0),
		floor_color.a
	)
	for y in _maze.height:
		for x in _maze.width:
			if _maze.is_open(x, y):
				draw_texture_rect(_floor_texture, Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), true, tint)
