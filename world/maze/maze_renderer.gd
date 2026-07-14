class_name MazeRenderer
extends Node2D
## Draws a MazeData as flat floor rectangles and taller, two-tone wall
## blocks (tunnel faux-3D rework, design: docs/superpowers/specs/
## 2026-07-14-tunnel-visual-rework-design.md). A wall's rendered block is
## taller than its own 48x48 footprint -- a lighter "top face" plus a
## shorter, darker "front face" anchored to the tile's own bottom edge,
## with the extra height poking up into the tile north of it -- rather
## than a single flat-color rect, so walls read as physically standing at
## floor level instead of the old point-light shadow artifact that made
## them look unnaturally (and accidentally) tall. Placeholder colors/
## proportions, not real tile art yet -- swap for a TileMapLayer once
## SpriteCook art exists; the collision/occluder/navigation pipeline is
## built separately by Level, so it's unaffected either way.
##
## Ceiling/plane mechanics rework: open tiles render in floor_color or
## ceiling_floor_color depending on which plane the player currently
## occupies (set_active_plane(), driven by Level) — replaces the old
## per-sprite ceiling tint entirely. Wall rendering is unchanged on both
## planes for now: walls exist identically on both layers (CeilingData
## mirrors MazeData's wall geometry 1:1), and the ceiling-plane inverse
## wall treatment (front face hanging down instead of rising up) is a
## later phase, not yet built.

var _maze: MazeData
var _tile_size := 48
var floor_color := Color(0.17, 0.15, 0.13)
var ceiling_floor_color := Color(0.13, 0.17, 0.24)
var wall_top_face_color := Color(0.36, 0.31, 0.26)
var wall_front_face_color := Color(0.2, 0.16, 0.12)
## Grid lines on top of open floor tiles, so the tile-stepped movement reads
## clearly against the map.
var grid_line_color := Color(1, 1, 1, 0.08)

## How far a wall's rendered block pokes up above its own tile's top edge,
## and the height of the darker front-face band anchored to its own bottom
## edge -- see this file's own doc comment. Placeholder proportions, easy
## to retune once real tile art exists.
var wall_overdraw_height := 16.0
var wall_front_face_height := 16.0

## Any wall whose rendered block would currently overlap this world-space
## position fades to wall_fade_alpha -- set by Level every frame to the
## player's own position (occlusion fade), so a wall directly "in front of"
## the player on screen never hides them. Vector2.INF (the default) can
## never fall inside any wall's finite occlusion band, so nothing fades
## until Level calls set_fade_focus().
var fade_focus_position := Vector2.INF
var wall_fade_alpha := 0.25

var _active_plane: Level.Layer = Level.Layer.GROUND


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	queue_redraw()


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


## Which plane's floor color open tiles should currently draw in — the
## player's own plane (there's one camera, one local viewer).
func set_active_plane(plane: Level.Layer) -> void:
	_active_plane = plane
	queue_redraw()


## Where the occlusion fade should center -- see fade_focus_position's own
## doc comment.
func set_fade_focus(world_position: Vector2) -> void:
	fade_focus_position = world_position


func _draw() -> void:
	if _maze == null:
		return
	var open_color := floor_color if _active_plane == Level.Layer.GROUND else ceiling_floor_color
	for y in _maze.height:
		for x in _maze.width:
			if _maze.is_open(x, y):
				draw_rect(Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), open_color)
			else:
				_draw_wall(Vector2i(x, y))
	_draw_grid_lines()


## Draws one wall tile's block: a shorter, darker front face anchored to
## the tile's own bottom edge, with a taller, lighter top face above it
## poking up into the tile north of it. Fades both faces together if this
## wall currently occludes fade_focus_position (see wall_occludes_position).
func _draw_wall(tile: Vector2i) -> void:
	var alpha := wall_fade_alpha if wall_occludes_position(tile, fade_focus_position, _tile_size, wall_overdraw_height) else 1.0
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var block_top := tile_top - wall_overdraw_height
	var front_face_top := tile_bottom - wall_front_face_height
	draw_rect(Rect2(tile_left, block_top, _tile_size, front_face_top - block_top),
		Color(wall_top_face_color, wall_top_face_color.a * alpha))
	draw_rect(Rect2(tile_left, front_face_top, _tile_size, wall_front_face_height),
		Color(wall_front_face_color, wall_front_face_color.a * alpha))


## True if a wall at `wall_tile` (tile coordinates) would visually overlap
## `position` (world-space) given its rendered block pokes `overdraw`
## pixels above its own tile into the tile north of it -- anything
## standing in that northern sliver would otherwise be hidden behind the
## wall's own rendered height. A pure function (no scene tree needed) so
## it's directly unit-testable -- see docs/superpowers/specs/2026-07-14-
## tunnel-visual-rework-design.md.
static func wall_occludes_position(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_top := float(wall_tile.y) * tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_top - overdraw and position.y <= tile_top


func _draw_grid_lines() -> void:
	var width_px := _maze.width * _tile_size
	var height_px := _maze.height * _tile_size
	for x in (_maze.width + 1):
		var px := x * _tile_size
		draw_line(Vector2(px, 0), Vector2(px, height_px), grid_line_color)
	for y in (_maze.height + 1):
		var py := y * _tile_size
		draw_line(Vector2(0, py), Vector2(width_px, py), grid_line_color)
