class_name MazeRenderer
extends Node2D
## Draws a MazeData as flat floor/wall rectangles. A placeholder for the
## SpriteCook TileSet: once tile art exists this can be swapped for a
## TileMapLayer without touching the rest of the maze pipeline (collision,
## occluders and navigation are built separately by Level).

var _maze: MazeData
var _tile_size := 48
var floor_color := Color(0.17, 0.15, 0.13)
var wall_color := Color(0.31, 0.27, 0.23)


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


func _draw() -> void:
	if _maze == null:
		return
	for y in _maze.height:
		for x in _maze.width:
			var rect := Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size)
			draw_rect(rect, floor_color if _maze.is_open(x, y) else wall_color)
