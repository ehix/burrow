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
## Grid lines on top of open floor tiles, so the tile-stepped movement reads
## clearly against the map.
var grid_line_color := Color(1, 1, 1, 0.08)


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
	_draw_grid_lines()


func _draw_grid_lines() -> void:
	var width_px := _maze.width * _tile_size
	var height_px := _maze.height * _tile_size
	for x in (_maze.width + 1):
		var px := x * _tile_size
		draw_line(Vector2(px, 0), Vector2(px, height_px), grid_line_color)
	for y in (_maze.height + 1):
		var py := y * _tile_size
		draw_line(Vector2(0, py), Vector2(width_px, py), grid_line_color)
