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
## Tunnel visual rework Phase 2: floor rendering (including the old
## per-plane ceiling_floor_color recolor) has moved to FloorRenderer/
## GroundLayer, which reads "which plane am I on" via dimming instead of a
## color swap -- see docs/superpowers/specs/2026-07-14-tunnel-visual-
## rework-design.md. This class now draws walls only. set_active_plane()
## still drives which way a wall's front face renders (_draw_wall_ground()
## vs _draw_wall_ceiling()).

var _maze: MazeData
var _tile_size := 48
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


## Read-only access to which plane is currently active -- WallOverdrawMask
## needs this to know which neighbor direction (north for ground, south for
## ceiling) a given entity's own wall-adjacency check should use.
func active_plane() -> Level.Layer:
	return _active_plane


## The overdraw sliver's own rect in world space for `tile` (a wall tile),
## matching whichever plane is currently active -- the exact patch
## _draw_wall_ground()/_draw_wall_ceiling() paints for that wall's top face
## poking into its neighbor. WallOverdrawMask paints this same patch again,
## on top of Entities, whenever an entity (not the player) is standing
## inside it -- see WallOverdrawMask's own doc comment for why a second pass
## is needed instead of just relying on draw order once.
func overdraw_rect_for(tile: Vector2i) -> Rect2:
	var tile_left := float(tile.x) * _tile_size
	if _active_plane == Level.Layer.GROUND:
		var tile_top := float(tile.y) * _tile_size
		return Rect2(tile_left, tile_top - wall_overdraw_height, _tile_size, wall_overdraw_height)
	else:
		var tile_bottom := float(tile.y) * _tile_size + _tile_size
		return Rect2(tile_left, tile_bottom, _tile_size, wall_overdraw_height)


func _draw() -> void:
	if _maze == null:
		return
	for y in _maze.height:
		for x in _maze.width:
			if not _maze.is_open(x, y):
				_draw_wall(Vector2i(x, y))
	_draw_grid_lines()


## Draws one wall tile's block, dispatching to the plane-appropriate
## orientation -- see _draw_wall_ground()/_draw_wall_ceiling().
func _draw_wall(tile: Vector2i) -> void:
	if _active_plane == Level.Layer.GROUND:
		_draw_wall_ground(tile)
	else:
		_draw_wall_ceiling(tile)


## Ground-plane wall: front face anchored to the tile's own bottom edge,
## top face poking up into the tile north of it. Fades both faces together
## if this wall currently occludes fade_focus_position. Always renders at
## full height, even when a pit or flooded tile (same MazeData overlay --
## see MazeData.is_pit()) sits in the tile north of it (playtest fix,
## mirrors _draw_wall_ceiling()): the overdraw represents the wall's own
## height occluding whatever's behind it from the viewer's perspective, and
## a hole is no exception to that -- its near edge should partially
## disappear behind the wall's silhouette, not the wall shrinking to avoid
## touching it. An earlier version clipped the overdraw to 0 next to a pit;
## that produced a visible notch in the wall's own silhouette right where a
## consistent block was expected, which is a worse look than the wall
## simply doing what it does everywhere else.
func _draw_wall_ground(tile: Vector2i) -> void:
	var overdraw := wall_overdraw_height
	var alpha := wall_fade_alpha if wall_occludes_position(tile, fade_focus_position, _tile_size, overdraw) else 1.0
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var block_top := tile_top - overdraw
	var front_face_top := tile_bottom - wall_front_face_height
	draw_rect(Rect2(tile_left, block_top, _tile_size, front_face_top - block_top),
		Color(wall_top_face_color, wall_top_face_color.a * alpha))
	draw_rect(Rect2(tile_left, front_face_top, _tile_size, wall_front_face_height),
		Color(wall_front_face_color, wall_front_face_color.a * alpha))


## Ceiling-plane wall: mirrored -- front face anchored to the tile's own
## top edge, hanging down; top face pokes down into the tile south of it
## (tunnel visual rework Phase 2). Fades both faces together if this wall
## currently occludes fade_focus_position via the ceiling-mirrored check.
## Same full-height-always behavior as _draw_wall_ground() -- see its doc
## comment for why a pit/flooded neighbor never clips the overdraw on
## either plane.
func _draw_wall_ceiling(tile: Vector2i) -> void:
	var overdraw := wall_overdraw_height
	var alpha := wall_fade_alpha if wall_occludes_position_ceiling(tile, fade_focus_position, _tile_size, overdraw) else 1.0
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var block_bottom := tile_bottom + overdraw
	var front_face_bottom := tile_top + wall_front_face_height
	draw_rect(Rect2(tile_left, front_face_bottom, _tile_size, block_bottom - front_face_bottom),
		Color(wall_top_face_color, wall_top_face_color.a * alpha))
	draw_rect(Rect2(tile_left, tile_top, _tile_size, wall_front_face_height),
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


## Ceiling-plane mirror of wall_occludes_position(): the ceiling variant's
## rendered block pokes `overdraw` pixels below its own tile into the tile
## south of it (front face hangs down instead of rising up -- see
## _draw_wall_ceiling()) -- same occlusion idiom, opposite direction.
static func wall_occludes_position_ceiling(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_bottom := float(wall_tile.y) * tile_size + tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_bottom and position.y <= tile_bottom + overdraw


func _draw_grid_lines() -> void:
	var width_px := _maze.width * _tile_size
	var height_px := _maze.height * _tile_size
	for x in (_maze.width + 1):
		var px := x * _tile_size
		draw_line(Vector2(px, 0), Vector2(px, height_px), grid_line_color)
	for y in (_maze.height + 1):
		var py := y * _tile_size
		draw_line(Vector2(0, py), Vector2(width_px, py), grid_line_color)
